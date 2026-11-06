import Foundation

enum WorkoutCSV {
    private enum Column: String, CaseIterable {
        case rowType = "row_type", sessionID = "session_id", workout, activityType = "activity_type"
        case performedDay = "performed_day", startedAt = "started_at_utc", finishedAt = "finished_at_utc"
        case status, sessionNotes = "session_notes", routineID = "routine_id", occurrenceID = "occurrence_id"
        case scheduledDay = "scheduled_day", originalDay = "original_scheduled_day"
        case exerciseID = "session_exercise_id", prescriptionID = "prescription_id", variantID = "variant_id"
        case exercise, exerciseNotes = "exercise_notes", replacedExercise = "replaced_exercise"
        case basis = "load_basis", convention = "load_convention", setID = "set_id", plannedSetID = "planned_set_id"
        case ordinal = "set_number", kind = "set_type", performedAt = "set_performed_at_utc"
        case reps, seconds, load, unit = "load_unit", rightReps = "right_reps", rightLoad = "right_load"
        case distance, distanceUnit = "distance_unit", activityNotes = "activity_notes"
    }

    static func data(_ backup: WorkoutBackup, byteLimit: Int = WorkoutBackup.byteLimit) throws -> Data {
        let columns = Column.allCases
        let occurrences = Dictionary(backup.occurrences.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var output = Data()
        func append(_ fields: [String]) throws {
            for (index, field) in fields.enumerated() {
                let prefix = needsFormulaGuard(field)
                // Reserve quotes, a possible comma/apostrophe and the record
                // terminator before allocating or appending the escaped field.
                let overhead = 4 + (index == 0 ? 0 : 1) + (prefix ? 1 : 0)
                let remaining = byteLimit - output.count
                guard remaining >= overhead, field.utf8.count <= remaining - overhead else { throw sizeError }
                let extraQuotes = field.utf8.reduce(into: 0) { count, byte in if byte == 34 { count += 1 } }
                guard extraQuotes <= remaining - overhead - field.utf8.count else { throw sizeError }
                if index != 0 { output.append(44) }
                output.append(34)
                if prefix { output.append(39) }
                output.append(contentsOf: field.replacingOccurrences(of: "\"", with: "\"\"").utf8)
                output.append(34)
            }
            output.append(contentsOf: [13, 10])
        }
        func write(_ row: [Column: String]) throws { try append(columns.map { row[$0] ?? "" }) }

        try append(columns.map(\.rawValue))
        let ordered = backup.sessions.sorted {
            $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
        }
        for session in ordered {
            let occurrence = session.occurrenceID.flatMap { occurrences[$0] }
            let base: [Column: String] = [
                .rowType: "session", .sessionID: session.id.uuidString, .workout: session.name,
                .activityType: session.isCardio ? "cardio" : "strength",
                .performedDay: day(session.performedDay), .startedAt: timestamp(session.startedAt),
                .finishedAt: timestamp(session.finishedAt),
                .status: session.finishedAt == nil ? "in_progress" : (session.partial ? "partial" : "finished"),
                .sessionNotes: session.notes, .routineID: occurrence?.planID?.uuidString ?? "",
                .occurrenceID: session.occurrenceID?.uuidString ?? "",
                .scheduledDay: occurrence.map { day($0.scheduledDay) } ?? "",
                .originalDay: occurrence.map { day($0.sourceDay) } ?? ""
            ]
            try write(base)

            if let cardio = session.cardio {
                var row = base
                row[.rowType] = "cardio"
                row[.seconds] = String(cardio.seconds)
                row[.distance] = cardio.distance.map { String($0) }
                row[.distanceUnit] = cardio.distance == nil ? nil : cardio.unit
                row[.activityNotes] = cardio.notes
                try write(row)
            }
            for exercise in session.exercises {
                var details = base
                details[.rowType] = "set"
                details[.exerciseID] = exercise.id.uuidString
                details[.prescriptionID] = exercise.prescription.id.uuidString
                details[.variantID] = exercise.prescription.variantID?.uuidString
                details[.exercise] = exercise.prescription.name
                details[.exerciseNotes] = exercise.prescription.notes
                details[.replacedExercise] = exercise.replacedPrescription?.name
                details[.basis] = exercise.basis.rawValue
                details[.convention] = exercise.prescription.convention
                for (index, set) in exercise.sets.enumerated() {
                    guard let performed = set.confirmedAt else { continue }
                    var row = details
                    row[.setID] = set.id.uuidString
                    row[.plannedSetID] = set.plannedID?.uuidString
                    row[.ordinal] = String(set.ordinal ?? index + 1)
                    row[.kind] = set.warmup == true ? "warmup" : (set.optional == true ? "extra_working" : "working")
                    row[.performedAt] = timestamp(performed)
                    row[.reps] = set.actual.reps.map(String.init)
                    row[.seconds] = set.actual.seconds.map(String.init)
                    row[.load] = set.actual.load.map { String($0) }
                    row[.unit] = set.actual.load == nil && set.actual.rightLoad == nil ? nil : set.actual.unit
                    row[.rightReps] = set.actual.rightReps.map(String.init)
                    row[.rightLoad] = set.actual.rightLoad.map { String($0) }
                    try write(row)
                }
            }
        }
        return output
    }

    private static func day(_ value: CivilTrainingDay) -> String {
        String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
    }

    private static func timestamp(_ value: Date?) -> String {
        value?.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) ?? ""
    }

    private static var sizeError: PlanningError { PlanningError("The workout CSV exceeds the export size limit.") }

    private static func needsFormulaGuard(_ field: String) -> Bool {
        // Ignore leading whitespace and control characters before inspecting
        // a possibly full-width formula marker, without normalizing a whole note.
        let ignored = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard let first = field.unicodeScalars.first(where: { !ignored.contains($0) }) else { return false }
        let normalized = String(first).precomposedStringWithCompatibilityMapping
        return normalized.first.map { "=+-@".contains($0) } ?? false
    }
}
