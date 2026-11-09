import SwiftUI

struct WorkoutSetRow<Options: View>: View {
    let sessionID: UUID
    let exercise: TrainingExercise
    let row: TrainingSet
    let index: Int
    let store: TrainingStore
    let isCurrent: Bool
    let isExpanded: Bool
    let closingCorrection: Bool?
    let target: String
    let onToggle: () -> Void
    let onCloseCorrection: () -> Void
    let onEditorHeightChange: (CGFloat) -> Void
    @ViewBuilder let options: () -> Options

    @State private var correctionRevision: Int?
    @State private var correction: SetActual?
    @State private var unsaved: SetActual?
    @State private var issue: String?
    @State private var commandID = UUID()
    @State private var editorRevealed = true
    @FocusState private var focused: ActualField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    private enum ActualField { case reps, seconds, load, rightReps, rightLoad }
    private var latest: TrainingSet? {
        store.openSessions.first { $0.id == sessionID }?.exercises.first { $0.id == exercise.id }?.sets.first { $0.id == row.id }
    }
    private var suggestion: SetActual? {
        latest.flatMap { exercise.suggestedActual(for: $0) }
    }

    private var isLogged: Bool { row.confirmedAt != nil }
    private var title: String { setTitle(row, index: index) }
    private var isEditorMounted: Bool { isExpanded || closingCorrection != nil }
    private var editorIsCorrection: Bool { closingCorrection ?? isLogged }

    private var displayedActual: SetActual {
        if editorIsCorrection { return correction ?? row.actual }
        return unsaved ?? suggestion ?? latest?.actual ?? row.actual
    }

