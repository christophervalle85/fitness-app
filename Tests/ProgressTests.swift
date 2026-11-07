import Foundation
import Testing
@testable import Weekform

@MainActor
struct ProgressTests {
    private let monday = Calendar.current.date(from: .init(year: 2026, month: 3, day: 2, hour: 12))!

    private func row(_ reps: Int, _ load: Double, unit: String = "kg", on date: Date,
                     ordinal: Int = 1, planned: UUID? = nil, warmup: Bool = false) -> TrainingSet {
        TrainingSet(plannedID: planned, ordinal: ordinal, warmup: warmup,
                    actual: SetActual(reps: reps, load: load, unit: unit), confirmedAt: date)
    }

    private func session(_ exercises: [TrainingExercise], on date: Date, occurrence: UUID? = nil) -> TrainingSession {
        TrainingSession(name: "Training", startedAt: date, performedDay: CivilTrainingDay(date),
                        finishedAt: date.addingTimeInterval(100), occurrenceID: occurrence, exercises: exercises)
    }

    @Test func unitEquivalentRecordsUseActualDateAndSeparateProfilesAndSides() throws {
        let p = PlanExercise(variantID: UUID(), name: "Row", sets: 2, convention: "Machine setting")
        let later = monday.addingTimeInterval(90)
        let early = row(12, 100, unit: "lb", on: monday)
        let twice = row(12, WeightUnits.convert(100, from: "lb", to: "kg"), on: later, ordinal: 2)
        var warmup = row(8, 200, on: later)
        warmup.warmup = true
        var draft = row(8, 300, on: later)
        draft.confirmedAt = nil
        let common = TrainingExercise(prescription: p, basis: .machine, sets: [twice, warmup, draft, early])
        var other = common
        other.id = UUID()
        other.prescription.id = UUID()
        other.sets = [row(10, 400, on: later)]
        var bilateral = common
        bilateral.id = UUID()
        bilateral.basis = .unilateral
        bilateral.sets = [TrainingSet(actual: SetActual(reps: 6, load: 10, rightReps: 8, rightLoad: 12, unit: "kg"), confirmedAt: monday)]
        let metrics = ProgressMetrics(sessions: [session([common, other, bilateral], on: monday)], occurrences: [])
        #expect(metrics.records.count == 4)
        let record = try #require(metrics.records.first { $0.id.machineProfile == p.id })
        #expect(record.trend.map(\.id) == [early.id, twice.id])
        #expect(record.heaviest?.id == early.id)
        #expect(record.repBests.map(\.id) == [early.id])
        #expect(metrics.records.first { $0.side == "Left" }?.heaviest?.kg == 10)
        #expect(metrics.records.first { $0.side == "Right" }?.heaviest?.reps == 8)
    }

    @Test func independentRoutineCopySharesVariantRecordsButRenamedCustomExerciseDoesNot() {
        var plan = WeekPlan(name: "Original")
        plan.days[0] = PlanDay(name: "Upper", exercises: [PlanExercise(name: "Curl")])
        let original = plan.days[0].exercises[0]
        let copy = plan.independentCopy().days[0].exercises[0]
        var renamed = copy
        renamed.name = "Reverse curl"
        let exercises = [original, copy, renamed].enumerated().map { index, p in
            TrainingExercise(prescription: p, basis: .barbell,
                             sets: [row(10, Double(index + 1), on: monday.addingTimeInterval(Double(index)))])
        }
        let result = ProgressMetrics(sessions: [session(exercises, on: monday)], occurrences: [])
        #expect(result.records.count == 2)
        #expect(result.records.first { $0.name == "Curl" }?.trend.count == 2)
        #expect(result.records.first { $0.name == "Curl" }?.heaviest?.kg == 2)
        #expect(result.records.first { $0.name == "Reverse curl" }?.trend.count == 1)
    }

    @Test func progressionRequiresEntireSnapshotInOneSessionAtEquivalentLoad() {
        let p = PlanExercise(name: "Press", sets: 3, low: 8, high: 12)
        let day = PlanDay(name: "Upper", exercises: [p])
        let slots = (0..<3).map { _ in UUID() }
        let occurrence = TrainingOccurrence(name: "Upper", sourceDay: CivilTrainingDay(monday),
                                            scheduledDay: CivilTrainingDay(monday), day: day, plannedSets: [p.id: slots])
        let rows = slots.enumerated().map { i, id in
            row(12, i == 0 ? 100 : WeightUnits.convert(100, from: "lb", to: "kg"),
                unit: i == 0 ? "lb" : "kg", on: monday, ordinal: i + 1, planned: id)
        }
        func calculated(_ groups: [[TrainingSet]]) -> ProgressMetrics {
            let sessions = groups.enumerated().map { index, rows in
                session([TrainingExercise(prescription: p, basis: .barbell, sets: rows)],
                        on: monday.addingTimeInterval(Double(index)), occurrence: occurrence.id)
            }
            return ProgressMetrics(sessions: sessions, occurrences: [occurrence], asOf: monday)
        }
        #expect(calculated([rows]).suggestions.count == 1)
        #expect(calculated([[rows[0]], [rows[1], rows[2]]]).suggestions.isEmpty)
        var bonus = rows[2]
        bonus.id = UUID()
        bonus.optional = true
        bonus.plannedID = nil
        #expect(calculated([[rows[0], rows[1], bonus]]).suggestions.isEmpty)
        var changed = rows
        changed[1].actual.load = 50
        #expect(calculated([changed]).suggestions.isEmpty)
        changed = rows
        changed[1].confirmedAt = nil
        #expect(calculated([changed]).suggestions.isEmpty)
    }

