import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WeekformWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutActivityWidget()
        #if WEEKFORM_DEVELOPMENT
        FoundationWorkoutWidget()
        #endif
    }
}

private struct WorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivity.self) { context in
            WorkoutLiveControls(context: context)
                .padding()
                .widgetURL(WorkoutLiveRoute(context.attributes, state: context.state).url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { WorkoutLiveControls(context: context) }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").accessibilityLabel("Workout active")
            } compactTrailing: {
                if context.state.restStart != nil {
                    Image(systemName: context.state.restPausedAt == nil ? "timer" : "pause.fill").accessibilityLabel("Rest")
                } else if let number = context.state.ordinal {
                    Text("\(number)").monospacedDigit().accessibilityLabel("Set \(number)")
                } else { Image(systemName: "checkmark.circle") }
            } minimal: {
                Image(systemName: context.state.restStart == nil ? "dumbbell.fill" : "timer")
            }
            .widgetURL(WorkoutLiveRoute(context.attributes, state: context.state).url)
        }
    }
}

private struct WorkoutLiveControls: View {
    let context: ActivityViewContext<WorkoutLiveActivity>
    @Environment(\.redactionReasons) private var redactions
    private var state: WorkoutLiveActivity.ContentState { context.state }
    private var url: URL { WorkoutLiveRoute(context.attributes, state: state).url }

    var body: some View {
        ViewThatFits(in: .vertical) {
            fullControls.fixedSize(horizontal: false, vertical: true)
            // If complete actuals and their action cannot fit together, the
            // user can inspect and confirm the same set in the app.
            Link("Open workout", destination: url)
        }
    }

    private var fullControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(state.exerciseName ?? "Weekform workout").font(.headline).privacySensitive(state.exerciseName != nil)
            if let number = state.ordinal {
                Text("\(state.warmup ? "Warm-up" : "Set") \(number)").font(.caption)
            }
            if let result = state.result { Text(result).font(.subheadline).monospacedDigit().privacySensitive() }
            if let start = state.restStart, let target = state.restTarget {
                HStack(spacing: 4) {
                    Text(state.restPausedAt == nil ? "Rest timer" : "Rest timer paused")
                    if let paused = state.restPausedAt {
                        let elapsed = paused.timeIntervalSince(start)
                        if elapsed.isFinite, elapsed < Double(Int.max) {
                            Text(duration(Int(max(0, elapsed))))
                        }
                    } else if start <= .distantFuture {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .monospacedDigit().fixedSize()
                    }
                    Text("· target \(duration(target))")
                }.font(.caption)
            }
            HStack {
                switch state.primary {
                case .edit:
                    Link(state.setID == nil ? "Open workout" : "Edit result", destination: url)
                case .review:
                    Link("Review workout", destination: url)
                case .confirm:
                    if redactions.isEmpty {
                        action(state.finalSet ? "Log final set" : (state.willRest ? "Confirm & rest" : "Confirm set"), .confirm)
                        Link("Edit", destination: url)
                    } else {
                        Link("Open workout", destination: url)
                    }
                case .nextExercise:
                    action("Next exercise", .nextExercise)
                case .resume:
                    action("Resume", .resume)
                case .startSet:
                    action("Start set", .startSet)
                }
                if state.canStartSet { action("Start set", .startSet) }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func action(_ title: String, _ action: WorkoutLiveAction) -> some View {
        Button(intent: WorkoutLiveIntent(action, activityID: context.activityID, state: state)) { Text(title) }
    }

    private func duration(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

#if WEEKFORM_DEVELOPMENT
private struct FoundationWorkoutWidget: Widget {
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

#endif
