import Foundation

enum WeightUnits {
    static let kilogramsPerPound = 0.45359237

    static func convert(_ value: Double, from source: String, to destination: String) -> Double {
        if source == destination { return value }
        switch (source, destination) {
        case ("lb", "kg"): return value * kilogramsPerPound
        case ("kg", "lb"): return value / kilogramsPerPound
        default: return .nan
        }
    }

    static func equal(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(lhs.ulp, rhs.ulp) * 8
    }
}

extension SetActual {
    func converted(to target: String) -> SetActual {
        guard unit != target else { return self }
        var value = self
        value.load = load.map { WeightUnits.convert($0, from: unit, to: target) }
        value.rightLoad = rightLoad.map { WeightUnits.convert($0, from: unit, to: target) }
        value.unit = target
        return value
    }
}

struct RecordIdentity: Hashable {
    let variant: UUID
    let name: String
    let convention: String
    let basis: LoadBasis
    let machineProfile: UUID?
    let side: String?

    init(_ exercise: TrainingExercise, side: String? = nil) {
        let p = exercise.prescription
        variant = p.variantID ?? p.id
        name = p.name
        convention = p.convention
        basis = exercise.basis
        // Legacy rows have no equipment-profile ID. Within those rows the
        // original prescription is the narrowest repeatable machine identity.
        machineProfile = [.machine, .assisted].contains(exercise.basis) ? p.id : nil
        self.side = side
    }
}

struct ProgressSet: Identifiable {
    let id: UUID
    let sessionID: UUID
    let date: Date
    let kg: Double?
    let reps: Int?
    let seconds: Int?
}

struct ExerciseRecords: Identifiable {
    let id: RecordIdentity
    let name: String
    var basis: LoadBasis { id.basis }
    var side: String? { id.side }
    var trend: [ProgressSet]
    let heaviest: ProgressSet?
    let repBests: [ProgressSet]

    init(id: RecordIdentity, name: String, rows: [ProgressSet]) {
        self.id = id
        self.name = name
        trend = rows.sorted { a, b in a.date == b.date ? a.id.uuidString < b.id.uuidString : a.date < b.date }
        guard ![.timed, .assisted, .bodyweight].contains(id.basis) else {
            heaviest = nil
            repBests = []
            return
        }
        var best: ProgressSet?
        var byReps: [Int: ProgressSet] = [:]
        for row in trend {
            guard let reps = row.reps, let weight = row.kg else { continue }
            if Self.improves(weight: weight, reps: reps, over: best) { best = row }
            if Self.improves(weight: weight, reps: reps, over: byReps[reps]) { byReps[reps] = row }
        }
        heaviest = best
        repBests = byReps.keys.sorted().compactMap { byReps[$0] }
    }

    private static func improves(weight: Double, reps: Int, over previous: ProgressSet?) -> Bool {
        guard let previous, let best = previous.kg else { return true }
        if WeightUnits.equal(weight, best) { return reps > (previous.reps ?? 0) }
        return weight > best
    }
}

struct ProgressionSuggestion: Identifiable {
    let id: UUID // The particular prescription instance in the qualifying session.
    let sessionID: UUID
    let name: String
    let date: Date
    let kg: Double
}

struct ProgressActivityDay: Identifiable {
    let date: Date
    let sessions: [TrainingSession]
    var id: Date { date }
}

struct ProgressMetrics {
    let history: [TrainingSession]
    let activityDays: [ProgressActivityDay]
    let sessionCount: Int
    let cardioCount: Int
    let cardioSeconds: Int
    let adherence: (fulfilled: Int, scheduled: Int)
    let knownAdherence: (fulfilled: Int, scheduled: Int)
    let records: [ExerciseRecords]
    let suggestions: [ProgressionSuggestion]

