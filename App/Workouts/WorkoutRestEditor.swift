import SwiftUI

struct WorkoutRestEditor: View {
    let current: Int?
    let save: (Int?) throws -> Void
    @State private var custom: Int?
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("For the next rest interval") {
                Button("No timer") { apply(nil) }
                ForEach([60, 90, 120, 180], id: \.self) { duration in
                    Button {
                        apply(duration)
                    } label: {
                        HStack {
                            Text("\(duration) seconds")
                            Spacer()
                            if current == duration { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section("Custom duration") {
                TextField("Seconds", value: $custom, format: .number).keyboardType(.numberPad)
                Button("Use custom duration") {
                    guard let custom, custom > 0 else { problem = "Enter a positive duration in seconds."; return }
                    apply(custom)
                }
                if let problem { Text(problem) }
            }
        }
        .navigationTitle("Rest timer")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { custom = current }
    }

    private func apply(_ seconds: Int?) {
        do { try save(seconds); dismiss() } catch { problem = error.localizedDescription }
    }
}