    @Test func adherenceIncludesMissedCurrentWeekAndDoesNotDoubleCountMoveOrExtra() {
        var template = WeekPlan(name: "Weekly")
        template.days[0] = PlanDay(name: "Monday cardio", cardioGoalSeconds: 120)
        template.days[1] = PlanDay(name: "Tuesday cardio", cardioGoalSeconds: 120)
        let wednesday = Calendar.current.date(byAdding: .day, value: 2, to: monday)!
        let moved = TrainingOccurrence(name: "Moved", sourceDay: CivilTrainingDay(monday), scheduledDay: CivilTrainingDay(wednesday),
                                       planID: template.id, cardioGoalSeconds: 120)
        var planned = session([], on: monday, occurrence: moved.id)
        planned.isCardio = true
        planned.cardio = CardioResult(seconds: 120)
        var extra = planned
        extra.id = UUID()
        extra.occurrenceID = nil
        let result = ProgressMetrics(sessions: [planned, extra], occurrences: [moved], activePlan: template, asOf: wednesday)
        #expect(result.adherence.fulfilled == 1)
        #expect(result.adherence.scheduled == 2)
        #expect(result.knownAdherence.scheduled == 1)
        #expect(result.sessionCount == 2)
        #expect(result.cardioCount == 2)
        #expect(result.cardioSeconds == 240)
    }

    @Test func activityUsesSevenCivilDaysAndKeepsOlderSessionsInHistory() throws {
        let calendar = Calendar.current
        let today = try #require(calendar.date(byAdding: .day, value: 8, to: monday))
        let first = try #require(calendar.date(byAdding: .day, value: -6, to: today))
        let previous = try #require(calendar.date(byAdding: .day, value: -7, to: today))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        var older = session([], on: previous)
        older.isCardio = true
        older.cardio = CardioResult(seconds: 600)
        var corrected = session([], on: previous)
        corrected.performedDay = CivilTrainingDay(first)
        corrected.isCardio = true
        corrected.cardio = CardioResult(seconds: 120)
        var partial = session([], on: today)
        partial.partial = true
        var open = session([], on: today)
        open.finishedAt = nil
        let future = session([], on: tomorrow)

        let metrics = ProgressMetrics(sessions: [older, corrected, partial, open, future], occurrences: [], asOf: today)
        #expect(metrics.activityDays.count == 7)
        #expect(metrics.activityDays.first.map { CivilTrainingDay($0.date) } == CivilTrainingDay(first))
        #expect(metrics.activityDays.first?.sessions.map(\.id) == [corrected.id])
        #expect(metrics.activityDays.last?.sessions.map(\.id) == [partial.id])
        #expect(metrics.sessionCount == 2)
        #expect(metrics.cardioCount == 1)
        #expect(metrics.cardioSeconds == 120)
        #expect(Set(metrics.history.map(\.id)) == [older.id, corrected.id, partial.id, future.id])
    }

    @Test func assignedExtraMustMeetOriginalPrescriptionAndUnitSuggestionsPreservePhysicalLoad() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TrainingStore(directory: path, now: { monday })
        try store.load(profileID: UUID())
        var template = WeekPlan(name: "Monday")
        let variant = UUID()
        let intended = PlanExercise(variantID: variant, name: "Curl", sets: 1, low: 10, high: 12)
        template.days[0] = PlanDay(name: "Upper", exercises: [intended])
        try store.startExtra(name: "Extra")
        let extraID = try #require(store.active?.id)
        let easier = PlanExercise(variantID: variant, name: "Curl", sets: 1, low: 4, high: 6)
        try store.add(sessionID: extraID, prescription: easier, basis: .external)
        let first = try #require(store.active?.exercises.first?.sets.first)
        try store.confirm(sessionID: extraID, setID: first.id, actual: SetActual(reps: 6, load: 100, unit: "lb"),
                          revision: 0, commandID: UUID())
        try store.finish(sessionID: extraID, partial: false)
        try store.assign(sessionID: extraID, plan: template, date: monday, setID: first.id, exerciseID: intended.id, slot: 0)
        #expect(ProgressMetrics(sessions: store.sessions, occurrences: store.occurrences).suggestions.isEmpty)

