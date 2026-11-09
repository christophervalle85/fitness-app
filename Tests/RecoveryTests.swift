import Foundation
import Testing
@testable import Weekform

@MainActor struct RecoveryTests {
    @Test func backupPreservesMultipleOpenWorkoutsAndRecreatesFocusGeneration() throws {
        let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Recovery")
        let original = try RecoveryPaths.current(at: root)
        let planner = PlanningStore(directory: original.planning)
        let training = TrainingStore(directory: original.training)
        try planner.load()
        let owner = try #require(planner.profileID)
        try training.load(profileID: owner)
        let first = try training.startExtra(name: "Strength")
        try training.note(sessionID: first, text: "First draft")
        let second = try training.startCardio(name: "Walk")
        try training.focus(sessionID: first)
        let priorToken = try #require(training.focusToken)
        let backup = try WorkoutBackup(planner, training)
        #expect(backup.version == 3)
        #expect(backup.focusedSessionID == first)
        var invalidFocus = backup
        invalidFocus.focusedSessionID = UUID()
        #expect(throws: PlanningError.self) { try invalidFocus.validate() }

        try RecoveryPaths.replace(with: backup, planner: planner, training: training, at: root)
        let restored = TrainingStore(directory: try RecoveryPaths.current(at: root).training)
        try restored.load(profileID: owner)
        #expect(Set(restored.openSessions.map(\.id)) == Set([first, second]))
        #expect(restored.active?.id == first)
        #expect(restored.active?.notes == "First draft")
        #expect(restored.focusToken != nil && restored.focusToken != priorToken)

        try restored.finish(sessionID: first, partial: true)
        #expect(restored.openSessions.map(\.id) == [second] && restored.active == nil)
        let withoutFocus = try WorkoutBackup(planner, restored)
        try RecoveryPaths.replace(with: withoutFocus, planner: planner, training: restored, at: root)
        let reopened = TrainingStore(directory: try RecoveryPaths.current(at: root).training)
        try reopened.load(profileID: owner)
        #expect(reopened.openSessions.map(\.id) == [second] && reopened.active == nil)
    }

    @Test func versionTwoRestoreStagesExpiredSessionsAndPreservesLegacyDetails() throws {
        let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Recovery")
        let original = try RecoveryPaths.current(at: root)
        let planner = PlanningStore(directory: original.planning)
        let training = TrainingStore(directory: original.training)
        try planner.load()
        let owner = try #require(planner.profileID)
        try training.load(profileID: owner)
        var legacy = try WorkoutBackup(planner, training)
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = TrainingSession(name: "Renamed walk", startedAt: past, performedDay: CivilTrainingDay(past), isCardio: true)
        legacy.sessions = [workout]
        legacy.version = 2
        try RecoveryPaths.replace(with: legacy, planner: planner, training: training, at: root)

        let restored = TrainingStore(directory: try RecoveryPaths.current(at: root).training)
        try restored.load(profileID: owner)
        #expect(restored.active == workout)
        try restored.reconcileExpiredSessions()
        #expect(restored.active == nil)
        #expect(restored.sessions.first?.finishedAt == past)
        #expect(restored.sessions.first?.name == "Renamed walk")
        #expect(restored.sessions.first?.closedAtWeekBoundary == true)
        #expect(restored.sessions.first?.cardio == nil)
    }

    @Test func deletingTheLastRoutinePreservesLinkedWorkAndTheLibraryDraft() throws {
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appending(path: "Recovery")
        let original = try RecoveryPaths.current(at: root)
        let planner = PlanningStore(directory: original.planning)
        let training = TrainingStore(directory: original.training)
        try planner.load()
        try training.load(profileID: #require(planner.profileID))
        let plan = Starters.general()
        try planner.begin(plan, step: "review")
        try planner.confirm(plan)
        let today = CivilTrainingDay(.now)
        let monday = try #require(Calendar.current.date(byAdding: .day, value: -today.mondayIndex, to: today.date))
        try training.startPlanned(plan: plan, date: monday)
        let before = try WorkoutBackup(planner, training)

        try planner.deleteRoutine(plan.id)
        #expect(planner.plans.isEmpty)
        #expect(planner.activeID == nil)
        #expect(planner.step == "home")
        let replacement = Starters.general()
        try planner.begin(replacement, step: "edit")
        try planner.update(replacement, step: "review")

        let backup = try WorkoutBackup(planner, training)
        #expect(backup.sessions == before.sessions)
        #expect(backup.occurrences == before.occurrences)
        try RecoveryPaths.replace(with: backup, planner: planner, training: training, at: root)
        let restored = PlanningStore(directory: try RecoveryPaths.current(at: root).planning)
        try restored.load()
        #expect(restored.isLibraryDraft)
        #expect(restored.editorStep == "review")
        #expect(restored.draft == replacement)
        try restored.discard()
        #expect(restored.step == "home")
        #expect(restored.plans.isEmpty)
    }

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
        let custom = PlanExercise(name: "Local row")
        try p.saveCustomExercise(custom)
        try p.setExerciseFavorite(custom.id, favorite: true)
        let before = try WorkoutBackup(p, t)
        #expect(before.library?.favorites.contains(custom.id) == true)
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
        var legacy = next
        legacy.version = 1
        legacy.focusedSessionID = nil
        legacy.library = nil
        try RecoveryPaths.replace(with: legacy, planner: restored, training: logged, at: root)
        let legacyPath = try RecoveryPaths.current(at: root)
        let oldStyle = PlanningStore(directory: legacyPath.planning)
        try oldStyle.load()
        #expect(oldStyle.customExercises.isEmpty && oldStyle.favoriteExerciseIDs.isEmpty)
        #expect(oldStyle.plans == p.plans)
    }
}
