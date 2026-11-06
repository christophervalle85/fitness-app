import SwiftUI

enum PlannerStyle {
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .init(white: 0.085, alpha: 1) : .init(red: 0.975, green: 0.970, blue: 0.950, alpha: 1) })
    static let moss = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.61, green: 0.83, blue: 0.60, alpha: 1) : UIColor(red: 0.14, green: 0.34, blue: 0.23, alpha: 1)
    })
    static let ochre = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.96, green: 0.72, blue: 0.46, alpha: 1) : UIColor(red: 0.56, green: 0.29, blue: 0.10, alpha: 1)
    })
    static let forest = Color(red: 0.10, green: 0.23, blue: 0.17)
    static let ink = Color.primary
    static let rule = Color(uiColor: .separator)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let blue = moss
    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
}

enum PlanStartTargetError: LocalizedError {
    case changed
    var errorDescription: String? { "The selected workout changed. Choose it again in Plan." }
}

enum PlanStartTarget {
    case template(WeekPlan, Date)
    case occurrence(UUID)

    @MainActor func title(in training: TrainingStore) -> String {
        switch self {
        case .template(let plan, let date):
            let index = CivilTrainingDay(date).mondayIndex
            return plan.days.indices.contains(index) ? plan.days[index].name : "Selected workout"
        case .occurrence(let id):
            return training.occurrences.first { $0.id == id }?.name ?? "Selected workout"
        }
    }

    @MainActor func start(planner: PlanningStore, training: TrainingStore, expectedDay: CivilTrainingDay) throws {
        guard training.active == nil else { throw TrainingError("Finish the open workout before starting another.") }
        switch self {
        case .template(let snapshot, let date):
            let day = CivilTrainingDay(date)
            let index = day.mondayIndex
            guard day == expectedDay,
                  let plan = planner.plans.first(where: { $0.id == snapshot.id && !$0.archived }),
                  snapshot.days.indices.contains(index), plan.days.indices.contains(index),
                  snapshot.days[index] == plan.days[index], snapshot.restSeconds == plan.restSeconds else {
                throw PlanStartTargetError.changed
            }
            if let dated = training.occurrences.first(where: { $0.planID == plan.id && $0.sourceDay == day }),
               dated.scheduledDay != day || dated.day != snapshot.days[index] || dated.restSeconds != snapshot.restSeconds {
                throw PlanStartTargetError.changed
            }
            try training.startPlanned(plan: plan, date: date)
        case .occurrence(let id):
            guard training.occurrences.contains(where: { $0.id == id && $0.scheduledDay == expectedDay }) else {
                throw PlanStartTargetError.changed
            }
            try training.startOccurrence(id)
        }
    }
}

private struct WorkoutSwitch {
    let sourceID: UUID
    let target: PlanStartTarget
    let targetDay: CivilTrainingDay
    let owner: UUID
    let generation: UUID
}

