import SwiftUI

private struct EditorPaper: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(PlannerStyle.paper)
            .scrollDismissesKeyboard(.interactively)
    }
}

struct RoutineEditor: View {
    @Binding var plan: WeekPlan
    let needsDiscardConfirmation: () -> Bool
    let onReview: () -> Void
    let onDiscard: () -> Void

    @State private var showingVariants = false
    @State private var attemptedReview = false
    @State private var confirmingDiscard = false
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var discardPromptFocused: Bool

    private var unresolved: Int {
        plan.days.flatMap(\.exercises).filter { !$0.choices.isEmpty && $0.name.isEmpty }.count
    }

    var body: some View {
        List {
            Section("Routine name") {
                TextField("Name your routine", text: $plan.name)
                    .font(.title3.weight(.semibold))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("routineName")
            }
            if plan.days.contains(where: { $0.exercises.contains { !$0.choices.isEmpty } }) {
                Section {
                    Button {
                        showingVariants = true
                    } label: {
                        HStack {
                            Label("Choose variants", systemImage: "arrow.triangle.branch")
                            Spacer()
                            if unresolved > 0 {
                                Text("\(unresolved) left")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption.bold()).accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("chooseVariants")
                    .accessibilityValue(String(unresolved))
                }
            }
            Section("Weekly schedule") {
                ForEach(plan.days.indices, id: \.self) { index in
                    let day = plan.days[index]
                    NavigationLink {
                        DayEditor(plan: $plan, index: index)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(PlannerStyle.weekdays[index])
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(day.name.isEmpty ? (day.isWorkout ? "Unnamed workout" : "Rest day") : day.name)
                                .font(.body.weight(day.name.isEmpty ? .regular : .semibold))
                                .foregroundStyle(day.name.isEmpty ? .secondary : .primary)
                        }
                        .padding(.vertical, 3)
                    }
                    .accessibilityIdentifier("day\(index)")
                }
            }

            Section("Routine preferences") {
                RestSelector(seconds: $plan.restSeconds)
                TextField("Training notes (optional)", text: $plan.notes, axis: .vertical)
                    .lineLimit(2...8)
            }
        }
        .modifier(EditorPaper())
        .navigationTitle("Edit your week")
        .safeAreaInset(edge: .bottom) {
            Group {
                if confirmingDiscard {
                    discardControls
                } else {
                    reviewControls
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    nameFocused = false
                    if needsDiscardConfirmation() {
                        confirmingDiscard = true
                    } else {
                        onDiscard()
                    }
                }
            }
        }
        .sheet(isPresented: $showingVariants) {
            NavigationStack { VariantChoices(plan: $plan) }
        }
    }

    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attemptedReview, let issue = plan.validationMessage {
                Label(issue, systemImage: "info.circle")
                    .font(.subheadline).accessibilityIdentifier("routineGuidance")
                if unresolved > 0 {
                    Button("Choose remaining variants") { showingVariants = true }
                        .accessibilityIdentifier("resolveVariants")
                }
            }
            Button {
                nameFocused = false
                attemptedReview = true
                if plan.validationMessage == nil { onReview() }
            } label: {
                Text("Review week").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("reviewWeek")
        }
    }

