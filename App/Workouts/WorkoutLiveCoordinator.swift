import ActivityKit
import CryptoKit
import Foundation
import OSLog

struct WorkoutLivePrivacy {
    static var isolatedRun: UUID? {
        #if WEEKFORM_DEVELOPMENT
        return ProcessInfo.processInfo.environment["WEEKFORM_UI_TEST_RUN"].flatMap(UUID.init(uuidString:))
        #else
        return nil
        #endif
    }
    static func key(_ name: String) -> String {
        let prefix = isolatedRun.map { "workoutLive.test.\($0.uuidString)" } ?? "workoutLive"
        return "\(prefix).\(name)"
    }
    static var showExerciseKey: String { key("showExercise") }
    static var showLoadKey: String { key("showLoad") }
    static var epochKey: String { key("privacyEpoch") }
    let showExercise: Bool
    let showLoad: Bool
    let epoch: String

    static var current: Self {
        let settings = UserDefaults.standard
        return Self(showExercise: settings.bool(forKey: showExerciseKey), showLoad: settings.bool(forKey: showLoadKey),
                    epoch: settings.string(forKey: epochKey) ?? "initial")
    }
}

extension Notification.Name {
    static let workoutLiveDidCommit = Notification.Name("workoutLiveDidCommit")
}

@MainActor
enum WorkoutLiveCoordinator {
    private static var lastRequestKey: String { WorkoutLivePrivacy.key("lastRequested") }
    private static var updateTail: Task<Void, Never>?
    private static var failedRequest: (key: String, retryAfter: Date)?

    private static func generation(_ paths: RecoveryPaths) -> String {
        paths.previous == nil ? "original" : paths.training.deletingLastPathComponent().lastPathComponent
    }

    static func isCurrent(_ route: WorkoutLiveRoute, training: TrainingStore, owner: UUID?) -> Bool {
        guard route.owner == owner, let paths = try? RecoveryPaths.current(), route.generation == generation(paths),
              training.isOpen(at: paths.training, owner: route.owner), let session = training.active,
              session.id == route.sessionID, !training.isExpired(session),
              let token = route.focusToken, token == training.focusToken else { return false }
        if let exerciseID = route.exerciseID {
            guard let exercise = session.exercises.first(where: { $0.id == exerciseID }) else { return false }
            if let setID = route.setID { return exercise.sets.contains { $0.id == setID } }
        }
        return true
    }

    static func snapshot(_ session: TrainingSession, revision: Int, privacy: WorkoutLivePrivacy) -> WorkoutLiveActivity.ContentState {
        let exercise = session.exercises.first { $0.id == session.currentExerciseID } ?? session.exercises.first
        var state = WorkoutLiveActivity.ContentState(revision: revision, privacyEpoch: privacy.epoch, exerciseID: exercise?.id)
        if let rest = session.rest {
            state.restStart = rest.startedAt.addingTimeInterval(rest.pausedSeconds)
            state.restPausedAt = rest.pausedAt
            state.restTarget = rest.targetSeconds
        }
        guard let exercise else {
            state.primary = session.isCardio && session.cardio != nil ? .review : .edit
            return state
        }
        let name = exercise.prescription.name
        if privacy.showExercise, !name.isEmpty, name.utf8.count <= 80, !name.contains(where: \.isNewline) { state.exerciseName = name }
        let pending = exercise.sets.filter { $0.confirmedAt == nil }
        guard let row = pending.first else {
            state.primary = nextExercise(in: session) == nil ? .review : .nextExercise
            return state
        }
        state.setID = row.id
        state.ordinal = row.ordinal ?? (exercise.sets.firstIndex { $0.id == row.id } ?? 0) + 1
        state.warmup = row.warmup == true
        state.finalSet = pending.count == 1
        state.willRest = !state.finalSet && exercise.restSeconds != nil
        // The user-facing setting covers every actual, including unweighted reps and seconds.
        let actual = exercise.suggestedActual(for: row) ?? row.actual
        if state.exerciseName != nil, privacy.showLoad, (try? actual.validate(for: exercise.basis)) != nil {
            state.result = resultLabel(actual, basis: exercise.basis, convention: exercise.prescription.convention)
        }
        if state.restPausedAt != nil { state.primary = .resume }
        else { state.primary = state.result == nil ? .edit : .confirm }
        return state
    }

