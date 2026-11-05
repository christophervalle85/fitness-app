import SwiftUI

enum PlannerStyle {
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .init(white: 0.085, alpha: 1) : .init(red: 0.975, green: 0.970, blue: 0.950, alpha: 1) })
    static let blue = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .init(red: 0.41, green: 0.62, blue: 1, alpha: 1) : .init(red: 0.10, green: 0.29, blue: 0.78, alpha: 1) })
    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
}

struct PlannerRoot: View {
    @State private var store = PlanningStore()
    @State private var editing = WeekPlan()
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var retry: (() -> Void)?
    @State private var discardAlert = false
    @State private var tab = "Today"
    #if WEEKFORM_DEVELOPMENT
    @State private var developer = false
    @State private var resetAlert = false
    #endif

    var body: some View {
        Group {
            if !loaded {
                if loadFailed {
                    ContentUnavailableView {
                        Label("Planner unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Your local planner could not be opened.")
                    } actions: {
                        Button("Try again", action: load)
                    }
                } else {
                    ProgressView("Opening your week")
                }
            } else if store.step == "home" {
                TabView(selection: $tab) {
                    Tab("Today", systemImage: "calendar", value: "Today") {
                        NavigationStack {
                            TodayScreen(plan: store.plans.first { $0.id == store.activeID },
                                        showRoutines: { tab = "Routines" })
                                .toolbar { developerButton }
                        }
                    }
                    Tab("Routines", systemImage: "square.stack.3d.up", value: "Routines") {
                        NavigationStack {
                            RoutinesScreen(plans: store.plans, active: store.activeID,
                                           newPlan: { begin(WeekPlan(), "welcome") },
                                           edit: { begin($0, "edit") },
                                           activate: { id in perform { try store.activate(id) } },
                                           duplicate: { id in perform { try store.duplicate(id) } },
                                           archive: { id in perform { try store.archive(id) } })
                                .toolbar { developerButton }
                        }
                    }
                }
            } else {
                NavigationStack {
                    switch store.step {
                    case "edit":
                        RoutineEditor(plan: Binding(get: { editing }, set: { value in
                            // A resigning text field can deliver a final write after review opens.
                            guard store.step == "edit", editing.id == value.id, editing != value else { return }
                            editing = value
                            perform { try store.update(value, step: "edit") }
                        }), onReview: { changeStep("review") }, onCancel: { discardAlert = true })
                    case "review":
                        ReviewWeek(plan: editing, editingExisting: store.plans.contains { $0.id == editing.id },
                                   goBack: { changeStep("edit") }, save: {
                            perform {
                                try store.confirm(editing)
                                tab = "Today"
                            }
                        })
                    case "starters":
                        StarterPicker(select: { begin($0, "edit") }, back: { changeStep("welcome") })
                    default:
                        WelcomeScreen(manual: { begin(WeekPlan(), "edit") },
                                      starters: { begin(WeekPlan(), "starters") })
                            .toolbar {
                                if !store.plans.isEmpty {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Cancel", action: discard)
                                    }
                                }
                                developerButton
                            }
                    }
                }
            }
        }
        .tint(PlannerStyle.blue)
        .task { if !loaded { load() } }
        .alert("Couldn’t save or open your routine", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Retry") { retry?() }
            Button("Close", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Discard this draft?", isPresented: $discardAlert, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive, action: discard)
            Button("Keep editing", role: .cancel) {}
        }
        #if WEEKFORM_DEVELOPMENT
        .sheet(isPresented: $developer) {
            NavigationStack {
                List {
                    NavigationLink("Foundation workout") { FoundationView() }
                    Button("Replay onboarding") {
                        developer = false
                        begin(WeekPlan(), "welcome")
                    }
                    Button("Reset planner test data", role: .destructive) { resetAlert = true }
                }
                .navigationTitle("Developer tools")
                .toolbar { Button("Done") { developer = false } }
                .confirmationDialog("Erase this planner’s routines and setup draft?", isPresented: $resetAlert, titleVisibility: .visible) {
                    Button("Erase planner data", role: .destructive) {
                        developer = false
                        perform { try store.reset(); editing = WeekPlan(); tab = "Today" }
                    }
                }
            }
        }
        #endif
    }

    @ToolbarContentBuilder private var developerButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            #if WEEKFORM_DEVELOPMENT
            Button("Developer tools", systemImage: "wrench.and.screwdriver") { developer = true }
                .accessibilityIdentifier("developerTools")
            #endif
        }
    }

    private func load() {
        loadFailed = false
        perform {
            do { try store.load() } catch { loadFailed = true; throw error }
            if let draft = store.draft { editing = draft }
            loaded = true
        }
    }

    private func begin(_ plan: WeekPlan, _ step: String) {
        perform {
            try store.begin(plan, step: step)
            editing = plan
        }
    }

    private func changeStep(_ step: String) {
        perform { try store.update(editing, step: step) }
    }

    private func discard() {
        perform {
            try store.discard()
            editing = WeekPlan()
        }
    }

    private func perform(_ action: @escaping () throws -> Void) {
        do {
            try action()
            retry = nil
        } catch {
            errorMessage = error.localizedDescription
            retry = { perform(action) }
        }
    }
}
