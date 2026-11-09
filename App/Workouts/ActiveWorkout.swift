import SwiftUI

struct ActiveWorkout: View {
    let store: TrainingStore
    let sessionID: UUID
    var planner: PlanningStore? = nil
    var route: WorkoutLiveRoute? = nil
    let onClose: () -> Void
    var onFinished: ((TrainingSession) -> Void)? = nil
    var applyToRoutine: ((PlanExercise, PlanExercise) throws -> Void)? = nil
    var routineExercises: [PlanExercise] = []

    @State private var panel: WorkoutPanel?
    @State private var problem: String?
    @State private var changedFuture: UUID?
    @State private var confirmingDiscard = false
    @State private var reviewing = false
    @State private var handledRoute = false
    @State private var chosenRow: UUID?
    @State private var setEditor = SetEditor.current
    @State private var closingEditor: ClosingSetEditor?
    @State private var expandedGroups: [UUID: Bool] = [:]
    @State private var checklistPosition = ScrollPosition()
    @State private var checklistLayout = ChecklistLayout()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var progressTitleSize = 24.0

    private var session: TrainingSession? { store.openSessions.first { $0.id == sessionID } }
    private var exercise: TrainingExercise? {
        guard let session else { return nil }
        return session.exercises.first { $0.id == session.currentExerciseID } ?? session.exercises.first
    }

    private var availableExercises: [PlanExercise] {
        var seen = Set<UUID>()
        return (store.knownExercises + routineExercises).filter { seen.insert($0.variantID ?? $0.id).inserted }
    }

