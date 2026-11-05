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
}
