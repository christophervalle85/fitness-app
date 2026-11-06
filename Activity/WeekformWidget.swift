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
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.restStart == nil ? "Workout" : (context.state.restPausedAt == nil ? "Rest" : "Paused"),
                          systemImage: context.state.restStart == nil ? "figure.strengthtraining.traditional" : "timer")
                        .font(.caption.bold()).foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.restStart != nil {
                        RestClock(state: context.state).frame(width: 68, alignment: .trailing)
                            .font(.headline).foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutLiveControls(context: context, island: true)
                        .foregroundStyle(.white)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").accessibilityLabel("Workout active")
            } compactTrailing: {
                if context.state.restStart != nil {
                    RestClock(state: context.state)
                        .font(.caption2.weight(.semibold)).frame(width: 41, alignment: .trailing)
                        .foregroundStyle(.white)
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

private struct RestClock: View {
    let state: WorkoutLiveActivity.ContentState

    @ViewBuilder var body: some View {
        if let start = state.restStart, start <= .distantFuture {
            Group {
                if let paused = state.restPausedAt {
                    let seconds = max(0, Int(exactly: paused.timeIntervalSince(start).rounded(.down)) ?? 0)
                    Text(restDuration(seconds))
                } else {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                }
            }
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            .accessibilityLabel(state.restPausedAt == nil ? "Elapsed rest" : "Paused rest")
        }
    }
}

private func restDuration(_ seconds: Int) -> String {
    let value = max(0, seconds)
    return "\(value / 60):" + String(format: "%02d", value % 60)
}

private struct WorkoutLiveControls: View {
    let context: ActivityViewContext<WorkoutLiveActivity>
    var island = false
    @Environment(\.redactionReasons) private var redactions
    private var state: WorkoutLiveActivity.ContentState { context.state }
    private var url: URL { WorkoutLiveRoute(context.attributes, state: state).url }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(state.exerciseName ?? "Weekform workout")
                    .font(.headline).lineLimit(1).privacySensitive(state.exerciseName != nil)
                Spacer(minLength: 4)
                if let number = state.ordinal {
                    Text("\(state.warmup ? "Warm-up" : "Set") \(number)").font(.caption.bold())
                }
            }
            if state.restStart != nil, let target = state.restTarget {
                HStack(spacing: 5) {
                    if !island {
                        Text(state.restPausedAt == nil ? "Rest" : "Paused")
                        RestClock(state: state).frame(width: 66, alignment: .leading)
                    }
                    Text("Target \(restDuration(target))")
                }.font(.caption.weight(.semibold))
            }
            if state.primary != .confirm, let result = state.result {
                Text(result).font(.subheadline.weight(.medium)).monospacedDigit()
                    .lineLimit(2).privacySensitive()
            }
            HStack(spacing: 8) {
                switch state.primary {
                case .edit:
                    Link(state.setID == nil ? "Open workout" : "Edit result", destination: url)
                case .review:
                    Link("Review workout", destination: url)
                case .confirm:
                    if redactions.isEmpty, let result = state.result, !result.isEmpty {
                        ViewThatFits {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result).font(.subheadline.weight(.medium))
                                    .monospacedDigit().lineLimit(nil).privacySensitive()
                                HStack {
                                    action(state.finalSet ? "Log final set" : (state.willRest ? "Confirm & rest" : "Confirm set"), .confirm)
                                    Link("Edit", destination: url)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: true)
                            Link("Edit in app", destination: url)
                        }
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
                if state.canStartSet && state.primary != .startSet { action("Start set", .startSet) }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func action(_ title: String, _ action: WorkoutLiveAction) -> some View {
        Button(intent: WorkoutLiveIntent(action, activityID: context.activityID, state: state)) { Text(title) }
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
