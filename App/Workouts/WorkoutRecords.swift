import Foundation

enum WeightUnits {
    static let kilogramsPerPound = 0.45359237

    static func convert(_ value: Double, from source: String, to destination: String) -> Double {
        if source == destination { return value }
        switch (source, destination) {
        case ("lb", "kg"): return value * kilogramsPerPound
        case ("kg", "lb"): return value / kilogramsPerPound
        default: return .nan
        }
    }

    static func equal(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(lhs.ulp, rhs.ulp) * 8
    }
}

extension SetActual {
    func converted(to target: String) -> SetActual {
        guard unit != target else { return self }
        var value = self
        value.load = load.map { WeightUnits.convert($0, from: unit, to: target) }
        value.rightLoad = rightLoad.map { WeightUnits.convert($0, from: unit, to: target) }
        value.unit = target
        return value
    }
}

struct RecordIdentity: Hashable {
    let variant: UUID
    let name: String
    let convention: String
    let basis: LoadBasis
    let machineProfile: UUID?
    let side: String?

    init(_ exercise: TrainingExercise, side: String? = nil) {
        let p = exercise.prescription
        variant = p.variantID ?? p.id
        name = p.name
        convention = p.convention
        basis = exercise.basis
        // Legacy rows have no equipment-profile ID. Within those rows the
        // original prescription is the narrowest repeatable machine identity.
        machineProfile = [.machine, .assisted].contains(exercise.basis) ? p.id : nil
        self.side = side
    }
}

extension TrainingSession {
    var isArchivedDraft: Bool {
        finishedAt != nil && partial && (closedAtWeekBoundary == true || hasSavedContent) && cardio == nil &&
            !exercises.contains { $0.sets.contains { $0.confirmedAt != nil } }
    }
}
