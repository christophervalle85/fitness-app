import Darwin
import Foundation
import Observation
import SwiftData

enum TrainingSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Head.self, Entry.self] }

    @Model final class Head {
        var revision: Int
        init() { revision = 0 }
    }

    @Model final class Entry {
        @Attribute(.unique) var id: UUID
        var kind: String
        var data: Data
        init(id: UUID, kind: String, data: Data) {
            self.id = id
            self.kind = kind
            self.data = data
        }
    }
}

@MainActor @Observable
final class TrainingStore {
    private(set) var sessions: [TrainingSession] = []
    private(set) var occurrences: [TrainingOccurrence] = []
    var active: TrainingSession? { sessions.first { $0.finishedAt == nil } }
    var knownExercises: [PlanExercise] {
        var seen = Set<UUID>()
        return sessions.reversed().flatMap(\.exercises).map(\.prescription).filter { seen.insert($0.id).inserted }
    }

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let beforeSave: () throws -> Void
    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var revision = 0

    convenience init() {
        var directory = URL.applicationSupportDirectory.appending(path: "Training")
        #if WEEKFORM_DEVELOPMENT
        if let run = ProcessInfo.processInfo.environment["WEEKFORM_UI_TEST_RUN"].flatMap(UUID.init(uuidString:)) {
            directory = directory.appending(path: run.uuidString)
        }
        #endif
        self.init(directory: directory)
    }

    init(directory: URL, now: @escaping () -> Date = { Date() }, beforeSave: @escaping () throws -> Void = {}) {
        root = directory
        self.now = now
        self.beforeSave = beforeSave
    }

    func load(profileID: UUID) throws {
        let directory = root.appending(path: profileID.uuidString)
        // Clear the previous profile before opening a different owner, including on failure.
        if self.directory != directory {
            sessions = []
            occurrences = []
            self.directory = nil
        }
        try withDatabase(directory) { context, head in
            let rows = try context.fetch(FetchDescriptor<TrainingSchemaV1.Entry>())
            let decoder = JSONDecoder()
            let logged = try rows.filter { $0.kind == "session" }.map { try decoder.decode(TrainingSession.self, from: $0.data) }
            let planned = try rows.filter { $0.kind == "occurrence" }.map { try decoder.decode(TrainingOccurrence.self, from: $0.data) }
            guard logged.count + planned.count == rows.count, logged.filter({ $0.finishedAt == nil }).count <= 1 else {
                throw TrainingError("The saved workouts could not be read.")
            }
            sessions = logged.sorted { $0.startedAt < $1.startedAt }
            occurrences = planned
            revision = head.revision
            self.directory = directory
        }
    }

    func isScheduled(_ occurrence: TrainingOccurrence, on date: Date) -> Bool { occurrence.scheduledDay == CivilTrainingDay(date) }
    func isOriginal(_ occurrence: TrainingOccurrence, on date: Date) -> Bool { occurrence.sourceDay == CivilTrainingDay(date) }
    func isPerformed(_ session: TrainingSession, on date: Date) -> Bool { session.performedDay == CivilTrainingDay(date) }

    func progress(for occurrence: TrainingOccurrence) -> (completed: Int, total: Int) {
        let linked = sessions.filter { $0.occurrenceID == occurrence.id }
        if let goal = occurrence.cardioGoalSeconds {
            let seconds = linked.compactMap { $0.cardio?.seconds }.reduce(0) { $0 + min($1, Int.max - $0) }
            return (min(seconds, goal), goal)
        }
        let ids = Set(occurrence.plannedSets.values.joined())
        return (ids.intersection(creditedIDs(in: linked)).count, ids.count)
    }

    func remainingSetIDs(for occurrence: TrainingOccurrence) -> Set<UUID> {
        let credited = creditedIDs(in: sessions.filter { $0.occurrenceID == occurrence.id })
        return Set(occurrence.plannedSets.values.joined()).subtracting(credited)
    }

    func status(for occurrence: TrainingOccurrence) -> String {
        if occurrence.skipped { return "Skipped" }
        let (completed, total) = progress(for: occurrence)
        guard total > 0, completed == total else { return completed > 0 ? "Partial" : "Scheduled" }
        let contributors = sessions.filter {
            $0.occurrenceID == occurrence.id && ($0.cardio != nil || !creditedIDs(in: [$0]).isEmpty)
        }
        return contributors.allSatisfy { $0.performedDay.date < occurrence.date } ? "Done early" : "Done"
    }

