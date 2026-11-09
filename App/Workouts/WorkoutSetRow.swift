import SwiftUI
import UIKit

struct WorkoutSetRow: View {
    let sessionID: UUID
    let exercise: TrainingExercise
    let row: TrainingSet
    let index: Int
    let store: TrainingStore
    let isCurrent: Bool
    let isExpanded: Bool
    let closingCorrection: Bool?
    let isRemovalRevealed: Bool
    let isFolding: Bool
    let target: String
    let onToggle: () -> Void
    let onCloseCorrection: () -> Void
    let onRevealRemoval: (Bool) -> Void
    let onRemove: () -> Void
    let onFoldComplete: () -> Void
    let onEditorHeightChange: (CGFloat) -> Void

    @State private var correctionRevision: Int?
    @State private var correction: SetActual?
    @State private var unsaved: SetActual?
    @State private var issue: String?
    @State private var commandID = UUID()
    @State private var editorRevealed = true
    @State private var removalDrag: RemovalDrag?
    @State private var removalSettle: RemovalSettle?
    @State private var foldStartedAt: Date?
    @FocusState private var focused: ActualField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .subheadline) private var scaledRemoveWidth: CGFloat = 86
    @ScaledMetric(relativeTo: .subheadline) private var scaledStatusWidth: CGFloat = 122
    @ScaledMetric(relativeTo: .subheadline) private var statusPointSize: CGFloat = 15

    private enum ActualField { case reps, seconds, load, rightReps, rightLoad }
    private var latest: TrainingSet? {
        store.openSessions.first { $0.id == sessionID }?.exercises.first { $0.id == exercise.id }?.sets.first { $0.id == row.id }
    }
    private var suggestion: SetActual? {
        (isFolding ? row : latest).flatMap { exercise.suggestedActual(for: $0) }
    }

    private var isLogged: Bool { row.confirmedAt != nil }
    private var title: String { setTitle(row, index: index) }
    private var isEditorMounted: Bool { isExpanded || closingCorrection != nil }
    private var editorIsCorrection: Bool { closingCorrection ?? isLogged }
    private var isRemovable: Bool { !isLogged && row.optional == true && row.plannedID == nil }

    private var displayedActual: SetActual {
        if editorIsCorrection { return correction ?? row.actual }
        return unsaved ?? suggestion ?? latest?.actual ?? row.actual
    }

    private var values: Binding<SetActual> {
        Binding(get: { displayedActual }, set: { actual in
            guard !isFolding else { return }
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
        Group {
            if isFolding { foldingRow } else { rowContents }
        }
        .onChange(of: isFolding) { _, folding in
            if folding { focused = nil }
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
        .onChange(of: isRemovable) { _, removable in
            if !removable {
                removalDrag = nil
                removalSettle = nil
                if isRemovalRevealed { onRevealRemoval(false) }
            }
        }
        .onChange(of: isRemovalRevealed) { _, revealed in
            if !revealed, removalSettle?.destination == 1 { removalSettle = nil }
        }
        .toolbar {
            if focused != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }.accessibilityIdentifier("dismissSetKeyboard")
                }
            }
        }
    }

    private var foldingRow: some View {
        let content = rowContents
        let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.20, y: 0.74),
                                     endControlPoint: UnitPoint(x: 0.23, y: 1))
        return TimelineView(.animation) { timeline in
            let elapsed = foldStartedAt.map { unitProgress(timeline.date.timeIntervalSince($0) / 0.18) } ?? 0
            let fraction = elapsed >= 1 ? 0 : 1 - curve.value(at: elapsed)
            FoldHeight(fraction: fraction) { content }
                .clipped()
                .opacity(fraction)
                .onChange(of: foldStartedAt == nil, initial: true) { _, shouldStart in
                    // Reserve the existing slot before the first shrinking frame.
                    if shouldStart { foldStartedAt = timeline.date }
                }
                .onChange(of: elapsed >= 1) { _, ended in
                    if ended { onFoldComplete() }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onDisappear(perform: onFoldComplete)
    }

    private var rowContents: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isRemovable { swipeableHeading } else { rowHeading }
            if isEditorMounted {
                FoldHeight(fraction: isExpanded ? 1 : 0) {
                    editor
                        .padding(.top, 4)
                        .mask {
                            Rectangle().scaleEffect(x: 1, y: editorRevealed ? 1 : 0, anchor: .top)
                        }
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                            if isExpanded, !isFolding { onEditorHeightChange(height) }
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
    }

    private var swipeableHeading: some View {
        rowHeading
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(RemovalPan(update: updateRemoval))
    }

    private func updateRemoval(_ state: UIGestureRecognizer.State, horizontal: CGFloat) {
        guard !isFolding else { return }
        switch state {
        case .began:
            let origin = removalSettle?.progress(at: .now) ?? (isRemovalRevealed ? 1 : 0)
            removalSettle = nil
            removalDrag = RemovalDrag(origin: origin, horizontal: horizontal)
        case .changed:
            if let drag = removalDrag { removalDrag = RemovalDrag(origin: drag.origin, horizontal: horizontal) }
        case .ended, .cancelled, .failed:
            guard let drag = removalDrag else { return }
            let progress = state == .ended ? RemovalDrag(origin: drag.origin, horizontal: horizontal).progress : drag.progress
            let revealed = state == .ended ? progress >= 0.5 : isRemovalRevealed
            let destination: CGFloat = revealed ? 1 : 0
            removalSettle = reduceMotion || progress == destination ? nil : RemovalSettle(origin: progress, destination: destination)
            removalDrag = nil
            if revealed != isRemovalRevealed { onRevealRemoval(revealed) }
        default:
            break
        }
    }

    private var removalWidth: CGFloat { min(220, scaledRemoveWidth) }
    private var statusHeight: CGFloat { max(44, ceil(statusPointSize * 1.5 + 8)) }
    private var removalInk: Color {
        colorScheme == .dark ? Color(red: 1, green: 0.84, blue: 0.82) : Color(red: 0.62, green: 0.16, blue: 0.16)
    }
    private var removalTint: Color {
        colorScheme == .dark ? Color(red: 0.30, green: 0.18, blue: 0.17) : Color(red: 0.98, green: 0.89, blue: 0.88)
    }

    private var removalLabel: some View {
        Text("Remove").font(.subheadline.bold()).foregroundStyle(removalInk)
            .padding(.trailing, removalWidth * 13 / 86)
            .frame(width: removalWidth, height: statusHeight, alignment: .trailing)
            .background {
                RoundedRectangle(cornerRadius: 9).fill(removalTint).padding(.vertical, 4)
            }
            .contentShape(Rectangle())
    }

    private func letterpress(_ progress: CGFloat) -> some View {
        RemovalLetterpress(progress: progress, previous: isCurrent ? "Current" : "Pending",
                           previousColor: isCurrent ? PlannerStyle.moss : .secondary,
                           previousBold: isCurrent, ink: removalInk, tint: removalTint,
                           pointSize: statusPointSize, pillWidth: removalWidth, direction: layoutDirection)
            .accessibilityHidden(true).allowsHitTesting(false)
    }

    private var removalStatus: some View {
        ZStack(alignment: .trailing) {
            if isFolding {
                if isRemovalRevealed { removalLabel } else { rowStatus }
            } else if let settle = removalSettle {
                TimelineView(.animation) { timeline in
                    letterpress(settle.progress(at: timeline.date))
                        .onChange(of: settle.hasEnded(at: timeline.date), initial: true) { _, ended in
                            if ended, removalSettle == settle { removalSettle = nil }
                        }
                }
            } else if let drag = removalDrag, !reduceMotion {
                letterpress(drag.progress)
            } else if isRemovalRevealed {
                if removalDrag == nil {
                    Button(role: .destructive, action: onRemove) { removalLabel }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(title)")
                        .accessibilityIdentifier("removeSet\(index)")
                } else {
                    removalLabel.accessibilityHidden(true)
                }
            } else {
                rowStatus
            }
        }
        .frame(width: min(250, scaledStatusWidth), height: statusHeight, alignment: .trailing)
        .clipped()
    }

    @ViewBuilder private var headingStatus: some View {
        if isRemovable { removalStatus } else { rowStatus }
    }

    private var rowHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                setButton.fixedSize()
                Spacer(minLength: 4)
                headingStatus.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                setButton
                headingStatus.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var setButton: some View {
        Button {
            removalDrag = nil
            removalSettle = nil
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
        .accessibilityActions {
            if isRemovable { Button("Remove \(title)", role: .destructive, action: onRemove) }
        }
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
                Text("Target \(target)").font(.caption).foregroundStyle(.secondary)
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
}

private struct RemovalPan: UIGestureRecognizerRepresentable {
    let update: (UIGestureRecognizer.State, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        update(pan.state, pan.translation(in: pan.view).x)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let motion = pan.translation(in: pan.view)
            return abs(motion.x) > abs(motion.y)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}

private struct RemovalDrag {
    let origin: CGFloat
    let horizontal: CGFloat

    var progress: CGFloat { unitProgress(origin - horizontal / 118) }
}

private struct RemovalSettle: Equatable {
    let token = UUID()
    let origin: CGFloat
    let destination: CGFloat
    let start = Date.now

    func hasEnded(at date: Date) -> Bool { date.timeIntervalSince(start) >= 0.22 }

    func progress(at date: Date) -> CGFloat {
        let remaining = 1 - unitProgress(date.timeIntervalSince(start) / 0.22)
        return origin + (destination - origin) * (1 - remaining * remaining * remaining)
    }
}

private func unitProgress(_ value: CGFloat) -> CGFloat { min(1, max(0, value)) }

private func smoothProgress(_ value: CGFloat) -> CGFloat {
    let progress = unitProgress(value)
    return progress * progress * (3 - 2 * progress)
}

private struct RemovalLetterpress: View {
    let progress: CGFloat
    let previous: String
    let previousColor: Color
    let previousBold: Bool
    let ink: Color
    let tint: Color
    let pointSize: CGFloat
    let pillWidth: CGFloat
    let direction: LayoutDirection

    var body: some View {
        Canvas { context, size in
            let softness = smoothProgress(progress)
            drawPill(in: context, size: size, softness: softness)

            let next = "Remove"
            let nextCharacters = Array(next)
            let oldPositions = positions(previous, size: size, bold: previousBold, inset: 0)
            let newPositions = positions(next, size: size, bold: true, inset: pillWidth * 13 / 86)
            for (index, character) in previous.enumerated() {
                let replacement = index < nextCharacters.count ? nextCharacters[index] : nil
                let destinationX = index < newPositions.count ? newPositions[index] : newPositions.last! + pointSize / 2
                let x = oldPositions[index] + (destinationX - oldPositions[index]) * softness
                let local = smoothProgress((progress - 0.055 * CGFloat(previous.count - 1 - index)) / 0.64)
                let blur = sin(.pi * local) * 1.05
                if replacement == character {
                    draw(character, in: context, x: x, y: size.height / 2,
                         color: previousColor.mix(with: ink, by: softness, in: .device),
                         bold: previousBold || progress > 0.64, opacity: 1, blur: 0)
                } else {
                    draw(character, in: context, x: x, y: size.height / 2 - pointSize * local,
                         color: previousColor, bold: previousBold, opacity: 1 - local, blur: blur)
                    if let replacement {
                        draw(replacement, in: context, x: x, y: size.height / 2 + pointSize * (1 - local),
                             color: ink, bold: true, opacity: local, blur: blur)
                    }
                }
            }
        }
    }

    private func positions(_ word: String, size: CGSize, bold: Bool, inset: CGFloat) -> [CGFloat] {
        let font = UIFont.systemFont(ofSize: pointSize, weight: bold ? .bold : .regular)
        func width(_ value: String) -> CGFloat { (value as NSString).size(withAttributes: [.font: font]).width }
        let leading = direction == .leftToRight ? size.width - inset - width(word) : inset
        return (0..<word.count).map { leading + width(String(word.prefix($0))) }
    }

    private func drawPill(in context: GraphicsContext, size: CGSize, softness: CGFloat) {
        let width = pillWidth * (0.24 + 0.76 * softness)
        let x = direction == .leftToRight ? size.width - width : 0
        let rect = CGRect(x: x, y: 4, width: width, height: size.height - 8)
        let pill = RoundedRectangle(cornerRadius: 9).path(in: rect)
        context.fill(pill, with: .color(tint.opacity(smoothProgress((progress - 0.12) / 0.64))))

        let glint = sin(.pi * unitProgress((progress - 0.22) / 0.68)) * 0.35
        guard glint > 0 else { return }
        let glintX = rect.midX + 20 - 44 * softness
        let gradient = Gradient(colors: [.clear, .white.opacity(glint), .clear])
        context.fill(pill, with: .linearGradient(gradient, startPoint: CGPoint(x: glintX - 20, y: rect.maxY),
                                                 endPoint: CGPoint(x: glintX + 20, y: rect.minY)))
    }

    private func draw(_ character: Character, in context: GraphicsContext, x: CGFloat, y: CGFloat,
                      color: Color, bold: Bool, opacity: CGFloat, blur: CGFloat) {
        guard opacity > 0 else { return }
        var glyph = context
        glyph.opacity = opacity
        if blur > 0 { glyph.addFilter(.blur(radius: blur)) }
        glyph.draw(Text(String(character)).font(.system(size: pointSize, weight: bold ? .bold : .regular))
            .foregroundColor(color), at: CGPoint(x: x, y: y), anchor: .leading)
    }
}

private struct FoldHeight: Layout {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let fullSize = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: fullSize.width, height: fullSize.height * min(1, max(0, fraction)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
