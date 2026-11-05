import Foundation

enum Starters {
    static func general() -> WeekPlan {
        var week = WeekPlan()
        week.name = "Three-day strength"
        for (index, title, names) in [
            (0, "Lower body", ["Squat", "Hip hinge"]),
            (2, "Upper body", ["Push-up", "Row"]),
            (4, "Full body", ["Split squat", "Overhead press"])
        ] {
            week.days[index].name = title
            week.days[index].exercises = names.map { PlanExercise(name: $0) }
        }
        return week
    }

    #if WEEKFORM_DEVELOPMENT
    static func local() throws -> WeekPlan? {
        guard let url = Bundle.main.url(forResource: "LocalStarter", withExtension: "json") else { return nil }
        let plan = try JSONDecoder().decode(WeekPlan.self, from: Data(contentsOf: url))
        guard plan.days.count == 7 else { throw CocoaError(.fileReadCorruptFile) }
        return plan.independentCopy()
    }
    #endif
}