    private func creditedIDs(in sessions: [TrainingSession]) -> Set<UUID> {
        Set(sessions.flatMap(\.exercises).flatMap(\.sets).filter { $0.confirmedAt != nil && $0.warmup != true }.compactMap(\.plannedID))
    }

    private func planned(_ plan: WeekPlan, _ date: Date) throws -> TrainingOccurrence {
        let civil = CivilTrainingDay(date)
        if let existing = occurrences.first(where: { $0.planID == plan.id && $0.sourceDay == civil }) {
            return existing
        }
        guard !plan.archived, plan.days.indices.contains(civil.mondayIndex) else { throw TrainingError("Choose a scheduled workout.") }
        let day = plan.days[civil.mondayIndex]
        guard !day.exercises.isEmpty || day.cardioGoalSeconds != nil else { throw TrainingError("This is a rest day.") }
        var occurrence = TrainingOccurrence(name: day.name, sourceDay: civil, scheduledDay: civil, planID: plan.id, day: day,
                                            restSeconds: plan.restSeconds, cardioGoalSeconds: day.cardioGoalSeconds)
        if let duration = day.cardioGoalSeconds {
            guard duration > 0, day.exercises.isEmpty else { throw TrainingError("Check the scheduled cardio goal.") }
        }
        for exercise in day.exercises {
            guard exercise.sets > 0, exercise.sets <= 1000, occurrence.plannedSets[exercise.id] == nil else {
                throw TrainingError("Check the prescribed set count and exercise identities.")
            }
            occurrence.plannedSets[exercise.id] = (0..<exercise.sets).map { _ in UUID() }
        }
        return occurrence
    }

    @discardableResult func materialize(plan: WeekPlan, date: Date) throws -> UUID {
        let occurrence = try planned(plan, date)
        if !occurrences.contains(where: { $0.id == occurrence.id }) { try commit(occurrence: occurrence) }
        return occurrence.id
    }

    func assign(sessionID: UUID, occurrenceID: UUID, setID: UUID?, plannedSetID: UUID?) throws {
        guard let occurrence = occurrences.first(where: { $0.id == occurrenceID }) else {
            throw TrainingError("Choose a scheduled workout.")
        }
        try assign(sessionID: sessionID, to: occurrence, setID: setID, plannedSetID: plannedSetID)
    }

    func assign(sessionID: UUID, plan: WeekPlan, date: Date, setID: UUID?, exerciseID: UUID?, slot: Int?) throws {
        let occurrence = try planned(plan, date)
        guard isScheduled(occurrence, on: date) else { throw TrainingError("This workout moved to another date.") }
        var target: UUID?
        if let exerciseID, let slot, let slots = occurrence.plannedSets[exerciseID], slots.indices.contains(slot) {
            target = slots[slot]
        } else if exerciseID != nil || slot != nil {
            throw TrainingError("Choose a planned set in this workout.")
        }
        try assign(sessionID: sessionID, to: occurrence, setID: setID, plannedSetID: target)
    }

