import Foundation

enum PlanStartTargetError: LocalizedError {
    case changed
    case pastWeek

    var errorDescription: String? {
        switch self {
        case .changed: "The selected workout changed. Choose it again in Plan."
        case .pastWeek: "This week is read-only. Choose a current or upcoming week."
        }
    }
}

enum PlanStartTarget {
    case template(WeekPlan, Date)
    case occurrence(UUID)
    case extra
    case cardio

    @MainActor @discardableResult
    func start(planner: PlanningStore, training: TrainingStore, expectedDay: CivilTrainingDay) throws -> UUID {
        guard !training.isPastWeek(expectedDay.date) else { throw PlanStartTargetError.pastWeek }
        switch self {
        case .template(let snapshot, let date):
            let day = CivilTrainingDay(date)
            let index = day.mondayIndex
            guard day == expectedDay,
                  let plan = planner.plans.first(where: { $0.id == snapshot.id && !$0.archived }),
                  snapshot.days.indices.contains(index), plan.days.indices.contains(index),
                  snapshot.days[index] == plan.days[index], snapshot.restSeconds == plan.restSeconds else {
                throw PlanStartTargetError.changed
            }
            if let dated = training.occurrences.first(where: { $0.planID == plan.id && $0.sourceDay == day }),
               dated.scheduledDay != day || dated.day != snapshot.days[index] || dated.restSeconds != snapshot.restSeconds {
                throw PlanStartTargetError.changed
            }
            return try training.startPlanned(plan: plan, date: date)
        case .occurrence(let id):
            guard training.occurrences.contains(where: { $0.id == id && $0.scheduledDay == expectedDay }) else {
                throw PlanStartTargetError.changed
            }
            return try training.startOccurrence(id)
        case .extra:
            return try training.startExtra(name: "Extra workout")
        case .cardio:
            return try training.startCardio(name: "Cardio")
        }
    }
}