    private static func resultLabel(_ actual: SetActual, basis: LoadBasis, convention: String) -> String? {
        func weight(_ value: Double?) -> String {
            guard let value else { return "" }
            return "\(value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...16)).grouping(.never))) \(actual.unit)"
        }
        // Avoid logging a rounded number as a more precise stored result.
        for load in [actual.load, actual.rightLoad].compactMap({ $0 }) {
            guard Double(weight(load).split(separator: " ").first.map(String.init) ?? "") == load else { return nil }
        }
        let text: String
        switch basis {
        case .unilateral:
            text = "L \(actual.reps!) × \(weight(actual.load)) · R \(actual.rightReps!) × \(weight(actual.rightLoad))"
        case .timed:
            text = "\(actual.seconds!) s" + (actual.load == nil ? "" : " · \(weight(actual.load))")
        case .bodyweight:
            text = "\(actual.reps!) reps · bodyweight"
        default:
            let weightQualifier: String = switch basis {
            case .assisted: " assistance"
            case .added: " added"
            case .barbell: " total"
            case .dumbbell: " each"
            case .machine: " machine"
            default: ""
            }
            text = "\(actual.reps!) reps · \(weight(actual.load))\(weightQualifier)"
        }
        // A lengthy or custom machine convention needs the full in-app editor.
        if basis == .machine && !convention.isEmpty && !["machine setting", "machine"].contains(convention.lowercased()) { return nil }
        return text.utf8.count <= 85 ? text : nil
    }

    private static func nextExercise(in session: TrainingSession) -> TrainingExercise? {
        let items = session.exercises
        guard let i = items.firstIndex(where: { $0.id == session.currentExerciseID }) else { return nil }
        let order = Array(items.indices.dropFirst(i + 1)) + Array(items.indices.prefix(i))
        return order.lazy.map { items[$0] }.first { $0.sets.contains { $0.confirmedAt == nil } }
    }

