import SwiftUI

struct PlanScreen: View {
    let plan: WeekPlan?
    let training: TrainingStore
    @Binding var selected: Date
    let finishPulse: Int
    let isPastWeek: Bool
    let openWorkout: (UUID) -> Void
    let showRoutines: () -> Void
    let requestPlanStart: (PlanStartTarget) -> Void
    var onRootVisibilityChanged: (Bool) -> Void = { _ in }
    @State private var calendarOpen = false
    @State private var reviewID: UUID?
    @State private var visibleWeek: Date?
    @State private var pagerOrigin: Date?
    private var calendar: Calendar { .autoupdatingCurrent }
    private var weekday: Int { (calendar.component(.weekday, from: selected) + 5) % 7 }
    private var weekStart: Date {
        let day = calendar.startOfDay(for: selected)
        return calendar.date(byAdding: .day, value: -weekday, to: day) ?? day
    }
    private var datedWork: [TrainingOccurrence] {
        training.occurrences.filter { training.isScheduled($0, on: selected) }
    }
    private var standaloneSessions: [TrainingSession] {
        let displayed = Set(datedWork.map(\.id))
        return training.sessions.filter { session in
            training.isPerformed(session, on: selected) && session.finishedAt != nil && session.occurrenceID.map(displayed.contains) != true
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private var unscheduledWorkouts: [TrainingSession] {
        training.openSessions.filter { $0.occurrenceID == nil }
    }
    private var templateOccurrence: TrainingOccurrence? {
        guard let plan else { return nil }
        return training.occurrences.first { $0.planID == plan.id && training.isOriginal($0, on: selected) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                calendarHeader
                weekPager
                VStack(alignment: .leading, spacing: 20) {
                    if let plan { Label(plan.name, systemImage: "calendar").font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss) }
                    if isPastWeek {
                        Text("Read-only week").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !isPastWeek && !unscheduledWorkouts.isEmpty { unscheduledWorkoutList }
                    if let plan, plan.days.count == 7, templateOccurrence == nil, plan.days[weekday].isWorkout {
                        let day = plan.days[weekday]
                        let sourceDate = selected
                        PlannedWorkoutCard(name: day.name, day: day, goal: day.cardioGoalSeconds,
                                           status: PlanWorkoutState.notStarted.rawValue, detail: nil,
                                           primaryAction: isPastWeek ? nil : .startTemplate, selected: sourceDate,
                                           start: { _ in requestPlanStart(.template(plan, sourceDate)) },
                                           move: isPastWeek ? nil : { target in
                                               try training.move(plan: plan, date: sourceDate, to: target)
                                               selected = target
                                           }, skip: isPastWeek ? nil : {
                                               try training.skip(plan: plan, date: sourceDate)
                                           })
                    }
                    ForEach(datedWork) { entry in
                        let card = PlanCardState(state: training.planState(for: entry),
                                                 openSessionID: training.openSession(for: entry.id)?.id,
                                                 isPastWeek: isPastWeek)
                        PlannedWorkoutCard(name: entry.name, day: entry.day, goal: entry.cardioGoalSeconds,
                                           status: card.status, detail: detail(entry), credited: training.slotProgress(for: entry),
                                           primaryAction: card.action, selected: selected,
                                           start: { action in
                                               if case .resume(let id) = action { openWorkout(id) }
                                               else { requestPlanStart(.occurrence(entry.id)) }
                                           },
                                           move: card.canMoveOrSkip ? { date in try training.move(entry.id, to: date); selected = date } : nil,
                                           skip: card.canMoveOrSkip && entry.planID != nil ? { try training.skip(entry.id) } : nil,
                                           remove: !isPastWeek && training.canRemoveAdditionalActivity(entry) ? { try training.removeAdditionalActivity(entry.id) } : nil,
                                           review: card.canReview ? { reviewID = entry.id } : nil)
                        let contributions = training.sessions.filter { $0.occurrenceID == entry.id && $0.finishedAt != nil }
                            .sorted { $0.startedAt < $1.startedAt }
                        if !contributions.isEmpty {
                            SessionLogGroup(sessions: contributions, title: "Workout sessions (\(contributions.count))",
                                            training: training, plan: plan, allowAssignment: !isPastWeek)
                        }
                    }
                    if let moved = templateOccurrence, !training.isScheduled(moved, on: selected) {
                        Label("\(moved.name) moved to \(moved.date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                    } else if datedWork.isEmpty && !(plan?.days[safe: weekday]?.isWorkout ?? false) {
                        if plan == nil {
                            Text("No active routine").font(.title2.bold())
                            Button("Open Routines", action: showRoutines)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "moon.stars").font(.title2).foregroundStyle(PlannerStyle.moss)
                                Text("Rest day").font(.system(.largeTitle, design: .serif))
                                Text(isPastWeek ? "No workout scheduled." : "No workout scheduled. You can still log an extra session.")
                                    .foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                                .background(PlannerStyle.moss.opacity(0.085), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    if !isPastWeek {
                        NavigationLink {
                            AddCardioScreen(selected: selected, training: training, onScheduled: { selected = $0 })
                        } label: {
                            Label("Add cardio", systemImage: "figure.run").frame(minHeight: 44)
                        }.accessibilityIdentifier("scheduleCardio")
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Train now").font(.headline)
                            HStack {
                                Button { requestPlanStart(.extra) } label: { Label("Extra workout", systemImage: "plus") }
                                    .accessibilityIdentifier("extraWorkout")
                                Button { requestPlanStart(.cardio) } label: { Label("Log cardio", systemImage: "figure.run") }
                                    .accessibilityIdentifier("extraCardio")
                            }.buttonStyle(.bordered)
                        }
                    }
                    if !standaloneSessions.isEmpty {
                        Text("Activity on this date").font(.system(.title2, design: .serif))
                        ForEach(standaloneSessions) { session in
                            if let id = session.occurrenceID, let occurrence = training.occurrences.first(where: { $0.id == id }) {
                                let parts = standaloneSessions.filter { $0.occurrenceID == id }
                                if parts.first?.id == session.id {
                                    SessionLogGroup(sessions: parts, title: "\(occurrence.name) · \(occurrence.date.formatted(date: .abbreviated, time: .omitted))",
                                                    training: training, plan: plan, allowAssignment: !isPastWeek)
                                }
                            } else {
                                NavigationLink {
                                    SavedWorkoutDetail(id: session.id, training: training, plan: plan, allowAssignment: !isPastWeek)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(session.name).font(.headline)
                                            Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.planSessionStatus)")
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption)
                                    }
                                }.accessibilityIdentifier("savedSession")
                            }
                        }
                    }
                }
                .keyframeAnimator(initialValue: 1.0, trigger: CivilTrainingDay(selected)) { [reducedMotion] content, opacity in
                    content.opacity(reducedMotion ? 1 : opacity)
                } keyframes: { _ in
                    MoveKeyframe(0.78)
                    LinearKeyframe(1.0, duration: 0.18)
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(PlannerStyle.paper)
        .onAppear { onRootVisibilityChanged(true) }
        .onDisappear { onRootVisibilityChanged(false) }
        .navigationTitle("Plan").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $calendarOpen) {
            PlanMonthCalendar(date: selected) { date in selected = date; calendarOpen = false }
        }
        .navigationDestination(item: $reviewID) { id in
            if let entry = training.occurrences.first(where: { $0.id == id }) {
                List {
                    Section(entry.name) {
                        LabeledContent("Planned date", value: entry.date.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Status", value: training.status(for: entry))
                        if let progress = detail(entry) { Text(progress) }
                    }
                    Section("Workout sessions") {
                        ForEach(training.sessions.filter { $0.occurrenceID == id && $0.finishedAt != nil }.sorted { $0.startedAt < $1.startedAt }) { item in
                            NavigationLink {
                                SavedWorkoutDetail(id: item.id, training: training, plan: plan, allowAssignment: !isPastWeek)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.headline)
                                    Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                                    if item.isArchivedDraft {
                                        Text(item.planSessionStatus).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }.accessibilityIdentifier("reviewedSession")
                        }
                    }
                }.navigationTitle("Workout review")
            }
        }
    }

    private var unscheduledWorkoutList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open unscheduled workouts").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(unscheduledWorkouts) { session in
                let started = session.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                Button { openWorkout(session.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.name).font(.subheadline.weight(.semibold))
                            Text(started).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("Resume").font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Resume \(session.name), started \(started)")
                .accessibilityIdentifier("resumeUnscheduledWorkout")
            }
        }
    }

    private var calendarHeader: some View {
        Button { calendarOpen = true } label: {
            Text(selected.formatted(.dateTime.month(.wide).year()))
                .font(.system(.title, design: .serif, weight: .medium)).foregroundStyle(PlannerStyle.ink)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("monthYear")
        .accessibilityHint("Choose a date in the calendar.")
        .accessibilityAction(named: "Previous week") { changeWeek(-1) }
        .accessibilityAction(named: "Next week") { changeWeek(1) }
        .accessibilityAction(named: "Return to today") { selected = .now }
    }

    private func changeWeek(_ direction: Int) {
        if let date = calendar.date(byAdding: .day, value: 7 * direction, to: selected) { selected = date }
    }

    private func detail(_ entry: TrainingOccurrence) -> String? {
        let counts = training.progress(for: entry)
        let sessions = training.sessions.filter { $0.occurrenceID == entry.id }
        guard counts.completed > 0 || !sessions.isEmpty else { return nil }
        let amount = "\(counts.completed) / \(counts.total) \(entry.cardioGoalSeconds == nil ? "sets" : "seconds")"
        let dates = Set(sessions.map { $0.startedAt.formatted(date: .abbreviated, time: .omitted) }).sorted()
        return dates.isEmpty ? amount : amount + " · " + dates.joined(separator: ", ")
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reducedMotion: Bool {
        #if WEEKFORM_DEVELOPMENT
        let environment = ProcessInfo.processInfo.environment
        if environment["WEEKFORM_UI_TEST_RUN"].flatMap(UUID.init(uuidString:)) != nil,
           environment["WEEKFORM_UI_TEST_REDUCE_MOTION"] == "1" { return true }
        #endif
        return systemReduceMotion
    }
    private var weekPager: some View {
        let start = weekStart
        let origin = pagerOrigin ?? start
        let pages = (-52...52).compactMap { calendar.date(byAdding: .day, value: $0 * 7, to: origin) }
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages, id: \.self) { page in
                        weekStrip(start: page)
                            .containerRelativeFrame(.horizontal)
                            .accessibilityHidden(page != start)
                            .id(page)
                    }
                }.scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(.center)
            .scrollPosition(id: $visibleWeek, anchor: .center)
            .onScrollPhaseChange { _, phase in
                guard phase == .idle, let page = visibleWeek, pages.contains(page), page != weekStart,
                      let date = calendar.date(byAdding: .day, value: weekday, to: page) else { return }
                selected = date
            }
            .onChange(of: start, initial: true) { _, newStart in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if pagerOrigin == nil { pagerOrigin = origin }
                    // Keep page indices fixed across normal swipes. Build a new
                    // centered pager only at an endpoint or after a distant jump.
                    if !pages.contains(newStart) || newStart == pages.first || newStart == pages.last {
                        pagerOrigin = newStart
                        visibleWeek = newStart
                    } else if visibleWeek != newStart {
                        visibleWeek = newStart
                        proxy.scrollTo(newStart, anchor: .center)
                    }
                }
            }
        }
        .id(origin)
    }

    private func weekStrip(start: Date) -> some View {
        let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: typeSize.isAccessibilitySize ? 4 : 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(week, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selected)
                let entries = training.occurrences.filter { training.isScheduled($0, on: date) }
                let index = CivilTrainingDay(date).mondayIndex
                let templateScheduled = (plan?.days[safe: index]?.isWorkout == true) &&
                    !training.occurrences.contains { $0.planID == plan?.id && training.isOriginal($0, on: date) && !training.isScheduled($0, on: date) }
                let pendingTemplate = templateScheduled && !entries.contains { $0.planID == plan?.id && training.isOriginal($0, on: date) }
                let complete = !pendingTemplate && !entries.isEmpty && entries.allSatisfy { training.planState(for: $0) == .finished }
                let planned = templateScheduled || !entries.isEmpty
                let tile = VStack(spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(isSelected ? Color(uiColor: .systemBackground).opacity(0.87) : PlannerStyle.moss)
                        .opacity(calendar.isDateInToday(date) ? 1 : 0)
                        .accessibilityHidden(true)
                    Text(date, format: .dateTime.day()).font(.system(.headline, design: .rounded).monospacedDigit())
                    Image(systemName: complete ? "checkmark.circle.fill" : planned ? "dumbbell.fill" : "minus")
                        .font(.caption2)
                        .symbolEffect(.bounce, value: reducedMotion || !isSelected || !complete ? 0 : finishPulse)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : PlannerStyle.moss)
                .background(isSelected ? PlannerStyle.moss : PlannerStyle.moss.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                if start == weekStart {
                    Button { selected = date } label: { tile }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("weekday\(index)")
                        .accessibilityLabel((calendar.isDateInToday(date) ? "Today, " : "") + date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue(complete ? "Complete" : planned ? "Workout" : "Rest day")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    tile.accessibilityHidden(true).allowsHitTesting(false)
                }
            }
        }
    }
}