    private var discardControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Discard this draft?")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($discardPromptFocused)
                .onAppear { discardPromptFocused = true }
            HStack(spacing: 12) {
                Button("Keep editing") { confirmingDiscard = false }
                Spacer(minLength: 0)
                Button("Discard draft", role: .destructive, action: onDiscard)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

private struct VariantChoices: View {
    @Binding var plan: WeekPlan
    @Environment(\.dismiss) private var dismiss

    @State private var library: [CatalogEntry] = []
    private struct Match {
        var entryKey: String { "\(day)-\(row)" }
        let day: Int
        let row: Int
        let entry: CatalogEntry
    }
    private var matches: [Match] {
        plan.days.enumerated().flatMap { day, workout in
            workout.exercises.enumerated().compactMap { row, exercise in
                guard exercise.name.isEmpty else { return nil }
                for choice in exercise.choices {
                    let candidates = library.filter { $0.name.localizedCaseInsensitiveCompare(choice) == .orderedSame }
                    if candidates.count == 1, let entry = candidates.first, entry.prescription.timed == exercise.timed {
                        return Match(day: day, row: row, entry: entry)
                    }
                }
                return nil
            }
        }
    }

    var body: some View {
        List {
            if !matches.isEmpty {
                NavigationLink {
                    List {
                        ForEach(matches, id: \.entryKey) { match in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(PlannerStyle.weekdays[match.day]).font(.caption.bold()).foregroundStyle(PlannerStyle.moss)
                                Text(match.entry.name).font(.headline)
                            }
                        }
                        Button("Use these choices") {
                            var edited = plan
                            for match in matches {
                                var row = edited.days[match.day].exercises[match.row]
                                selectVariant(match.entry.name, for: &row)
                                row.variantID = match.entry.id
                                row.convention = match.entry.convention
                                edited.days[match.day].exercises[match.row] = row
                            }
                            plan = edited
                            dismiss()
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("useCatalogMatches")
                    }.navigationTitle("Suggested choices")
                } label: { Label("Review library matches (\(matches.count))", systemImage: "books.vertical") }
                    .accessibilityIdentifier("reviewCatalogMatches")
            }

            ForEach(plan.days.indices, id: \.self) { d in
                let day = plan.days[d]
                if day.exercises.contains(where: { !$0.choices.isEmpty }) {
                    Section(PlannerStyle.weekdays[d]) {
                        ForEach(day.exercises.indices, id: \.self) { e in
                            let exercise = day.exercises[e]
                            if !exercise.choices.isEmpty {
                                Menu {
                                    ForEach(exercise.choices.indices, id: \.self) { index in
                                        let choice = exercise.choices[index]
                                        Button(choice) { selectVariant(choice, for: &plan.days[d].exercises[e]) }
                                            .accessibilityIdentifier("variantOption\(index)")
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(exercise.choices.joined(separator: " / "))
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Label(exercise.name.isEmpty ? "Choose exercise" : exercise.name,
                                              systemImage: exercise.name.isEmpty ? "chevron.up.chevron.down" : "checkmark.circle")
                                    }
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .accessibilityIdentifier("variant\(d)-\(e)")
                                .accessibilityValue(exercise.name.isEmpty ? "Unresolved" : exercise.name)
                            }
                        }
                    }
                }
            }
        }
        .modifier(EditorPaper())
        .task { library = (try? ExerciseCatalog.bundled().entries) ?? [] }
        .navigationTitle("Choose variants")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

func selectVariant(_ choice: String, for exercise: inout PlanExercise) {
    guard choice != exercise.name else { return }
    exercise.startingLoad = nil
    exercise.variantID = nil
    if inferredConvention(for: exercise.name) == exercise.convention || exercise.convention.isEmpty {
        exercise.convention = inferredConvention(for: choice)
    }
    exercise.name = choice
}

private func inferredConvention(for choice: String) -> String {
    // When switching equipment, recheck how the working load is expressed.
    // The alternatives themselves belong to the starter, not to this editor.
    if choice.localizedCaseInsensitiveContains("barbell") {
        return "Total barbell weight"
    } else if choice.localizedCaseInsensitiveContains("dumbbell") {
        return "Per dumbbell"
    } else if choice.localizedCaseInsensitiveContains("assisted") {
        return "Assistance"
    } else if choice.localizedCaseInsensitiveContains("machine") {
        return "Machine setting"
    }
    return ""
}

private struct RestSelector: View {
    @Binding var seconds: Int?
    @State private var custom = false
    private let presets = [60, 90, 120, 180]

    var body: some View {
        Picker("Rest timer", selection: Binding(
            get: { custom || (seconds.map { !presets.contains($0) } ?? false) ? -1 : seconds ?? 0 },
            set: { value in
                custom = value == -1
                if custom { seconds = seconds ?? 45 } else { seconds = value == 0 ? nil : value }
            }
        )) {
            Text("Off").tag(0)
            ForEach(presets, id: \.self) { Text("\($0) sec").tag($0) }
            Text("Custom").tag(-1)
        }
        if custom || (seconds.map { !presets.contains($0) } ?? false) {
            LabeledContent("Rest in seconds") {
                TextField("Seconds", value: $seconds, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Custom rest in seconds")
            }
        }
    }
}

private struct DayEditor: View {
    @Binding var plan: WeekPlan
    let index: Int
    @State private var selected: PlanExercise.ID?
    @State private var moving = false
    @State private var clearing = false
    @Environment(\.dismiss) private var dismiss

    private var day: PlanDay { plan.days[index] }

    var body: some View {
        List {
            Section("Workout") {
                TextField("Workout name", text: $plan.days[index].name)
                    .font(.title3.weight(.semibold))
                    .submitLabel(.done)
                    .accessibilityIdentifier("workoutName")
            }
            if day.exercises.isEmpty {
                Section("Workout type") {
                    Picker("Workout type", selection: Binding(
                        get: { day.cardioGoalSeconds != nil },
                        set: { plan.days[index].cardioGoalSeconds = $0 ? 1200 : nil }
                    )) {
                        Text("Strength").tag(false)
                        Text("Cardio").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if day.cardioGoalSeconds != nil {
                        Stepper("Duration · \((day.cardioGoalSeconds ?? 1200) / 60) min", value: Binding(
                            get: { (day.cardioGoalSeconds ?? 1200) / 60 },
                            set: { plan.days[index].cardioGoalSeconds = $0 * 60 }
                        ), in: 1...1440)
                    }
                }
            }
            if day.cardioGoalSeconds == nil {
            Section("Exercises") {
                ForEach(day.exercises) { exercise in
                    Button {
                        selected = exercise.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name.isEmpty ? (exercise.choices.isEmpty ? "Unnamed exercise" : "Choose exercise") : exercise.name)
                                .font(.body.weight(.medium))
                            Text(prescription(exercise)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onMove { plan.days[index].exercises.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { plan.days[index].exercises.remove(atOffsets: $0) }
                Button {
                    let exercise = PlanExercise()
                    plan.days[index].exercises.append(exercise)
                    selected = exercise.id
                } label: { Label("Add exercise", systemImage: "plus") }
                    .accessibilityIdentifier("addExercise")
            }
            }
            if !day.name.isEmpty || day.isWorkout {
                Section {
                    Button("Move to another weekday") { moving = true }
                    Button("Make rest day", role: .destructive) { clearing = true }
                }
            }
        }
        .modifier(EditorPaper())
        .navigationTitle(PlannerStyle.weekdays[index])
        .toolbar { if !day.exercises.isEmpty { EditButton() } }
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected, let e = day.exercises.firstIndex(where: { $0.id == selected }) {
                NavigationStack { ExerciseEditor(exercise: $plan.days[index].exercises[e]) }
            }
        }
        .confirmationDialog("Move workout", isPresented: $moving, titleVisibility: .visible) {
            ForEach(plan.days.indices.filter { $0 != index }, id: \.self) { target in
                let other = plan.days[target]
                Button(other.name.isEmpty && other.exercises.isEmpty ? "Move to \(PlannerStyle.weekdays[target])" : "Swap with \(PlannerStyle.weekdays[target])") {
                    plan.days.swapAt(index, target)
                    dismiss()
                }
            }
        }
        .confirmationDialog("Remove this workout from \(PlannerStyle.weekdays[index])?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Make rest day", role: .destructive) { plan.days[index] = PlanDay(); dismiss() }
        } message: { Text("This clears its exercises from the draft.") }
    }
}

private struct ExerciseEditor: View {
    @Environment(PlanningStore.self) private var planner
    @State private var browseCatalog = false
    @Binding var exercise: PlanExercise
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section("Exercise") {
                Button { browseCatalog = true } label: { Label("Choose from exercise library", systemImage: "books.vertical") }
                    .fullScreenCover(isPresented: $browseCatalog) {
                        NavigationStack {
                            CatalogPicker(planner: planner) { choice in
                                var updated = exercise
                                if exercise.variantID != choice.variantID || exercise.convention != choice.convention {
                                    updated.startingLoad = nil
                                }
                                if updated.timed != choice.timed {
                                    updated.low = choice.low
                                    updated.high = choice.high
                                }
                                updated.name = choice.name
                                updated.variantID = choice.variantID ?? choice.id
                                updated.convention = choice.convention
                                updated.timed = choice.timed
                                exercise = updated
                                browseCatalog = false
                            }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { browseCatalog = false } } }
                        }
                    }

                if !exercise.choices.isEmpty {
                    ForEach(exercise.choices, id: \.self) { choice in
                        Button {
                            selectVariant(choice, for: &exercise)
                        } label: {
                            HStack {
                                Text(choice)
                                Spacer()
                                if exercise.name == choice { Image(systemName: "checkmark") }
                            }
                        }
                        .accessibilityAddTraits(exercise.name == choice ? .isSelected : [])
                    }
                }
                TextField(exercise.choices.isEmpty ? "Exercise name" : "Or enter a custom exercise", text: Binding(get: { exercise.name }, set: { name in
                    var updated = exercise
                    selectVariant(name, for: &updated)
                    exercise = updated
                }))
                    .focused($focused)
                    .accessibilityIdentifier("exerciseName")
            }
            Section("Prescription") {
                Stepper("\(exercise.sets) \(exercise.sets == 1 ? "working set" : "working sets")", value: $exercise.sets, in: 1...99)
                Picker("Target", selection: $exercise.timed) {
                    Text("Reps").tag(false)
                    Text("Duration").tag(true)
                }
                .pickerStyle(.segmented)
                targetField(exercise.timed ? "Minimum seconds" : "Minimum reps", number: $exercise.low)
                targetField(exercise.timed ? "Maximum seconds" : "Maximum reps", number: $exercise.high)
            }
            Section("Load and notes") {
                TextField("Load convention", text: $exercise.convention, axis: .vertical)
                LabeledContent("Starting load") {
                    TextField("Optional", value: $exercise.startingLoad, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Starting load")
                }
                Picker("Load unit", selection: Binding(
                    get: { exercise.loadUnit },
                    set: { unit in
                        guard unit != exercise.loadUnit else { return }
                        var updated = exercise
                        if let load = updated.startingLoad {
                            updated.startingLoad = unit == "kg" ? load * 0.45359237 : load / 0.45359237
                        }
                        updated.loadUnit = unit
                        exercise = updated
                    }
                )) {
                    Text("Pounds").tag("lb")
                    Text("Kilograms").tag("kg")
                }
                TextField("Exercise notes (optional)", text: $exercise.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .modifier(EditorPaper())
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { focused = exercise.choices.isEmpty && exercise.name.isEmpty }
    }

    private func targetField(_ label: String, number: Binding<Int>) -> some View {
        LabeledContent(label) {
            TextField(label, value: number, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
        }
    }
}