        try store.startExtra(name: "Metric day")
        let nextID = try #require(store.active?.id)
        var metric = easier
        metric.loadUnit = "kg"
        try store.add(sessionID: nextID, prescription: metric, basis: .external)
        let suggested = try #require(store.active?.exercises.first?.sets.first)
        #expect(suggested.actual.reps == 6)
        #expect(suggested.actual.unit == "kg")
        #expect(suggested.actual.load == WeightUnits.convert(100, from: "lb", to: "kg"))
        #expect(suggested.confirmedAt == nil)
    }

    @Test func assistedTimedAndBodyweightRetainHistoryWithoutLoadProgression() {
        let p = PlanExercise(name: "Test", sets: 1)
        let rows: [(LoadBasis, SetActual)] = [
            (.assisted, SetActual(reps: 12, load: 20)), (.timed, SetActual(seconds: 45, load: 10)),
            (.bodyweight, SetActual(reps: 12))
        ]
        let exercises = rows.map { basis, values in
            TrainingExercise(prescription: p, basis: basis, sets: [TrainingSet(ordinal: 1, actual: values, confirmedAt: monday)])
        }
        let metrics = ProgressMetrics(sessions: [session(exercises, on: monday)], occurrences: [])
        #expect(metrics.suggestions.isEmpty)
        #expect(metrics.records.count == 3)
        #expect(metrics.records.compactMap(\.heaviest).isEmpty)
        #expect(metrics.records.first { $0.basis == .timed }?.trend.first?.seconds == 45)
    }

    @Test func saturatedStoredOrdinalAndRevisionFailWithoutChangingWorkout() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let planner = PlanningStore(directory: folder.appending(path: "plans"))
        try planner.load()
        let store = TrainingStore(directory: folder.appending(path: "training"))
        var backup = try WorkoutBackup(planner, store)
        let row = TrainingSet(ordinal: Int.max, revision: Int.max - 1)
        let exercise = TrainingExercise(prescription: PlanExercise(name: "Press"), basis: .external, sets: [row])
        let workout = TrainingSession(name: "Legacy workout", startedAt: monday,
                                      performedDay: CivilTrainingDay(monday), exercises: [exercise])
        backup.sessions = [workout]
        // Exercise the writer independently of the incoming-file validator.
        try store.stage(backup)
        try store.load(profileID: backup.owner)
        #expect(throws: TrainingError.self) { try store.addSet(sessionID: workout.id, exerciseID: exercise.id, warmup: false) }
        #expect(throws: TrainingError.self) {
            try store.edit(sessionID: workout.id, setID: row.id, actual: SetActual(reps: 5), revision: row.revision)
        }
        #expect(store.active == workout)
    }

    @Test func correctionsBackdatingAndUndoRecalculateWithoutChangingSessionIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var instant = monday
        let store = TrainingStore(directory: folder, now: { instant })
        try store.load(profileID: UUID())
        var routine = WeekPlan(name: "Plan")
        let exercise = PlanExercise(name: "Press", sets: 1, low: 10, high: 12)
        routine.days[0] = PlanDay(name: "Workout", exercises: [exercise])
        try store.startPlanned(plan: routine, date: monday)
        let active = try #require(store.active)
        let set = active.exercises[0].sets[0]
        instant = monday.addingTimeInterval(1)
        try store.confirm(sessionID: active.id, setID: set.id, actual: SetActual(reps: 12, load: 100), revision: 0, commandID: UUID())
        instant = monday.addingTimeInterval(5)
        try store.finish(sessionID: active.id, partial: false)
        func progress() -> ProgressMetrics { ProgressMetrics(sessions: store.sessions, occurrences: store.occurrences, asOf: monday) }
        #expect(progress().suggestions.count == 1)
        let occurrenceID = active.occurrenceID
        try store.correct(sessionID: active.id, setID: set.id, actual: SetActual(reps: 11, load: 90),
                          performedAt: monday.addingTimeInterval(2), revision: 1)
        #expect(progress().suggestions.isEmpty)
        #expect(progress().records.first?.heaviest?.reps == 11)
        let dayBefore = monday.addingTimeInterval(-86400)
        try store.redate(sessionID: active.id, startedAt: dayBefore)
        #expect(progress().records.first?.heaviest?.date == dayBefore.addingTimeInterval(2))
        #expect(store.sessions.first?.occurrenceID == occurrenceID)
        try store.undo(sessionID: active.id, setID: set.id, revision: 3)
        #expect(progress().records.isEmpty)
        #expect(progress().adherence.fulfilled == 0)
    }
}