private struct PlanMonthCalendar: View {
    @State private var date: Date
    let choose: (Date) -> Void

    init(date: Date, choose: @escaping (Date) -> Void) {
        _date = State(initialValue: date)
        self.choose = choose
    }

    var body: some View {
        ScrollView {
            DatePicker("Plan date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
        }
        .background(PlannerStyle.paper)
        .navigationTitle("Calendar")
        .safeAreaInset(edge: .bottom) {
            Button { choose(date) } label: {
                Text("Show \(date.formatted(.dateTime.month(.abbreviated).day()))")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large).padding()
             .accessibilityIdentifier("showPlanDate")
        }
    }
}

private struct SessionLogGroup: View {
    let sessions: [TrainingSession]
    let title: String
    let training: TrainingStore
    let plan: WeekPlan?
    let allowAssignment: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack { Label(title, systemImage: "clock.arrow.circlepath"); Spacer(); Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .frame(minHeight: 44)
            }.accessibilityIdentifier("workoutSessions").accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                ForEach(Array(sessions.sorted { $0.startedAt < $1.startedAt }.enumerated()), id: \.element.id) { index, item in
                    Divider()
                    NavigationLink {
                        SavedWorkoutDetail(id: item.id, training: training, plan: plan, allowAssignment: allowAssignment)
                    } label: {
                        HStack {
                            Text("Session \(index + 1)").font(.headline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                                if item.isArchivedDraft { Text(item.planSessionStatus).foregroundStyle(.secondary) }
                            }.font(.subheadline)
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(.vertical, 10)
                    }.accessibilityIdentifier("savedSession")
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private struct PlannedWorkoutCard: View {
    let name: String
    let day: PlanDay?
    let goal: Int?
    let status: String
    let detail: String?
    var credited: [UUID: [Bool]] = [:]
    let primaryAction: PlanCardState.Action?
    let selected: Date
    let start: (PlanCardState.Action) -> Void
    let move: ((Date) throws -> Void)?
    let skip: (() throws -> Void)?
    var remove: (() throws -> Void)? = nil
    @State private var rescheduling = false
    @State private var confirmingSkip = false
    @State private var confirmingRemove = false
    @State private var problem: String?
    var review: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(status)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("planWorkoutStatus")
                    Spacer(minLength: 8)
                    if move != nil || skip != nil || remove != nil {
                        Menu {
                            if move != nil {
                                Button { rescheduling = true } label: { Label("Reschedule", systemImage: "calendar.badge.clock") }
                                .accessibilityIdentifier("rescheduleWorkout")
                            }
                            if skip != nil {
                                Button(role: .destructive) { confirmingSkip = true } label: { Label("Skip", systemImage: "forward.end") }
                                    .accessibilityIdentifier("skipPlannedWorkout")
                            }
                            if remove != nil {
                                Button(role: .destructive) { confirmingRemove = true } label: { Label("Remove", systemImage: "trash") }
                                    .accessibilityIdentifier("removePlannedActivity")
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.body.weight(.semibold))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .tint(.white).accessibilityLabel("Options for \(name)")
                        .accessibilityIdentifier("planWorkoutOptions")
                    }
                }
                Text(name).font(.system(.largeTitle, design: .serif, weight: .medium))
                if let detail { Text(detail).font(.subheadline) }
                else if let goal { Text("\(goal / 60) min cardio").font(.subheadline) }
                else if let day {
                    Text("\(day.exercises.count) prescribed exercises")
                        .font(.subheadline.weight(.medium))
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.white).background(PlannerStyle.forest)
            if let day {
                ForEach(day.exercises) { exercise in
                    let slots = credited[exercise.id] ?? []
                    let completed = slots.filter { $0 }.count
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).font(.headline)
                            Text(prescription(exercise))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if exercise.sets <= 6 {
                            HStack(spacing: 3) {
                                ForEach(0..<max(0, exercise.sets), id: \.self) { index in
                                    Capsule().fill((slots.indices.contains(index) && slots[index]) ? PlannerStyle.moss : PlannerStyle.rule)
                                        .frame(width: 5, height: 16)
                                }
                            }.accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(completed) of \(exercise.sets) sets complete")
                        } else {
                            Text("\(completed)/\(exercise.sets)").font(.subheadline.monospacedDigit())
                                .accessibilityLabel("\(completed) of \(exercise.sets) sets complete")
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 12)
                    Divider().padding(.leading, 18)
                }
            }
            if let primaryAction {
                Button { start(primaryAction) } label: {
                    Label(primaryAction.title, systemImage: "play.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).padding(14)
                    .accessibilityLabel("\(primaryAction.title) \(name)").accessibilityIdentifier(primaryAction.accessibilityID)
            }
            if let review {
                Button(action: review) { Label("Review workout", systemImage: "checkmark.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large).padding(14).accessibilityIdentifier("reviewOccurrence")
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.subheadline).padding(14)
                    .accessibilityIdentifier("planWorkoutActionError")
            }
        }
        .background(PlannerStyle.surface).clipShape(RoundedRectangle(cornerRadius: 20))
        .navigationDestination(isPresented: $rescheduling) {
            if let move { RescheduleWorkoutScreen(selected: selected, title: name, move: move) }
        }
        .confirmationDialog("Skip this scheduled workout?", isPresented: $confirmingSkip, titleVisibility: .visible) {
            Button("Skip workout", role: .destructive) { if let skip { perform(skip) } }
                .accessibilityIdentifier("confirmSkipWorkout")
            Button("Keep workout", role: .cancel) {}
        } message: { Text("Only this scheduled workout is skipped. Your routine and logged workouts are kept.") }
        .confirmationDialog("Remove this planned activity?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove activity", role: .destructive) { if let remove { perform(remove) } }
                .accessibilityIdentifier("confirmRemovePlannedActivity")
            Button("Keep activity", role: .cancel) {}
        } message: { Text("This activity will be removed from the plan. Logged workouts stay in your history on their original dates.") }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); problem = nil } catch { problem = error.localizedDescription }
    }
}

private struct SavedWorkoutDetail: View {
    let id: UUID
    let training: TrainingStore
    let plan: WeekPlan?
    let allowAssignment: Bool

    var body: some View {
        if let session = training.sessions.first(where: { $0.id == id }) {
            let canAssign = session.isCardio ? session.cardio != nil && session.occurrenceID == nil :
                session.exercises.flatMap(\.sets).contains { $0.confirmedAt != nil && $0.warmup != true && $0.plannedID == nil }
            List {
                Section { LabeledContent("Status", value: session.planSessionStatus) }
                TrainingSummaryContent(session: session)
                if allowAssignment && canAssign {
                    Section {
                        NavigationLink("Assign to planned work") {
                            AssignTrainingWork(sessionID: session.id, training: training, plan: plan)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(PlannerStyle.paper)
            .navigationTitle(session.name)
        }
    }
}

private extension TrainingSession {
    var planSessionStatus: String {
        if isArchivedDraft { return "Closed draft" }
        return partial ? "Finished partial" : "Finished"
    }
}