    static func changePrivacy(showExercise: Bool, showLoad: Bool) async {
        let defaults = UserDefaults.standard
        let current = WorkoutLivePrivacy.current
        guard current.showExercise != showExercise || current.showLoad != showLoad else { return }
        defaults.set(UUID().uuidString, forKey: WorkoutLivePrivacy.epochKey)
        defaults.set(showExercise, forKey: WorkoutLivePrivacy.showExerciseKey)
        defaults.set(showLoad, forKey: WorkoutLivePrivacy.showLoadKey)
        if let opened = try? openCanonical() {
            await sync(training: opened.training, owner: opened.owner, allowStart: false)
        }
        // A store read can also fail inside the publication queue. Withdraw
        // anything that still uses the old privacy setting after the sync.
        for activity in Activity<WorkoutLiveActivity>.activities where activity.attributes.isolatedRun == WorkoutLivePrivacy.isolatedRun {
            if activity.content.state.privacyEpoch != WorkoutLivePrivacy.current.epoch {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func sync(training: TrainingStore, owner: UUID?, allowStart: Bool = true) async {
        // Updates share one ordered queue so an earlier asynchronous publication
        // cannot land after a newer privacy or session change.
        let previous = updateTail
        let task = Task { @MainActor in
            await previous?.value
            await publish(training: training, owner: owner, allowStart: allowStart)
        }
        updateTail = task
        await task.value
    }

    private static func publish(training: TrainingStore, owner: UUID?, allowStart: Bool) async {
        // The foreground and intents may have separate store instances. Read the
        // current focus after entering the publication queue before ending an activity.
        guard let owner, let opened = try? openCanonical(), opened.owner == owner,
              training.isOpen(at: opened.paths.training, owner: owner) else { return }
        let generation = generation(opened.paths)
        let current = opened.training
        let session = current.active.flatMap { current.isExpired($0) ? nil : $0 }
        let focusToken = current.focusToken
        var existing: Activity<WorkoutLiveActivity>?
        for activity in Activity<WorkoutLiveActivity>.activities where activity.attributes.isolatedRun == WorkoutLivePrivacy.isolatedRun {
            if activity.attributes.sessionID == session?.id, activity.attributes.owner == owner,
               activity.attributes.generation == generation, let focusToken,
               activity.attributes.focusToken == focusToken, existing == nil {
                existing = activity
            } else { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard let session, let focusToken, let latest = try? openCanonical(), latest.owner == owner,
              Self.generation(latest.paths) == generation, latest.training.focusToken == focusToken,
              let focused = latest.training.active, focused.id == session.id, !latest.training.isExpired(focused) else { return }
        let state = snapshot(focused, revision: latest.training.liveRevision, privacy: .current)
        let content = ActivityContent(state: state, staleDate: latest.training.expirationDate(for: focused))
        if let existing {
            // Never overwrite an externally committed intent with this foreground
            // store's older revision while the app is reloading its read model.
            if existing.content.state.revision <= state.revision && existing.content.state != state {
                await existing.update(content)
            }
        } else if allowStart && ActivityAuthorizationInfo().areActivitiesEnabled {
            let key = "\(generation)/\(owner)/\(focusToken)"
            guard UserDefaults.standard.string(forKey: lastRequestKey) != key else { return }
            if let failedRequest, failedRequest.key == key, failedRequest.retryAfter > Date() { return }
            do {
                _ = try Activity.request(attributes: WorkoutLiveActivity(owner: owner, generation: generation, sessionID: session.id,
                                                                       focusToken: focusToken, isolatedRun: WorkoutLivePrivacy.isolatedRun), content: content)
                UserDefaults.standard.set(key, forKey: lastRequestKey)
                failedRequest = nil
            } catch {
                failedRequest = (key, Date().addingTimeInterval(15))
                Logger(subsystem: "com.christophervalle.weekform", category: "LiveActivity").info("System declined the workout activity request.")
                // ActivityKit may deny a request while locked or backgrounded.
                // The in-app workout remains usable and a foreground sync retries.
            }
        }
    }

    private static func openCanonical() throws -> (paths: RecoveryPaths, owner: UUID, training: TrainingStore) {
        let paths = try RecoveryPaths.current()
        guard try paths.planning.appending(path: "planning.store").checkResourceIsReachable() else {
            throw TrainingError("Open Weekform to access your stored workout.")
        }
        let planner = PlanningStore(directory: paths.planning)
        try planner.load()
        guard let owner = planner.profileID else { throw TrainingError("Open Weekform to resume this workout.") }
        guard try paths.training.appending(path: owner.uuidString).appending(path: "training.store").checkResourceIsReachable() else {
            throw TrainingError("Your workout is temporarily unavailable.")
        }
        let training = TrainingStore(directory: paths.training)
        try training.load(profileID: owner)
        return (paths, owner, training)
    }

    static func perform(activityID: String, action: WorkoutLiveAction, revision: Int, privacyEpoch: String) async throws {
        guard let activity = Activity<WorkoutLiveActivity>.activities.first(where: { $0.id == activityID }),
              activity.attributes.isolatedRun == WorkoutLivePrivacy.isolatedRun,
              activity.activityState == .active || activity.activityState == .stale else {
            throw TrainingError("Open Weekform to resume this workout.")
        }
        let opened = try openCanonical()
        let attributes = activity.attributes
        let state = activity.content.state
        let originalRevision = opened.training.liveRevision
        defer {
            if opened.training.liveRevision != originalRevision {
                NotificationCenter.default.post(name: .workoutLiveDidCommit, object: nil)
            }
        }
        do {
            try opened.training.reconcileExpiredSessions()
            try validateScope(attributes, paths: opened.paths, owner: opened.owner, training: opened.training)
        }
        catch {
            await sync(training: opened.training, owner: opened.owner, allowStart: false)
            throw error
        }
        let commandID = commandID(activityID: activityID, revision: revision, privacyEpoch: privacyEpoch)
        if action == .confirm && opened.training.active?.receipts[commandID] != nil {
            await sync(training: opened.training, owner: opened.owner, allowStart: false)
            return
        }
        do {
            try apply(action, expected: state, revision: revision, epoch: privacyEpoch, privacy: .current,
                      commandID: commandID, training: opened.training)
        } catch {
            await sync(training: opened.training, owner: opened.owner, allowStart: false)
            throw error
        }
        await sync(training: opened.training, owner: opened.owner, allowStart: false)
    }

    static func validateScope(_ attributes: WorkoutLiveActivity, paths: RecoveryPaths, owner: UUID, training: TrainingStore) throws {
        guard attributes.isolatedRun == WorkoutLivePrivacy.isolatedRun, attributes.owner == owner, attributes.generation == generation(paths),
              training.isOpen(at: paths.training, owner: owner), let session = training.active,
              session.id == attributes.sessionID, !training.isExpired(session),
              let token = attributes.focusToken, token == training.focusToken else {
            throw TrainingError("This workout has changed.")
        }
    }

    static func apply(_ action: WorkoutLiveAction, expected: WorkoutLiveActivity.ContentState, revision: Int,
                      epoch: String, privacy: WorkoutLivePrivacy, commandID: UUID, training: TrainingStore) throws {
        guard let session = training.active, !training.isExpired(session),
              training.liveRevision == revision, expected.revision == revision,
              expected.privacyEpoch == epoch, privacy.epoch == epoch,
              snapshot(session, revision: revision, privacy: privacy) == expected else { throw TrainingError("Review the updated workout.") }
        guard expected.primary == action || (action == .startSet && expected.canStartSet) else {
            throw TrainingError("Open Weekform to review the result.")
        }
        switch action {
        case .confirm:
            guard let exercise = session.exercises.first(where: { $0.id == expected.exerciseID }),
                  let row = exercise.sets.first(where: { $0.id == expected.setID }), expected.result != nil else {
                throw TrainingError("Open the set to review its values.")
            }
            let actual = exercise.suggestedActual(for: row) ?? row.actual
            try training.confirm(sessionID: session.id, setID: row.id, actual: actual, revision: row.revision, commandID: commandID)
        case .startSet:
            try training.startSet(sessionID: session.id)
        case .resume:
            try training.resumeRest(sessionID: session.id)
        case .nextExercise:
            guard let next = nextExercise(in: session) else { throw TrainingError("Review this workout in Weekform.") }
            try training.select(sessionID: session.id, exerciseID: next.id)
        case .edit, .review:
            throw TrainingError("Open Weekform to continue.")
        }
    }

    private static func commandID(activityID: String, revision: Int, privacyEpoch: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("\(activityID)/\(revision)/\(privacyEpoch)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