    var body: some View {
        Group {
            if let session {
                let occurrence = store.occurrences.first { $0.id == session.occurrenceID }
                let checklist = WorkoutChecklist(session: session, occurrence: occurrence, sessions: store.sessions)
                ScrollViewReader { scroll in
                    Group {
                        if session.isCardio {
                            List { CardioLog(session: session, store: store) }
                                .listStyle(.insetGrouped)
                                .scrollContentBackground(.hidden)
                        } else {
                            strengthChecklist(checklist, session: session)
                        }
                    }
                    .background(PlannerStyle.paper)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: currentRowID) { _, id in
                        if let id, id != chosenRow, setEditor == .current { scroll.scrollTo(id) }
                    }
                    .onChange(of: exercise?.id) { _, _ in
                        if setEditor == .current, currentRowID == nil, let first = exercise?.sets.first {
                            scroll.scrollTo(first.id)
                        }
                    }
                    .onChange(of: openEditorID) { _, id in
                        if case .correction(let correctionID) = setEditor, id != correctionID {
                            setEditor = .closed
                        }
                    }
                    .task {
                        if let route, !handledRoute {
                            handledRoute = true
                            panel = nil
                            reviewing = route.review
                            guard !route.review else { return }
                            chosenRow = route.setID
                            await Task.yield()
                        }
                        if let id = currentRowID { scroll.scrollTo(id, anchor: .center) }
                    }
                }
                .navigationTitle(session.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose).accessibilityHint("Keeps this workout open to resume later")
                    }
                    .sharedBackgroundVisibility(session.isCardio ? .automatic : .hidden)
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish") { reviewing = true }
                            .accessibilityHint("Opens the workout summary").accessibilityIdentifier("reviewSession")
                    }
                    .sharedBackgroundVisibility(session.isCardio ? .automatic : .hidden)
                }
                .toolbarBackground(PlannerStyle.paper, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !session.isCardio { progressHeader(checklist) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if let problem { Label(problem, systemImage: "exclamationmark.circle").font(.footnote).padding(8) }
                        if !session.isCardio { actionBar(session) }
                    }.background(PlannerStyle.surface)
                }
                .navigationDestination(isPresented: $reviewing) { summary(session) }
                .sheet(item: $panel) { panel in
                    NavigationStack {
                        switch panel {
                        case .instructions(let prescription):
                            List {
                                Text(prescription.notes)
                            }
                            .navigationTitle(prescription.name)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { self.panel = nil }
                                }
                            }
                        case .rest:
                            if let exercise {
                                WorkoutRestEditor(current: exercise.restSeconds) { seconds in
                                    try store.configureRest(sessionID: session.id, exerciseID: exercise.id, seconds: seconds)
                                }
                            }
                        case .add, .swap:
                            let swapping: Bool = if case .swap = panel { true } else { false }
                            WorkoutExercisePicker(planner: planner, known: availableExercises,
                                                  replacing: swapping ? exercise : nil) { prescription, basis in
                                if swapping, let exercise {
                                    try store.substitute(sessionID: session.id, exerciseID: exercise.id, prescription: prescription, basis: basis)
                                } else {
                                    try store.add(sessionID: session.id, prescription: prescription, basis: basis)
                                }
                                closingEditor = nil
                                setEditor = .current
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Workout closed", systemImage: "checkmark.circle",
                                       description: Text("You can review saved workouts in Progress."))
                    .toolbar { Button("Done", action: onClose) }
            }
        }
        .tint(PlannerStyle.moss)
    }

    private var currentRowID: UUID? {
        guard let exercise else { return nil }
        return exercise.sets.first { $0.id == chosenRow && $0.confirmedAt == nil }?.id ??
            exercise.sets.first { $0.confirmedAt == nil }?.id
    }

    private var openEditorID: UUID? {
        switch setEditor {
        case .current: currentRowID
        case .closed: nil
        case .correction(let id):
            session?.exercises.contains { exercise in
                exercise.sets.contains { $0.id == id && $0.confirmedAt != nil }
            } == true ? id : nil
        }
    }

    private var disclosureAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.24) }

    private func strengthChecklist(_ checklist: WorkoutChecklist, session: TrainingSession) -> some View {
        let editorID = openEditorID
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let exercise, session.rest != nil {
                    GroupBox("Rest timer") {
                        VStack(alignment: .leading, spacing: 8) {
                            restControls(session: session, exercise: exercise)
                        }
                    }
                } else if exercise == nil {
                    Text("Add your first exercise to start logging sets.").foregroundStyle(.secondary)
                }
                ForEach(checklist.groups) { group in
                    checklistSection(group, session: session, editorID: editorID) { id in
                        retainHeading(id, in: checklist)
                    }
                }
                if let exercise, exercise.sets.allSatisfy({ $0.confirmedAt != nil }),
                   let next = session.exercises.first(where: { $0.id != exercise.id && $0.sets.contains { $0.confirmedAt == nil } }) {
                    Button("Next exercise: \(next.prescription.name)") {
                        selectExercise(next, session: session)
                    }
                    .frame(minHeight: 44)
                }
                if let exercise, let original = exercise.replacedPrescription {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Replaced", value: original.name)
                            if let applyToRoutine, session.occurrenceID != nil {
                                if changedFuture == exercise.id {
                                    Label("Future workouts updated", systemImage: "checkmark")
                                } else {
                                    Button("Also change future workouts") {
                                        run {
                                            try applyToRoutine(original, exercise.prescription)
                                            changedFuture = exercise.id
                                        }
                                    }
                                    .frame(minHeight: 44)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .scrollPosition($checklistPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            checklistLayout.offset = offset
        }
    }

    private func retainHeading(_ id: UUID, in checklist: WorkoutChecklist) {
        guard checklistLayout.offset > 0, let editor = checklistLayout.editor, editor.id == openEditorID, editor.id != id,
              checklist.groups.lazy.flatMap(\.rows).first(where: { $0.id == id || $0.id == editor.id })?.id == editor.id else { return }
        // Only compensate for space removed above the tapped heading. At the
        // top, let the earlier panel compact without leaving an empty gap.
        checklistPosition.scrollTo(y: max(0, checklistLayout.offset - editor.height))
    }

    private func progressHeader(_ checklist: WorkoutChecklist) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    progressTitle.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    progressCount(checklist).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    progressTitle
                    progressCount(checklist)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Workout progress")
            .accessibilityValue("\(checklist.completed) of \(checklist.total) sets logged")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("workoutSetProgress")
            ProgressView(value: Double(checklist.completed), total: Double(max(1, checklist.total)))
                .tint(PlannerStyle.moss).accessibilityHidden(true)
        }
        .foregroundStyle(PlannerStyle.ink)
        .padding(.horizontal, 16).padding(.bottom, 6)
        .background(PlannerStyle.paper)
    }

    private var progressTitle: some View {
        Text("Workout progress").font(.system(size: progressTitleSize, weight: .semibold)).tracking(-0.7)
    }

    private func progressCount(_ checklist: WorkoutChecklist) -> some View {
        Text("\(checklist.completed) of \(checklist.total) logged")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }

    private func checklistSection(_ group: WorkoutChecklist.Group, session: TrainingSession, editorID: UUID?,
                                  beforeOpening: @escaping (UUID) -> Void) -> some View {
        let isCurrent = group.liveExercise?.id == exercise?.id && group.liveExercise != nil
        let isExpanded = expandedGroups[group.id] ?? isCurrent
        let showsInlineOptions = isCurrent && isExpanded && editorID != nil && editorID == currentRowID
        return LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(disclosureAnimation) {
                        expandedGroups[group.id] = !isExpanded
                        if isExpanded, let editorID, group.rows.contains(where: { $0.id == editorID }) {
                            setEditor = .closed
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(group.prescription.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text("\(group.completed)/\(group.rows.count)")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.prescription.name)
                .accessibilityValue("\(group.completed) of \(group.rows.count) sets logged, \(isExpanded ? "expanded" : "collapsed")")
                .accessibilityIdentifier("exerciseChecklist-\(group.id.uuidString)")
                if let live = group.liveExercise, !showsInlineOptions {
                    exerciseOptions(session: session, exercise: live)
                } else if group.liveExercise == nil, !group.prescription.notes.isEmpty {
                    Button {
                        panel = .instructions(group.prescription)
                    } label: {
                        Image(systemName: "info.circle").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Instructions for \(group.prescription.name)")
                }
            }
            if isExpanded {
                ForEach(group.rows) { item in
                    checklistRow(item, group: group, session: session, isCurrentExercise: isCurrent,
                                 editorID: editorID, beforeOpening: beforeOpening)
                        .id(item.id)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.bottom, isExpanded ? 4 : 0)
        .background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(PlannerStyle.moss.opacity(0.18))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func checklistRow(_ item: WorkoutChecklist.Row, group: WorkoutChecklist.Group,
                              session: TrainingSession, isCurrentExercise: Bool, editorID: UUID?,
                              beforeOpening: @escaping (UUID) -> Void) -> some View {
        switch item {
        case .earlier(let set, let ordinal, let date):
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Set \(ordinal)").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(actualDescription(set.actual, basis: group.basis)).font(.subheadline)
                        .multilineTextAlignment(.trailing)
                }
                Text("Logged earlier · \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("priorSet-\((set.plannedID ?? set.id).uuidString)")
        case .remaining(_, let ordinal):
            Label("Set \(ordinal) · Remaining in plan", systemImage: "circle.dashed")
                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 5)
        case .live(let row, let index):
            if let live = group.liveExercise {
                WorkoutSetRow(sessionID: session.id, exercise: live, row: row, index: index, store: store,
                              isCurrent: isCurrentExercise && row.id == currentRowID, isExpanded: row.id == editorID,
                              closingCorrection: closingEditor?.rowID == row.id ? closingEditor?.isCorrection : nil,
                              target: targetDescription(group.prescription), onToggle: {
                    if row.id == editorID {
                        closeEditor(row)
                    } else if row.confirmedAt != nil {
                        beforeOpening(row.id)
                        closingEditor = nil
                        setEditor = .correction(row.id)
                    } else {
                        selectExercise(live, session: session, rowID: row.id, beforeOpening: beforeOpening)
                    }
                }, onCloseCorrection: { closeEditor(row) }, onEditorHeightChange: { height in
                    checklistLayout.editor = (row.id, height)
                }) {
                    exerciseOptions(session: session, exercise: live)
                }
            }
        }
    }

    private func closeEditor(_ row: TrainingSet) {
        guard setEditor != .closed else { return }
        if reduceMotion {
            closingEditor = nil
            setEditor = .closed
            return
        }
        let closing = ClosingSetEditor(rowID: row.id, isCorrection: row.confirmedAt != nil)
        withAnimation(.easeOut(duration: 0.20), completionCriteria: .removed) {
            closingEditor = closing
            setEditor = .closed
        } completion: {
            if closingEditor == closing { closingEditor = nil }
        }
    }

    private func selectExercise(_ exercise: TrainingExercise, session: TrainingSession, rowID: UUID? = nil,
                                beforeOpening: (UUID) -> Void = { _ in }) {
        run {
            if let previous = self.exercise?.id, previous != exercise.id {
                try store.select(sessionID: session.id, exerciseID: exercise.id)
                if rowID != nil, expandedGroups[previous] == nil { expandedGroups[previous] = true }
            }
            if let rowID { beforeOpening(rowID) }
            closingEditor = nil
            expandedGroups[exercise.id] = true
            chosenRow = rowID
            setEditor = .current
        }
    }

    private func exerciseOptions(session: TrainingSession, exercise: TrainingExercise) -> some View {
        Menu {
            if !exercise.prescription.notes.isEmpty {
                Button("Instructions", systemImage: "info.circle") { panel = .instructions(exercise.prescription) }
            }
            basisPicker(session: session, exercise: exercise)
        } label: {
            Image(systemName: "ellipsis").font(.subheadline.weight(.semibold))
                .foregroundStyle(PlannerStyle.moss).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Options for \(exercise.prescription.name)")
    }

    private func actionBar(_ session: TrainingSession) -> some View {
        let columns = typeSize.isAccessibilitySize ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            Button { panel = .add } label: { tool("Add exercise", "plus") }
                .accessibilityIdentifier("addCustomExercise")
            Menu {
                if let exercise {
                    Button("Add warm-up set") { run { try store.addSet(sessionID: session.id, exerciseID: exercise.id, warmup: true) } }
                    Button("Add working set") { run { try store.addSet(sessionID: session.id, exerciseID: exercise.id, warmup: false) } }
                }
            } label: { tool("Add set", "square.stack") }
                .disabled(exercise == nil).accessibilityIdentifier("addSet")
            Button { panel = .rest } label: { tool("Rest", "timer") }
                .disabled(exercise == nil).accessibilityIdentifier("workoutRest")
            Button { panel = .swap } label: { tool("Swap", "arrow.triangle.2.circlepath") }
                .disabled(exercise?.sets.contains { $0.confirmedAt == nil } != true)
                .accessibilityLabel("Swap remaining sets").accessibilityIdentifier("swapExercise")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 4)
        .overlay(alignment: .top) { Rectangle().fill(PlannerStyle.rule).frame(height: 1) }
    }

    private func tool(_ label: String, _ systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).font(.subheadline.weight(.medium))
            Text(label).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(PlannerStyle.moss).frame(maxWidth: .infinity, minHeight: 47)
        .background(PlannerStyle.moss.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func basisPicker(session: TrainingSession, exercise: TrainingExercise) -> some View {
        let options = LoadBasis.allCases.filter { ($0 == .timed) == exercise.prescription.timed }
        return Picker("What to track", selection: Binding(get: { exercise.basis }, set: { basis in
            run { try store.setBasis(sessionID: session.id, exerciseID: exercise.id, basis: basis) }
        })) {
            ForEach(options, id: \.self) { Text(basisTitle($0)).tag($0) }
        }
        .disabled(exercise.sets.contains { $0.confirmedAt != nil })
    }

    @ViewBuilder
    private func restControls(session: TrainingSession, exercise: TrainingExercise) -> some View {
        if let rest = session.rest {
            let sourceTime = session.exercises.lazy.flatMap(\.sets).first { $0.id == rest.sourceSetID }?.confirmedAt
            let uninterrupted = sourceTime == rest.startedAt && rest.pausedAt == nil && rest.pausedSeconds == 0
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(uninterrupted ? "Since last logged set" : (rest.pausedAt == nil ? "Rest timer" : "Rest paused")) {
                        Text("\(elapsedString(rest.elapsed(at: timeline.date))) / \(elapsedString(TimeInterval(rest.targetSeconds)))")
                            .monospacedDigit()
                    }
                    if !uninterrupted, let sourceTime {
                        Text("\(elapsedString(timeline.date.timeIntervalSince(sourceTime))) since last logged set")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Start set") { run { try store.startSet(sessionID: session.id) } }
            HStack {
                Button(rest.pausedAt == nil ? "Pause" : "Resume") {
                    run {
                        if rest.pausedAt == nil { try store.pauseRest(sessionID: session.id) }
                        else { try store.resumeRest(sessionID: session.id) }
                    }
                }
                Spacer()
                Button("+30 sec") { run { try store.extendRest(sessionID: session.id, seconds: 30) } }
                Spacer()
                Button("Reset") { run { try store.resetRest(sessionID: session.id) } }
            }
            .buttonStyle(.bordered)
        }
        Button { panel = .rest } label: {
            LabeledContent("Rest between sets", value: exercise.restSeconds.map { "\($0) sec" } ?? "Off")
        }
    }

    private func summary(_ session: TrainingSession) -> some View {
        let rows = session.exercises.flatMap(\.sets)
        let occurrenceProgress = store.occurrences.first { $0.id == session.occurrenceID }.map { store.progress(for: $0) }
        let cardioComplete = session.cardio != nil && (occurrenceProgress.map { $0.completed >= $0.total } ?? true)
        let cardioEdits = session.isCardio && session.cardio != nil && session.cardioDraft != session.cardio
        let allConfirmed = session.isCardio ? cardioComplete : rows.contains { $0.confirmedAt != nil } && rows.allSatisfy { $0.optional == true || $0.confirmedAt != nil }
        let hasSavedContent = session.hasSavedContent
        return List {
            TrainingSummaryContent(session: session, showsNotes: false)
            Section {
                DisclosureGroup("Workout notes") {
                    TextField("Add a note", text: Binding(get: { self.session?.notes ?? "" }, set: { text in
                        run { try store.note(sessionID: session.id, text: text) }
                    }), axis: .vertical).lineLimit(1...5)
                }
            }
            if let occurrenceProgress {
                Section("Scheduled workout") {
                    LabeledContent(session.isCardio ? "Duration credited" : "Sets credited",
                                   value: session.isCardio
                                   ? "\(elapsedString(TimeInterval(occurrenceProgress.completed))) of \(elapsedString(TimeInterval(occurrenceProgress.total)))"
                                   : "\(occurrenceProgress.completed) of \(occurrenceProgress.total)")
                }
            }
            if cardioEdits {
                Text("Go back and confirm your activity changes before finishing.").foregroundStyle(.secondary)
            }
            if !hasSavedContent {
                Button("Discard empty workout", role: .destructive) { confirmingDiscard = true }
                    .confirmationDialog("Discard this empty workout?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Discard workout", role: .destructive) {
                            run {
                                try store.cancelEmpty(sessionID: session.id)
                                onClose()
                            }
                        }
                    }
            }
        }
        .navigationTitle("Workout summary").navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let problem { Label(problem, systemImage: "exclamationmark.circle").font(.footnote) }
                Button {
                    run {
                        try store.finish(sessionID: session.id, partial: !allConfirmed)
                        if let saved = store.sessions.first(where: { $0.id == session.id }), let onFinished {
                            onFinished(saved)
                        } else { onClose() }
                    }
                } label: {
                    Text(allConfirmed ? "Finish workout" : "Finish as partial").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!hasSavedContent || cardioEdits)
                .accessibilityIdentifier(allConfirmed ? "finishSession" : "finishPartial")
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(PlannerStyle.surface)
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action(); problem = nil } catch { problem = error.localizedDescription }
    }
}

// Layout measurements are only read on a title tap, so scrolling does not
// invalidate the workout view on every frame.
private final class ChecklistLayout {
    var offset: CGFloat = 0
    var editor: (id: UUID, height: CGFloat)?
}

private enum SetEditor: Equatable {
    case current, closed
    case correction(UUID)
}

private struct ClosingSetEditor: Equatable {
    let token = UUID()
    let rowID: UUID
    let isCorrection: Bool
}

private enum WorkoutPanel: Identifiable {
    case add, swap, rest
    case instructions(PlanExercise)

    var id: String {
        switch self {
        case .add: "add"
        case .swap: "swap"
        case .rest: "rest"
        case .instructions(let prescription): prescription.id.uuidString
        }
    }
}

private func targetDescription(_ prescription: PlanExercise) -> String {
    let range = prescription.low == prescription.high ? String(prescription.low) : "\(prescription.low)–\(prescription.high)"
    return "\(range) \(prescription.timed ? "sec" : "reps")"
}
