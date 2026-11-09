import SwiftUI

struct CardioLog: View {
    let session: TrainingSession
    let store: TrainingStore
    @State private var pending: CardioResult?
    @State private var error: String?
    @FocusState private var focusSeconds: Bool
    @State private var activityName: String?
    @State private var commandID = UUID()

    private var draft: CardioResult? {
        pending ?? store.openSessions.first { $0.id == session.id }?.cardioDraft ?? session.cardio
    }

    private var values: Binding<CardioResult> {
        Binding(get: { draft ?? CardioResult(seconds: 0) }, set: { result in
            do {
                try store.updateCardio(sessionID: session.id, result: result)
                pending = nil
                error = nil
            } catch {
                pending = result
                self.error = error.localizedDescription
            }
        })
    }

    var body: some View {
        Section("Cardio activity") {
            LabeledContent("Activity") {
                TextField("Activity name", text: Binding(
                    get: { activityName ?? session.name },
                    set: { name in
                        activityName = name
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        do { try store.renameCardio(sessionID: session.id, name: name); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                )).multilineTextAlignment(.trailing).submitLabel(.done).accessibilityIdentifier("cardioName")
            }
            LabeledContent("Actual seconds") {
                TextField("Seconds", value: Binding<Int?>(get: {
                    draft?.seconds
                }, set: { newValue in
                    var draft = values.wrappedValue
                    draft.seconds = newValue ?? 0
                    values.wrappedValue = draft
                }), format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .focused($focusSeconds).accessibilityIdentifier("cardioSeconds")
            }
            LabeledContent("Distance") {
                TextField("Optional", value: values.distance, format: .number)
                    .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
            }
            Picker("Distance unit", selection: values.unit) {
                Text("Kilometers").tag("km")
                Text("Miles").tag("mi")
            }
            TextField("Activity notes", text: values.notes, axis: .vertical)
            if let saved = session.cardio {
                Label("Activity saved · \(elapsedString(TimeInterval(saved.seconds)))", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("cardioStatus")
            }
            Button(session.cardio == nil ? "Confirm activity" : "Save activity changes") {
                let result = values.wrappedValue
                let name = (activityName ?? session.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { error = "Enter the activity name."; return }
                guard result.seconds > 0 else { error = "Enter the duration you completed."; focusSeconds = true; return }
                do {
                    if session.name != name { try store.renameCardio(sessionID: session.id, name: name) }
                    try store.recordCardio(sessionID: session.id, result: result, revision: session.cardioRevision, commandID: commandID)
                    pending = nil
                    error = nil
                    focusSeconds = false
                } catch { self.error = error.localizedDescription }
            }.accessibilityIdentifier("confirmCardio")
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote) }
        }
        .onChange(of: session.cardioRevision) { _, _ in commandID = UUID() }
    }
}