    private func assign(sessionID: UUID, to occurrence: TrainingOccurrence, setID: UUID?, plannedSetID: UUID?) throws {
        guard var session = sessions.first(where: { $0.id == sessionID }),
              session.finishedAt != nil, session.occurrenceID == nil || session.occurrenceID == occurrence.id else {
            throw TrainingError("Choose a saved session that is available for this workout.")
        }
        guard !occurrence.skipped else { throw TrainingError("This workout was skipped.") }
        guard active?.occurrenceID != occurrence.id else { throw TrainingError("Finish the open contribution before assigning more work.") }
        if session.isCardio {
            guard occurrence.cardioGoalSeconds != nil, session.cardio != nil, setID == nil, plannedSetID == nil else {
                throw TrainingError("Assign a confirmed cardio activity to a scheduled cardio goal.")
            }
            if session.occurrenceID == occurrence.id { return }
            let progress = progress(for: occurrence)
            guard progress.completed < progress.total else { throw TrainingError("This cardio goal is already fulfilled.") }
        } else {
            guard let setID, let plannedSetID, let day = occurrence.day,
                  let target = day.exercises.first(where: { occurrence.plannedSets[$0.id]?.contains(plannedSetID) == true }) else {
                throw TrainingError("Choose the planned set this result fulfills.")
            }
            let (i, j) = try location(setID, session)
            let exercise = session.exercises[i]
            let set = exercise.sets[j]
            guard set.confirmedAt != nil, set.warmup != true else { throw TrainingError("Only confirmed working sets can fulfill a planned set.") }
            if set.plannedID == plannedSetID, session.occurrenceID == occurrence.id { return }
            guard exercise.matchesPlannedItem(target) else {
                throw TrainingError("Choose a matching exercise and result type.")
            }
            guard set.plannedID == nil, !creditedIDs(in: sessions.filter { $0.occurrenceID == occurrence.id }).contains(plannedSetID) else {
                throw TrainingError("This result or planned set already has a credit.")
            }
            session.exercises[i].sets[j].plannedID = plannedSetID
            session.exercises[i].sets[j].revision = try increment(session.exercises[i].sets[j].revision)
        }
        session.occurrenceID = occurrence.id
        try commit(session: session, occurrence: occurrence)
    }

    func startPlanned(plan: WeekPlan, date: Date) throws {
        let occurrence = try planned(plan, date)
        guard isScheduled(occurrence, on: date) else { throw TrainingError("This workout moved to another date.") }
        try start(occurrence)
    }

    func startOccurrence(_ id: UUID) throws {
        guard let occurrence = occurrences.first(where: { $0.id == id }) else { throw TrainingError("Choose a scheduled workout.") }
        try start(occurrence)
    }

    private func start(_ occurrence: TrainingOccurrence) throws {
        guard active == nil else { throw TrainingError("Resume or finish your open workout first.") }
        let (completed, total) = progress(for: occurrence)
        guard !occurrence.skipped, completed < total else { throw TrainingError("This planned workout is already closed.") }
        let instant = now()
        var session = TrainingSession(name: occurrence.name, startedAt: instant, performedDay: CivilTrainingDay(instant),
                                      occurrenceID: occurrence.id, isCardio: occurrence.cardioGoalSeconds != nil)
        let credited = creditedIDs(in: sessions.filter { $0.occurrenceID == occurrence.id })
        for prescription in occurrence.day?.exercises ?? [] {
            let original = occurrence.plannedSets[prescription.id] ?? []
            let pending = original.filter { !credited.contains($0) }
            if !pending.isEmpty {
                session.exercises.append(makeExercise(prescription, basis: LoadBasis(prescription),
                                                       slots: pending.map(Optional.some), rest: occurrence.restSeconds,
                                                       ordinals: original.indices.filter { !credited.contains(original[$0]) }.map { $0 + 1 }))
            }
        }
        session.currentExerciseID = session.exercises.first?.id
        try commit(session: session, occurrence: occurrence)
    }

    func startExtra(name: String) throws { try startExtra(name: name, cardio: false) }
    func startCardio(name: String) throws { try startExtra(name: name, cardio: true) }

    private func startExtra(name: String, cardio: Bool) throws {
        guard active == nil else { throw TrainingError("Resume or finish your open workout first.") }
        let instant = now()
        try commit(session: TrainingSession(name: try nonempty(name), startedAt: instant, performedDay: CivilTrainingDay(instant),
                                           isCardio: cardio))
    }

    func scheduleCardio(name: String, date: Date, goalSeconds: Int) throws {
        guard goalSeconds > 0 else { throw TrainingError("Enter a positive duration goal.") }
        let day = CivilTrainingDay(date)
        try commit(occurrence: TrainingOccurrence(name: try nonempty(name), sourceDay: day, scheduledDay: day, cardioGoalSeconds: goalSeconds))
    }

    func move(_ occurrenceID: UUID, to date: Date) throws {
        guard var occurrence = occurrences.first(where: { $0.id == occurrenceID }), !occurrence.skipped else {
            throw TrainingError("Choose a scheduled workout.")
        }
        occurrence.scheduledDay = CivilTrainingDay(date)
        try commit(occurrence: occurrence)
    }

