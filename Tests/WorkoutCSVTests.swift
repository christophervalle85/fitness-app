import Foundation
import Testing
@testable import Weekform

@MainActor
struct WorkoutCSVTests {
    private func emptyBackup() throws -> WorkoutBackup {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let planner = PlanningStore(directory: directory.appending(path: "plans"))
        let training = TrainingStore(directory: directory.appending(path: "training"))
        try planner.load()
        try training.load(profileID: try #require(planner.profileID))
        return try WorkoutBackup(planner, training)
    }

    @Test func exportsConfirmedResultsWithStableColumnsAndRecordedUnits() throws {
        let date = Date(timeIntervalSince1970: 0)
        var backup = try emptyBackup()
        let actual = SetActual(reps: 9, load: 0, rightReps: 8, rightLoad: 2.5, unit: "kg")
        let saved = TrainingSet(ordinal: 2, warmup: true, actual: actual, confirmedAt: date)
        let draft = TrainingSet(ordinal: 3, actual: actual)
        let exercise = TrainingExercise(prescription: PlanExercise(name: "Split squat"), basis: .unilateral, sets: [saved, draft])
        let strength = TrainingSession(name: "Morning", startedAt: date, performedDay: CivilTrainingDay(date),
                                       finishedAt: date, partial: true, exercises: [exercise])
        let later = date.addingTimeInterval(60)
        var cardio = TrainingSession(name: "Walk", startedAt: later, performedDay: CivilTrainingDay(later), isCardio: true)
        cardio.cardioDraft = CardioResult(seconds: 9999)
        cardio.cardio = CardioResult(seconds: 240, distance: 1.5, unit: "mi", notes: "Outside")
        backup.sessions = [cardio, strength]
        let csv = String(decoding: try WorkoutCSV.data(backup), as: UTF8.self)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.count == 6)
        #expect(lines.last == "")
        // These fixture values contain no commas, quotes or line breaks.
        let fields = { (line: String) in line.components(separatedBy: ",").map { String($0.dropFirst().dropLast()) } }
        let headers = fields(lines[0])
        func row(_ number: Int) -> [String: String] {
            let values = fields(lines[number])
            #expect(values.count == headers.count)
            return Dictionary(uniqueKeysWithValues: zip(headers, values))
        }
        #expect(row(1)["row_type"] == "session")
        let set = row(2)
        #expect(set["row_type"] == "set")
        #expect(set["set_id"] == saved.id.uuidString)
        #expect(set["set_type"] == "warmup")
        #expect(set["set_performed_at_utc"] == "1970-01-01T00:00:00.000Z")
        #expect(set["set_number"] == "2")
        #expect(set["load"] == "0.0")
        #expect(set["load_unit"] == "kg")
        #expect(set["right_reps"] == "8")
        #expect(set["right_load"] == "2.5")
        #expect(row(3)["status"] == "in_progress")
        let activity = row(4)
        #expect(activity["row_type"] == "cardio")
        #expect(activity["seconds"] == "240")
        #expect(activity["distance"] == "1.5")
        #expect(activity["distance_unit"] == "mi")
        #expect(!csv.contains(draft.id.uuidString))
        #expect(!csv.contains("9999"))
    }

    @Test func rejectsOutputOverLimitEvenWhenFieldsExpandOrRepeat() throws {
        var backup = try emptyBackup()
        let date = Date(timeIntervalSince1970: 0)
        let actual = TrainingSet(actual: SetActual(reps: 5), confirmedAt: date)
        let exercise = TrainingExercise(prescription: PlanExercise(name: "Press"), basis: .bodyweight, sets: [actual])
        var session = TrainingSession(name: "Quoted", startedAt: date, performedDay: CivilTrainingDay(date), exercises: [exercise])
        session.notes = String(repeating: "é\"", count: 1000)
        backup.sessions = [session]
        let full = try WorkoutCSV.data(backup)
        #expect(try WorkoutCSV.data(backup, byteLimit: full.count) == full)
        #expect(throws: PlanningError.self) { try WorkoutCSV.data(backup, byteLimit: full.count - 1) }
        #expect(throws: PlanningError.self) { try WorkoutCSV.data(backup, byteLimit: 0) }
    }

    @Test func quotesUserTextAndNeutralizesFormulaPrefixes() throws {
        var backup = try emptyBackup()
        let date = Date(timeIntervalSince1970: 0)
        var session = TrainingSession(name: "Rows, \"A\"", startedAt: date, performedDay: CivilTrainingDay(date))
        session.notes = "line one\r\nline \"two\""
        backup.sessions = [session]
        let quoted = String(decoding: try WorkoutCSV.data(backup), as: UTF8.self)
        #expect(quoted.contains("\"Rows, \"\"A\"\"\""))
        #expect(quoted.contains("\"line one\r\nline \"\"two\"\"\""))
        for prefix in ["=", "+", "-", "@", " \t=", "\u{FEFF}=", "＝"] {
            let cell = prefix + "SUM(2,3)"
            backup.sessions[0].notes = cell
            let csv = String(decoding: try WorkoutCSV.data(backup), as: UTF8.self)
            #expect(csv.contains("\"'" + cell + "\""))
        }
    }
}