struct PlannerRoot: View {
    @State private var store = PlanningStore()
    @State private var training = TrainingStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingURL: URL?
    @State private var workoutRouteEvent = UUID()
    @State private var workoutRoute: WorkoutLiveRoute?
    @State private var workoutOpen = false
    @State private var reviewingSwitch: WorkoutSwitch?
    @State private var startAfterDismiss: WorkoutSwitch?
    @State private var agendaDate = Date.now
    @State private var planRootVisible = true
    @State private var finishPulse = 0
    @State private var pendingCelebration = false
    @State private var editing = WeekPlan()
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var retry: (() -> Void)?
    @State private var discardAlert = false
    @State private var tab = "Plan"
    @State private var restoreGeneration = UUID()
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
                    Tab("Plan", systemImage: "calendar", value: "Plan") {
                        NavigationStack {
                            PlanScreen(plan: store.plans.first { $0.id == store.activeID },
                                        training: training, selected: $agendaDate, finishPulse: finishPulse, openWorkout: { workoutOpen = true },
                                        showRoutines: { tab = "Routines" }, requestPlanStart: requestPlanStart,
                                        onRootVisibilityChanged: { planRootVisible = $0 })
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
                    Tab("Exercises", systemImage: "dumbbell", value: "Exercises") {
                        NavigationStack { ExercisesScreen(planner: store, training: training) }
                    }
                    Tab("Progress", systemImage: "chart.xyaxis.line", value: "Progress") {
                        NavigationStack {
                            ProgressScreen(store: training, activePlan: store.plans.first { $0.id == store.activeID },
                                           unit: store.weightUnit, setUnit: { try store.setWeightUnit($0) }) {
                                recoveryScreen
                            }
                        }
                    }
                }
                .tabViewBottomAccessory(isEnabled: showsWorkoutAccessory) {
                    if showsWorkoutAccessory, let session = training.active { resumeAccessory(session) }
                }
            } else {
                NavigationStack {
                    Group {
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
                                tab = "Plan"
                            }
                        })
                    case "starters":
                        StarterPicker(select: { begin($0, "edit") }, back: { changeStep("welcome") })
                    default:
                        WelcomeScreen(manual: { begin(WeekPlan(), "edit") },
                                      starters: { begin(WeekPlan(), "starters") }, recovery: { recoveryScreen })
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
                    .toolbar {
                        if ["edit", "review", "starters"].contains(store.step) {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink { recoveryScreen } label: { Label("Backup and restore", systemImage: "externaldrive") }
                                    .accessibilityIdentifier("setupRecovery")
                            }
                        }
                    }
                }
            }
        }
        .id(restoreGeneration)
        .fullScreenCover(isPresented: $workoutOpen, onDismiss: workoutDismissed) {
            NavigationStack {
                ActiveWorkout(store: training, planner: store, route: workoutRoute, routeEvent: workoutRouteEvent,
                              reviewOnOpen: reviewingSwitch != nil, switchTargetName: reviewingSwitch?.target.title(in: training),
                              onClose: minimizeWorkout, onFinished: finishWorkout, onDiscarded: discardedWorkout,
                              onCancelSwitch: { reviewingSwitch = nil }, applyToRoutine: futureReplacement,
                              routineExercises: store.plans.first { $0.id == store.activeID }?.days.flatMap(\.exercises) ?? [])
            }.id(workoutRouteEvent)
        }
        .preferredColorScheme(testAppearance)
        .environment(store)
        .tint(PlannerStyle.blue)
        .task { if !loaded { load() } }
        .task(id: "\(loaded)-\(restoreGeneration)-\(training.liveRevision)") {
            if loaded { await WorkoutLiveCoordinator.sync(training: training, owner: store.profileID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutLiveDidCommit)) { _ in refreshTraining() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, refreshTraining() {
                Task { await WorkoutLiveCoordinator.sync(training: training, owner: store.profileID) }
            }
        }
        .onOpenURL { url in pendingURL = url; openPendingRoute() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                    HStack {
                        if let retry { Button("Retry", action: retry) }
                        Button("Dismiss") { self.errorMessage = nil }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(.regularMaterial)
            }
        }
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
                        perform { try store.reset(); loaded = false; load(); editing = WeekPlan(); tab = "Plan" }
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

    private var futureReplacement: ((PlanExercise, PlanExercise) throws -> Void)? {
        guard let id = training.active?.occurrenceID,
              let occurrence = training.occurrences.first(where: { $0.id == id }),
              let planID = occurrence.planID, let day = occurrence.day else { return nil }
        return { original, replacement in
            try store.replaceFutureExercise(planID: planID, dayID: day.id, original: original, replacement: replacement)
        }
    }

    private var recoveryScreen: some View {
        RecoveryScreen(planner: store, training: training, onRestore: {
            tab = "Plan"
            clearSwitch()
            workoutOpen = false
            errorMessage = nil
            retry = nil
            restoreGeneration = UUID()
            load()
        })
    }

    @discardableResult private func refreshTraining() -> Bool {
        guard loaded, let owner = store.profileID else { return false }
        do {
            try training.load(profileID: owner)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func openPendingRoute() {
        guard loaded, let url = pendingURL else { return }
        pendingURL = nil
        guard let route = WorkoutLiveRoute.parse(url),
              WorkoutLiveCoordinator.isCurrent(route, training: training, owner: store.profileID) else { return }
        perform {
            if let exerciseID = route.exerciseID, training.active?.currentExerciseID != exerciseID {
                try training.select(sessionID: route.sessionID, exerciseID: exerciseID)
            }
            clearSwitch()
            workoutRoute = route
            workoutRouteEvent = UUID()
            workoutOpen = true
        }
    }

    private var showsWorkoutAccessory: Bool {
        guard let session = training.active else { return false }
        guard tab == "Plan", planRootVisible, let id = session.occurrenceID,
              let occurrence = training.occurrences.first(where: { $0.id == id }) else { return true }
        return !training.isScheduled(occurrence, on: agendaDate)
    }

    private func resumeAccessory(_ session: TrainingSession) -> some View {
        let occurrence = training.occurrences.first { $0.id == session.occurrenceID }
        let exercise = session.exercises.first { $0.id == session.currentExerciseID }?.prescription.name ?? session.name
        let planned = occurrence.map { "Planned " + $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "Unscheduled"
        let started = "Started " + session.performedDay.date.formatted(.dateTime.month(.abbreviated).day())
        return Button { workoutOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                VStack(alignment: .leading, spacing: 1) {
                    Text(exercise).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(planned) · \(started)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("Resume").font(.subheadline.weight(.semibold))
            }.padding(.horizontal).contentShape(Rectangle())
        }
        .accessibilityLabel("Resume \(session.name). \(exercise). \(planned). \(started).")
        .accessibilityIdentifier("resumeAccessory")
    }

    private func requestPlanStart(_ target: PlanStartTarget) {
        guard let owner = store.profileID else { return }
        let targetDay = CivilTrainingDay(agendaDate)
        if let source = training.active {
            if case .occurrence(let id) = target, id == source.occurrenceID {
                workoutOpen = true
                return
            }
            reviewForSwitch(WorkoutSwitch(sourceID: source.id, target: target, targetDay: targetDay,
                                         owner: owner, generation: restoreGeneration))
        } else {
            startTarget(target, on: targetDay, owner: owner, generation: restoreGeneration)
        }
    }

    private func reviewForSwitch(_ request: WorkoutSwitch) {
        guard request.owner == store.profileID, request.generation == restoreGeneration,
              request.sourceID == training.active?.id else {
            errorMessage = "The open workout changed. Choose the workout you want to start again."
            retry = nil
            return
        }
        reviewingSwitch = request
        workoutRoute = nil
        workoutRouteEvent = UUID()
        workoutOpen = true
    }

    private func startTarget(_ target: PlanStartTarget, on day: CivilTrainingDay, owner: UUID, generation: UUID) {
        // Retry captures just the new start, never the already committed finish.
        perform {
            guard owner == store.profileID, generation == restoreGeneration else {
                throw TrainingError("The profile changed. Choose a workout again.")
            }
            try training.load(profileID: owner)
            try target.start(planner: store, training: training, expectedDay: day)
            workoutRoute = nil
            workoutRouteEvent = UUID()
            workoutOpen = true
        }
    }

    private func minimizeWorkout() {
        reviewingSwitch = nil
        workoutOpen = false
    }

    private func clearSwitch() {
        reviewingSwitch = nil
        startAfterDismiss = nil
    }

    private func workoutDismissed() {
        workoutRoute = nil
        reviewingSwitch = nil
        if let request = startAfterDismiss {
            startAfterDismiss = nil
            pendingCelebration = false
            startTarget(request.target, on: request.targetDay, owner: request.owner, generation: request.generation)
        } else if pendingCelebration {
            finishPulse += 1
            pendingCelebration = false
        }
    }

    private func discardedWorkout(_ id: UUID) {
        if let request = reviewingSwitch, request.sourceID == id, !training.sessions.contains(where: { $0.id == id }) {
            startAfterDismiss = request
        }
        minimizeWorkout()
    }

    private func finishWorkout(_ session: TrainingSession) {
        guard session.finishedAt != nil else { return }
        if let request = reviewingSwitch, request.sourceID == session.id {
            startAfterDismiss = request
            minimizeWorkout()
            return
        }
        let occurrence = training.occurrences.first { $0.id == session.occurrenceID }
        agendaDate = occurrence?.date ?? session.performedDay.date
        tab = "Plan"
        workoutOpen = false
        if let occurrence, training.status(for: occurrence).hasPrefix("Done") { pendingCelebration = true }
    }

    private var testAppearance: ColorScheme? {
        #if WEEKFORM_DEVELOPMENT
        let environment = ProcessInfo.processInfo.environment
        if environment["WEEKFORM_UI_TEST_RUN"].flatMap(UUID.init(uuidString:)) != nil {
            switch environment["WEEKFORM_UI_TEST_APPEARANCE"] {
            case "dark": return .dark
            case "light": return .light
            default: break
            }
        }
        #endif
        return nil
    }

    private func load() {
        loaded = false
        loadFailed = false
        perform {
            do {
                let paths = try RecoveryPaths.current()
                store = PlanningStore(directory: paths.planning)
                training = TrainingStore(directory: paths.training)
                try store.load()
            } catch { loadFailed = true; throw error }
            if let owner = store.profileID {
                do { try training.load(profileID: owner) } catch { loadFailed = true; throw error }
            }
            if let draft = store.draft { editing = draft }
            loaded = true
            openPendingRoute()
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
            errorMessage = nil
            retry = nil
        } catch {
            errorMessage = error.localizedDescription
            retry = error is PlanStartTargetError ? nil : { perform(action) }
        }
    }
}
