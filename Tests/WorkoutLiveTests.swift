import Foundation
import Testing
@testable import Weekform

@MainActor
struct WorkoutLiveTests {
    private let visible = WorkoutLivePrivacy(showExercise: true, showLoad: true, epoch: "visible")

    private func setup(now: @escaping () -> Date = { Date() }, beforeSave: @escaping () throws -> Void = {},
                       _ test: (TrainingStore, URL, UUID) throws -> Void) throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrainingStore(directory: root, now: now, beforeSave: beforeSave)
        let owner = UUID()
        try store.load(profileID: owner)
        try store.startExtra(name: "Private session name")
        let id = try #require(store.active?.id)
        try store.add(sessionID: id, prescription: PlanExercise(name: "Cable row", sets: 2, convention: "Machine setting", notes: "Private exercise note"), basis: .machine)
        let first = try #require(store.active?.exercises.first)
        try store.configureRest(sessionID: id, exerciseID: first.id, seconds: 90)
        for row in first.sets { try store.edit(sessionID: id, setID: row.id, actual: SetActual(reps: 12, load: 42.5), revision: row.revision) }
        try store.note(sessionID: id, text: "Private workout note")
        try test(store, root, owner)
    }

    private func snapshot(_ store: TrainingStore, privacy: WorkoutLivePrivacy? = nil) throws -> WorkoutLiveActivity.ContentState {
        WorkoutLiveCoordinator.snapshot(try #require(store.active), revision: store.liveRevision, privacy: privacy ?? visible)
    }

    private func tap(_ action: WorkoutLiveAction, _ state: WorkoutLiveActivity.ContentState,
                     on store: TrainingStore, privacy: WorkoutLivePrivacy? = nil) throws {
        try WorkoutLiveCoordinator.apply(action, expected: state, revision: state.revision, epoch: state.privacyEpoch,
                                         privacy: privacy ?? visible, commandID: UUID(), training: store)
    }

    @Test func publishedControlsLogOnceAndPersistRestBeforeAdvancing() throws {
        try setup { store, root, owner in
            let first = try snapshot(store)
            #expect(first.primary == .confirm)
            #expect(first.result == "12 reps · 42.5 lb machine")
            #expect(first.willRest)
            try tap(.confirm, first, on: store)
            #expect(throws: TrainingError.self) { try tap(.confirm, first, on: store) }
            let reopened = TrainingStore(directory: root)
            try reopened.load(profileID: owner)
            var next = try snapshot(reopened)
            #expect(next.canStartSet)
            #expect(next.ordinal == 2)
            try reopened.pauseRest(sessionID: try #require(reopened.active?.id))
            next = try snapshot(reopened)
            #expect(next.primary == .resume)
            try tap(.resume, next, on: reopened)
            try tap(.startSet, try snapshot(reopened), on: reopened)
            #expect(reopened.active?.rest == nil)
            #expect(reopened.active?.restHistory.last?.precise == true)
            let finalSet = try snapshot(reopened)
            #expect(finalSet.finalSet)
            try tap(.confirm, finalSet, on: reopened)
            #expect(reopened.active?.rest == nil)
            #expect(try snapshot(reopened).primary == .review)
            #expect(reopened.active != nil)
        }
    }

    @Test func hiddenMissingOrChangedValuesRequireInAppEditing() throws {
        try setup { store, _, _ in
            let visibleRow = try snapshot(store)
            let hidden = WorkoutLivePrivacy(showExercise: false, showLoad: false, epoch: "restricted")
            let redacted = try snapshot(store, privacy: hidden)
            #expect(redacted.primary == .edit)
            let payload = String(decoding: try JSONEncoder().encode(redacted), as: UTF8.self)
            for sensitive in ["Private", "Cable row", "42.5"] { #expect(!payload.contains(sensitive)) }
            #expect(throws: TrainingError.self) { try tap(.confirm, visibleRow, on: store, privacy: hidden) }
            #expect(throws: TrainingError.self) { try tap(.confirm, redacted, on: store, privacy: hidden) }
            let session = try #require(store.active)
            let row = session.exercises[0].sets[0]
            try store.edit(sessionID: session.id, setID: row.id, actual: SetActual(reps: 12), revision: row.revision)
            #expect(throws: TrainingError.self) { try tap(.confirm, visibleRow, on: store) }
            #expect(try snapshot(store).primary == .edit)
            #expect(store.active?.exercises[0].sets[0].confirmedAt == nil)
        }
    }

    @Test func hidingValuesRedactsBodyweightRepsAndUnloadedHoldDuration() throws {
        try setup { store, _, _ in
            let session = try #require(store.active)
            let hidden = WorkoutLivePrivacy(showExercise: true, showLoad: false, epoch: "no-values")
            let cases: [(String, LoadBasis, SetActual)] = [
                ("Push-up", .bodyweight, SetActual(reps: 11)),
                ("Hold", .timed, SetActual(seconds: 45))
            ]
            for (name, basis, actual) in cases {
                let p = PlanExercise(name: name, sets: 1, timed: basis == .timed)
                try store.add(sessionID: session.id, prescription: p, basis: basis)
                let row = try #require(store.active?.exercises.last?.sets.first)
                try store.edit(sessionID: session.id, setID: row.id, actual: actual, revision: row.revision)
                let before = try snapshot(store)
                #expect(before.primary == .confirm)
                let redacted = try snapshot(store, privacy: hidden)
                #expect(redacted.exerciseName == name)
                #expect(redacted.result == nil)
                #expect(redacted.primary == .edit)
                #expect(throws: TrainingError.self) { try tap(.confirm, redacted, on: store, privacy: hidden) }
                #expect(throws: TrainingError.self) { try tap(.confirm, before, on: store, privacy: hidden) }
                #expect(store.active?.exercises.last?.sets.first?.confirmedAt == nil)
            }
        }
    }

    @Test func restDisplayTracksPauseResumeAndResetOnStoredDates() throws {
        var instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try setup(now: { instant }) { store, _, _ in
            let session = try #require(store.active)
            try tap(.confirm, try snapshot(store), on: store)
            instant = instant.addingTimeInterval(20)
            try store.pauseRest(sessionID: session.id)
            let frozen = try snapshot(store)
            #expect(frozen.restPausedAt == instant)
            instant = instant.addingTimeInterval(12)
            try tap(.resume, frozen, on: store)
            let resumed = try snapshot(store)
            #expect(resumed.restStart == instant.addingTimeInterval(-20))
            #expect(resumed.restPausedAt == nil)
            try store.resetRest(sessionID: session.id)
            let reset = try snapshot(store)
            #expect(reset.restStart == instant)
            #expect(reset.restTarget == 90)
            #expect(store.active?.exercises[0].sets[1].confirmedAt == nil)
        }
    }

    @Test func exerciseCompletionOnlyNavigatesAndDeepLinkTargetsThatExactSet() throws {
        try setup { store, _, owner in
            let initial = try #require(store.active)
            try store.add(sessionID: initial.id, prescription: PlanExercise(name: "Second exercise", sets: 1), basis: .bodyweight)
            try store.select(sessionID: initial.id, exerciseID: initial.exercises[0].id)
            let first = try snapshot(store)
            let focusToken = try #require(store.focusToken)
            let attributes = WorkoutLiveActivity(owner: owner, generation: "original", sessionID: initial.id, focusToken: focusToken)
            let link = try #require(WorkoutLiveRoute.parse(WorkoutLiveRoute(attributes, state: first).url))
            #expect(link.sessionID == initial.id)
            #expect(link.focusToken == focusToken)
            #expect(link.exerciseID == first.exerciseID)
            #expect(link.setID == first.setID)
            try tap(.confirm, first, on: store)
            try tap(.confirm, try snapshot(store), on: store)
            let done = try snapshot(store)
            #expect(done.primary == .nextExercise)
            try tap(.nextExercise, done, on: store)
            #expect(try snapshot(store).exerciseName == "Second exercise")
            #expect(store.active?.exercises[1].sets[0].confirmedAt == nil)
            #expect(throws: TrainingError.self) { try tap(.nextExercise, done, on: store) }
        }
    }

    @Test func overdueActionUsesDurableClockAndFailedSaveLeavesControlUnchanged() throws {
        var instant = Date()
        var fail = false
        try setup(now: { instant }, beforeSave: { if fail { throw CocoaError(.fileWriteOutOfSpace) } }) { store, _, _ in
            let original = try snapshot(store)
            fail = true
            #expect(throws: CocoaError.self) { try tap(.confirm, original, on: store) }
            #expect(try snapshot(store) == original)
            fail = false
            try tap(.confirm, original, on: store)
            let resting = try snapshot(store)
            instant = instant.addingTimeInterval(150)
            #expect(try snapshot(store) == resting)
            try tap(.startSet, resting, on: store)
            #expect(store.active?.restHistory.last?.elapsed == 150)
            #expect(store.active?.exercises[0].sets[1].confirmedAt == nil)
        }
    }

    @Test func controlsWithoutAFocusTokenCannotChangeAWorkout() throws {
        try setup { store, root, owner in
            let session = try #require(store.active)
            let legacy = WorkoutLiveActivity(owner: owner, generation: "original", sessionID: session.id,
                                             isolatedRun: WorkoutLivePrivacy.isolatedRun)
            let paths = RecoveryPaths(planning: root, training: root, previous: nil)
            #expect(throws: TrainingError.self) {
                try WorkoutLiveCoordinator.validateScope(legacy, paths: paths, owner: owner, training: store)
            }
        }
    }

    @Test func oldControlsStayInvalidAfterRefocusingTheSameSession() throws {
        try setup { store, root, owner in
            let session = try #require(store.active)
            let initialToken = try #require(store.focusToken)
            let first = WorkoutLiveActivity(owner: owner, generation: "original", sessionID: session.id,
                                            focusToken: initialToken, isolatedRun: WorkoutLivePrivacy.isolatedRun)
            let paths = RecoveryPaths(planning: root, training: root, previous: nil)
            try WorkoutLiveCoordinator.validateScope(first, paths: paths, owner: owner, training: store)

            try store.startExtra(name: "Second workout")
            #expect(throws: TrainingError.self) {
                try WorkoutLiveCoordinator.validateScope(first, paths: paths, owner: owner, training: store)
            }
            try store.focus(sessionID: session.id)
            #expect(throws: TrainingError.self) {
                try WorkoutLiveCoordinator.validateScope(first, paths: paths, owner: owner, training: store)
            }
            let currentToken = try #require(store.focusToken)
            #expect(currentToken != initialToken)
            var current = first
            current.focusToken = currentToken
            try WorkoutLiveCoordinator.validateScope(current, paths: paths, owner: owner, training: store)
        }
    }

    @Test func currentControlsExpireAtTheWeekBoundary() throws {
        var instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try setup(now: { instant }) { store, root, owner in
            let session = try #require(store.active)
            let current = WorkoutLiveActivity(owner: owner, generation: "original", sessionID: session.id,
                                              focusToken: try #require(store.focusToken), isolatedRun: WorkoutLivePrivacy.isolatedRun)
            let paths = RecoveryPaths(planning: root, training: root, previous: nil)
            let state = try snapshot(store)
            try WorkoutLiveCoordinator.validateScope(current, paths: paths, owner: owner, training: store)

            instant = store.expirationDate(for: session)
            #expect(throws: TrainingError.self) {
                try WorkoutLiveCoordinator.validateScope(current, paths: paths, owner: owner, training: store)
            }
            #expect(throws: TrainingError.self) { try tap(.confirm, state, on: store) }
            #expect(store.sessions.first?.exercises[0].sets[0].confirmedAt == nil)
        }
    }

    @Test func storeReplacementRejectsOldIdentityEvenWithSameSessionAndRevision() throws {
        try setup { store, root, owner in
            let sessionID = try #require(store.active?.id)
            let original = WorkoutLiveActivity(owner: owner, generation: "original", sessionID: sessionID,
                                               focusToken: try #require(store.focusToken), isolatedRun: WorkoutLivePrivacy.isolatedRun)
            let oldPaths = RecoveryPaths(planning: root, training: root, previous: nil)
            try WorkoutLiveCoordinator.validateScope(original, paths: oldPaths, owner: owner, training: store)
            var otherRun = original
            otherRun.isolatedRun = UUID()
            #expect(throws: TrainingError.self) { try WorkoutLiveCoordinator.validateScope(otherRun, paths: oldPaths, owner: owner, training: store) }
            let previous = root.deletingLastPathComponent().appending(path: "previous.json")
            let changed = RecoveryPaths(planning: root, training: root, previous: previous)
            #expect(throws: TrainingError.self) { try WorkoutLiveCoordinator.validateScope(original, paths: changed, owner: owner, training: store) }
            #expect(throws: TrainingError.self) { try WorkoutLiveCoordinator.validateScope(original, paths: oldPaths, owner: UUID(), training: store) }
            #expect(store.active?.exercises[0].sets[0].confirmedAt == nil)
        }
    }
}
