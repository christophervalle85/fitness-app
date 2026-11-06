import Foundation
import Testing
@testable import Weekform

@MainActor
struct TrainingTests {
    // Thursday noon in local civil time; DST does not affect weekday arithmetic.
    private let thursday = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 12))!
    private var friday: Date { Calendar.current.date(byAdding: .day, value: 1, to: thursday)! }

    private func withDirectory(_ run: (URL) throws -> Void) throws {
        let path = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try run(path)
    }

    private func plan() -> WeekPlan {
        var plan = WeekPlan(name: "Test week")
        plan.days[4] = PlanDay(name: "Pull", exercises: [PlanExercise(name: "Row", sets: 3, convention: "Machine setting")])
        plan.restSeconds = 90
        return plan
    }

    private func confirm(_ store: TrainingStore, row: Int = 0, exercise: Int = 0,
                         actual: SetActual = SetActual(reps: 12, load: 40), commandID: UUID = UUID()) throws {
        let session = try #require(store.active)
        let set = session.exercises[exercise].sets[row]
        try store.confirm(sessionID: session.id, setID: set.id, actual: actual, revision: set.revision, commandID: commandID)
    }

    @Test func calendarTicksKeepOutOfOrderCreditsOnTheirPrescribedSlots() throws {
        try withDirectory { directory in
            let store = TrainingStore(directory: directory)
            try store.load(profileID: UUID())
            try store.startPlanned(plan: plan(), date: friday)
            try confirm(store, row: 2)
            let occurrence = try #require(store.occurrences.first)
            let exercise = try #require(occurrence.day?.exercises.first)
            #expect(store.slotProgress(for: occurrence)[exercise.id] == [false, false, true])
        }
    }

    @Test func differentCatalogVariantsCannotShareCreditByName() {
        let a = PlanExercise(variantID: UUID(), name: "Machine row", convention: "Machine")
        let b = PlanExercise(variantID: UUID(), name: "Machine row", convention: "Machine")
        let logged = TrainingExercise(prescription: a, basis: .machine, sets: [])
        #expect(!logged.matchesPlannedItem(b))
        #expect(logged.matchesPlannedItem(a))
    }

    @Test func sharedVariantRequiresCompatibleLoadMethodForCredit() {
        let target = PlanExercise(variantID: UUID(), name: "Pull-up", convention: "Assistance")
        let logged = TrainingExercise(prescription: target, basis: .added, sets: [])
        #expect(!logged.matchesPlannedItem(target))
    }

    @Test func retriesUndoAndRestartKeepSessionAndCreditConsistent() throws {
        try withDirectory { path in
            var instant = thursday
            let store = TrainingStore(directory: path, now: { instant })
            let profile = UUID()
            try store.load(profileID: profile)
            try store.startPlanned(plan: plan(), date: friday)
            let s = try #require(store.active)
            let row = s.exercises[0].sets[0]
            #expect(row.actual.reps == nil)
            let actual = SetActual(reps: 10, load: 30)
            let id = UUID()
            #expect(throws: TrainingError.self) { try store.confirm(sessionID: s.id, setID: row.id, actual: SetActual(reps: 10), revision: 0, commandID: UUID()) }
            try store.edit(sessionID: s.id, setID: row.id, actual: actual, revision: 0)
            try store.confirm(sessionID: s.id, setID: row.id, actual: actual, revision: 1, commandID: id)
            try store.confirm(sessionID: s.id, setID: row.id, actual: actual, revision: 1, commandID: id)
            #expect(throws: TrainingError.self) { try store.confirm(sessionID: s.id, setID: row.id, actual: SetActual(reps: 11, load: 30), revision: 1, commandID: id) }
            let occurrence = try #require(store.occurrences.first)
            #expect(store.progress(for: occurrence).completed == 1)
            instant = instant.addingTimeInterval(35)
            #expect(store.active?.rest?.elapsed(at: instant) == 35)
            try store.pauseRest(sessionID: s.id)
            instant = instant.addingTimeInterval(60)
            try store.resumeRest(sessionID: s.id)
            #expect(store.active?.rest?.elapsed(at: instant) == 35)
            let rest = store.active?.rest
            try store.undo(sessionID: s.id, setID: row.id, revision: 2)
            #expect(store.active?.rest == rest)
            try store.confirm(sessionID: s.id, setID: row.id, actual: actual, revision: 1, commandID: id)
            #expect(store.progress(for: occurrence).completed == 0)
            let reopened = TrainingStore(directory: path)
            try reopened.load(profileID: profile)
            #expect(reopened.active?.exercises[0].sets[0].actual == actual)
            #expect(reopened.active?.exercises[0].sets[0].confirmedAt == nil)
            #expect(reopened.active?.rest == rest)
        }
    }

    @Test func partialEarlySwapMoveAndResumeKeepOneCreditPerSlot() throws {
        try withDirectory { path in
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: UUID())
            let template = plan()
            try store.startPlanned(plan: template, date: friday)
            let s = try #require(store.active)
            let original = try #require(store.occurrences.first)
            try confirm(store)
            try store.substitute(sessionID: s.id, exerciseID: s.exercises[0].id,
                                 prescription: PlanExercise(name: "Replacement", sets: 2), basis: .bodyweight)
            try confirm(store, exercise: 1, actual: SetActual(reps: 8))
            try store.finish(sessionID: s.id, partial: true)
            #expect(store.progress(for: original).completed == 2)
            #expect(store.sessions[0].exercises[0].sets.count == 1)
            #expect(store.sessions[0].exercises[1].replacedPrescription?.id == template.days[4].exercises[0].id)
            let afterDST = Calendar.current.date(byAdding: .day, value: 5, to: friday)!
            try store.move(original.id, to: afterDST)
            let same = try store.materialize(plan: template, date: friday)
            #expect(same == original.id)
            let moved = try #require(store.occurrences.first)
            #expect(store.isOriginal(moved, on: friday))
            #expect(store.isScheduled(moved, on: afterDST))
            #expect(throws: TrainingError.self) { try store.startPlanned(plan: template, date: friday) }
            try store.startOccurrence(moved.id)
            #expect(store.active?.exercises[0].sets.count == 1)
            try confirm(store)
            try store.finish(sessionID: try #require(store.active?.id), partial: false)
            #expect(store.status(for: moved) == "Done early")
            #expect(store.sessions.count == 2)
            #expect(store.sessions[0].partial)
            #expect(store.progress(for: moved).completed == 3)
            #expect(throws: TrainingError.self) { try store.startOccurrence(moved.id) }
        }
    }

    @Test func explicitCardioContributionsSeparateExtraActivity() throws {
        try withDirectory { path in
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: UUID())
            var weekly = WeekPlan(name: "Cardio week")
            weekly.days[4] = PlanDay(name: "Cycling", cardioGoalSeconds: 600)
            let id = try store.materialize(plan: weekly, date: friday)
            let occurrence = try #require(store.occurrences.first)
            try store.startCardio(name: "Extra cardio")
            let extra = try #require(store.active?.id)
            try store.recordCardio(sessionID: extra, result: CardioResult(seconds: 1500))
            try store.finish(sessionID: extra, partial: false)
            #expect(store.progress(for: occurrence).completed == 0)
            for (index, duration) in [250, 350].enumerated() {
                try store.startOccurrence(id)
                let session = try #require(store.active)
                #expect(session.exercises.isEmpty)
                let result = CardioResult(seconds: duration, distance: 1.25)
                try store.updateCardio(sessionID: session.id, result: result)
                #expect(throws: TrainingError.self) { try store.finish(sessionID: session.id, partial: true) }
                try store.recordCardio(sessionID: session.id, result: result)
                try store.recordCardio(sessionID: session.id, result: result)
                #expect(store.progress(for: occurrence).completed == (index == 0 ? 250 : 600))
                try store.finish(sessionID: session.id, partial: index == 0)
            }
            #expect(store.status(for: occurrence) == "Done early")
        }
    }

    @Test func separateOwnersStaleWritersAndFailedCommitPreserveSavedState() throws {
        try withDirectory { path in
            var fail = false
            let owner = UUID()
            let store = TrainingStore(directory: path, beforeSave: { if fail { throw CocoaError(.fileWriteOutOfSpace) } })
            try store.load(profileID: owner)
            let stale = TrainingStore(directory: path)
            try stale.load(profileID: owner)
            fail = true
            #expect(throws: CocoaError.self) { try store.startPlanned(plan: plan(), date: friday) }
            #expect(store.active == nil)
            #expect(store.occurrences.isEmpty)
            fail = false
            try store.startPlanned(plan: plan(), date: friday)
            #expect(throws: TrainingError.self) { try stale.startExtra(name: "Stale writer") }
            try stale.load(profileID: owner)
            #expect(stale.active?.id == store.active?.id)
            #expect(throws: TrainingError.self) { try stale.startExtra(name: "Second active workout") }
            try store.load(profileID: UUID())
            #expect(store.sessions.isEmpty)
            try store.load(profileID: owner)
            #expect(store.sessions.count == 1)
        }
    }

    @Test func latestUndoRestoresPriorIntervalButOlderUndoLeavesCurrentRest() throws {
        try withDirectory { path in
            var instant = thursday
            let store = TrainingStore(directory: path, now: { instant })
            try store.load(profileID: UUID())
            try store.startPlanned(plan: plan(), date: friday)
            let session = try #require(store.active)
            try confirm(store)
            let first = try #require(store.active?.rest)
            instant = instant.addingTimeInterval(45)
            try confirm(store, row: 1)
            try store.undo(sessionID: session.id, setID: session.exercises[0].sets[1].id, revision: 1)
            #expect(store.active?.rest == first)
            try confirm(store, row: 1)
            let second = try #require(store.active?.rest)
            try store.edit(sessionID: session.id, setID: session.exercises[0].sets[0].id, actual: SetActual(reps: 11, load: 42), revision: 1)
            try store.undo(sessionID: session.id, setID: session.exercises[0].sets[0].id, revision: 2)
            #expect(store.active?.rest == second)
            try confirm(store)
            try confirm(store, row: 2)
            #expect(store.active?.rest == nil)
        }
    }

    @Test func assignExtraResultsAtomicallyToDistinctPlannedSlots() throws {
        try withDirectory { path in
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: UUID())
            let template = plan()
            let prescription = template.days[4].exercises[0]
            try store.startExtra(name: "Extra")
            let sessionID = try #require(store.active?.id)
            try store.add(sessionID: sessionID, prescription: prescription, basis: .machine)
            try confirm(store)
            try confirm(store, row: 1)
            let sets = try #require(store.active?.exercises.first?.sets)
            try store.finish(sessionID: sessionID, partial: true)
            #expect(throws: TrainingError.self) {
                try store.assign(sessionID: sessionID, plan: template, date: friday, setID: sets[2].id, exerciseID: prescription.id, slot: 2)
            }
            #expect(store.occurrences.isEmpty)
            try store.assign(sessionID: sessionID, plan: template, date: friday, setID: sets[0].id, exerciseID: prescription.id, slot: 0)
            let occurrence = try #require(store.occurrences.first)
            let slots = try #require(occurrence.plannedSets[prescription.id])
            try store.assign(sessionID: sessionID, occurrenceID: occurrence.id, setID: sets[0].id, plannedSetID: slots[0])
            #expect(throws: TrainingError.self) {
                try store.assign(sessionID: sessionID, occurrenceID: occurrence.id, setID: sets[1].id, plannedSetID: slots[0])
            }
            #expect(throws: TrainingError.self) {
                try store.assign(sessionID: sessionID, occurrenceID: occurrence.id, setID: sets[0].id, plannedSetID: slots[1])
            }
            try store.startOccurrence(occurrence.id)
            let contributing = try #require(store.active)
            #expect(contributing.exercises[0].sets.first?.ordinal == 2)
            #expect(throws: TrainingError.self) {
                try store.assign(sessionID: sessionID, occurrenceID: occurrence.id, setID: sets[1].id, plannedSetID: slots[1])
            }
            try store.cancelEmpty(sessionID: contributing.id)
            try store.assign(sessionID: sessionID, occurrenceID: occurrence.id, setID: sets[1].id, plannedSetID: slots[1])
            #expect(store.remainingSetIDs(for: occurrence) == Set([slots[2]]))
            #expect(store.progress(for: occurrence).completed == 2)
            let revision = try #require(store.sessions.first?.exercises[0].sets[1].revision)
            try store.undo(sessionID: sessionID, setID: sets[1].id, revision: revision)
            #expect(store.progress(for: occurrence).completed == 1)
        }
    }

    @Test func explicitStartKeepsPreciseDurationAndDeadlineNeverLogs() throws {
        try withDirectory { path in
            var instant = thursday
            let store = TrainingStore(directory: path, now: { instant })
            try store.load(profileID: UUID())
            try store.startPlanned(plan: plan(), date: friday)
            let session = try #require(store.active)
            try confirm(store)
            instant = instant.addingTimeInterval(80)
            try store.pauseRest(sessionID: session.id)
            instant = instant.addingTimeInterval(10)
            try store.resetRest(sessionID: session.id)
            instant = instant.addingTimeInterval(100)
            #expect(store.active?.exercises[0].sets[1].confirmedAt == nil)
            try store.startSet(sessionID: session.id)
            let measurement = try #require(store.active?.restHistory.last)
            #expect(measurement.precise)
            #expect(measurement.elapsed == 180)
            #expect(store.active?.rest == nil)
            #expect(store.active?.exercises[0].sets[1].confirmedAt == nil)
        }
    }

    @Test func warmupsStaySeparateFromPrescriptionsSuggestionsAndExtraAssignment() throws {
        try withDirectory { path in
            var instant = thursday
            let store = TrainingStore(directory: path, now: { instant })
            try store.load(profileID: UUID())
            var template = plan()
            template.days[4].exercises[0].sets = 1
            let p = template.days[4].exercises[0]
            try store.startPlanned(plan: template, date: friday)
            let session = try #require(store.active)
            let occurrence = try #require(store.occurrences.first)
            try store.addSet(sessionID: session.id, exerciseID: session.exercises[0].id, warmup: true)
            try store.addSet(sessionID: session.id, exerciseID: session.exercises[0].id, warmup: false)
            try confirm(store, actual: SetActual(reps: 10, load: 50))
            instant = instant.addingTimeInterval(10)
            try confirm(store, row: 1, actual: SetActual(reps: 5, load: 10))
            #expect(store.progress(for: occurrence).completed == 1)
            try store.finish(sessionID: session.id, partial: false)
            try store.startExtra(name: "Extra")
            let extraID = try #require(store.active?.id)
            try store.add(sessionID: extraID, prescription: p, basis: .machine)
            let extra = try #require(store.active)
            #expect(extra.exercises[0].sets[0].actual.load == 50)
            try store.addSet(sessionID: extraID, exerciseID: extra.exercises[0].id, warmup: true)
            try confirm(store, row: 1, actual: SetActual(reps: 5, load: 10))
            let warmupID = try #require(store.active?.exercises[0].sets[1].id)
            try store.finish(sessionID: extraID, partial: true)
            let next = Calendar.current.date(byAdding: .day, value: 7, to: friday)!
            #expect(throws: TrainingError.self) {
                try store.assign(sessionID: extraID, plan: template, date: next, setID: warmupID, exerciseID: p.id, slot: 0)
            }
            #expect(store.occurrences.count == 1)
        }
    }

    @Test func cardioRetryAfterCorrectionCannotReinstateOldDuration() throws {
        try withDirectory { path in
            let store = TrainingStore(directory: path)
            try store.load(profileID: UUID())
            try store.startCardio(name: "Walk")
            let id = try #require(store.active?.id)
            let originalID = UUID()
            let original = CardioResult(seconds: 60)
            try store.recordCardio(sessionID: id, result: original, revision: 0, commandID: originalID)
            try store.recordCardio(sessionID: id, result: CardioResult(seconds: 80), revision: 1, commandID: UUID())
            try store.recordCardio(sessionID: id, result: original, revision: 0, commandID: originalID)
            #expect(store.active?.cardio?.seconds == 80)
            #expect(throws: TrainingError.self) { try store.recordCardio(sessionID: id, result: original, revision: 0, commandID: UUID()) }
        }
    }

    @Test func typedActualsKeepLoadAndSideSemantics() throws {
        try SetActual(seconds: 30).validate(for: .timed)
        try SetActual(reps: 8).validate(for: .bodyweight)
        try SetActual(reps: 8, load: 0).validate(for: .assisted)
        try SetActual(reps: 8, load: 10, rightReps: 7, rightLoad: 12).validate(for: .unilateral)
        #expect(throws: TrainingError.self) { try SetActual(reps: 12).validate(for: .timed) }
        #expect(throws: TrainingError.self) { try SetActual(reps: 8, load: 20).validate(for: .unilateral) }
        #expect(throws: TrainingError.self) { try SetActual(reps: 8, load: .infinity).validate(for: .barbell) }
    }
}
