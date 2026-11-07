import Foundation
import Testing
@testable import Weekform

@MainActor
struct PlanActionsTests {
    private var monday: Date {
        Calendar(identifier: .gregorian).date(from: .init(year: 2026, month: 3, day: 2, hour: 12))!
    }

    private var nextDay: Date { Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: monday)! }

    private var week: WeekPlan {
        var plan = WeekPlan(name: "Weekly")
        plan.days[0] = PlanDay(name: "Upper", exercises: [PlanExercise(name: "Curl", sets: 2)])
        return plan
    }

    private func withDirectory(_ run: (URL) throws -> Void) throws {
        let path = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try run(path)
    }

    @Test func firstMoveAndSkipCommitOnlyOnceAndFailedSaveLeavesNoSnapshot() throws {
        try withDirectory { directory in
            let owner = UUID()
            var fail = true
            var writes = 0
            let store = TrainingStore(directory: directory, beforeSave: {
                writes += 1
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
            })
            try store.load(profileID: owner)
            let routine = week
            #expect(throws: CocoaError.self) { try store.move(plan: routine, date: monday, to: nextDay) }
            #expect(throws: CocoaError.self) { try store.skip(plan: routine, date: monday) }
            #expect(store.occurrences.isEmpty)
            let fresh = TrainingStore(directory: directory)
            try fresh.load(profileID: owner)
            #expect(fresh.occurrences.isEmpty)
            fail = false
            writes = 0
            try store.move(plan: routine, date: monday, to: monday)
            #expect(writes == 0)
            try store.move(plan: routine, date: monday, to: nextDay)
            try store.move(plan: routine, date: monday, to: nextDay)
            #expect(writes == 1)
            let moved = try #require(store.occurrences.first)
            #expect(store.isOriginal(moved, on: monday))
            #expect(store.isScheduled(moved, on: nextDay))
            #expect(throws: TrainingError.self) { try store.skip(plan: routine, date: monday) }
            let nextWeek = Calendar(identifier: .gregorian).date(byAdding: .day, value: 7, to: monday)!
            try store.skip(plan: routine, date: nextWeek)
            try store.skip(plan: routine, date: nextWeek)
            #expect(writes == 2)
            #expect(store.occurrences.filter(\.skipped).count == 1)
        }
    }

    @Test func moveKeepsSnapshotConfirmedCreditsAndOpenSessionOwnership() throws {
        try withDirectory { directory in
            let store = TrainingStore(directory: directory)
            try store.load(profileID: UUID())
            var routine = week
            try store.startPlanned(plan: routine, date: monday)
            let session = try #require(store.active)
            let exercise = try #require(session.exercises.first)
            let row = try #require(exercise.sets.first)
            try store.confirm(sessionID: session.id, setID: row.id, actual: SetActual(reps: 10, load: 15),
                              revision: row.revision, commandID: UUID())
            let snapshot = try #require(store.occurrences.first)
            routine.days[0].exercises[0].sets = 5
            try store.move(plan: routine, date: monday, to: nextDay)
            let moved = try #require(store.occurrences.first)
            #expect(store.occurrences.count == 1)
            #expect(moved.id == snapshot.id)
            #expect(moved.plannedSets == snapshot.plannedSets)
            #expect(store.progress(for: moved).completed == 1)
            #expect(store.progress(for: moved).total == 2)
            #expect(store.active?.id == session.id)
            #expect(throws: TrainingError.self) { try store.startCardio(name: "Cycling") }
            #expect(store.active?.id == session.id && store.sessions.count == 1)
        }
    }

    @Test func retryStartsOnlyTheRequestedTargetAfterTheOldSessionIsSaved() throws {
        try withDirectory { directory in
            let planner = PlanningStore(directory: directory.appending(path: "plans"))
            try planner.load()
            let routine = week
            try planner.begin(routine, step: "review")
            try planner.confirm(routine)
            var fail = false
            let training = TrainingStore(directory: directory.appending(path: "training"), beforeSave: {
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
            })
            try training.load(profileID: try #require(planner.profileID))
            try training.startCardio(name: "Walk")
            let source = try #require(training.active)
            let target = PlanStartTarget.template(routine, monday)
            let selected = CivilTrainingDay(monday)
            #expect(throws: TrainingError.self) { try target.start(planner: planner, training: training, expectedDay: selected) }
            #expect(training.active?.id == source.id)
            try training.recordCardio(sessionID: source.id, result: CardioResult(seconds: 120))
            try training.finish(sessionID: source.id, partial: false)
            let saved = try #require(training.sessions.first)
            fail = true
            #expect(throws: CocoaError.self) { try target.start(planner: planner, training: training, expectedDay: selected) }
            #expect(training.sessions == [saved] && training.active == nil)
            fail = false
            try target.start(planner: planner, training: training, expectedDay: selected)
            #expect(training.sessions.count == 2 && training.sessions[0] == saved)
            #expect(training.active?.occurrenceID != nil)
        }
    }

    @Test func retainedTargetRequiresTheSameSelectedDayAndIgnoresUnrelatedDayEdits() throws {
        try withDirectory { directory in
            let planner = PlanningStore(directory: directory.appending(path: "plans"))
            try planner.load()
            let baseline = week
            @MainActor func save(_ plan: WeekPlan) throws {
                try planner.begin(plan, step: "review")
                try planner.confirm(plan)
            }
            try save(baseline)
            var fail = true
            let training = TrainingStore(directory: directory.appending(path: "training"), beforeSave: {
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
            })
            try training.load(profileID: try #require(planner.profileID))
            let target = PlanStartTarget.template(baseline, monday)
            let day = CivilTrainingDay(monday)
            #expect(throws: CocoaError.self) { try target.start(planner: planner, training: training, expectedDay: day) }
            fail = false
            var updated = baseline
            updated.days[0].id = UUID()
            try save(updated)
            #expect(throws: PlanStartTargetError.self) { try target.start(planner: planner, training: training, expectedDay: day) }
            updated = baseline
            updated.days[0].exercises[0].sets += 1
            try save(updated)
            #expect(throws: PlanStartTargetError.self) { try target.start(planner: planner, training: training, expectedDay: day) }
            #expect(training.sessions.isEmpty && training.occurrences.isEmpty)
            updated = baseline
            updated.days[2] = PlanDay(name: "Walk", cardioGoalSeconds: 1200)
            try save(updated)
            try target.start(planner: planner, training: training, expectedDay: day)
            #expect(training.active?.name == baseline.days[0].name)
        }
    }

    @Test func cardioSchedulingIsRetrySafeAndCreatesOnlyPlannedWork() throws {
        try withDirectory { directory in
            let store = TrainingStore(directory: directory)
            try store.load(profileID: UUID())
            let id = UUID()
            #expect(throws: TrainingError.self) { try store.scheduleCardio(name: " ", date: monday, goalSeconds: 1200, id: id) }
            #expect(throws: TrainingError.self) { try store.scheduleCardio(name: "Cycling", date: monday, goalSeconds: 0, id: id) }
            try store.scheduleCardio(name: "Cycling", date: monday, goalSeconds: 1200, id: id)
            try store.scheduleCardio(name: "Cycling", date: monday, goalSeconds: 1200, id: id)
            #expect(throws: TrainingError.self) { try store.scheduleCardio(name: "Running", date: monday, goalSeconds: 1200, id: id) }
            let activity = try #require(store.occurrences.first)
            #expect(store.isScheduled(activity, on: monday))
            #expect(activity.cardioGoalSeconds == 1200)
            #expect(store.occurrences.count == 1 && store.sessions.isEmpty)
            #expect(store.progress(for: activity).completed == 0)
        }
    }
}
