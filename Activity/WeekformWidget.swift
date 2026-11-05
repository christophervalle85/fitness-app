import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WeekformWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FoundationActivity.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text("Weekform").font(.headline)
                TestSetStatus(confirmed: context.state.confirmed)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("Weekform") }
                DynamicIslandExpandedRegion(.bottom) { TestSetStatus(confirmed: context.state.confirmed) }
            } compactLeading: {
                Image(systemName: "dumbbell")
            } compactTrailing: {
                Image(systemName: context.state.confirmed ? "checkmark" : "circle")
            } minimal: {
                Image(systemName: context.state.confirmed ? "checkmark" : "dumbbell")
            }
        }
    }
}

private struct TestSetStatus: View {
    let confirmed: Bool

    var body: some View {
        #if WEEKFORM_DEVELOPMENT
        if confirmed {
            Label("Test set saved", systemImage: "checkmark.circle")
        } else {
            Button(intent: ConfirmTestSet()) { Text("Confirm 8 test reps") }
        }
        #else
        Text("Weekform")
        #endif
    }
}
