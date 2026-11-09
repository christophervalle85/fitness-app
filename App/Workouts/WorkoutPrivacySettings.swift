import SwiftUI

struct WorkoutPrivacySettings: View {
    @AppStorage(WorkoutLivePrivacy.showExerciseKey) private var exercise = false
    @AppStorage(WorkoutLivePrivacy.showLoadKey) private var values = false

    var body: some View {
        Form {
            Section {
                Toggle("Show exercise name", isOn: Binding(get: { exercise }, set: { enabled in
                    Task { await WorkoutLiveCoordinator.changePrivacy(showExercise: enabled, showLoad: values) }
                }))
                Toggle("Show set values", isOn: Binding(get: { values }, set: { enabled in
                    Task { await WorkoutLiveCoordinator.changePrivacy(showExercise: exercise, showLoad: enabled) }
                }))
            } footer: {
                Text("These details appear on the Lock Screen and Dynamic Island during a workout. With details hidden, open Weekform to confirm a set.")
            }
        }
        .navigationTitle("Lock Screen privacy")
    }
}
