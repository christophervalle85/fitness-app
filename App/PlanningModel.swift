import Foundation

struct PlanExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var variantID: UUID?
    var name = ""
    var choices: [String] = []
    var sets = 3
    var low = 10
    var high = 12
    var timed = false
    var convention = ""
    var notes = ""
    var startingLoad: Double?
    var loadUnit = "lb"
}

struct PlanDay: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var exercises: [PlanExercise] = []
    var cardioGoalSeconds: Int?

    var isWorkout: Bool { cardioGoalSeconds != nil || !exercises.isEmpty }
}

struct WeekPlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var days = (0..<7).map { _ in PlanDay() } // Monday first
    var restSeconds: Int?
    var notes = ""
    var archived = false

    func independentCopy() -> WeekPlan {
        var copy = self
        copy.id = UUID()
        copy.archived = false
        for day in copy.days.indices {
            copy.days[day].id = UUID()
            for exercise in copy.days[day].exercises.indices {
                let source = days[day].exercises[exercise]
                copy.days[day].exercises[exercise].variantID = source.variantID ?? source.id
                copy.days[day].exercises[exercise].id = UUID()
            }
        }
        return copy
    }

    var validationMessage: String? {
        guard !name.trimmed.isEmpty else { return "Give your routine a name." }
        guard days.count == 7 else { return "Schedule seven days, including rest days." }
        if let restSeconds, restSeconds < 1 { return "Choose a positive rest duration or turn off the timer." }
        guard days.contains(where: \.isWorkout) else { return "Add at least one workout to your week." }

        var identifiers = Set<UUID>()
        for (index, day) in days.enumerated() {
            let weekday = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][index]
            guard identifiers.insert(day.id).inserted else { return "Each scheduled day needs its own identity." }
            if let seconds = day.cardioGoalSeconds, seconds <= 0 || !day.exercises.isEmpty { return "Give cardio a positive duration and its own workout day." }
            if !day.isWorkout && !day.name.trimmed.isEmpty { return "Add an exercise to \(weekday) or clear its workout name for a rest day." }
            if day.isWorkout && day.name.trimmed.isEmpty { return "Name the workout on \(weekday)." }
            for (offset, exercise) in day.exercises.enumerated() {
                guard identifiers.insert(exercise.id).inserted else { return "Each scheduled exercise needs its own identity." }
                guard !exercise.name.trimmed.isEmpty else {
                    return "Choose an exercise or enter a custom name for exercise \(offset + 1) on \(weekday)."
                }
                guard exercise.sets > 0, exercise.low > 0, exercise.high >= exercise.low else {
                    return "Check the sets and target range for \(exercise.name) on \(weekday)."
                }
                if let load = exercise.startingLoad,
                   !load.isFinite || load < 0 || !["lb", "kg"].contains(exercise.loadUnit) {
                    return "Enter a valid starting load in lb or kg for \(exercise.name)."
                }
            }
        }
        return nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
