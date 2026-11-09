import Foundation

struct PlanCardState {
    enum Action: Equatable {
        case startTemplate
        case startOccurrence
        case continueWorkout
        case resume(UUID)

        var title: String {
            switch self {
            case .startTemplate, .startOccurrence: "Start"
            case .continueWorkout: "Continue"
            case .resume: "Resume"
            }
        }

        var accessibilityID: String {
            switch self {
            case .startTemplate: "startPlanned"
            case .startOccurrence, .continueWorkout: "startOccurrence"
            case .resume: "resumeWorkout"
            }
        }
    }

    let status: String
    let action: Action?
    let canMoveOrSkip: Bool
    let canReview: Bool

    init(state: PlanWorkoutState, openSessionID: UUID?, isPastWeek: Bool) {
        let partial = state == .inProgress && openSessionID == nil
        let available = !isPastWeek && (state == .notStarted || state == .inProgress)
        status = partial ? "Partial" : state.rawValue
        canMoveOrSkip = available && openSessionID == nil
        canReview = state == .finished
        if !available { action = nil }
        else if let openSessionID { action = .resume(openSessionID) }
        else { action = partial ? .continueWorkout : .startOccurrence }
    }
}
