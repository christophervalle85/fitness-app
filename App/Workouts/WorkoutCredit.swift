import Foundation

struct WorkoutCredit {
    let completed: Int
    let total: Int
    private let skipped: Bool

    var isFulfilled: Bool { !skipped && total > 0 && completed == total }

    init(for occurrence: TrainingOccurrence, linkedSessions: [TrainingSession]) {
        skipped = occurrence.skipped
        if let goal = occurrence.cardioGoalSeconds {
            total = goal
            completed = min(goal, Self.cardioSeconds(in: linkedSessions.compactMap(\.cardio)))
        } else {
            let required = Self.plannedSetIDs(for: occurrence)
            total = required.count
            completed = required.intersection(Self.creditedSetIDs(in: linkedSessions)).count
        }
    }

    static func plannedSetIDs(for occurrence: TrainingOccurrence) -> Set<UUID> {
        Set(occurrence.plannedSets.values.joined())
    }

    static func creditedSetIDs(in sessions: [TrainingSession]) -> Set<UUID> {
        Set(sessions.flatMap(\.exercises).flatMap(\.sets).compactMap { set in
            guard set.confirmedAt != nil, set.warmup != true else { return nil }
            return set.plannedID
        })
    }

    static func cardioSeconds(in results: [CardioResult]) -> Int {
        results.reduce(0) { seconds, result in
            seconds + min(Int.max - seconds, max(0, result.seconds))
        }
    }
}
