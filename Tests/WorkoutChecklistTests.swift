import Foundation
import Testing
@testable import Weekform

struct WorkoutChecklistTests {
    @Test func continuedWorkoutCombinesPriorCreditsAndCurrentSetsWithoutChangingTheirOwnership() throws {
        let date = Date()
        let civil = CivilTrainingDay(date)
        let curl = PlanExercise(name: "Curl", sets: 3)
        let row = PlanExercise(name: "Row", sets: 1)
        let day = PlanDay(name: "Upper", exercises: [curl, row])
        let slots = [UUID(), UUID(), UUID()]
        let rowSlot = UUID()
        let plan = TrainingOccurrence(name: "Upper", sourceDay: civil, scheduledDay: civil, day: day,
                                      plannedSets: [curl.id: slots, row.id: [rowSlot]])
        let first = TrainingSet(plannedID: slots[0], ordinal: 4, actual: SetActual(reps: 10, load: 15), confirmedAt: date)
        let extra = TrainingSet(ordinal: 4, optional: true, actual: SetActual(reps: 7, load: 10), confirmedAt: date)
        let logged = TrainingExercise(prescription: curl, basis: .external, sets: [first, extra])
        let replacement = PlanExercise(name: "Cable curl", sets: 1)
        let swapCredit = TrainingSet(plannedID: slots[1], ordinal: 2, actual: SetActual(reps: 9, load: 20), confirmedAt: date)
        let swapped = TrainingExercise(prescription: replacement, basis: .machine, sets: [swapCredit], replacedPrescription: curl)
        let before = TrainingSession(name: "Earlier", startedAt: date, performedDay: civil, finishedAt: date,
                                     partial: true, occurrenceID: plan.id, exercises: [logged, swapped])
        let pending = TrainingSet(plannedID: slots[2], ordinal: 3)
        let live = TrainingExercise(prescription: curl, basis: .external, sets: [pending])
        let current = TrainingSession(name: "Now", startedAt: date, performedDay: civil,
                                      occurrenceID: plan.id, exercises: [live])

        let list = WorkoutChecklist(session: current, occurrence: plan, sessions: [before, current])
        #expect(list.total == 4)
        #expect(list.completed == 2)
        let original = try #require(list.groups.first { $0.id == live.id })
        #expect(original.rows.map(\.ordinal) == [1, 3])
        guard case .earlier(let saved) = original.rows[0] else { Issue.record("Expected earlier confirmed result"); return }
        #expect(saved.set == first)
        #expect(saved.sessionID == before.id)
        #expect(saved.exercise == logged)
        #expect(saved.ordinal == 1)
        #expect(saved.performedAt == date)
        guard case .live(let remaining, let index) = original.rows[1] else { Issue.record("Expected current row"); return }
        #expect(remaining.id == pending.id)
        #expect(index == 0)
        let replaced = try #require(list.groups.first { $0.prescription.name == replacement.name })
        #expect(replaced.liveExercise == nil)
        #expect(replaced.rows.map(\.id) == [swapCredit.id])
        guard case .earlier(let savedSwap) = replaced.rows[0] else { Issue.record("Expected earlier replacement result"); return }
        #expect(savedSwap.sessionID == before.id)
        #expect(savedSwap.exercise == swapped)
        #expect(savedSwap.ordinal == 2)
        let missing = try #require(list.groups.first { $0.prescription.id == row.id })
        guard case .remaining(let slot, let ordinal) = missing.rows[0] else { Issue.record("Expected remaining planned slot"); return }
        #expect(slot == rowSlot && ordinal == 1)
        #expect(!list.groups.flatMap(\.rows).map(\.id).contains(extra.id))
    }

    @Test func extraSessionOnlyCountsItsOwnRows() {
        let date = Date()
        let exercise = TrainingExercise(prescription: PlanExercise(name: "Push-up"), basis: .bodyweight,
                                        sets: [TrainingSet(ordinal: 1, actual: SetActual(reps: 9), confirmedAt: date), TrainingSet(ordinal: 2)])
        let session = TrainingSession(name: "Extra", startedAt: date, performedDay: CivilTrainingDay(date), exercises: [exercise])
        var unrelated = session
        unrelated.id = UUID()
        let result = WorkoutChecklist(session: session, occurrence: nil, sessions: [session, unrelated])
        #expect(result.total == 2 && result.completed == 1)
        #expect(result.groups.count == 1)
    }
}
