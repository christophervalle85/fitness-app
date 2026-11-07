import Foundation
import Testing
@testable import Weekform

@MainActor
struct PlanningTests {
    private func routine(_ name: String = "Demo") -> WeekPlan {
        var plan = WeekPlan(name: name)
        plan.days[0] = PlanDay(name: "Upper", exercises: [PlanExercise(name: "Press", convention: "Machine")])
        return plan
    }

    private func withDirectory(_ test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(directory)
    }

    @Test func confirmFutureSwapKeepsFullSetCountAndChecksOriginal() throws {
        try withDirectory { dir in
            let store = PlanningStore(directory: dir)
            try store.load()
            let plan = routine()
            let day = plan.days[0]
            let original = day.exercises[0]
            try store.begin(plan, step: "review")
            try store.confirm(plan)
            let swap = PlanExercise(name: "Cable variation", sets: 1)
            try store.replaceFutureExercise(planID: plan.id, dayID: day.id, original: original, replacement: swap)
            #expect(store.plans[0].days[0].exercises[0].sets == original.sets)
            #expect(store.plans[0].days[0].exercises[0].variantID == swap.id)
            #expect(store.plans[0].days[0].exercises[0].id != original.id)
            #expect(throws: PlanningError.self) {
                try store.replaceFutureExercise(planID: plan.id, dayID: day.id, original: original, replacement: swap)
            }
        }
    }

    @Test func legacyDayDecodesAndCardioHasAnExplicitGoal() throws {
        let data = Data("{\"id\":\"5013DF4E-2000-4B79-BF8B-103F89D0C401\",\"name\":\"\",\"exercises\":[]}".utf8)
        let legacy = try JSONDecoder().decode(PlanDay.self, from: data)
        #expect(!legacy.isWorkout)
        var plan = WeekPlan(name: "Cardio week")
        plan.days[0] = PlanDay(name: "Cycling", cardioGoalSeconds: 900)
        #expect(plan.validationMessage == nil)
        plan.days[0].cardioGoalSeconds = 0
        #expect(plan.validationMessage != nil)
    }

    @Test func aDifferentExerciseNeedsItsOwnStartingLoad() {
        var exercise = PlanExercise(name: "Example barbell", convention: "Total barbell weight")
        exercise.startingLoad = 20
        selectVariant("Example barbell", for: &exercise)
        #expect(exercise.startingLoad == 20)
        selectVariant("Example dumbbell", for: &exercise)
        #expect(exercise.startingLoad == nil)
        #expect(exercise.convention == "Per dumbbell")
    }

    @Test func prescriptionKeepsSideAndLoadVisible() {
        var exercise = PlanExercise(name: "Single-side test", convention: "Per side")
        exercise.startingLoad = 7.5
        exercise.loadUnit = "kg"
        let summary = prescription(exercise)
        #expect(summary.contains("Per side"))
        #expect(summary.contains("kg"))
        #expect(summary.contains("reps"))
    }

    @Test func interruptedSetupRestoresProfileDraftAndStep() throws {
        try withDirectory { directory in
            let store = PlanningStore(directory: directory)
            try store.load()
            #expect(store.step == "welcome")
            #expect(store.activeID == nil)
            let plan = routine()
            try store.begin(plan, step: "edit")
            try store.update(plan, step: "review")

            let reopened = PlanningStore(directory: directory)
            try reopened.load()
            #expect(reopened.profileID == store.profileID)
            #expect(reopened.draft == plan)
            #expect(reopened.step == "review")
            try reopened.confirm(plan)
            try reopened.confirm(plan)
            let saved = PlanningStore(directory: directory)
            try saved.load()
            try saved.confirm(plan)
            #expect(saved.plans == [plan])
            #expect(saved.activeID == plan.id)
            #expect(saved.step == "home")
            #expect(saved.draft == nil)
        }
    }

    @Test func failedConfirmationKeepsReviewAndCanRetry() throws {
        try withDirectory { directory in
            var failNext = false
            let store = PlanningStore(directory: directory) {
                if failNext { throw CocoaError(.fileWriteOutOfSpace) }
            }
            try store.load()
            let plan = routine()
            try store.begin(plan, step: "review")
            failNext = true
            #expect(throws: CocoaError.self) { try store.confirm(plan) }
            #expect(store.plans.isEmpty)
            #expect(store.activeID == nil)
            #expect(store.step == "review")
            #expect(store.draft == plan)

            let reopened = PlanningStore(directory: directory)
            try reopened.load()
            #expect(reopened.plans.isEmpty)
            #expect(reopened.step == "review")
            #expect(reopened.draft == plan)
            failNext = false
            try store.confirm(plan)
            #expect(store.plans == [plan])
        }
    }

    @Test func validationRequiresResolvedExercisesAndValidPrescription() {
        var plan = routine()
        plan.days[0].exercises[0].choices = ["Option A", "Option B"]
        plan.days[0].exercises[0].name = " "
        #expect(plan.validationMessage != nil)
        plan.days[0].exercises[0].name = "Custom variant"
        plan.days[0].exercises[0].startingLoad = 0
        #expect(plan.validationMessage == nil)
        plan.days[0].exercises[0].high = 0
        #expect(plan.validationMessage != nil)
        plan.days[0].exercises[0].high = 12
        plan.days[0].exercises[0].startingLoad = -1
        #expect(plan.validationMessage != nil)
        plan.days[0].exercises[0].startingLoad = nil
        plan.days[1].name = "Scheduled without exercises"
        #expect(plan.validationMessage != nil)
        plan.days[1].name = ""
        plan.days[0].name = ""
        #expect(plan.validationMessage != nil)
        #expect(WeekPlan(name: "All rest").validationMessage != nil)
    }

    @Test func replayAndManagementPreserveExistingPlans() throws {
        try withDirectory { directory in
            let store = PlanningStore(directory: directory)
            try store.load()
            let first = routine()
            try store.begin(first, step: "review")
            try store.confirm(first)
            let replay = first.independentCopy()
            try store.begin(replay, step: "welcome")
            try store.discard()
            #expect(store.plans == [first])
            #expect(store.activeID == first.id)
            try store.begin(replay, step: "review")
            try store.confirm(replay)
            #expect(store.activeID == replay.id)

            var edited = first
            edited.name = "Edited"
            try store.begin(edited, step: "edit")
            try store.confirm(first) // A delayed retry from the first save.
            #expect(store.draft == edited)
            try store.confirm(edited)
            #expect(store.activeID == replay.id)
            #expect(store.plans == [edited, replay])
            try store.duplicate(first.id)
            let copy = try #require(store.plans.last)
            #expect(copy.id != first.id)
            #expect(copy.days[0].id != first.days[0].id)
            #expect(copy.days[0].exercises[0].id != first.days[0].exercises[0].id)
            #expect(copy.days[0].exercises[0].variantID == first.days[0].exercises[0].id)
            try store.activate(copy.id)
            try store.archive(copy.id)
            try store.archive(replay.id)
            try store.archive(first.id)
            #expect(store.activeID == nil)
            #expect(store.step == "home")
            #expect(store.plans.count == 3)
            #expect(store.plans.filter { !$0.archived }.isEmpty)
        }
    }

    @Test func additionalRoutineCanBeSavedWithoutChangingTheActiveRoutine() throws {
        try withDirectory { directory in
            let store = PlanningStore(directory: directory)
            try store.load()
            let active = routine("Current week")
            try store.begin(active, step: "review")
            try store.confirm(active)

            let additional = routine("Next week")
            try store.begin(additional, step: "review")
            try store.confirm(additional, activateNew: false)
            try store.confirm(additional, activateNew: true) // A retry must not change the saved choice.

            let reopened = PlanningStore(directory: directory)
            try reopened.load()
            #expect(reopened.plans.contains(additional))
            #expect(reopened.activeID == active.id)
            #expect(reopened.draft == nil)
            #expect(reopened.step == "home")

            let replacement = routine("Replacement week")
            try reopened.begin(replacement, step: "review")
            try reopened.confirm(replacement, activateNew: true)
            #expect(reopened.activeID == replacement.id)
        }
    }

    @Test func savingOrEditingAnInactiveRoutineCanLeaveTheScheduleEmpty() throws {
        try withDirectory { directory in
            let store = PlanningStore(directory: directory)
            try store.load()
            let first = routine("Previous week")
            try store.begin(first, step: "review")
            try store.confirm(first)
            try store.archive(first.id)

            var inactive = routine("Saved for later")
            try store.begin(inactive, step: "review")
            try store.confirm(inactive, activateNew: false)
            #expect(store.activeID == nil)

            inactive.name = "Renamed"
            try store.begin(inactive, step: "review")
            try store.confirm(inactive)
            #expect(store.plans.contains(inactive))
            #expect(store.activeID == nil)
        }
    }

    @Test func failedDeletionKeepsTheRoutineAndActivationUntilRetry() throws {
        try withDirectory { directory in
            var failNext = false
            let store = PlanningStore(directory: directory) {
                if failNext { throw CocoaError(.fileWriteOutOfSpace) }
            }
            try store.load()
            let plan = routine()
            try store.begin(plan, step: "review")
            try store.confirm(plan)
            try store.duplicate(plan.id)
            let copy = try #require(store.plans.last)
            try store.archive(copy.id)

            failNext = true
            #expect(throws: CocoaError.self) { try store.deleteRoutine(plan.id) }
            #expect(store.plans.contains(plan))
            #expect(store.activeID == plan.id)
            failNext = false
            try store.deleteRoutine(copy.id)
            #expect(store.plans == [plan])
            #expect(store.activeID == plan.id)
            try store.deleteRoutine(plan.id)

            let reopened = PlanningStore(directory: directory)
            try reopened.load()
            #expect(reopened.plans.isEmpty)
            #expect(reopened.activeID == nil)
            #expect(reopened.step == "home")
        }
    }
}
