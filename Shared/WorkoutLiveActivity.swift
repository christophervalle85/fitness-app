import ActivityKit
import AppIntents
import Foundation

enum WorkoutLiveAction: String, Codable, Hashable {
    case confirm, startSet, nextExercise, resume, edit, review
}

struct WorkoutLiveActivity: ActivityAttributes {
    let owner: UUID
    let generation: String
    let sessionID: UUID
    var focusToken: UUID?
    var isolatedRun: UUID?

    struct ContentState: Codable, Hashable {
        var revision: Int
        var privacyEpoch: String
        var exerciseID: UUID?
        var setID: UUID?
        var exerciseName: String?
        var result: String?
        var ordinal: Int?
        var warmup = false
        var primary: WorkoutLiveAction = .edit
        var finalSet = false
        var willRest = false
        var restStart: Date?
        var restPausedAt: Date?
        var restTarget: Int?
        var canStartSet: Bool { restStart != nil && restPausedAt == nil && setID != nil }
    }
}

struct WorkoutLiveRoute {
    let owner: UUID
    let generation: String
    let sessionID: UUID
    let focusToken: UUID?
    let exerciseID: UUID?
    let setID: UUID?
    let review: Bool

    init(_ activity: WorkoutLiveActivity, state: WorkoutLiveActivity.ContentState) {
        owner = activity.owner
        generation = activity.generation
        sessionID = activity.sessionID
        focusToken = activity.focusToken
        exerciseID = state.exerciseID
        setID = state.setID
        review = state.primary == .review
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = "weekform"
        parts.host = "workout"
        parts.path = "/" + sessionID.uuidString
        var items = [URLQueryItem(name: "owner", value: owner.uuidString), URLQueryItem(name: "generation", value: generation)]
        if let focusToken { items.append(.init(name: "focus", value: focusToken.uuidString)) }
        if let exerciseID { items.append(.init(name: "exercise", value: exerciseID.uuidString)) }
        if let setID { items.append(.init(name: "set", value: setID.uuidString)) }
        if review { items.append(.init(name: "review", value: "1")) }
        parts.queryItems = items
        return parts.url!
    }

    static func parse(_ url: URL) -> Self? {
        guard url.scheme == "weekform", url.host == "workout", url.pathComponents.count == 2,
              let session = UUID(uuidString: url.lastPathComponent),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let args = parts.queryItems ?? []
        func value(_ key: String) -> String? { args.first { $0.name == key }?.value }
        guard Set(args.map(\.name)).count == args.count, let owner = value("owner").flatMap(UUID.init(uuidString:)),
              let generation = value("generation"), generation == "original" || UUID(uuidString: generation) != nil else { return nil }
        let focus = value("focus").flatMap(UUID.init(uuidString:))
        guard !args.contains(where: { $0.name == "focus" }) || focus != nil else { return nil }
        let exercise = value("exercise").flatMap(UUID.init(uuidString:))
        let set = value("set").flatMap(UUID.init(uuidString:))
        guard value("exercise") == nil || exercise != nil, value("set") == nil || (set != nil && exercise != nil) else { return nil }
        let activity = WorkoutLiveActivity(owner: owner, generation: generation, sessionID: session, focusToken: focus)
        return Self(activity, state: .init(revision: 0, privacyEpoch: "", exerciseID: exercise, setID: set,
                                           primary: value("review") == "1" ? .review : .edit))
    }
}

struct WorkoutLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update active workout"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Activity") var activityID: String
    @Parameter(title: "Action") var action: String
    @Parameter(title: "Workout revision") var revision: Int
    @Parameter(title: "Privacy revision") var privacyEpoch: String

    init() {}
    init(_ action: WorkoutLiveAction, activityID: String, state: WorkoutLiveActivity.ContentState) {
        self.action = action.rawValue
        self.activityID = activityID
        revision = state.revision
        privacyEpoch = state.privacyEpoch
    }

    func perform() async throws -> some IntentResult {
        try await dispatch()
        return .result()
    }

    private func dispatch() async throws {
        #if WEEKFORM_APP
        guard let action = WorkoutLiveAction(rawValue: action) else { throw TrainingError("Open Weekform to continue.") }
        try await WorkoutLiveCoordinator.perform(activityID: activityID, action: action, revision: revision, privacyEpoch: privacyEpoch)
        #else
        // LiveActivityIntent is performed by the containing app. Never create a
        // second local workout store if the system can't open that process.
        throw CocoaError(.fileReadNoPermission)
        #endif
    }
}
