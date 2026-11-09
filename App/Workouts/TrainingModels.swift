import Foundation

enum LoadBasis: String, Codable, CaseIterable {
    case external, barbell, dumbbell, machine, bodyweight, added, assisted, unilateral, timed

    init(_ exercise: PlanExercise) {
        let convention = exercise.convention.lowercased()
        if exercise.timed { self = .timed }
        else if convention.contains("side") || convention.contains("unilateral") { self = .unilateral }
        else if convention.contains("assist") { self = .assisted }
        else if convention.contains("added") || convention.contains("weighted body") { self = .added }
        else if convention.contains("bodyweight") || convention.contains("body weight") { self = .bodyweight }
        else if convention.contains("barbell") { self = .barbell }
        else if convention.contains("dumbbell") { self = .dumbbell }
        else if convention.contains("machine") { self = .machine }
        else { self = .external }
    }
}

struct SetActual: Codable, Equatable {
    var reps: Int?
    var seconds: Int?
    var load: Double?
    var rightReps: Int?
    var rightLoad: Double?
    var unit = "lb"

    func validate(for basis: LoadBasis) throws {
        guard ["lb", "kg"].contains(unit),
              [load, rightLoad].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 })
        else { throw TrainingError("Enter a valid weight in lb or kg.") }
        if basis == .timed {
            guard let seconds, seconds > 0 else { throw TrainingError("Enter the seconds you held this set.") }
        } else {
            guard let reps, reps > 0 else { throw TrainingError("Enter the reps you completed.") }
            if basis != .bodyweight && load == nil {
                throw TrainingError(basis == .assisted ? "Enter the assistance used." : "Enter the weight you used.")
            }
            if basis == .unilateral && ((rightReps ?? 0) <= 0 || rightLoad == nil) {
                throw TrainingError("Enter the reps and weight for both sides.")
            }
        }
        if basis != .unilateral && (rightLoad != nil || rightReps != nil) {
            throw TrainingError("Use per-side logging for separate side values.")
        }
        if (basis == .timed && reps != nil) || (basis != .timed && seconds != nil) || (basis == .bodyweight && load != nil) {
            throw TrainingError("Check that the values match how this exercise is logged.")
        }
    }
}

struct TrainingSet: Codable, Identifiable, Equatable {
    var id = UUID()
    var plannedID: UUID?
    var ordinal: Int?
    var warmup: Bool?
    var optional: Bool?
    var actual = SetActual()
    var confirmedAt: Date?
    var revision = 0
    var previousAt: Date?
}

struct TrainingExercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var prescription: PlanExercise
    var basis: LoadBasis
    var sets: [TrainingSet]
    var restSeconds: Int?
    var replacedPrescription: PlanExercise?
}

extension TrainingExercise {
    func suggestedActual(for set: TrainingSet) -> SetActual? {
        guard set.revision == 0, set.confirmedAt == nil else { return nil }
        let last = sets.filter {
            $0.confirmedAt != nil && ($0.warmup == true) == (set.warmup == true)
        }.max { ($0.confirmedAt ?? .distantPast) < ($1.confirmedAt ?? .distantPast) }
        guard let actual = last?.actual.converted(to: set.actual.unit),
              (try? actual.validate(for: basis)) != nil else { return nil }
        return actual
    }

