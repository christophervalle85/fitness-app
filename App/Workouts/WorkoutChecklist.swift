import Foundation

/// The checklist is a read model. A set credited by an earlier workout is
/// displayed with its original result and cannot issue a command in this session.
struct WorkoutChecklist {
    enum Row: Identifiable {
        case live(TrainingSet, index: Int)
        case earlier(TrainingSet, ordinal: Int, date: Date)
        case remaining(slot: UUID, ordinal: Int)

        var id: UUID {
            switch self {
            case .live(let set, _), .earlier(let set, _, _): set.id
            case .remaining(let slot, _): slot
            }
        }

        var ordinal: Int {
            switch self {
            case .live(let set, let index): set.ordinal ?? index + 1
            case .earlier(_, let ordinal, _), .remaining(_, let ordinal): ordinal
            }
        }

        var isComplete: Bool {
            switch self {
            case .live(let set, _): set.confirmedAt != nil
            case .earlier: true
            case .remaining: false
            }
        }
    }

    struct Group: Identifiable {
        let id: UUID
        let prescription: PlanExercise
        let basis: LoadBasis
        let liveExercise: TrainingExercise?
        let planIndex: Int?
        var rows: [Row]

        var completed: Int { rows.filter(\.isComplete).count }
    }

    let groups: [Group]
    var total: Int { groups.map(\.rows.count).reduce(0, +) }
    var completed: Int { groups.map(\.completed).reduce(0, +) }

    init(session: TrainingSession, occurrence: TrainingOccurrence?, sessions: [TrainingSession]) {
        let prescribed = occurrence?.day?.exercises ?? []
        var slots: [UUID: (index: Int, ordinal: Int)] = [:]
        for (index, exercise) in prescribed.enumerated() {
            for (offset, slot) in (occurrence?.plannedSets[exercise.id] ?? []).enumerated() {
                slots[slot] = (index, offset + 1)
            }
        }
        var sections = session.exercises.map { exercise in
            let source = exercise.sets.compactMap { $0.plannedID.flatMap { slots[$0]?.index } }.first
            return Group(id: exercise.id, prescription: exercise.prescription, basis: exercise.basis,
                         liveExercise: exercise, planIndex: source,
                         rows: exercise.sets.enumerated().map { .live($0.element, index: $0.offset) })
        }
        var represented = Set(session.exercises.flatMap(\.sets).compactMap(\.plannedID))
        if let occurrence {
            for earlier in sessions where earlier.id != session.id && earlier.occurrenceID == occurrence.id {
                for exercise in earlier.exercises {
                    for set in exercise.sets {
                        guard let slot = set.plannedID, let source = slots[slot], set.warmup != true,
                              let date = set.confirmedAt, represented.insert(slot).inserted else { continue }
                        let row = Row.earlier(set, ordinal: source.ordinal, date: date)
                        if let i = sections.firstIndex(where: {
                            $0.planIndex == source.index && $0.basis == exercise.basis &&
                            ($0.prescription.variantID ?? $0.prescription.id) == (exercise.prescription.variantID ?? exercise.prescription.id) &&
                            $0.prescription.name == exercise.prescription.name && $0.prescription.convention == exercise.prescription.convention
                        }) {
                            sections[i].rows.append(row)
                        } else {
                            sections.append(Group(id: slot, prescription: exercise.prescription, basis: exercise.basis,
                                                  liveExercise: nil, planIndex: source.index, rows: [row]))
                        }
                    }
                }
            }
            // A historical correction can free a slot after this session was
            // opened. Show the remaining prescription without inventing a result.
            for (index, exercise) in prescribed.enumerated() {
                let rows = (occurrence.plannedSets[exercise.id] ?? []).enumerated().compactMap { offset, slot in
                    represented.contains(slot) ? nil : Row.remaining(slot: slot, ordinal: offset + 1)
                }
                guard !rows.isEmpty else { continue }
                if let i = sections.firstIndex(where: { $0.planIndex == index && $0.prescription.id == exercise.id }) {
                    sections[i].rows += rows
                } else {
                    sections.append(Group(id: exercise.id, prescription: exercise, basis: LoadBasis(exercise), liveExercise: nil,
                                          planIndex: index, rows: rows))
                }
            }
        }
        for i in sections.indices {
            sections[i].rows.sort { $0.ordinal < $1.ordinal }
        }
        // Swift sort is stable, retaining workout order among unplanned exercises.
        groups = sections.sorted {
            let left = $0.planIndex ?? Int.max
            let right = $1.planIndex ?? Int.max
            if left != right { return left < right }
            guard left != Int.max else { return false }
            return ($0.rows.first?.ordinal ?? 0) < ($1.rows.first?.ordinal ?? 0)
        }
    }
}
