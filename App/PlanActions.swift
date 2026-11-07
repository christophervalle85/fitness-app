import SwiftUI

struct RescheduleWorkoutScreen: View {
    let selected: Date
    let title: String
    let move: (Date) throws -> Void
    let skip: (() throws -> Void)?
    @State private var destination: Date
    @State private var confirmingSkip = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    init(selected: Date, title: String, move: @escaping (Date) throws -> Void, skip: (() throws -> Void)? = nil) {
        self.selected = selected
        self.title = title
        self.move = move
        self.skip = skip
        _destination = State(initialValue: selected)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(selected, format: .dateTime.weekday(.wide).month(.wide).day().year()).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Move to").font(.headline)
                    DatePicker("New workout date", selection: $destination, displayedComponents: .date)
                        .datePickerStyle(.graphical).accessibilityIdentifier("rescheduleDate")
                }
                .padding(14).background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                Text("Only this scheduled workout moves. Its logged sets stay on the dates you performed them.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let skip {
                    Button("Skip this workout", role: .destructive) { confirmingSkip = true }
                        .accessibilityIdentifier("skipPlannedWorkout")
                        .confirmationDialog("Skip this scheduled workout?", isPresented: $confirmingSkip, titleVisibility: .visible) {
                            Button("Skip workout", role: .destructive) { save(skip) }
                                .accessibilityIdentifier("confirmSkipWorkout")
                            Button("Keep workout", role: .cancel) {}
                        }
                }
            }.frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .background(PlannerStyle.paper)
        .navigationTitle("Reschedule").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlanActionFooter(problem: problem, title: "Move workout", id: "confirmReschedule",
                             enabled: CivilTrainingDay(destination) != CivilTrainingDay(selected)) {
                save { try move(destination) }
            }
        }
        .onChange(of: destination) { _, _ in problem = nil }
    }

    private func save(_ action: () throws -> Void) {
        do { try action(); dismiss() } catch { problem = error.localizedDescription }
    }
}

private enum CardioChoice: String, CaseIterable, Identifiable {
    case walking = "Walking", running = "Running", cycling = "Cycling", custom = "Custom"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .custom: "plus"
        }
    }
}

struct AddCardioScreen: View {
    let training: TrainingStore
    let onScheduled: (Date) -> Void
    @State private var day: Date
    @State private var choice: CardioChoice?
    @State private var customName = ""
    @State private var minutes: Int? = 20
    @State private var requestID = UUID()
    @State private var problem: String?
    @FocusState private var field: Input?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Input { case name, minutes }

    init(selected: Date, training: TrainingStore, onScheduled: @escaping (Date) -> Void = { _ in }) {
        self.training = training
        self.onScheduled = onScheduled
        _day = State(initialValue: selected)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let choice {
                    HStack {
                        Label(choice.rawValue, systemImage: choice.symbol)
                            .font(.title2.weight(.semibold)).foregroundStyle(PlannerStyle.ink)
                        Spacer()
                        Button("Change") { self.choice = nil; problem = nil; field = nil }
                            .accessibilityLabel("Change activity")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        if choice == .custom {
                            Text("Activity name").font(.headline)
                            TextField("Activity name", text: $customName)
                                .textFieldStyle(.roundedBorder).focused($field, equals: .name)
                                .accessibilityIdentifier("scheduledCardioName")
                        }
                        Text("Duration goal").font(.headline)
                        HStack {
                            TextField("Minutes", value: $minutes, format: .number)
                                .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                .focused($field, equals: .minutes).accessibilityLabel("Duration in minutes")
                                .accessibilityIdentifier("cardioGoalMinutes")
                            Text("minutes")
                        }
                        Divider()
                        DatePicker("Scheduled date", selection: $day, displayedComponents: .date)
                            .accessibilityIdentifier("cardioScheduledDate")
                    }
                    .padding(16).background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("Choose an activity").font(.title2.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(CardioChoice.allCases) { option in
                            Button {
                                self.choice = option
                                problem = nil
                            } label: {
                                VStack(alignment: .leading, spacing: 15) {
                                    Image(systemName: option.symbol).font(.title2).foregroundStyle(PlannerStyle.moss)
                                    Text(option.rawValue).font(.headline).foregroundStyle(PlannerStyle.ink)
                                }
                                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                                .padding(14).background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(PlannerStyle.rule) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("cardioKind" + option.rawValue)
                        }
                    }
                }
            }.frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .background(PlannerStyle.paper).navigationTitle("Add cardio").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if choice != nil {
                PlanActionFooter(problem: problem, title: "Schedule activity", id: "saveScheduledCardio", enabled: true, action: schedule)
            }
        }
        .toolbar {
            if field != nil {
                ToolbarItem(placement: .keyboard) { Button("Done") { field = nil } }
            }
        }
    }

    private func schedule() {
        guard let choice else { return }
        let name = choice == .custom ? customName.trimmingCharacters(in: .whitespacesAndNewlines) : choice.rawValue
        guard !name.isEmpty else { problem = "Enter the activity name."; field = .name; return }
        guard let minutes, (1...1440).contains(minutes) else { problem = "Enter a duration from 1 to 1,440 minutes."; field = .minutes; return }
        do {
            try training.scheduleCardio(name: name, date: day, goalSeconds: minutes * 60, id: requestID)
            onScheduled(day)
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}

private struct PlanActionFooter: View {
    let problem: String?
    let title: String
    let id: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem { Label(problem, systemImage: "exclamationmark.circle").font(.footnote) }
            Button(action: action) { Text(title).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!enabled)
                .accessibilityIdentifier(id)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(PlannerStyle.surface)
    }
}
