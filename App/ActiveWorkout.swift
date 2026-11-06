import SwiftUI

struct ActiveWorkout: View {
    let store: TrainingStore
    var planner: PlanningStore? = nil
    var route: WorkoutLiveRoute? = nil
    var routeEvent: UUID? = nil
    let onClose: () -> Void
    var onFinished: ((TrainingSession) -> Void)? = nil
    var applyToRoutine: ((PlanExercise, PlanExercise) throws -> Void)? = nil
    var routineExercises: [PlanExercise] = []

    @State private var panel: WorkoutPanel?
    @State private var problem: String?
    @State private var changedFuture: UUID?
    @State private var confirmingDiscard = false
    @State private var reviewing = false
    @State private var chosenRow: UUID?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var session: TrainingSession? { store.active }
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
                    List {
                        if session.isCardio {
                            CardioLog(session: session, store: store)
                        } else {
                            if let exercise {
                                Section {
                                    if !exercise.prescription.notes.isEmpty {
                                        Text(exercise.prescription.notes).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    basisPicker(session: session, exercise: exercise)
                                }
                                if session.rest != nil {
                                    Section("Rest timer") { restControls(session: session, exercise: exercise) }
                                }
                            } else {
                                Section {
                                    Text("Add your first exercise to start logging sets.").foregroundStyle(.secondary)
                                }
                            }
                            ForEach(checklist.groups) { group in
                                checklistSection(group, session: session)
                            }
                            if let exercise, exercise.sets.allSatisfy({ $0.confirmedAt != nil }),
                               let next = session.exercises.first(where: { $0.id != exercise.id && $0.sets.contains { $0.confirmedAt == nil } }) {
                                Button("Next exercise: \(next.prescription.name)") {
                                    run { try store.select(sessionID: session.id, exerciseID: next.id) }
                                }
                            }
                            if let exercise, let original = exercise.replacedPrescription {
                                Section {
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
                                        }
                                    }
                                }
                            }
                        }
                        Section("Workout notes") {
                            TextField("Add a note", text: Binding(get: { store.active?.notes ?? "" }, set: { text in
                                run { try store.note(sessionID: session.id, text: text) }
                            }), axis: .vertical).lineLimit(1...5)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(PlannerStyle.paper)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: currentRowID) { _, id in
                        if let id { scroll.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: exercise?.id) { _, _ in
                        if currentRowID == nil, let first = exercise?.sets.first {
                            scroll.scrollTo(first.id, anchor: .center)
                        }
                    }
                    .task(id: routeEvent) {
                        if let route {
                            panel = nil
                            reviewing = route.review
                            guard !route.review else { return }
                            chosenRow = route.setID
                            await Task.yield()
                        }
                        if let id = route?.setID ?? currentRowID { scroll.scrollTo(id, anchor: .center) }
                    }
                }
                .navigationTitle(session.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose).accessibilityHint("Keeps this workout open to resume later")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Review") { reviewing = true }
                            .accessibilityLabel("Review workout").accessibilityIdentifier("reviewSession")
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !session.isCardio { progressHeader(checklist, session: session) }
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
                        case .rest:
                            if let exercise {
                                WorkoutRestEditor(current: exercise.restSeconds) { seconds in
                                    try store.configureRest(sessionID: session.id, exerciseID: exercise.id, seconds: seconds)
                                }
                            }
                        case .add, .swap:
                            let swapping = panel == .swap
                            WorkoutExercisePicker(planner: planner, known: availableExercises,
                                                  replacing: swapping ? exercise : nil) { prescription, basis in
                                if swapping, let exercise {
                                    try store.substitute(sessionID: session.id, exerciseID: exercise.id, prescription: prescription, basis: basis)
                                } else {
                                    try store.add(sessionID: session.id, prescription: prescription, basis: basis)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Workout closed", systemImage: "checkmark.circle")
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

    private func progressHeader(_ checklist: WorkoutChecklist, session: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let exercise {
                exerciseMenu(session: session, exercise: exercise)
            }
            HStack {
                Text("Set checklist").font(.subheadline)
                Spacer()
                Text("\(checklist.completed) of \(checklist.total)").font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(checklist.completed) of \(checklist.total) sets complete")
            .accessibilityIdentifier("workoutSetProgress")
            ProgressView(value: Double(checklist.completed), total: Double(max(1, checklist.total)))
                .tint(PlannerStyle.moss).accessibilityHidden(true)
        }
        .foregroundStyle(PlannerStyle.ink)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(PlannerStyle.surface)
    }

    private func checklistSection(_ group: WorkoutChecklist.Group, session: TrainingSession) -> some View {
        Section {
            ForEach(group.rows) { item in
                switch item {
                case .earlier(let set, let ordinal, let date):
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Set \(ordinal) · Completed earlier", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss)
                        Text(actualDescription(set.actual, basis: group.basis)).font(.subheadline)
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("priorSet-\((set.plannedID ?? set.id).uuidString)")
                case .remaining(_, let ordinal):
                    Label("Set \(ordinal) · Remaining in plan", systemImage: "circle.dashed").font(.subheadline)
                case .live(let row, let index):
                    if let live = group.liveExercise, live.id == exercise?.id, row.confirmedAt != nil || row.id == currentRowID {
                        WorkoutSetRow(sessionID: session.id, exercise: live, row: row, index: index, store: store,
                                      isCurrent: row.id == currentRowID)
                            .id(row.id)
                    } else if let live = group.liveExercise {
                        Button {
                            run {
                                if exercise?.id != live.id { try store.select(sessionID: session.id, exerciseID: live.id) }
                                chosenRow = row.id
                            }
                        } label: {
                            HStack {
                                Image(systemName: row.confirmedAt == nil ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(row.confirmedAt == nil ? .secondary : PlannerStyle.moss)
                                Text(setTitle(row, index: index)).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(row.confirmedAt == nil ? "Pending" : actualDescription(row.actual, basis: group.basis))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).id(row.id)
                    }
                }
            }.listRowBackground(PlannerStyle.surface)
        } header: {
            HStack {
                Text(group.prescription.name).font(.headline)
                Spacer()
                Text("\(group.completed)/\(group.rows.count)").font(.caption.monospacedDigit())
            }.textCase(nil).foregroundStyle(PlannerStyle.ink)
        } footer: {
            Text("Target: \(targetDescription(group.prescription))")
        }
    }

    private func actionBar(_ session: TrainingSession) -> some View {
        let columns = typeSize.isAccessibilitySize ? 2 : 4
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 2) {
            Button { panel = .add } label: { tool("Add exercise", "plus") }
                .accessibilityIdentifier("addCustomExercise")
            Menu {
                if let exercise {
                    Button("Add warm-up set") { run { try store.addSet(sessionID: session.id, exerciseID: exercise.id, warmup: true) } }
                    Button("Add working set") { run { try store.addSet(sessionID: session.id, exerciseID: exercise.id, warmup: false) } }
                }
            } label: { tool("Add set", "plus.circle") }
                .disabled(exercise == nil).accessibilityIdentifier("addSet")
            Button { panel = .rest } label: { tool("Rest", "timer") }
                .disabled(exercise == nil).accessibilityIdentifier("workoutRest")
            Button { panel = .swap } label: { tool("Swap", "arrow.triangle.2.circlepath") }
                .disabled(exercise?.sets.contains { $0.confirmedAt == nil } != true)
                .accessibilityLabel("Swap remaining sets").accessibilityIdentifier("swapExercise")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .overlay(alignment: .top) { Rectangle().fill(PlannerStyle.rule).frame(height: 1) }
    }

    private func tool(_ label: String, _ systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.body.weight(.medium))
            Text(label).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(PlannerStyle.moss).frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }

    private func exerciseMenu(session: TrainingSession, exercise: TrainingExercise) -> some View {
        Menu {
            ForEach(session.exercises) { item in
                Button {
                    run { try store.select(sessionID: session.id, exerciseID: item.id) }
                } label: {
                    if item.id == exercise.id { Label(item.prescription.name, systemImage: "checkmark") }
                    else { Text(item.prescription.name) }
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.prescription.name).font(.title2.bold()).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.subheadline.bold())
            }.multilineTextAlignment(.leading)
        }
        .accessibilityLabel("Switch exercise, \(exercise.prescription.name)")
        .accessibilityIdentifier("jumpExercise")
    }

    private func basisPicker(session: TrainingSession, exercise: TrainingExercise) -> some View {
        let options = LoadBasis.allCases.filter { ($0 == .timed) == exercise.prescription.timed }
        return Picker("Recording method", selection: Binding(get: { exercise.basis }, set: { basis in
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
        let cardioEdits = session.isCardio && session.cardioDraft != session.cardio
        let allConfirmed = session.isCardio ? cardioComplete : rows.contains { $0.confirmedAt != nil } && rows.allSatisfy { $0.optional == true || $0.confirmedAt != nil }
        let hasResult = session.cardio != nil || rows.contains { $0.confirmedAt != nil }
        return List {
            TrainingSummaryContent(session: session)
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
            if !hasResult {
                Button("Discard empty workout", role: .destructive) { confirmingDiscard = true }
                    .confirmationDialog("Discard this empty workout?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Discard workout", role: .destructive) {
                            run { try store.cancelEmpty(sessionID: session.id); onClose() }
                        }
                    }
            }
        }
        .navigationTitle("Workout summary")
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
                .disabled(!hasResult || cardioEdits)
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

private enum WorkoutPanel: String, Identifiable {
    case add, swap, rest
    var id: Self { self }
}

func elapsedString(_ interval: TimeInterval) -> String {
    guard interval.isFinite, interval > 0 else { return "0:00" }
    let seconds = Int(exactly: interval.rounded(.down)) ?? Int.max
    let remainder = seconds % 60
    return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
}

private func setTitle(_ row: TrainingSet, index: Int) -> String {
    let ordinal = row.ordinal ?? (index + 1)
    if row.warmup == true { return "Warm-up · Set \(ordinal)" }
    return row.optional == true ? "Extra working set \(ordinal)" : "Set \(ordinal)"
}

private func targetDescription(_ prescription: PlanExercise) -> String {
    let range = prescription.low == prescription.high ? String(prescription.low) : "\(prescription.low)–\(prescription.high)"
    return "\(range) \(prescription.timed ? "sec" : "reps")"
}

private func basisTitle(_ basis: LoadBasis) -> String {
    switch basis {
    case .external: "External load"
    case .barbell: "Barbell total"
    case .dumbbell: "Per dumbbell"
    case .machine: "Machine setting"
    case .bodyweight: "Bodyweight"
    case .added: "Added load"
    case .assisted: "Assistance"
    case .unilateral: "Separate sides"
    case .timed: "Duration"
    }
}

func actualDescription(_ actual: SetActual, basis: LoadBasis) -> String {
    func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }
    if basis == .unilateral {
        let left = [actual.reps.map { "\($0) reps" }, actual.load.map { "\(number($0)) \(actual.unit)" }].compactMap { $0 }.joined(separator: " × ")
        let right = [actual.rightReps.map { "\($0) reps" }, actual.rightLoad.map { "\(number($0)) \(actual.unit)" }].compactMap { $0 }.joined(separator: " × ")
        return "Left \(left) · Right \(right)"
    }
    var components: [String] = []
    if let reps = actual.reps, basis != .timed { components.append("\(reps) reps") }
    if let seconds = actual.seconds, basis == .timed { components.append("\(seconds) sec") }
    if basis != .bodyweight, let load = actual.load {
        components.append("\(number(load)) \(actual.unit) · \(basisTitle(basis).lowercased())")
    }
    return components.joined(separator: " × ")
}

private struct WorkoutSetRow: View {
    let sessionID: UUID
    let exercise: TrainingExercise
    let row: TrainingSet
    let index: Int
    let store: TrainingStore
    let isCurrent: Bool

    @State private var correctionRevision: Int?
    @State private var correction: SetActual?
    @State private var unsaved: SetActual?
    @State private var issue: String?
    @State private var commandID = UUID()
    @FocusState private var focused: ActualField?

    private enum ActualField { case reps, seconds, load, rightReps, rightLoad }
    private var latest: TrainingSet? {
        store.active?.exercises.first { $0.id == exercise.id }?.sets.first { $0.id == row.id }
    }
    private var values: Binding<SetActual> {
        Binding(get: { correction ?? unsaved ?? latest?.actual ?? row.actual }, set: { actual in
            if correction != nil { correction = actual; return }
            guard let latest, latest.confirmedAt == nil, actual != (unsaved ?? latest.actual) else { return }
            do {
                try store.edit(sessionID: sessionID, setID: row.id, actual: actual, revision: latest.revision)
                issue = nil
                unsaved = nil
            } catch {
                unsaved = actual
                issue = error.localizedDescription
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: row.confirmedAt == nil || correction != nil ? 10 : 2) {
            if row.confirmedAt == nil || correction != nil {
                HStack {
                    Text(setTitle(row, index: index)).font(.headline)
                    Spacer()
                    if isCurrent {
                        Label("Current set", systemImage: "scope").font(.caption.weight(.semibold)).foregroundStyle(PlannerStyle.ochre)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Current set, \(setTitle(row, index: index))").accessibilityIdentifier("currentSetLabel")
                    }
                }
            }
            if let issue {
                Label(issue, systemImage: "exclamationmark.circle").font(.footnote)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("setIssue\(index)")
            }
            if row.confirmedAt != nil && correction == nil {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(setTitle(row, index: index), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss)
                            .accessibilityLabel("\(setTitle(row, index: index)), completed")
                        Text(actualDescription(row.actual, basis: exercise.basis)).font(.subheadline)
                    }
                    Spacer(minLength: 0)
                    Button {
                        correctionRevision = row.revision
                        correction = row.actual
                        issue = nil
                    } label: { Image(systemName: "pencil").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Edit result for \(setTitle(row, index: index))")
                    .accessibilityIdentifier("editSet\(index)")
                    Button {
                        do { try store.undo(sessionID: sessionID, setID: row.id, revision: row.revision); issue = nil }
                        catch { issue = error.localizedDescription }
                    } label: { Image(systemName: "arrow.uturn.backward").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Undo \(setTitle(row, index: index))").accessibilityIdentifier("undoSet\(index)")
                }.buttonStyle(.borderless)
            } else {
                if row.confirmedAt == nil, let date = row.previousAt {
                    Text("Previous result · \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                inputs
                HStack {
                    Button {
                        submit()
                    } label: {
                        Label(correction == nil ? "Confirm set" : "Save correction", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(correction == nil ? "confirmSet\(index)" : "saveSet\(index)")
                    if correction != nil {
                        Button("Cancel") { correction = nil; issue = nil; focused = nil }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: row.revision) { _, _ in commandID = UUID() }
        .toolbar {
            if focused != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }.accessibilityIdentifier("dismissSetKeyboard")
                }
            }
        }
    }

    @ViewBuilder private var inputs: some View {
        let left = exercise.basis == .unilateral
        if exercise.basis == .timed {
            input("Actual seconds", value: values.seconds, kind: .seconds, id: "actualSeconds")
        } else {
            input(left ? "Left reps" : "Actual reps", value: values.reps, kind: .reps, id: "actualReps")
        }
        if exercise.basis != .bodyweight {
            let loadTitle = switch exercise.basis {
            case .unilateral: "Left load"
            case .assisted: "Assistance"
            case .added: "Added load"
            case .dumbbell: "Per dumbbell"
            case .barbell: "Total incl. bar"
            case .machine: "Machine setting"
            case .timed: "Load (optional)"
            default: "Load"
            }
            loadInput("\(loadTitle) (\(values.wrappedValue.unit))", value: values.load, kind: .load, id: "actualLoad")
        }
        if left {
            input("Right reps", value: values.rightReps, kind: .rightReps, id: "actualRightReps")
            loadInput("Right load (\(values.wrappedValue.unit))", value: values.rightLoad, kind: .rightLoad, id: "actualRightLoad")
        }
    }

    private func input(_ label: String, value: Binding<Int?>, kind: ActualField, id: String) -> some View {
        HStack {
            Text(label).accessibilityHidden(true)
            Spacer(minLength: 8)
            TextField("Enter", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 104)
                .focused($focused, equals: kind)
                .accessibilityLabel("\(label) for set \(row.ordinal ?? (index + 1))")
                .accessibilityIdentifier("\(id)\(index)")
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { focused = kind })
    }

    private func loadInput(_ label: String, value: Binding<Double?>, kind: ActualField, id: String) -> some View {
        HStack {
            Text(label).accessibilityHidden(true)
            Spacer(minLength: 8)
            TextField("Enter", value: value, format: .number.precision(.fractionLength(0...4)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 104)
                .focused($focused, equals: kind)
                .accessibilityLabel("\(label) for set \(row.ordinal ?? (index + 1))")
                .accessibilityIdentifier("\(id)\(index)")
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { focused = kind })
    }

    private func submit() {
        let actual = values.wrappedValue
        if exercise.basis == .timed {
            guard let seconds = actual.seconds, seconds > 0 else { issue = "Enter the seconds you completed."; focused = .seconds; return }
        } else {
            guard let reps = actual.reps, reps > 0 else { issue = "Enter the reps you completed."; focused = .reps; return }
        }
        if exercise.basis != .bodyweight && exercise.basis != .timed && actual.load == nil {
            issue = exercise.basis == .assisted ? "Enter the assistance used." : "Enter the load you used."
            focused = .load
            return
        }
        if exercise.basis == .unilateral {
            guard let reps = actual.rightReps, reps > 0 else { issue = "Enter right-side reps."; focused = .rightReps; return }
            guard actual.rightLoad != nil else { issue = "Enter the right-side load."; focused = .rightLoad; return }
        }
        guard let latest else { issue = "This set is no longer available."; return }
        guard correction != nil || latest.confirmedAt == nil else { return }
        do {
            if correction != nil {
                try store.edit(sessionID: sessionID, setID: row.id, actual: actual, revision: correctionRevision ?? row.revision)
            } else {
                try store.confirm(sessionID: sessionID, setID: row.id, actual: actual, revision: latest.revision, commandID: commandID)
            }
            correction = nil
            unsaved = nil
            issue = nil
            focused = nil
        } catch { issue = error.localizedDescription }
    }
}

private struct CardioLog: View {
    let session: TrainingSession
    let store: TrainingStore
    @State private var pending: CardioResult?
    @State private var error: String?
    @FocusState private var focusSeconds: Bool
    @State private var activityName: String?
    @State private var commandID = UUID()

    private var values: Binding<CardioResult> {
        Binding(get: { pending ?? store.active?.cardioDraft ?? session.cardio ?? CardioResult(seconds: 0) }, set: { result in
            do {
                try store.updateCardio(sessionID: session.id, result: result)
                pending = nil
                error = nil
            } catch {
                pending = result
                self.error = error.localizedDescription
            }
        })
    }

    var body: some View {
        Section("Cardio activity") {
            LabeledContent("Activity") {
                TextField("Activity name", text: Binding(
                    get: { activityName ?? session.name },
                    set: { name in
                        activityName = name
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        do { try store.renameCardio(sessionID: session.id, name: name); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                )).multilineTextAlignment(.trailing).submitLabel(.done).accessibilityIdentifier("cardioName")
            }
            LabeledContent("Actual seconds") {
                TextField("Seconds", value: Binding<Int?>(get: {
                    let draft = pending ?? store.active?.cardioDraft ?? session.cardio
                    return draft?.seconds
                }, set: { newValue in
                    var draft = values.wrappedValue
                    draft.seconds = newValue ?? 0
                    values.wrappedValue = draft
                }), format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .focused($focusSeconds).accessibilityIdentifier("cardioSeconds")
            }
            LabeledContent("Distance") {
                TextField("Optional", value: values.distance, format: .number)
                    .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
            }
            Picker("Distance unit", selection: values.unit) {
                Text("Kilometers").tag("km")
                Text("Miles").tag("mi")
            }
            TextField("Activity notes", text: values.notes, axis: .vertical)
            if let saved = session.cardio {
                Label("Activity saved · \(elapsedString(TimeInterval(saved.seconds)))", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("cardioStatus")
            }
            Button(session.cardio == nil ? "Confirm activity" : "Save activity changes") {
                let result = values.wrappedValue
                let name = (activityName ?? session.name).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { error = "Enter the activity name."; return }
                guard result.seconds > 0 else { error = "Enter the duration you completed."; focusSeconds = true; return }
                do {
                    if session.name != name { try store.renameCardio(sessionID: session.id, name: name) }
                    try store.recordCardio(sessionID: session.id, result: result, revision: session.cardioRevision, commandID: commandID)
                    pending = nil
                    error = nil
                    focusSeconds = false
                } catch { self.error = error.localizedDescription }
            }.accessibilityIdentifier("confirmCardio")
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote) }
        }
        .onChange(of: session.cardioRevision) { _, _ in commandID = UUID() }
    }
}

/// Shared with dated workout history; the summary only displays confirmed values.
struct TrainingSummaryContent: View {
    let session: TrainingSession

    var body: some View {
        Section(session.name) {
            LabeledContent("Performed", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Workout duration", value: elapsedString((session.finishedAt ?? .now).timeIntervalSince(session.startedAt)))
            if session.isCardio {
                if let cardio = session.cardio {
                    LabeledContent("Activity duration", value: elapsedString(TimeInterval(cardio.seconds)))
                    if let distance = cardio.distance {
                        LabeledContent("Distance", value: "\(distance.formatted()) \(cardio.unit)")
                    }
                    if !cardio.notes.isEmpty { Text(cardio.notes) }
                } else {
                    Text("No activity confirmed.").foregroundStyle(.secondary)
                }
            } else {
                let sets = session.exercises.flatMap(\.sets)
                let working = sets.filter { $0.optional != true }
                let confirmed = working.filter { $0.confirmedAt != nil }.count
                LabeledContent("Confirmed working sets", value: "\(confirmed) of \(working.count)")
                    .accessibilityIdentifier("sessionTally")
                let extra = sets.filter { $0.optional == true && $0.confirmedAt != nil }
                if extra.contains(where: { $0.warmup == true }) {
                    LabeledContent("Warm-ups logged", value: "\(extra.filter { $0.warmup == true }.count)")
                }
                if extra.contains(where: { $0.warmup != true }) {
                    LabeledContent("Extra working sets logged", value: "\(extra.filter { $0.warmup != true }.count)")
                }
            }
            if !session.notes.isEmpty { Text(session.notes) }
        }
        ForEach(session.exercises) { exercise in
            let results = exercise.sets.enumerated().filter { $0.element.confirmedAt != nil }
            if !results.isEmpty || exercise.replacedPrescription != nil {
                Section(exercise.prescription.name) {
                    if let original = exercise.replacedPrescription {
                        Text("In place of \(original.name)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(results), id: \.element.id) { index, set in
                        LabeledContent(setTitle(set, index: index), value: actualDescription(set.actual, basis: exercise.basis))
                    }
                }
            }
        }
    }
}

private struct WorkoutRestEditor: View {
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

extension PlanExercise {
    mutating func selectWorkoutLoadUnit(_ newUnit: String) {
        guard newUnit != loadUnit, ["kg", "lb"].contains(newUnit) else { return }
        if let startingLoad {
            self.startingLoad = newUnit == "kg" ? startingLoad * 0.45359237 : startingLoad / 0.45359237
        }
        loadUnit = newUnit
    }

    mutating func changeWorkoutBasis(from previous: LoadBasis, to next: LoadBasis) {
        guard previous != next else { return }
        startingLoad = nil
        convention = basisTitle(next)
        timed = next == .timed
    }
}

private struct WorkoutExercisePicker: View {
    let planner: PlanningStore?
    @State private var browsing = false
    let known: [PlanExercise]
    let replacing: TrainingExercise?
    let save: (PlanExercise, LoadBasis) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected = PlanExercise()
    @State private var basis = LoadBasis.external
    @State private var issue: String?
    @State private var pickedExisting = false
    @State private var initialized = false
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            if let planner {
                Button("Browse exercises") { browsing = true }.accessibilityIdentifier("browseCatalog")
                    .fullScreenCover(isPresented: $browsing) {
                        NavigationStack {
                        CatalogPicker(planner: planner, replacing: replacing?.prescription) { choice in
                            selected = choice
                            basis = LoadBasis(choice)
                            pickedExisting = true
                            browsing = false
                        }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close library") { browsing = false } } }
                        }
                    }
            }
            if !known.isEmpty {
                Section {
                    Menu("Choose a saved exercise") {
                        ForEach(known) { prescription in
                            Button(prescription.name) {
                                selected = prescription
                                basis = LoadBasis(prescription)
                                pickedExisting = true
                            }
                        }
                        if pickedExisting {
                            Button("New custom exercise") { makeCustom() }
                        }
                    }
                }
            }
            Section("Exercise") {
                if pickedExisting {
                    Text(selected.name)
                } else {
                    TextField("Exercise name", text: $selected.name)
                        .focused($focused).accessibilityIdentifier("customName")
                }
                Picker("Recording method", selection: Binding(get: { basis }, set: { newBasis in
                    selected.changeWorkoutBasis(from: basis, to: newBasis)
                    basis = newBasis
                })) {
                    ForEach(LoadBasis.allCases, id: \.self) { Text(basisTitle($0)).tag($0) }
                }
                if basis != .bodyweight {
                    Picker("Load unit", selection: Binding(get: { selected.loadUnit }, set: { unit in
                        selected.selectWorkoutLoadUnit(unit)
                    })) {
                        Text("Pounds").tag("lb")
                        Text("Kilograms").tag("kg")
                    }
                }
            }
            Section("Prescription") {
                if let replacing {
                    let remaining = replacing.sets.filter { $0.confirmedAt == nil }.count
                    LabeledContent("Remaining sets", value: "\(remaining)")
                } else {
                    Stepper("\(selected.sets) working sets", value: $selected.sets, in: 1...99)
                }
                numberInput(basis == .timed ? "Minimum seconds" : "Minimum reps", value: $selected.low)
                numberInput(basis == .timed ? "Maximum seconds" : "Maximum reps", value: $selected.high)
            }
            Section {
                if let issue { Label(issue, systemImage: "exclamationmark.circle").font(.footnote) }
                Button(replacing == nil ? "Add to workout" : "Use for remaining sets") {
                    commit()
                }.accessibilityIdentifier("customSave")
            }
        }
        .navigationTitle(replacing == nil ? "Add exercise" : "Swap exercise")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            if !initialized { makeCustom(); initialized = true }
        }
    }

    private func numberInput(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
        }
    }

    private func makeCustom() {
        var fresh = PlanExercise()
        if let replacing {
            fresh.low = replacing.prescription.low
            fresh.high = replacing.prescription.high
            fresh.loadUnit = replacing.prescription.loadUnit
        }
        selected = fresh
        basis = replacing?.basis ?? .external
        pickedExisting = false
    }

    private func commit() {
        guard !selected.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            issue = "Enter an exercise name."
            focused = true
            return
        }
        guard selected.low > 0 && selected.high >= selected.low else {
            issue = "Enter a positive target range."
            return
        }
        var prescription = selected
        prescription.timed = basis == .timed
        if !pickedExisting || LoadBasis(selected) != basis { prescription.convention = basisTitle(basis) }
        if let replacing { prescription.sets = replacing.sets.filter { $0.confirmedAt == nil }.count }
        do { try save(prescription, basis); dismiss() } catch { issue = error.localizedDescription }
    }
}