    func skip(_ occurrenceID: UUID) throws {
        guard var occurrence = occurrences.first(where: { $0.id == occurrenceID }) else { throw TrainingError("Choose a scheduled workout.") }
        let progress = progress(for: occurrence)
        guard progress.completed < progress.total, active?.occurrenceID != occurrenceID else {
            throw TrainingError("Only an unfinished workout without an active session can be skipped.")
        }
        occurrence.skipped = true
        try commit(occurrence: occurrence)
    }

    private func makeExercise(_ prescription: PlanExercise, basis: LoadBasis, slots: [UUID?], rest: Int?, ordinals: [Int]? = nil) -> TrainingExercise {
        let target = TrainingExercise(prescription: prescription, basis: basis, sets: [], restSeconds: rest)
        let identity = RecordIdentity(target)
        let match = sessions.flatMap(\.exercises).filter { RecordIdentity($0) == identity }
            .flatMap(\.sets).filter { $0.confirmedAt != nil && $0.warmup != true }
        let latest = match.max { ($0.confirmedAt ?? .distantPast) < ($1.confirmedAt ?? .distantPast) }
        let starting = SetActual(load: basis == .bodyweight ? nil : prescription.startingLoad, unit: prescription.loadUnit)
        let sets = slots.enumerated().map { index, slot in
            TrainingSet(plannedID: slot, ordinal: ordinals?[index] ?? index + 1,
                        actual: latest?.actual.converted(to: prescription.loadUnit) ?? starting, previousAt: latest?.confirmedAt)
        }
        return TrainingExercise(prescription: prescription, basis: basis, sets: sets, restSeconds: rest)
    }

    private func increment(_ value: Int) throws -> Int {
        guard value >= 0, value < Int.max - 1 else { throw TrainingError("This saved workout counter is outside the supported range.") }
        return value + 1
    }