    private var values: Binding<SetActual> {
        Binding(get: { displayedActual }, set: { actual in
            if editorIsCorrection {
                correction = actual
                return
            }
            guard let latest, latest.confirmedAt == nil, actual != displayedActual else { return }
            do {
                try store.edit(sessionID: sessionID, setID: row.id, actual: actual, revision: latest.revision,
                               markUnchangedDraft: suggestion != nil && actual == latest.actual)
                issue = nil
                unsaved = nil
            } catch {
                unsaved = actual
                issue = error.localizedDescription
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowHeading
            if isEditorMounted {
                SetEditorHeight(fraction: isExpanded ? 1 : 0) {
                    editor
                        .padding(.top, 4)
                        .mask {
                            Rectangle().scaleEffect(x: 1, y: editorRevealed ? 1 : 0, anchor: .top)
                        }
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            if isExpanded { onEditorHeightChange(height) }
                        }
                }
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
                .task(id: isExpanded) {
                    guard isExpanded, !editorRevealed else { return }
                    // Commit the new layout before revealing only the panel.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { editorRevealed = true }
                }
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                focused = nil
                editorRevealed = true
            }
        }
        .onChange(of: isEditorMounted) { _, mounted in
            if !mounted {
                correction = nil
                correctionRevision = nil
                if unsaved == nil { issue = nil }
            }
        }
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

    private var rowHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                setButton.fixedSize()
                Spacer(minLength: 4)
                rowStatus.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                setButton
                rowStatus.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var setButton: some View {
        Button {
            if !isExpanded { editorRevealed = reduceMotion }
            if isLogged, !isExpanded {
                correctionRevision = row.revision
                correction = row.actual
                issue = nil
            }
            onToggle()
        } label: {
            Text(title).font(.subheadline.weight(isExpanded ? .bold : .medium))
                .foregroundStyle(isExpanded ? PlannerStyle.ink : PlannerStyle.moss)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isLogged ? "editSet\(index)" : "openSet\(index)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Closes the set editor" : "Opens the set editor")
    }

    @ViewBuilder private var rowStatus: some View {
        if isLogged {
            Text(actualDescription(row.actual, basis: exercise.basis)).font(.subheadline)
                .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        } else if isCurrent {
            Text("Current").font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss)
                .accessibilityLabel("Current set, \(title)")
                .accessibilityIdentifier("currentSetLabel")
        } else {
            Text("Pending").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !editorIsCorrection {
                HStack(spacing: 8) {
                    Text("Target \(target)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    options()
                }
            }
            issueMessage
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                      count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                inputs
            }
            if !editorIsCorrection, unsaved == nil {
                if suggestion != nil {
                    Text("Suggested from the last matching set")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let date = row.previousAt {
                    Text("Previous result · \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                } else if row.revision == 0 {
                    Text("Enter what you completed")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(action: submit) {
                Label(editorIsCorrection ? "Save correction" : "Confirm set", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 8)
                    .foregroundStyle(colorScheme == .dark ? PlannerStyle.forest : Color.white)
                    .background(PlannerStyle.moss, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(editorIsCorrection ? "saveSet\(index)" : "confirmSet\(index)")
            if editorIsCorrection {
                HStack {
                    Button("Cancel", action: onCloseCorrection)
                        .frame(minHeight: 44)
                    Spacer(minLength: 8)
                    Button(role: .destructive, action: undo) {
                        Label("Undo set", systemImage: "arrow.uturn.backward")
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Undo \(title)")
                    .accessibilityIdentifier("undoSet\(index)")
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
        .background(PlannerStyle.moss.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 4)
    }

    @ViewBuilder private var issueMessage: some View {
        if let issue {
            Label(issue, systemImage: "exclamationmark.circle").font(.footnote)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("setIssue\(index)")
        }
    }

    @ViewBuilder private var inputs: some View {
        let left = exercise.basis == .unilateral
        if exercise.basis == .timed {
            input("Seconds", value: values.seconds, kind: .seconds, id: "actualSeconds")
        } else {
            input(left ? "Left reps" : "Reps", value: values.reps, kind: .reps, id: "actualReps")
        }
        if exercise.basis != .bodyweight {
            let loadTitle = switch exercise.basis {
            case .unilateral: "Left weight"
            case .assisted: "Assistance"
            case .added: "Added weight"
            case .dumbbell: "Per dumbbell"
            case .barbell: "Total incl. bar"
            case .machine: "Machine setting"
            case .timed: "Weight (optional)"
            default: "Weight"
            }
            loadInput("\(loadTitle) (\(values.wrappedValue.unit))", value: values.load, kind: .load, id: "actualLoad")
        }
        if left {
            input("Right reps", value: values.rightReps, kind: .rightReps, id: "actualRightReps")
            loadInput("Right weight (\(values.wrappedValue.unit))", value: values.rightLoad, kind: .rightLoad, id: "actualRightLoad")
        }
    }

    private func input(_ label: String, value: Binding<Int?>, kind: ActualField, id: String) -> some View {
        let current = value.wrappedValue ?? 0
        return adjustableField(label, id: id, canDecrease: current > 1, canIncrease: current < Int.max) {
            value.wrappedValue = max(1, current - 1)
        } increment: {
            if current < Int.max { value.wrappedValue = max(1, current + 1) }
        } field: {
            TextField("–", value: value, format: .number)
                .keyboardType(.numberPad)
                .focused($focused, equals: kind)
        }
    }

    private func loadInput(_ label: String, value: Binding<Double?>, kind: ActualField, id: String) -> some View {
        let current = value.wrappedValue ?? 0
        let step = values.wrappedValue.unit == "kg" ? 2.5 : 5.0
        return adjustableField(label, id: id, canDecrease: current > 0, canIncrease: (current + step).isFinite) {
            value.wrappedValue = max(0, current - step)
        } increment: {
            value.wrappedValue = max(0, current + step)
        } field: {
            TextField("–", value: value, format: .number.precision(.fractionLength(0...4)))
                .keyboardType(.decimalPad)
                .focused($focused, equals: kind)
        }
    }

    private func adjustableField<Field: View>(_ label: String, id: String, canDecrease: Bool, canIncrease: Bool,
                                               decrement: @escaping () -> Void, increment: @escaping () -> Void,
                                               @ViewBuilder field: () -> Field) -> some View {
        let suffix = id.prefix(1).uppercased() + String(id.dropFirst()) + String(index)
        let ordinal = row.ordinal ?? (index + 1)
        return VStack(spacing: 3) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
            field()
                .font(.title2.weight(.semibold)).monospacedDigit()
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("\(label) for set \(ordinal)")
                .accessibilityIdentifier("\(id)\(index)")
            HStack(spacing: 4) {
                Button {
                    focused = nil
                    decrement()
                } label: {
                    stepLabel("minus")
                }
                .disabled(!canDecrease)
                .accessibilityLabel("Decrease \(label) for set \(ordinal)")
                .accessibilityIdentifier("decrement" + suffix)
                Button {
                    focused = nil
                    increment()
                } label: {
                    stepLabel("plus")
                }
                .disabled(!canIncrease)
                .accessibilityLabel("Increase \(label) for set \(ordinal)")
                .accessibilityIdentifier("increment" + suffix)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func stepLabel(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(PlannerStyle.moss)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(PlannerStyle.moss.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func submit() {
        let actual = values.wrappedValue
        if exercise.basis == .timed {
            guard let seconds = actual.seconds, seconds > 0 else { issue = "Enter the seconds you completed."; focused = .seconds; return }
        } else {
            guard let reps = actual.reps, reps > 0 else { issue = "Enter the reps you completed."; focused = .reps; return }
        }
        if exercise.basis != .bodyweight && exercise.basis != .timed && actual.load == nil {
            issue = exercise.basis == .assisted ? "Enter the assistance used." : "Enter the weight you used."
            focused = .load
            return
        }
        if exercise.basis == .unilateral {
            guard let reps = actual.rightReps, reps > 0 else { issue = "Enter right-side reps."; focused = .rightReps; return }
            guard actual.rightLoad != nil else { issue = "Enter the right-side weight."; focused = .rightLoad; return }
        }
        guard let latest else { issue = "This set is no longer available."; return }
        guard isLogged == (latest.confirmedAt != nil) else { return }
        do {
            if isLogged {
                try store.edit(sessionID: sessionID, setID: row.id, actual: actual, revision: correctionRevision ?? row.revision)
                onCloseCorrection()
            } else {
                try store.confirm(sessionID: sessionID, setID: row.id, actual: actual, revision: latest.revision, commandID: commandID)
            }
            correction = nil
            unsaved = nil
            issue = nil
            focused = nil
        } catch { issue = error.localizedDescription }
    }

    private func undo() {
        do {
            try store.undo(sessionID: sessionID, setID: row.id, revision: row.revision)
            onCloseCorrection()
        } catch { issue = error.localizedDescription }
    }
}

private struct SetEditorHeight: Layout {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let editor = subviews.first else { return .zero }
        let fullSize = editor.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: fullSize.width, height: fullSize.height * min(1, max(0, fraction)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
