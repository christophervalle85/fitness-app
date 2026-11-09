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
            let store = TrainingStore(directory: directory, now: { monday }, beforeSave: {
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

    @Test func openWorkCannotMoveOrSkipAndFinishedWorkKeepsCreditsWhenMoved() throws {
        try withDirectory { directory in
            let store = TrainingStore(directory: directory, now: { monday })
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
            let other = try store.startCardio(name: "Cycling")
            #expect(store.active?.id == other && store.sessions.count == 2)
            #expect(store.openSession(for: snapshot.id)?.id == session.id)
            #expect(throws: TrainingError.self) { try store.move(plan: routine, date: monday, to: nextDay) }
            #expect(throws: TrainingError.self) { try store.skip(snapshot.id) }
            try store.finish(sessionID: session.id, partial: true)
            try store.move(plan: routine, date: monday, to: nextDay)
            let moved = try #require(store.occurrences.first)
            #expect(store.occurrences.count == 1)
            #expect(moved.id == snapshot.id)
            #expect(moved.plannedSets == snapshot.plannedSets)
            #expect(store.progress(for: moved).completed == 1)
            #expect(store.progress(for: moved).total == 2)
            #expect(store.active?.id == other && store.sessions.count == 2)
            #expect(store.openSession(for: moved.id) == nil)
        }
    }

    @Test func retryStartsOnlyTheRequestedTargetAndLeavesTheOldSessionOpen() throws {
        try withDirectory { directory in
            let planner = PlanningStore(directory: directory.appending(path: "plans"))
            try planner.load()
            let routine = week
            try planner.begin(routine, step: "review")
            try planner.confirm(routine)
            var fail = false
            let training = TrainingStore(directory: directory.appending(path: "training"), now: { monday }, beforeSave: {
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
            })
            try training.load(profileID: try #require(planner.profileID))
            try training.startCardio(name: "Walk")
            let source = try #require(training.active)
            let target = PlanStartTarget.template(routine, monday)
            let selected = CivilTrainingDay(monday)
            let sourceFocus = training.focusToken
            fail = true
            #expect(throws: CocoaError.self) { try target.start(planner: planner, training: training, expectedDay: selected) }
            #expect(training.sessions == [source] && training.active == source)
            #expect(training.focusToken == sourceFocus)
            fail = false
            try target.start(planner: planner, training: training, expectedDay: selected)
            #expect(training.openSessions.count == 2 && training.sessions[0] == source)
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
            let training = TrainingStore(directory: directory.appending(path: "training"), now: { monday }, beforeSave: {
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
            let store = TrainingStore(directory: directory, now: { monday })
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

    @Test func planStateTracksActiveSessionAndRemainingCredit() throws {
        try withDirectory { directory in
            let store = TrainingStore(directory: directory, now: { monday })
            try store.load(profileID: UUID())
            let id = try store.materialize(plan: week, date: monday)
            let workout = try #require(store.occurrences.first)
            #expect(store.planState(for: workout) == .notStarted)
            try store.startOccurrence(id)
            let session = try #require(store.active)
            #expect(store.planState(for: workout) == .inProgress)
            let first = try #require(session.exercises.first?.sets.first)
            try store.confirm(sessionID: session.id, setID: first.id, actual: SetActual(reps: 8, load: 15),
                              revision: first.revision, commandID: UUID())
            try store.finish(sessionID: session.id, partial: true)
            #expect(store.planState(for: workout) == .inProgress)
            try store.startOccurrence(id)
            let resumed = try #require(store.active)
            let last = try #require(resumed.exercises.first?.sets.first)
            try store.confirm(sessionID: resumed.id, setID: last.id, actual: SetActual(reps: 8, load: 15),
                              revision: last.revision, commandID: UUID())
            #expect(store.planState(for: workout) == .inProgress)
            try store.finish(sessionID: resumed.id, partial: false)
            #expect(store.planState(for: workout) == .finished)

            let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: monday)!
            try store.skip(plan: week, date: nextWeek)
            let skipped = try #require(store.occurrences.first { $0.skipped })
            #expect(store.planState(for: skipped) == .skipped)
        }
    }

    @Test func removeAdditionalCardioPreservesSavedResultsAndRollsBackOnFailure() throws {
        try withDirectory { directory in
            let planner = PlanningStore(directory: directory.appending(path: "planning"))
            try planner.load()
            let owner = try #require(planner.profileID)
            var fail = false
            let store = TrainingStore(directory: directory, now: { monday }, beforeSave: {
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
            })
            try store.load(profileID: owner)
            var routine = week
            routine.days[0] = PlanDay(name: "Routine walk", cardioGoalSeconds: 300)
            let routineID = try store.materialize(plan: routine, date: monday)
            let id = UUID()
            try store.scheduleCardio(name: "Extra walk", date: monday, goalSeconds: 300, id: id)
            try store.startOccurrence(id)
            let active = try #require(store.active)
            let extra = try #require(store.occurrences.first { $0.id == id })
            #expect(!store.canRemoveAdditionalActivity(extra))
            #expect(throws: TrainingError.self) { try store.removeAdditionalActivity(id) }
            try store.recordCardio(sessionID: active.id, result: CardioResult(seconds: 100))
            try store.finish(sessionID: active.id, partial: true)
            try store.startOccurrence(id)
            let continuation = try #require(store.active)
            try store.recordCardio(sessionID: continuation.id, result: CardioResult(seconds: 200))
            try store.finish(sessionID: continuation.id, partial: false)
            let original = store.sessions
            #expect(store.canRemoveAdditionalActivity(extra))
            #expect(throws: TrainingError.self) { try store.removeAdditionalActivity(routineID) }
            fail = true
            #expect(throws: CocoaError.self) { try store.removeAdditionalActivity(id) }
            #expect(store.sessions == original && store.occurrences.contains { $0.id == id })
            let reloaded = TrainingStore(directory: directory)
            try reloaded.load(profileID: owner)
            #expect(reloaded.sessions.count == original.count && reloaded.sessions.allSatisfy { original.contains($0) })
            #expect(reloaded.occurrences.contains { $0.id == id })

            fail = false
            try store.removeAdditionalActivity(id)
            let expected = original.map { session in
                var saved = session
                saved.occurrenceID = nil
                return saved
            }
            #expect(store.sessions == expected)
            #expect(store.occurrences.map(\.id) == [routineID])
            #expect(throws: TrainingError.self) { try reloaded.removeAdditionalActivity(id) }
            try reloaded.load(profileID: owner)
            #expect(Set(reloaded.sessions.map(\.id)) == Set(expected.map(\.id)))
            #expect(reloaded.sessions.allSatisfy { expected.contains($0) })
            #expect(reloaded.occurrences.map(\.id) == [routineID])
            let backup = try WorkoutBackup(planner, reloaded)
            let encoded = try backup.encoded()
            let restored = try JSONDecoder().decode(WorkoutBackup.self, from: encoded)
            try restored.validate()
            #expect(restored == backup)
        }
    }
}