    private func nonempty(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TrainingError("Give the workout or exercise a name.") }
        return trimmed
    }

    private func withSession(_ id: UUID, allowFinished: Bool = false, _ change: (inout TrainingSession) throws -> Void) throws {
        guard var session = sessions.first(where: { $0.id == id }), allowFinished || session.finishedAt == nil else {
            throw TrainingError("This workout is no longer active.")
        }
        try change(&session)
        try commit(session: session)
    }

    private func location(_ set: UUID, _ session: TrainingSession) throws -> (Int, Int) {
        for index in session.exercises.indices {
            if let row = session.exercises[index].sets.firstIndex(where: { $0.id == set }) { return (index, row) }
        }
        throw TrainingError("This set is no longer available.")
    }

    func edit(sessionID: UUID, setID: UUID, actual: SetActual, revision: Int) throws {
        try withSession(sessionID, allowFinished: true) { session in
            let (i, j) = try location(setID, session)
            let set = session.exercises[i].sets[j]
            guard set.revision == revision else { throw TrainingError("Review the latest set values.") }
            if set.confirmedAt != nil { try actual.validate(for: session.exercises[i].basis) }
            else if session.finishedAt != nil { throw TrainingError("This workout has finished.") }
            guard actual != set.actual else { return }
            session.exercises[i].sets[j].actual = actual
            session.exercises[i].sets[j].previousAt = nil
            session.exercises[i].sets[j].revision = try increment(session.exercises[i].sets[j].revision)
        }
    }

    func correct(sessionID: UUID, setID: UUID, actual: SetActual, performedAt: Date, revision: Int) throws {
        try withSession(sessionID, allowFinished: true) { session in
            let (i, j) = try location(setID, session)
            let row = session.exercises[i].sets[j]
            guard row.revision == revision, row.confirmedAt != nil else { throw TrainingError("Review the latest saved set.") }
            guard performedAt >= session.startedAt, performedAt <= (session.finishedAt ?? now()) else {
                throw TrainingError("Choose a time within this workout, or change the workout date first.")
            }
            try actual.validate(for: session.exercises[i].basis)
            if row.actual == actual, row.confirmedAt == performedAt { return }
            session.exercises[i].sets[j].actual = actual
            session.exercises[i].sets[j].confirmedAt = performedAt
            session.exercises[i].sets[j].previousAt = nil
            session.exercises[i].sets[j].revision = try increment(session.exercises[i].sets[j].revision)
        }
    }

    func redate(sessionID: UUID, startedAt: Date) throws {
        try withSession(sessionID, allowFinished: true) { session in
            guard let finish = session.finishedAt else { throw TrainingError("Finish the workout before changing its date.") }
            let delta = startedAt.timeIntervalSince(session.startedAt)
            let newFinish = finish.addingTimeInterval(delta)
            guard startedAt.timeIntervalSinceReferenceDate.isFinite, newFinish <= now() else {
                throw TrainingError("Choose a date that keeps the completed workout in the past.")
            }
            guard delta != 0 else { return }
            session.startedAt = startedAt
            session.performedDay = CivilTrainingDay(startedAt)
            session.finishedAt = newFinish
            for i in session.exercises.indices {
                for j in session.exercises[i].sets.indices {
                    if let old = session.exercises[i].sets[j].confirmedAt {
                        session.exercises[i].sets[j].confirmedAt = old.addingTimeInterval(delta)
                        session.exercises[i].sets[j].revision = try increment(session.exercises[i].sets[j].revision)
                    }
                }
            }
            session.restHistory = session.restHistory.map { item in
                var interval = item.interval
                interval.startedAt = interval.startedAt.addingTimeInterval(delta)
                interval.pausedAt = interval.pausedAt?.addingTimeInterval(delta)
                return RestMeasurement(id: item.id, interval: interval, endedAt: item.endedAt.addingTimeInterval(delta),
                                       precise: item.precise)
            }
        }
    }

    func confirm(sessionID: UUID, setID: UUID, actual: SetActual, revision: Int, commandID: UUID) throws {
        let receipt = ConfirmationReceipt(setID: setID, actual: actual, expectedRevision: revision)
        if let old = sessions.first(where: { $0.id == sessionID })?.receipts[commandID] {
            guard old == receipt else { throw TrainingError("This action already confirmed different values.") }
            return
        }
        try withSession(sessionID) { session in
            let (i, j) = try location(setID, session)
            let exercise = session.exercises[i]
            let set = exercise.sets[j]
            guard set.revision == revision, set.confirmedAt == nil else { throw TrainingError("Review the latest set values.") }
            try actual.validate(for: exercise.basis)
            if let planned = set.plannedID, creditedIDs(in: sessions.filter { $0.occurrenceID == session.occurrenceID }).contains(planned) {
                throw TrainingError("This planned set has already been credited.")
            }
            let instant = now()
            session.exercises[i].sets[j].actual = actual
            session.exercises[i].sets[j].confirmedAt = instant
            session.exercises[i].sets[j].previousAt = nil
            session.exercises[i].sets[j].revision = try increment(session.exercises[i].sets[j].revision)
            session.receipts[commandID] = receipt
            let measurement = session.rest.map { RestMeasurement(interval: $0, endedAt: instant, precise: false) }
            if let measurement { session.restHistory.append(measurement) }
            session.timerUndo = TrainingTimerUndo(setID: setID, previous: session.rest, previousExerciseID: session.currentExerciseID,
                                                 measurementID: measurement?.id)
            session.currentExerciseID = exercise.id
            session.rest = nil
            if let seconds = exercise.restSeconds, session.exercises[i].sets.contains(where: { $0.confirmedAt == nil }) {
                session.rest = TrainingRest(sourceSetID: setID, startedAt: instant, targetSeconds: seconds)
            }
        }
    }

    func undo(sessionID: UUID, setID: UUID, revision: Int) throws {
        try withSession(sessionID, allowFinished: true) { session in
            let (i, j) = try location(setID, session)
            let set = session.exercises[i].sets[j]
            guard set.revision == revision, set.confirmedAt != nil else { throw TrainingError("Review the latest set before undoing it.") }
            session.exercises[i].sets[j].confirmedAt = nil
            session.exercises[i].sets[j].revision = try increment(session.exercises[i].sets[j].revision)
            if let undo = session.timerUndo, undo.setID == setID {
                if let measurementID = undo.measurementID { session.restHistory.removeAll { $0.id == measurementID } }
                session.rest = undo.previous
                session.currentExerciseID = undo.previousExerciseID
                session.timerUndo = nil
            } else if session.timerUndo?.previous?.sourceSetID == setID {
                // Undoing a later confirmation must not bring back an interval
                // whose own originating set was already withdrawn.
                session.timerUndo?.previous = nil
            }
        }
    }

    func select(sessionID: UUID, exerciseID: UUID) throws {
        try withSession(sessionID) { session in
            guard session.exercises.contains(where: { $0.id == exerciseID }) else { throw TrainingError("Choose an exercise in this workout.") }
            if session.currentExerciseID != exerciseID { session.timerUndo = nil }
            session.currentExerciseID = exerciseID
        }
    }

    private func validate(_ p: PlanExercise) throws {
        _ = try nonempty(p.name)
        guard (1...1000).contains(p.sets), p.low > 0, p.high >= p.low else { throw TrainingError("Check the exercise prescription.") }
    }

    func add(sessionID: UUID, prescription: PlanExercise, basis: LoadBasis) throws {
        try validate(prescription)
        guard (basis == .timed) == prescription.timed else { throw TrainingError("Choose a target that matches the recording method.") }
        try withSession(sessionID) { session in
            guard !session.isCardio else { throw TrainingError("Log duration for a cardio workout.") }
            let rest = occurrences.first(where: { $0.id == session.occurrenceID })?.restSeconds
            let exercise = makeExercise(prescription, basis: basis, slots: Array(repeating: nil, count: prescription.sets), rest: rest)
            session.exercises.append(exercise)
            session.currentExerciseID = exercise.id
            session.timerUndo = nil
        }
    }

    func addSet(sessionID: UUID, exerciseID: UUID, warmup: Bool) throws {
        try withSession(sessionID) { session in
            guard let i = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { throw TrainingError("Choose an exercise.") }
            let exercise = session.exercises[i]
            var set = TrainingSet(ordinal: try increment(exercise.sets.compactMap(\.ordinal).max() ?? 0),
                                  warmup: warmup, optional: true, actual: SetActual(unit: exercise.prescription.loadUnit))
            if !warmup {
                let suggested = makeExercise(exercise.prescription, basis: exercise.basis, slots: [nil], rest: exercise.restSeconds)
                if let first = suggested.sets.first {
                    set.actual = first.actual
                    set.previousAt = first.previousAt
                }
            }
            session.exercises[i].sets.append(set)
        }
    }

    func substitute(sessionID: UUID, exerciseID: UUID, prescription: PlanExercise, basis: LoadBasis) throws {
        try validate(prescription)
        guard (basis == .timed) == prescription.timed else { throw TrainingError("Choose a target that matches the recording method.") }
        try withSession(sessionID) { session in
            guard let i = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { throw TrainingError("Choose the exercise to replace.") }
            let old = session.exercises[i]
            let remaining = old.sets.filter { $0.confirmedAt == nil }
            guard !remaining.isEmpty else { throw TrainingError("All sets for this exercise are confirmed.") }
            var replacement = makeExercise(prescription, basis: basis, slots: remaining.map(\.plannedID), rest: old.restSeconds,
                                           ordinals: remaining.enumerated().map { $0.element.ordinal ?? $0.offset + 1 })
            for j in remaining.indices {
                replacement.sets[j].warmup = remaining[j].warmup
                replacement.sets[j].optional = remaining[j].optional
                if remaining[j].warmup == true {
                    replacement.sets[j].actual = SetActual(unit: prescription.loadUnit)
                    replacement.sets[j].previousAt = nil
                }
            }
            replacement.replacedPrescription = old.replacedPrescription ?? old.prescription
            replacement.prescription.sets = remaining.count
            session.exercises[i].sets.removeAll { $0.confirmedAt == nil }
            if session.exercises[i].sets.isEmpty { session.exercises[i] = replacement }
            else { session.exercises.insert(replacement, at: i + 1) }
            session.currentExerciseID = replacement.id
            session.rest = nil
            session.timerUndo = nil
        }
    }

    func setBasis(sessionID: UUID, exerciseID: UUID, basis: LoadBasis) throws {
        try withSession(sessionID) { session in
            guard let i = session.exercises.firstIndex(where: { $0.id == exerciseID }),
                  session.exercises[i].sets.allSatisfy({ $0.confirmedAt == nil }) else {
                throw TrainingError("Change logging type before confirming sets.")
            }
            guard (basis == .timed) == session.exercises[i].prescription.timed else {
                throw TrainingError("Swap the exercise to change between rep and duration targets.")
            }
            guard session.exercises[i].basis != basis else { return }
            session.exercises[i].basis = basis
            for j in session.exercises[i].sets.indices {
                session.exercises[i].sets[j].actual = SetActual(unit: session.exercises[i].prescription.loadUnit)
                session.exercises[i].sets[j].previousAt = nil
                session.exercises[i].sets[j].revision = try increment(session.exercises[i].sets[j].revision)
            }
        }
    }

    func note(sessionID: UUID, text: String) throws { try withSession(sessionID) { $0.notes = text } }

    func renameCardio(sessionID: UUID, name: String) throws {
        try withSession(sessionID) { session in
            guard session.isCardio else { throw TrainingError("Choose a cardio workout.") }
            session.name = try nonempty(name)
        }
    }

    func updateCardio(sessionID: UUID, result: CardioResult) throws {
        try withSession(sessionID) { session in
            guard session.isCardio else { throw TrainingError("Choose a cardio workout.") }
            session.cardioDraft = result
        }
    }

    func recordCardio(sessionID: UUID, result: CardioResult) throws {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { throw TrainingError("Choose a cardio workout.") }
        if session.cardio == result { return }
        guard session.cardio == nil else { throw TrainingError("Review the saved activity before making a correction.") }
        try recordCardio(sessionID: sessionID, result: result, revision: session.cardioRevision, commandID: UUID())
    }

    func recordCardio(sessionID: UUID, result: CardioResult, revision: Int, commandID: UUID) throws {
        try result.validate()
        let receipt = CardioReceipt(result: result, revision: revision)
        if let saved = sessions.first(where: { $0.id == sessionID })?.cardioReceipts?[commandID] {
            guard saved == receipt else { throw TrainingError("This action already saved a different activity.") }
            return
        }
        try withSession(sessionID, allowFinished: true) { session in
            guard session.isCardio, revision == session.cardioRevision else { throw TrainingError("Review the latest activity.") }
            session.cardioDraft = result
            session.cardio = result
            session.cardioVersion = try increment(revision)
            var receipts = session.cardioReceipts ?? [:]
            receipts[commandID] = receipt
            session.cardioReceipts = receipts
        }
    }

    func finish(sessionID: UUID, partial: Bool) throws {
        try withSession(sessionID) { session in
            if session.isCardio {
                guard session.cardio != nil else { throw TrainingError("Confirm a cardio duration before finishing.") }
                if !partial, let occurrence = occurrences.first(where: { $0.id == session.occurrenceID }) {
                    let p = progress(for: occurrence)
                    guard p.completed >= p.total else { throw TrainingError("Finish this shorter contribution as partial.") }
                }
            } else if !partial {
                let rows = session.exercises.flatMap(\.sets)
                guard rows.contains(where: { $0.confirmedAt != nil }), rows.allSatisfy({ $0.optional == true || $0.confirmedAt != nil }) else {
                    throw TrainingError("Confirm the remaining sets or finish as partial.")
                }
            }
            session.partial = partial
            session.finishedAt = now()
            session.rest = nil
            session.timerUndo = nil
        }
    }

    func cancelEmpty(sessionID: UUID) throws {
        guard let session = active, session.id == sessionID, session.cardio == nil,
              session.exercises.flatMap(\.sets).allSatisfy({ $0.confirmedAt == nil }) else {
            throw TrainingError("Finish a workout with saved results.")
        }
        try commit(deletingSession: sessionID)
    }

    func startSet(sessionID: UUID) throws {
        try withSession(sessionID) { session in
            if let interval = session.rest {
                session.restHistory.append(RestMeasurement(interval: interval, endedAt: now(), precise: true))
            }
            session.rest = nil
            session.timerUndo = nil
        }
    }
    func pauseRest(sessionID: UUID) throws { try changeRest(sessionID) { if $0.pausedAt == nil { $0.pausedAt = now() } } }
    func resumeRest(sessionID: UUID) throws {
        try changeRest(sessionID) {
            if let paused = $0.pausedAt { $0.pausedSeconds += max(0, now().timeIntervalSince(paused)); $0.pausedAt = nil }
        }
    }
    func resetRest(sessionID: UUID) throws {
        try changeRest(sessionID) { rest in
            let instant = now()
            let measured = (rest.measuredBeforeReset ?? 0) + rest.elapsed(at: instant)
            rest = TrainingRest(sourceSetID: rest.sourceSetID, startedAt: instant, targetSeconds: rest.targetSeconds,
                                measuredBeforeReset: measured)
        }
    }
    func extendRest(sessionID: UUID, seconds: Int) throws {
        try changeRest(sessionID) {
            guard seconds > 0, $0.targetSeconds <= Int.max - seconds else { throw TrainingError("Enter a valid extension.") }
            $0.targetSeconds += seconds
        }
    }

    private func changeRest(_ sessionID: UUID, _ change: (inout TrainingRest) throws -> Void) throws {
        try withSession(sessionID) { session in
            guard var rest = session.rest else { throw TrainingError("There is no active rest interval.") }
            try change(&rest)
            session.rest = rest
            session.timerUndo = nil
        }
    }

    func configureRest(sessionID: UUID, exerciseID: UUID, seconds: Int?) throws {
        if let seconds, seconds < 1 { throw TrainingError("Enter a positive rest duration.") }
        try withSession(sessionID) { session in
            guard let i = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { throw TrainingError("Choose an exercise.") }
            session.exercises[i].restSeconds = seconds
        }
    }

    private func commit(session: TrainingSession? = nil, occurrence: TrainingOccurrence? = nil, deletingSession: UUID? = nil) throws {
        guard let directory else { throw TrainingError("Open your local profile and try again.") }
        try withDatabase(directory) { context, head in
            guard head.revision == revision else { throw TrainingError("Workout data changed. Reopen the workout before retrying.") }
            if let session { try write(session, kind: "session", context: context) }
            if let occurrence { try write(occurrence, kind: "occurrence", context: context) }
            if let deletingSession, let row = try fetch(deletingSession, context) { context.delete(row) }
            head.revision = try increment(head.revision)
            try beforeSave()
            try context.save()
            revision = head.revision
        }
        if let session {
            if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i] = session }
            else { sessions.append(session) }
        }
        if let occurrence {
            if let i = occurrences.firstIndex(where: { $0.id == occurrence.id }) { occurrences[i] = occurrence }
            else { occurrences.append(occurrence) }
        }
        if let deletingSession { sessions.removeAll { $0.id == deletingSession } }
    }

    private func fetch(_ id: UUID, _ context: ModelContext) throws -> TrainingSchemaV1.Entry? {
        try context.fetch(FetchDescriptor<TrainingSchemaV1.Entry>(predicate: #Predicate { $0.id == id })).first
    }

    private func write<T: Codable & Identifiable>(_ value: T, kind: String, context: ModelContext) throws where T.ID == UUID {
        let data = try JSONEncoder().encode(value)
        if let row = try fetch(value.id, context) {
            guard row.kind == kind else { throw TrainingError("The saved record could not be updated.") }
            row.data = data
        } else { context.insert(TrainingSchemaV1.Entry(id: value.id, kind: kind, data: data)) }
    }

    private func withDatabase<T>(_ directory: URL, _ action: (ModelContext, TrainingSchemaV1.Head) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appending(path: "writer.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw TrainingError("Your workout is being saved. Try again.") }
        let schema = Schema(versionedSchema: TrainingSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: directory.appending(path: "training.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let heads = try context.fetch(FetchDescriptor<TrainingSchemaV1.Head>())
        let head: TrainingSchemaV1.Head
        if let first = heads.first {
            guard heads.count == 1 else { throw TrainingError("The training store could not be opened.") }
            head = first
        } else {
            head = TrainingSchemaV1.Head()
            context.insert(head)
        }
        return try action(context, head)
    }
}

extension TrainingStore {
    func stage(_ backup: WorkoutBackup) throws {
        let target = root.appending(path: backup.owner.uuidString)
        try withDatabase(target) { context, head in
            guard try context.fetchCount(FetchDescriptor<TrainingSchemaV1.Entry>()) == 0 else {
                throw TrainingError("Choose an empty restore destination.")
            }
            for session in backup.sessions { try write(session, kind: "session", context: context) }
            for occurrence in backup.occurrences { try write(occurrence, kind: "occurrence", context: context) }
            head.revision = 1
            try context.save()
        }
    }
}