    func matchesPlannedItem(_ target: PlanExercise) -> Bool {
        guard basis == LoadBasis(target) else { return false }
        if let variant = prescription.variantID, let targetVariant = target.variantID {
            return variant == targetVariant
        }
        if (prescription.variantID ?? prescription.id) == (target.variantID ?? target.id) { return true }
        return prescription.convention == target.convention &&
            prescription.name.compare(target.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct TrainingRest: Codable, Equatable {
    var sourceSetID: UUID
    var startedAt: Date
    var targetSeconds: Int
    var pausedAt: Date?
    var pausedSeconds: TimeInterval = 0
    var measuredBeforeReset: TimeInterval?

    func elapsed(at date: Date) -> TimeInterval {
        max(0, (pausedAt ?? date).timeIntervalSince(startedAt) - pausedSeconds)
    }
}

struct RestMeasurement: Codable, Identifiable, Equatable {
    var id = UUID()
    let interval: TrainingRest
    let endedAt: Date
    let precise: Bool // Only an explicit Start set measures the end of rest.
    var elapsed: TimeInterval { (interval.measuredBeforeReset ?? 0) + interval.elapsed(at: endedAt) }
}

struct CardioResult: Codable, Equatable {
    var seconds: Int
    var distance: Double?
    var unit = "km"
    var notes = ""

    func validate() throws {
        guard seconds > 0 else { throw TrainingError("Enter the completed duration.") }
        if let distance, !distance.isFinite || distance < 0 || !["km", "mi", "m"].contains(unit) {
            throw TrainingError("Enter a valid distance and unit.")
        }
    }
}

struct CivilTrainingDay: Codable, Equatable {
    let year: Int
    let month: Int
    let day: Int

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    init(_ date: Date) {
        let calendar = Self.calendar
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }

    var date: Date {
        // Noon avoids a midnight that was skipped or repeated by a DST change.
        Self.calendar.date(from: .init(year: year, month: month, day: day, hour: 12))!
    }

    var mondayIndex: Int { (Self.calendar.component(.weekday, from: date) + 5) % 7 }

    var nextMonday: Date {
        let calendar = Self.calendar
        let monday = calendar.date(byAdding: .day, value: 7 - mondayIndex, to: date)!
        return calendar.startOfDay(for: monday)
    }
}

struct TrainingOccurrence: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sourceDay: CivilTrainingDay
    var scheduledDay: CivilTrainingDay
    var planID: UUID?
    var day: PlanDay?
    var restSeconds: Int?
    var plannedSets: [UUID: [UUID]] = [:]
    var cardioGoalSeconds: Int?
    var skipped = false
    var date: Date { scheduledDay.date }
    var originalDate: Date { sourceDay.date }
}

struct CardioReceipt: Codable, Equatable {
    let result: CardioResult
    let revision: Int
}

struct ConfirmationReceipt: Codable, Equatable {
    let setID: UUID
    let actual: SetActual
    let expectedRevision: Int
}

struct TrainingTimerUndo: Codable, Equatable {
    let setID: UUID
    var previous: TrainingRest?
    let previousExerciseID: UUID?
    let measurementID: UUID?
}

struct TrainingSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var startedAt: Date
    var performedDay: CivilTrainingDay
    var finishedAt: Date?
    var partial = false
    var closedAtWeekBoundary: Bool?
    var occurrenceID: UUID?
    var isCardio = false
    var cardioDraft: CardioResult?
    var cardio: CardioResult?
    var cardioRecordedAt: Date?
    var cardioVersion: Int?
    var cardioReceipts: [UUID: CardioReceipt]?
    var cardioRevision: Int { cardioVersion ?? 0 }
    var exercises: [TrainingExercise] = []
    var notes = ""
    var rest: TrainingRest?
    var restHistory: [RestMeasurement] = []
    var currentExerciseID: UUID?
    var receipts: [UUID: ConfirmationReceipt] = [:]
    var timerUndo: TrainingTimerUndo?
    var workoutDetailsChanged: Bool?

    var hasSavedContent: Bool {
        if !notes.isEmpty || cardio != nil || cardioDraft != nil || workoutDetailsChanged == true || !restHistory.isEmpty {
            return true
        }
        return exercises.contains { exercise in
            exercise.replacedPrescription != nil || exercise.sets.contains {
                $0.confirmedAt != nil || $0.revision > 0 || $0.plannedID == nil
            }
        }
    }

    var lastRecordedAt: Date {
        let lastSet = exercises.flatMap(\.sets).compactMap(\.confirmedAt).max() ?? startedAt
        return max(startedAt, lastSet, cardioRecordedAt ?? startedAt)
    }
}

struct TrainingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
