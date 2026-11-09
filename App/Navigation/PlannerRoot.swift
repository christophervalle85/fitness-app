import SwiftUI

private struct PresentedWorkout: Identifiable {
    let id = UUID()
    let sessionID: UUID
    var route: WorkoutLiveRoute? = nil
}

struct PlannerRoot: View {
    @State private var store = PlanningStore()
    @State private var training = TrainingStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingURL: URL?
    @State private var workout: PresentedWorkout?
    @State private var weekBoundary: Date?
    @State private var agendaDate = Date.now
    @State private var planRootVisible = true
    @State private var finishPulse = 0
    @State private var pendingCelebration = false
    @State private var editing = WeekPlan()
    @State private var activateNewRoutine = false
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var retry: (() -> Void)?
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
                                        training: training, selected: $agendaDate, finishPulse: finishPulse,
                                        isPastWeek: training.isPastWeek(agendaDate), openWorkout: resumeWorkout,
                                        showRoutines: { tab = "Routines" }, requestPlanStart: requestPlanStart,
                                        onRootVisibilityChanged: { planRootVisible = $0 })
                                .toolbar { developerButton }
                        }
                    }
                    Tab("Routines", systemImage: "square.stack.3d.up", value: "Routines") {
                        NavigationStack {
                            RoutinesScreen(plans: store.plans, active: store.activeID,
                                           newPlan: { begin(WeekPlan(), "edit") },
                                           usePreset: { begin($0, "edit") },
                                           edit: { begin($0, "edit") },
                                           activate: { id in perform { try store.activate(id) } },
                                           duplicate: { id in perform { try store.duplicate(id) } },
                                           archive: { id in perform { try store.archive(id) } },
                                           delete: { id in perform { try store.deleteRoutine(id) } })
                                .toolbar { developerButton }
                        }
                    }
                    Tab("Exercises", systemImage: "dumbbell", value: "Exercises") {
                        NavigationStack { ExercisesScreen(planner: store, training: training) }
                    }
                    Tab("Progress", systemImage: "chart.xyaxis.line", value: "Progress") {
                        NavigationStack {
                            ProgressScreen(store: training, activePlan: store.plans.first { $0.id == store.activeID },
                                           unit: { store.weightUnit }, setUnit: { try store.setWeightUnit($0) }) {
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
                    switch store.editorStep {
                    case "edit":
                        RoutineEditor(plan: Binding(get: { editing }, set: { value in
                            // A resigning text field can deliver a final write after review opens.
                            guard store.editorStep == "edit", editing.id == value.id, editing != value else { return }
                            editing = value
                            perform { try store.update(value, step: "edit") }
                        }), needsDiscardConfirmation: { !store.plans.contains(editing) },
                            onReview: { changeStep("review") }, onDiscard: discard)
                    case "review":
                        ReviewWeek(plan: editing, editingExisting: store.plans.contains { $0.id == editing.id },
                                   additionalRoutine: isReturningRoutineEditor, activateNew: $activateNewRoutine,
                                   goBack: { changeStep("edit") }, save: {
                            let plan = editing
                            let returning = isReturningRoutineEditor
                            let activate = !returning || activateNewRoutine
                            let destination = returning ? "Routines" : "Plan"
                            perform {
                                try store.confirm(plan, activateNew: activate)
                                tab = destination
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
                        if !isReturningRoutineEditor && ["edit", "review", "starters"].contains(store.editorStep) {
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
        .fullScreenCover(item: $workout, onDismiss: workoutDismissed) { workout in
            NavigationStack {
                ActiveWorkout(store: training, sessionID: workout.sessionID, planner: store, route: workout.route,
                              onClose: minimizeWorkout, onFinished: finishWorkout,
                              applyToRoutine: futureReplacement(for: workout.sessionID),
                              routineExercises: store.plans.first { $0.id == store.activeID }?.days.flatMap(\.exercises) ?? [])
            }.id(workout.id)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshTraining()
        }
        .task(id: weekBoundary) {
            guard let weekBoundary else { return }
            var checkAt = weekBoundary
            while !Task.isCancelled, self.weekBoundary == weekBoundary {
                do { try await Task.sleep(for: .seconds(max(0, checkAt.timeIntervalSinceNow))) }
                catch { return }
                guard !Task.isCancelled, self.weekBoundary == weekBoundary else { return }
                if refreshTraining() { return }
                checkAt = .now.addingTimeInterval(5)
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

    private func futureReplacement(for sessionID: UUID) -> ((PlanExercise, PlanExercise) throws -> Void)? {
        guard let id = training.sessions.first(where: { $0.id == sessionID })?.occurrenceID,
              let occurrence = training.occurrences.first(where: { $0.id == id }),
              let planID = occurrence.planID, let day = occurrence.day else { return nil }
        return { original, replacement in
            try training.reconcileExpiredSessions()
            guard training.openSessions.contains(where: { $0.id == sessionID }) else {
                throw TrainingError("This workout is closed. Review its results in Progress.")
            }
            try store.replaceFutureExercise(planID: planID, dayID: day.id, original: original, replacement: replacement)
        }
    }

    private var recoveryScreen: some View {
        RecoveryScreen(planner: store, training: training, onRestore: {
            tab = "Plan"
            workout = nil
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
            try training.reconcileExpiredSessions()
            weekBoundary = training.nextWeekBoundary
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func openPendingRoute() {
        guard loaded, let url = pendingURL else { return }
        pendingURL = nil
        guard let route = WorkoutLiveRoute.parse(url), refreshTraining(),
              WorkoutLiveCoordinator.isCurrent(route, training: training, owner: store.profileID) else { return }
        perform {
            if let exerciseID = route.exerciseID,
               training.sessions.first(where: { $0.id == route.sessionID })?.currentExerciseID != exerciseID {
                try training.select(sessionID: route.sessionID, exerciseID: exerciseID)
            }
            workout = PresentedWorkout(sessionID: route.sessionID, route: route)
        }
    }

    private var showsWorkoutAccessory: Bool {
        guard let session = training.active else { return false }
        guard tab == "Plan", planRootVisible, !training.isPastWeek(agendaDate) else { return true }
        guard let id = session.occurrenceID else { return false }
        guard let occurrence = training.occurrences.first(where: { $0.id == id }) else { return true }
        return !training.isScheduled(occurrence, on: agendaDate)
    }

    private func resumeAccessory(_ session: TrainingSession) -> some View {
        let occurrence = training.occurrences.first { $0.id == session.occurrenceID }
        let exercise = session.exercises.first { $0.id == session.currentExerciseID }?.prescription.name ?? session.name
        let planned = occurrence.map { "Planned " + $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "Unscheduled"
        let started = "Started " + session.performedDay.date.formatted(.dateTime.month(.abbreviated).day())
        return Button { resumeWorkout(session.id) } label: {
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
        let day = CivilTrainingDay(agendaDate)
        presentWorkout(owner: owner, generation: restoreGeneration) {
            try target.start(planner: store, training: training, expectedDay: day)
        }
    }

    private func resumeWorkout(_ sessionID: UUID) {
        guard let owner = store.profileID else { return }
        presentWorkout(owner: owner, generation: restoreGeneration) {
            guard training.openSessions.contains(where: { $0.id == sessionID }) else { throw PlanStartTargetError.changed }
            try training.focus(sessionID: sessionID)
            return sessionID
        }
    }

    private func presentWorkout(owner: UUID, generation: UUID, select: @escaping () throws -> UUID) {
        perform {
            guard owner == store.profileID, generation == restoreGeneration else { throw PlanStartTargetError.changed }
            try training.load(profileID: owner)
            try training.reconcileExpiredSessions()
            weekBoundary = training.nextWeekBoundary
            workout = PresentedWorkout(sessionID: try select())
        }
    }

    private func minimizeWorkout() {
        workout = nil
    }

    private func workoutDismissed() {
        if pendingCelebration {
            finishPulse += 1
            pendingCelebration = false
        }
    }

    private func finishWorkout(_ session: TrainingSession) {
        guard session.finishedAt != nil else { return }
        let occurrence = training.occurrences.first { $0.id == session.occurrenceID }
        agendaDate = occurrence?.date ?? session.performedDay.date
        tab = "Plan"
        workout = nil
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
        weekBoundary = nil
        perform {
            do {
                let paths = try RecoveryPaths.current()
                store = PlanningStore(directory: paths.planning)
                training = TrainingStore(directory: paths.training)
                try store.load()
            } catch { loadFailed = true; throw error }
            if let owner = store.profileID {
                do {
                    try training.load(profileID: owner)
                    try training.reconcileExpiredSessions()
                    weekBoundary = training.nextWeekBoundary
                } catch { loadFailed = true; throw error }
            }
            activateNewRoutine = false
            if let draft = store.draft { editing = draft }
            loaded = true
            openPendingRoute()
        }
    }

    private func begin(_ plan: WeekPlan, _ step: String) {
        perform {
            try store.begin(plan, step: step)
            activateNewRoutine = false
            editing = plan
        }
    }

    private func changeStep(_ step: String) {
        perform { try store.update(editing, step: step) }
    }

    private var isReturningRoutineEditor: Bool {
        !store.plans.isEmpty || store.isLibraryDraft
    }

    private func discard() {
        let returning = isReturningRoutineEditor
        perform {
            try store.discard()
            if returning { tab = "Routines" }
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
