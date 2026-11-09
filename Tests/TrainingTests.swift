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

    @Test func workingSetDefaultsUseHeaviestExactRepResultAcrossUnits() throws {
        try withDirectory { path in
            var instant = thursday
            let store = TrainingStore(directory: path, now: { instant })
            try store.load(profileID: UUID())
            let prescription = PlanExercise(name: "Row", sets: 3, low: 8, high: 12, startingLoad: 25)
            let history = try store.startExtra(name: "History")
            try store.add(sessionID: history, prescription: prescription, basis: .external)
            let source = try #require(store.active?.exercises.first)
            let recorded = [SetActual(reps: 8, load: 100), SetActual(reps: 8, load: 40, unit: "kg"),
                            SetActual(reps: 6, load: 250)]
            for (row, actual) in zip(source.sets, recorded) {
                instant = instant.addingTimeInterval(1)
                try store.confirm(sessionID: history, setID: row.id, actual: actual, revision: row.revision, commandID: UUID())
            }
            try store.addSet(sessionID: history, exerciseID: source.id, warmup: true)
            let warmup = try #require(store.active?.exercises.first?.sets.last)
            try store.confirm(sessionID: history, setID: warmup.id, actual: SetActual(reps: 8, load: 400),
                              revision: warmup.revision, commandID: UUID())
            try store.finish(sessionID: history, partial: false)
            let workout = try store.startExtra(name: "Next")
            try store.add(sessionID: workout, prescription: prescription, basis: .external)
            let exercise = try #require(store.active?.exercises.first)
            let row = try #require(exercise.sets.first)

            #expect(row.actual == SetActual())
            #expect(store.suggestedActual(for: row, in: exercise) == SetActual(reps: 8, load: 100))

            var legacy = row
            legacy.actual = SetActual(reps: 6, load: 250)
            #expect(store.suggestedActual(for: legacy, in: exercise) == SetActual(reps: 8, load: 100))

            try store.edit(sessionID: workout, setID: row.id, actual: SetActual(), revision: row.revision, markUnchangedDraft: true)
            let edited = try #require(store.active?.exercises.first)
            let cleared = try #require(edited.sets.first)
            #expect(cleared.actual == SetActual() && cleared.revision == 1)
            #expect(store.suggestedActual(for: cleared, in: edited) == nil)
        }
    }

    @Test func unilateralDefaultsMatchRepCountForEachSide() throws {
        try withDirectory { path in
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: UUID())
            let prescription = PlanExercise(name: "Split squat", sets: 2, low: 8)
            let history = try store.startExtra(name: "History")
            try store.add(sessionID: history, prescription: prescription, basis: .unilateral)
            let source = try #require(store.active?.exercises.first)
            let results = [SetActual(reps: 8, load: 30, rightReps: 9, rightLoad: 100),
                           SetActual(reps: 9, load: 90, rightReps: 8, rightLoad: 35)]
            for (row, actual) in zip(source.sets, results) {
                try store.confirm(sessionID: history, setID: row.id, actual: actual, revision: row.revision, commandID: UUID())
            }
            try store.finish(sessionID: history, partial: false)

            let workout = try store.startExtra(name: "Next")
            try store.add(sessionID: workout, prescription: prescription, basis: .unilateral)
            let exercise = try #require(store.active?.exercises.first)
            let row = try #require(exercise.sets.first)
            #expect(store.suggestedActual(for: row, in: exercise) ==
                    SetActual(reps: 8, load: 30, rightReps: 8, rightLoad: 35))
        }
    }

    @Test func missingWorkingSetHistoryUsesOnlyAnApplicableStartingLoad() throws {
        try withDirectory { path in
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: UUID())
            let session = try store.startExtra(name: "Defaults")
            let cases: [(PlanExercise, LoadBasis, SetActual?)] = [
                (PlanExercise(name: "Press", low: 7, startingLoad: 20), .external, SetActual(reps: 7, load: 20)),
                (PlanExercise(name: "Pull", low: 6), .external, SetActual(reps: 6)),
                (PlanExercise(name: "Push-up", low: 9, startingLoad: 20), .bodyweight, SetActual(reps: 9)),
                (PlanExercise(name: "Split squat", low: 8, startingLoad: 20), .unilateral,
                 SetActual(reps: 8, load: 20, rightReps: 8, rightLoad: 20)),
                (PlanExercise(name: "Hold", timed: true), .timed, nil)
            ]
            for (prescription, basis, expected) in cases {
                try store.add(sessionID: session, prescription: prescription, basis: basis)
                let exercise = try #require(store.active?.exercises.last)
                let row = try #require(exercise.sets.first)
                #expect(store.suggestedActual(for: row, in: exercise) == expected)
                var warmup = row
                warmup.warmup = true
                #expect(store.suggestedActual(for: warmup, in: exercise) == nil)
            }
        }
    }

    @Test func clearingSuggestedActualsRemembersTheDraftWithoutLoggingASet() throws {
        try withDirectory { path in
            let owner = UUID()
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: owner)
            let id = try store.startPlanned(plan: plan(), date: friday)
            try confirm(store)
            let pending = try #require(store.active?.exercises.first?.sets[1])

            try store.edit(sessionID: id, setID: pending.id, actual: pending.actual,
                           revision: pending.revision, markUnchangedDraft: true)

            let reopened = TrainingStore(directory: path, now: { thursday })
            try reopened.load(profileID: owner)
            let saved = try #require(reopened.active?.exercises.first?.sets[1])
            #expect(saved.actual == pending.actual)
            #expect(saved.revision == pending.revision + 1)
            #expect(saved.confirmedAt == nil)
        }
    }

    @Test func openingAnotherWorkoutKeepsTheFirstWorkoutAndItsTimer() throws {
        try withDirectory { path in
            let owner = UUID()
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: owner)
            let template = plan()
            try store.startPlanned(plan: template, date: friday)
            let first = try #require(store.active)
            let firstFocus = try #require(store.focusToken)
            try confirm(store)
            let timer = try #require(store.active?.rest)
            try store.startCardio(name: "Walk")
            let second = try #require(store.active)
            #expect(second.id != first.id)
            #expect(store.focusToken != firstFocus)
            try store.note(sessionID: second.id, text: "Easy effort")

            try store.startPlanned(plan: template, date: friday)
            #expect(store.active?.id == first.id)
            #expect(store.active?.rest == timer)
            let resumedFocus = try #require(store.focusToken)
            #expect(resumedFocus != firstFocus)
            let reopened = TrainingStore(directory: path, now: { thursday })
            try reopened.load(profileID: owner)
            #expect(reopened.active?.id == first.id)
            #expect(reopened.focusToken == resumedFocus)
            #expect(reopened.sessions.count == 2)
            #expect(reopened.sessions.first { $0.id == second.id }?.notes == "Easy effort")
        }
    }

    @Test func mondayClosesExpiredWorkAtomicallyAndKeepsOnlySavedContent() throws {
        try withDirectory { path in
            let owner = UUID()
            let monday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9)))
            var instant = monday.addingTimeInterval(-60)
            var fail = false
            let store = TrainingStore(directory: path, now: { instant }, beforeSave: {
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
            })
            try store.load(profileID: owner)
            try store.startPlanned(plan: plan(), date: friday)
            let strength = try #require(store.active)
            try confirm(store)
            let lastConfirmedAt = instant
            let draft = try #require(store.active?.exercises[0].sets[1])
            try store.edit(sessionID: strength.id, setID: draft.id, actual: SetActual(reps: 7, load: 35), revision: draft.revision)
            try store.startCardio(name: "Draft cardio")
            let cardio = try #require(store.active)
            try store.updateCardio(sessionID: cardio.id, result: CardioResult(seconds: 90, notes: "Draft"))
            let notes = try store.startExtra(name: "Notes only")
            try store.note(sessionID: notes, text: "Saved plan for next time")
            try store.startExtra(name: "Untouched")
            #expect(store.nextWeekBoundary == monday)

            instant = monday
            fail = true
            #expect(throws: CocoaError.self) { try store.reconcileExpiredSessions() }
            #expect(store.sessions.count == 4 && store.sessions.allSatisfy { $0.finishedAt == nil })
            fail = false
            try store.reconcileExpiredSessions()
            #expect(store.active == nil)
            #expect(store.sessions.count == 3)
            #expect(store.sessions.first { $0.id == notes }?.notes == "Saved plan for next time")
            let saved = try #require(store.sessions.first { $0.id == strength.id })
            #expect(saved.finishedAt == lastConfirmedAt)
            #expect(saved.partial && saved.closedAtWeekBoundary == true && saved.rest == nil && saved.timerUndo == nil)
            #expect(saved.exercises[0].sets[1].actual.reps == 7)
            #expect(saved.exercises[0].sets[1].confirmedAt == nil)
            let cardioSaved = try #require(store.sessions.first { $0.id == cardio.id })
            #expect(cardioSaved.cardioDraft?.notes == "Draft")
            #expect(cardioSaved.cardio == nil && cardioSaved.finishedAt == cardio.startedAt)
            #expect(throws: TrainingError.self) { try store.recordCardio(sessionID: cardio.id, result: CardioResult(seconds: 90)) }

            let occurrence = try #require(store.occurrences.first)
            #expect(store.progress(for: occurrence).completed == 1)
            #expect(throws: TrainingError.self) { try store.startOccurrence(occurrence.id) }
            #expect(throws: TrainingError.self) { try store.move(occurrence.id, to: monday) }
            #expect(throws: TrainingError.self) { try store.skip(occurrence.id) }
            let row = saved.exercises[0].sets[0]
            try store.correct(sessionID: saved.id, setID: row.id, actual: SetActual(reps: 9, load: 40),
                              performedAt: lastConfirmedAt, revision: row.revision)
            #expect(store.progress(for: occurrence).completed == 1)
        }
    }

    @Test func assigningAConfirmedResultCannotAddCreditToAPastPlan() throws {
        try withDirectory { path in
            let monday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9)))
            var instant = friday
            let store = TrainingStore(directory: path, now: { instant })
            try store.load(profileID: UUID())
            let target = UUID()
            try store.scheduleCardio(name: "Walk", date: friday, goalSeconds: 300, id: target)
            let source = try store.startCardio(name: "Walk")
            try store.recordCardio(sessionID: source, result: CardioResult(seconds: 120))
            try store.finish(sessionID: source, partial: false)
            let saved = store.sessions
            instant = monday
            #expect(throws: TrainingError.self) {
                try store.assign(sessionID: source, occurrenceID: target, setID: nil, plannedSetID: nil)
            }
            #expect(store.sessions == saved)
        }
    }

    @Test func staleCardioEditsRejectAtRolloverButFreshHistoryCorrectionWorks() throws {
        try withDirectory { path in
            let monday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9)))
            var instant = monday.addingTimeInterval(-60)
            let store = TrainingStore(directory: path, now: { instant })
            try store.load(profileID: UUID())
            let session = try store.startCardio(name: "Walk")
            instant = instant.addingTimeInterval(30)
            try store.recordCardio(sessionID: session, result: CardioResult(seconds: 60))
            let recordedAt = instant
            instant = monday
            let correction = CardioResult(seconds: 75)
            #expect(throws: TrainingError.self) {
                try store.recordCardio(sessionID: session, result: correction, revision: 1, commandID: UUID())
            }
            let saved = try #require(store.sessions.first)
            #expect(saved.finishedAt == recordedAt && saved.cardio?.seconds == 60)
            try store.recordCardio(sessionID: session, result: correction, revision: 1, commandID: UUID())
            #expect(store.sessions.first?.cardio?.seconds == 75)
            #expect(store.sessions.first?.finishedAt == recordedAt)
        }
    }

    @Test func confirmationCrossingMondayBeforeSaveDoesNotGrantLateCredit() throws {
        try withDirectory { path in
            let monday = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9)))
            var instant = monday.addingTimeInterval(-1)
            var advanceOnSave = false
            let store = TrainingStore(directory: path, now: { instant }, beforeSave: {
                if advanceOnSave { instant = monday }
            })
            try store.load(profileID: UUID())
            try store.startPlanned(plan: plan(), date: friday)
            let occurrence = try #require(store.occurrences.first)
            let original = store.active
            advanceOnSave = true
            #expect(throws: TrainingError.self) { try confirm(store) }
            #expect(store.active == original)
            #expect(store.progress(for: occurrence).completed == 0)
            try store.reconcileExpiredSessions()
            #expect(store.sessions.isEmpty)
        }
    }

    @Test func calendarTicksKeepOutOfOrderCreditsOnTheirPrescribedSlots() throws {
        try withDirectory { directory in
            let store = TrainingStore(directory: directory, now: { thursday })
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

    @Test func swappingAnotherExercisePreservesTheActiveRestAndUndo() throws {
        try withDirectory { path in
            let store = TrainingStore(directory: path, now: { thursday })
            try store.load(profileID: UUID())
            var template = plan()
            template.days[4].exercises.append(PlanExercise(name: "Press", sets: 2))
            let sessionID = try store.startPlanned(plan: template, date: friday)
            let exercises = try #require(store.active?.exercises)
            try store.select(sessionID: sessionID, exerciseID: exercises[1].id)
            try confirm(store)
            let rest = try #require(store.active?.rest)
            let undo = try #require(store.active?.timerUndo)

            let replacementID = try store.substitute(sessionID: sessionID, exerciseID: exercises[1].id,
                                                     prescription: PlanExercise(name: "Replacement", sets: 2), basis: .bodyweight)

            let swapped = try #require(store.active)
            let replacement = swapped.exercises[1]
            #expect(replacement.id == replacementID)
            #expect(swapped.currentExerciseID == exercises[0].id)
            #expect(swapped.rest == rest)
            #expect(swapped.timerUndo == TrainingTimerUndo(setID: undo.setID, previous: undo.previous,
                                                           previousExerciseID: replacement.id, measurementID: undo.measurementID))
            #expect(replacement.sets.map(\.plannedID) == exercises[1].sets.map(\.plannedID))
            let confirmed = swapped.exercises[0].sets[0]
            try store.undo(sessionID: sessionID, setID: confirmed.id, revision: confirmed.revision)
            #expect(store.active?.currentExerciseID == replacement.id)
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
                #expect(throws: TrainingError.self) { try store.finish(sessionID: session.id, partial: true) }
                try store.updateCardio(sessionID: session.id, result: result)
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
            let store = TrainingStore(directory: path, now: { thursday }, beforeSave: { if fail { throw CocoaError(.fileWriteOutOfSpace) } })
            try store.load(profileID: owner)
            let stale = TrainingStore(directory: path, now: { thursday })
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
            let second = try stale.startExtra(name: "Second active workout")
            try store.load(profileID: UUID())
            #expect(store.sessions.isEmpty && store.active == nil && store.focusToken == nil)
            try store.load(profileID: owner)
            #expect(store.sessions.count == 2 && store.active?.id == second)
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
            #expect(extra.exercises[0].sets[0].actual.load == nil)
            #expect(store.suggestedActual(for: extra.exercises[0].sets[0], in: extra.exercises[0])?.load == 50)
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

    @Test(arguments: [false, true])
    func removingAnAddedSetPreservesPlannedRowsAndUnrelatedRest(warmup: Bool) throws {
        try withDirectory { path in
            let owner = UUID()
            var fail = false
            let store = TrainingStore(directory: path, now: { thursday }, beforeSave: {
                if fail { throw CocoaError(.fileWriteOutOfSpace) }
            })
            try store.load(profileID: owner)
            let sessionID = try store.startPlanned(plan: plan(), date: friday)
            try confirm(store)
            let original = try #require(store.active)
            let exercise = original.exercises[0]
            let planned = exercise.sets[1]
            try store.addSet(sessionID: sessionID, exerciseID: exercise.id, warmup: warmup)
            let added = try #require(store.active?.exercises[0].sets.last)
            #expect(added.ordinal == 4 && added.warmup == warmup)
            #expect(throws: TrainingError.self) {
                try store.removeAddedSet(sessionID: sessionID, setID: planned.id, revision: planned.revision)
            }

            try store.edit(sessionID: sessionID, setID: added.id, actual: SetActual(reps: 5), revision: added.revision)
            let edited = try #require(store.active?.exercises[0].sets.last)
            #expect(throws: TrainingError.self) {
                try store.removeAddedSet(sessionID: sessionID, setID: added.id, revision: added.revision)
            }
            fail = true
            #expect(throws: CocoaError.self) {
                try store.removeAddedSet(sessionID: sessionID, setID: edited.id, revision: edited.revision)
            }
            #expect(store.active?.exercises[0].sets.last == edited)
            fail = false

            try store.removeAddedSet(sessionID: sessionID, setID: edited.id, revision: edited.revision)
            #expect(store.active == original)
            let reopened = TrainingStore(directory: path, now: { thursday })
            try reopened.load(profileID: owner)
            #expect(reopened.active == original)
        }
    }

    @Test func removalProtectsOriginalAndLoggedSetsAndKeepsValidRestReferences() throws {
        try withDirectory { path in
            let planner = PlanningStore(directory: path.appending(path: "Planning"))
            try planner.load()
            let store = TrainingStore(directory: path.appending(path: "Training"), now: { thursday })
            try store.load(profileID: try #require(planner.profileID))
            let sessionID = try store.startExtra(name: "Ad hoc workout")
            try store.add(sessionID: sessionID, prescription: PlanExercise(name: "Row", sets: 2), basis: .external)
            let exercise = try #require(store.active?.exercises.first)
            let original = exercise.sets[0]
            #expect(throws: TrainingError.self) {
                try store.removeAddedSet(sessionID: sessionID, setID: original.id, revision: original.revision)
            }
            try store.configureRest(sessionID: sessionID, exerciseID: exercise.id, seconds: 90)
            try store.addSet(sessionID: sessionID, exerciseID: exercise.id, warmup: false)
            try confirm(store, row: 2)
            let logged = try #require(store.active?.exercises[0].sets[2])
            #expect(throws: TrainingError.self) {
                try store.removeAddedSet(sessionID: sessionID, setID: logged.id, revision: logged.revision)
            }
            try store.pauseRest(sessionID: sessionID)
            try store.undo(sessionID: sessionID, setID: logged.id, revision: logged.revision)
            #expect(store.active?.rest?.sourceSetID == logged.id)
            let pending = try #require(store.active?.exercises[0].sets[2])
            try store.removeAddedSet(sessionID: sessionID, setID: pending.id, revision: pending.revision)
            #expect(store.active?.rest == nil)
            #expect(store.active?.exercises[0].sets == exercise.sets)
            try WorkoutBackup(planner, store).validate()
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
