import Foundation
import Testing
@testable import Weekform

@MainActor struct RecoveryTests {
    @Test func interruptedRestorePreservesBothStoresAndSuccessfulRestoreKeepsRecoveryCopy() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Recovery")
        let original = try RecoveryPaths.current(at: root)
        let p = PlanningStore(directory: original.planning), t = TrainingStore(directory: original.training)
        try p.load()
        try t.load(profileID: #require(p.profileID))
        var plan = WeekPlan(name: "Recovery fixture")
        plan.days[0] = PlanDay(name: "Strength", exercises: [PlanExercise(name: "Row")])
        try p.begin(plan, step: "review"); try p.confirm(plan)
        try t.startPlanned(plan: plan, date: CivilTrainingDay(Date()).date.addingTimeInterval(Double(-CivilTrainingDay(Date()).mondayIndex) * 86400))
        let before = try WorkoutBackup(p, t)
        var next = before
        next.unit = "kg"
        next.sessions[0].notes = "Restored workout"
        #expect(throws: PlanningError.self) {
            try RecoveryPaths.replace(with: next, planner: p, training: t, at: root) { throw PlanningError("test interruption") }
        }
        #expect(try RecoveryPaths.current(at: root).planning == original.planning)
        var broken = next
        broken.sessions[0].occurrenceID = UUID()
        #expect(throws: PlanningError.self) { try RecoveryPaths.replace(with: broken, planner: p, training: t, at: root) }
        var missingSlots = next
        missingSlots.occurrences[0].plannedSets.removeAll()
        #expect(throws: PlanningError.self) { try missingSlots.validate() }
        var exhausted = next
        exhausted.sessions[0].exercises[0].sets[0].ordinal = .max
        #expect(throws: PlanningError.self) { try exhausted.validate() }
        var unfinished = next
        unfinished.draft = plan
        unfinished.draft?.days[0].exercises[0].low = -1
        #expect(try !unfinished.encoded().isEmpty)
        try RecoveryPaths.replace(with: next, planner: p, training: t, at: root)
        let switched = try RecoveryPaths.current(at: root)
        let restored = PlanningStore(directory: switched.planning), logged = TrainingStore(directory: switched.training)
        try restored.load(); try logged.load(profileID: before.owner)
        #expect(try WorkoutBackup(restored, logged) == next)
        #expect(try WorkoutBackup.read(#require(switched.previous)) == before)
    }
}