    init(sessions: [TrainingSession], occurrences: [TrainingOccurrence], activePlan: WeekPlan? = nil, asOf: Date = Date()) {
        history = sessions.filter { $0.finishedAt != nil }.sorted {
            if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.startedAt > $1.startedAt
        }
        let today = CivilTrainingDay(asOf)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let sessionsByDay = Dictionary(grouping: history) { $0.performedDay.date }
        activityDays = (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today.date) else { return nil }
            let day = CivilTrainingDay(date).date
            return ProgressActivityDay(date: day, sessions: sessionsByDay[day] ?? [])
        }
        let recentSessions = activityDays.flatMap(\.sessions)
        sessionCount = recentSessions.count
        let cardio = recentSessions.filter(\.isCardio).compactMap(\.cardio)
        cardioCount = cardio.count
        cardioSeconds = cardio.reduce(0) { $0 + min(Int.max - $0, max(0, $1.seconds)) }

        let linked = Dictionary(grouping: sessions.filter { $0.occurrenceID != nil }) { $0.occurrenceID! }
        let done = Set(occurrences.filter { Self.fulfilled($0, by: linked[$0.id] ?? []) }.map(\.id))
        let known = occurrences.filter { $0.scheduledDay.date <= today.date }
        knownAdherence = (known.filter { done.contains($0.id) }.count, known.count)
        var scheduled = 0
        var fulfilled = 0
        let weekStart = calendar.date(byAdding: .day, value: -today.mondayIndex, to: today.date)!
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let day = CivilTrainingDay(date)
            let dated = occurrences.filter { $0.scheduledDay == day }
            scheduled += dated.count
            fulfilled += dated.filter { done.contains($0.id) }.count
            if let plan = activePlan, !plan.archived, plan.days.indices.contains(offset), plan.days[offset].isWorkout,
               !occurrences.contains(where: { $0.sourceDay == day && $0.planID == plan.id }) {
                scheduled += 1
            }
        }
        adherence = (fulfilled, scheduled)

        var points: [RecordIdentity: [ProgressSet]] = [:]
        var titles: [RecordIdentity: String] = [:]
        var attempts: [RecordIdentity: (date: Date, suggestion: ProgressionSuggestion?)] = [:]
        let occurrenceByID = Dictionary(occurrences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for session in sessions {
            guard !session.isCardio else { continue }
            let occurrence = session.occurrenceID.flatMap { occurrenceByID[$0] }
            for exercise in session.exercises {
                let working = exercise.sets.filter { $0.warmup != true }
                guard !working.isEmpty else { continue }
                let sides: [String?] = exercise.basis == .unilateral ? ["Left", "Right"] : [nil]
                for row in working {
                    guard let date = row.confirmedAt, (try? row.actual.validate(for: exercise.basis)) != nil else { continue }
                    let actual = row.actual.converted(to: "kg")
                    for side in sides {
                        let key = RecordIdentity(exercise, side: side)
                        let right = side == "Right"
                        let entry = ProgressSet(id: row.id, sessionID: session.id, date: date,
                                                kg: right ? actual.rightLoad : actual.load,
                                                reps: right ? actual.rightReps : actual.reps, seconds: actual.seconds)
                        points[key, default: []].append(entry)
                        titles[key] = exercise.prescription.name
                    }
                }
                // The last performed prescription determines the current advice.
                // An incomplete later attempt withdraws an older recommendation.
                guard let attempted = working.compactMap(\.confirmedAt).max() ?? session.finishedAt else { continue }
                let key = RecordIdentity(exercise)
                if let previous = attempts[key], previous.date >= attempted { continue }
                attempts[key] = (attempted, Self.suggestion(exercise, session: session, occurrence: occurrence))
            }
        }
        records = points.map { ExerciseRecords(id: $0.key, name: titles[$0.key] ?? "", rows: $0.value) }.sorted {
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if $0.id.variant != $1.id.variant { return $0.id.variant.uuidString < $1.id.variant.uuidString }
            if $0.id.convention != $1.id.convention { return $0.id.convention < $1.id.convention }
            if $0.basis != $1.basis { return $0.basis.rawValue < $1.basis.rawValue }
            if $0.id.machineProfile != $1.id.machineProfile {
                return ($0.id.machineProfile?.uuidString ?? "") < ($1.id.machineProfile?.uuidString ?? "")
            }
            return ($0.side ?? "") < ($1.side ?? "")
        }
        suggestions = attempts.values.compactMap(\.suggestion).sorted { $0.date > $1.date }
    }

    private static func fulfilled(_ occurrence: TrainingOccurrence, by sessions: [TrainingSession]) -> Bool {
        guard !occurrence.skipped else { return false }
        if let goal = occurrence.cardioGoalSeconds {
            return goal > 0 && sessions.compactMap { $0.cardio?.seconds }.reduce(0) { $0 + min(Int.max - $0, max(0, $1)) } >= goal
        }
        let required = Set(occurrence.plannedSets.values.joined())
        let credits = sessions.flatMap(\.exercises).flatMap(\.sets)
            .filter { $0.confirmedAt != nil && $0.warmup != true }.compactMap(\.plannedID)
        return !required.isEmpty && required.isSubset(of: Set(credits))
    }

    private static func suggestion(_ exercise: TrainingExercise, session: TrainingSession,
                                   occurrence: TrainingOccurrence?) -> ProgressionSuggestion? {
        guard ![.timed, .bodyweight, .assisted].contains(exercise.basis) else { return nil }
        let p = exercise.prescription
        var upperTarget = p.high
        let prescribed: [TrainingSet]
        if let occurrence, let day = occurrence.day {
            let original = exercise.replacedPrescription ?? p
            // For an explicitly assigned extra session the source prescription
            // may have its own ID. Locate its designated slots in the snapshot.
            let linked = Set(exercise.sets.compactMap(\.plannedID))
            let source = day.exercises.first { $0.id == original.id } ??
                day.exercises.first { !(Set(occurrence.plannedSets[$0.id] ?? []).isDisjoint(with: linked)) }
            if let source, let slots = occurrence.plannedSets[source.id] {
                // A result assigned after an extra workout must meet the dated
                // prescription's target, even if its own template was easier.
                if exercise.replacedPrescription == nil { upperTarget = source.high }
                let required = Set(slots)
                guard !required.isEmpty, required.count == slots.count else { return nil }
                prescribed = exercise.sets.filter { $0.warmup != true && $0.optional != true && $0.plannedID.map(required.contains) == true }
                guard prescribed.count == required.count, Set(prescribed.compactMap(\.plannedID)) == required else { return nil }
            } else {
                // A session-only exercise never substitutes for a dated prescription.
                guard linked.isEmpty else { return nil }
                prescribed = exercise.sets.filter { $0.warmup != true && $0.optional != true }
                guard prescribed.count == p.sets else { return nil }
            }
        } else {
            prescribed = exercise.sets.filter { $0.warmup != true && $0.optional != true }
            let ordinals = prescribed.compactMap(\.ordinal)
            guard p.sets > 0, prescribed.count == p.sets, Set(ordinals).count == p.sets,
                  ordinals.allSatisfy({ $0 >= 1 && $0 <= p.sets }) else { return nil }
        }
        guard !prescribed.isEmpty, upperTarget > 0 else { return nil }
        var reference: Double?
        var latest: Date?
        for row in prescribed {
            guard let performed = row.confirmedAt, (try? row.actual.validate(for: exercise.basis)) != nil,
                  let reps = row.actual.reps, reps >= upperTarget else { return nil }
            let value = row.actual.converted(to: "kg")
            guard let load = value.load, reference.map({ WeightUnits.equal(load, $0) }) != false else { return nil }
            if exercise.basis == .unilateral {
                guard let right = value.rightLoad, WeightUnits.equal(load, right), (value.rightReps ?? 0) >= upperTarget else { return nil }
            }
            reference = load
            latest = max(latest ?? performed, performed)
        }
        guard let kg = reference, let date = latest else { return nil }
        return ProgressionSuggestion(id: exercise.id, sessionID: session.id, name: p.name, date: date, kg: kg)
    }
}
