import SwiftUI

/// Shared with dated workout history; the summary only displays confirmed values.
struct TrainingSummaryContent: View {
    let session: TrainingSession
    var showsNotes = true

    var body: some View {
        Section(session.name) {
            LabeledContent("Performed", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Workout duration", value: elapsedString((session.finishedAt ?? .now).timeIntervalSince(session.startedAt)))
            if session.isCardio {
                if let cardio = session.cardio {
                    LabeledContent("Activity duration", value: elapsedString(TimeInterval(cardio.seconds)))
                    if let distance = cardio.distance {
                        LabeledContent("Distance", value: "\(distance.formatted()) \(cardio.unit)")
                    }
                    if !cardio.notes.isEmpty { Text(cardio.notes) }
                } else {
                    Text("No activity confirmed.").foregroundStyle(.secondary)
                }
            } else {
                let sets = session.exercises.flatMap(\.sets)
                let working = sets.filter { $0.optional != true }
                let confirmed = working.filter { $0.confirmedAt != nil }.count
                LabeledContent("Confirmed working sets", value: "\(confirmed) of \(working.count)")
                    .accessibilityIdentifier("sessionTally")
                let extra = sets.filter { $0.optional == true && $0.confirmedAt != nil }
                if extra.contains(where: { $0.warmup == true }) {
                    LabeledContent("Warm-ups logged", value: "\(extra.filter { $0.warmup == true }.count)")
                }
                if extra.contains(where: { $0.warmup != true }) {
                    LabeledContent("Extra working sets logged", value: "\(extra.filter { $0.warmup != true }.count)")
                }
            }
            if showsNotes && !session.notes.isEmpty { Text(session.notes) }
        }
        ForEach(session.exercises) { exercise in
            let results = exercise.sets.enumerated().filter { $0.element.confirmedAt != nil }
            if !results.isEmpty || exercise.replacedPrescription != nil {
                Section(exercise.prescription.name) {
                    if let original = exercise.replacedPrescription {
                        Text("In place of \(original.name)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(results), id: \.element.id) { index, set in
                        LabeledContent(setTitle(set, index: index), value: actualDescription(set.actual, basis: exercise.basis))
                    }
                }
            }
        }
    }
}
