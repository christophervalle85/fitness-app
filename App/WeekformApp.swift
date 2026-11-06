import ActivityKit
import SwiftUI

@main
struct WeekformApp: App {
    var body: some Scene {
        WindowGroup {
            PlannerRoot()
        }
    }
}

#if WEEKFORM_DEVELOPMENT
struct FoundationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmed: Bool?
    @State private var hasActivity = false
    @State private var message: String?
    @State private var busy = false

    // UI tests keep a private store across their two launches.
    private let testRun = ProcessInfo.processInfo.environment["WEEKFORM_UI_TEST_RUN"].flatMap(UUID.init(uuidString:))

    private func store() throws -> FoundationStore {
        let live = try FoundationStore.live()
        guard let testRun else { return live }
        return FoundationStore(directory: live.directory.appending(path: testRun.uuidString))
    }

    private var status: String { confirmed.map { $0 ? "Saved" : "Ready" } ?? "Unavailable" }

    var body: some View {
        NavigationStack {
            List {
                Section("Foundation workout") {
                    LabeledContent("Test set", value: "\(FoundationActivity.reps) reps")
                    LabeledContent("Status", value: status)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Status")
                        .accessibilityValue(status)
                        .accessibilityIdentifier("foundationStatus")
                    if confirmed == false {
                        Button("Confirm 8 reps") {
                            Task { await confirm() }
                        }
                    }
                }
                Section("Live Activity") {
                    if hasActivity {
                        Button("End Live Activity") {
                            Task { await endActivity() }
                        }
                    } else if confirmed == false {
                        Button("Start Live Activity", action: startActivity)
                    } else {
                        Text("Inactive")
                    }
                }
                if let message {
                    Section { Text(message) }
                }
                Button("Refresh saved result") {
                    Task { await refresh() }
                }
            }
            .disabled(busy)
            .navigationTitle("Weekform")
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
        }
    }

    private func refresh() async {
        do {
            let saved = try store().confirmedReps() != nil
            confirmed = saved
            message = nil
            if saved && testRun == nil { await FoundationActivity.publishConfirmation() }
        } catch {
            confirmed = nil
            message = "Saved result unavailable. Unlock your iPhone and refresh to retry."
        }
        hasActivity = !Activity<FoundationActivity>.activities.isEmpty
    }

    private func confirm() async {
        busy = true
        defer { busy = false }
        do {
            try store().confirm(id: FoundationActivity.commandID, reps: FoundationActivity.reps)
            await refresh()
        } catch {
            confirmed = nil
            message = "Couldn’t save the set. Unlock your iPhone and refresh to retry."
        }
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are turned off. You can confirm this set here."
            return
        }
        do {
            if Activity<FoundationActivity>.activities.isEmpty {
                _ = try Activity.request(attributes: FoundationActivity(),
                                         content: ActivityContent(state: .init(confirmed: false), staleDate: nil))
            }
            hasActivity = true
            Task { await refresh() }
        } catch {
            message = "Couldn’t start the Live Activity. You can confirm this set here."
        }
    }

    private func endActivity() async {
        busy = true
        defer { busy = false }
        for activity in Activity<FoundationActivity>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        await refresh()
    }
}
#endif
