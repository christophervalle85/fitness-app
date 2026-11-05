import SwiftUI

struct TodayScreen: View {
    let plan: WeekPlan?
    let training: TrainingStore
    let openWorkout: () -> Void
    let showRoutines: () -> Void
    @State private var selected = Date.now
    @State private var issue: String?
    @State private var scheduling = false
    @State private var cardioName = ""
    @State private var cardioMinutes = 20
    private var calendar: Calendar { .autoupdatingCurrent }
    private var weekday: Int { (calendar.component(.weekday, from: selected) + 5) % 7 }
    private var week: [Date] {
        let start = calendar.startOfDay(for: selected)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - weekday, to: start) }
    }
    private var datedWork: [TrainingOccurrence] {
        training.occurrences.filter { training.isScheduled($0, on: selected) }
    }
    private var actualSessions: [TrainingSession] {
        training.sessions.filter { training.isPerformed($0, on: selected) && $0.finishedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }
    private var templateOccurrence: TrainingOccurrence? {
        guard let plan else { return nil }
        return training.occurrences.first { $0.planID == plan.id && training.isOriginal($0, on: selected) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let running = training.active {
                    Button(action: openWorkout) {
                        Label("Resume \(running.name)", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("resumeWorkout")
                }
                DatePicker("Selected date", selection: $selected, displayedComponents: .date)
                    .datePickerStyle(.compact)
                weekStrip
                if let plan { Text(plan.name).font(.subheadline.bold()).foregroundStyle(PlannerStyle.blue) }
                if let issue {
                    Label(issue, systemImage: "exclamationmark.circle").font(.subheadline)
                }
                if let plan, plan.days.count == 7, templateOccurrence == nil, plan.days[weekday].isWorkout {
                    let day = plan.days[weekday]
                    PlannedWorkoutCard(name: day.name, day: day, goal: day.cardioGoalSeconds,
                                       status: "Scheduled", detail: nil, canStart: training.active == nil,
                                       startTitle: startTitle, primaryID: "startPlanned", selected: selected,
                                       start: { run { try training.startPlanned(plan: plan, date: selected); openWorkout() } },
                                       move: { target in run {
                                           let id = try training.materialize(plan: plan, date: selected)
                                           try training.move(id, to: target)
                                       } }, skip: { run {
                                           let id = try training.materialize(plan: plan, date: selected)
                                           try training.skip(id)
                                       } })
                }
                ForEach(datedWork) { entry in
                    let status = training.status(for: entry)
                    let available = status == "Scheduled" || status == "Partial"
                    PlannedWorkoutCard(name: entry.name, day: entry.day, goal: entry.cardioGoalSeconds,
                                       status: status, detail: detail(entry), canStart: available && training.active == nil,
                                       startTitle: status == "Partial" ? "Continue planned workout" : startTitle,
                                       primaryID: "startOccurrence", selected: selected,
                                       start: { run { try training.startOccurrence(entry.id); openWorkout() } },
                                       move: available ? { date in run { try training.move(entry.id, to: date) } } : nil,
                                       skip: available ? { run { try training.skip(entry.id) } } : nil)
                    ForEach(training.sessions.filter { $0.occurrenceID == entry.id && $0.finishedAt != nil && !training.isPerformed($0, on: selected) }) { contribution in
                        NavigationLink {
                            SavedWorkoutDetail(id: contribution.id, training: training, plan: plan)
                        } label: {
                            Label("View session from \(contribution.startedAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
                if let moved = templateOccurrence, !training.isScheduled(moved, on: selected) {
                    Label("\(moved.name) moved to \(moved.date.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                } else if datedWork.isEmpty && !(plan?.days[safe: weekday]?.isWorkout ?? false) {
                    if plan == nil {
                        Text("No active routine").font(.title2.bold())
                        Button("Open Routines", action: showRoutines)
                    } else {
                        Text("Rest day").font(.title.bold())
                        Text("No workout scheduled. You can still log an extra session.").foregroundStyle(.secondary)
                    }
                }
                if training.active == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Train today").font(.headline)
                        HStack {
                            Button { run { try training.startExtra(name: "Extra workout"); openWorkout() } }
                                label: { Label("Extra workout", systemImage: "plus") }
                                .accessibilityIdentifier("extraWorkout")
                            Button { run { try training.startCardio(name: "Cardio"); openWorkout() } }
                                label: { Label("Cardio", systemImage: "figure.run") }
                                .accessibilityIdentifier("extraCardio")
                        }.buttonStyle(.bordered)
                    }
                }
                DisclosureGroup("Schedule a cardio activity", isExpanded: $scheduling) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Activity name", text: $cardioName).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("scheduledCardioName")
                        Stepper("Duration · \(cardioMinutes) min", value: $cardioMinutes, in: 1...1440)
                        Button("Schedule for \(selected.formatted(date: .abbreviated, time: .omitted))") {
                            run {
                                try training.scheduleCardio(name: cardioName, date: selected, goalSeconds: cardioMinutes * 60)
                                cardioName = ""
                                scheduling = false
                            }
                        }.buttonStyle(.bordered).accessibilityIdentifier("saveScheduledCardio")
                            .disabled(cardioName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.top, 12)
                }
                if !actualSessions.isEmpty {
                    Text("Sessions performed").font(.title3.bold())
                    ForEach(actualSessions) { session in
                        NavigationLink {
                            SavedWorkoutDetail(id: session.id, training: training, plan: plan)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(session.name).font(.headline)
                                    Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.partial ? "Finished partial" : "Finished")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }.accessibilityIdentifier("savedSession")
                    }
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(PlannerStyle.paper)
        .navigationTitle("Today")
        .onChange(of: selected) { _, _ in issue = nil; scheduling = false }
    }

    private var startTitle: String {
        calendar.isDateInToday(selected) ? "Start planned workout" : "Do this workout today"
    }

    private func detail(_ entry: TrainingOccurrence) -> String? {
        let counts = training.progress(for: entry)
        let sessions = training.sessions.filter { $0.occurrenceID == entry.id }
        guard counts.completed > 0 || !sessions.isEmpty else { return nil }
        let amount = "\(counts.completed) / \(counts.total) \(entry.cardioGoalSeconds == nil ? "sets" : "seconds")"
        let dates = Set(sessions.map { $0.startedAt.formatted(date: .abbreviated, time: .omitted) }).sorted()
        return dates.isEmpty ? amount : amount + " · " + dates.joined(separator: ", ")
    }

    private func run(_ action: () throws -> Void) {
        do { try action(); issue = nil } catch { issue = error.localizedDescription }
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder private var weekStrip: some View {
        if !typeSize.isAccessibilitySize {
            HStack(spacing: 2) {
                ForEach(week, id: \.self) { date in
                    let isSelected = calendar.isDate(date, inSameDayAs: selected)
                    Button { selected = date } label: {
                        VStack(spacing: 5) {
                            Text(date, format: .dateTime.weekday(.narrow)).font(.caption)
                            Text(date, format: .dateTime.day()).font(.headline.monospacedDigit())
                        }.frame(maxWidth: .infinity, minHeight: 55)
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .background(isSelected ? PlannerStyle.blue : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("weekday\((calendar.component(.weekday, from: date) + 5) % 7)")
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    let canStart: Bool
    let startTitle: String
    let primaryID: String
    let selected: Date
    let start: () -> Void
    let move: ((Date) -> Void)?
    let skip: (() -> Void)?
    @State private var destination = Date.now
    @State private var editingSchedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.system(.title, design: .rounded, weight: .bold))
            HStack {
                Text(status).font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.blue)
                if let goal { Text("\(goal / 60) min").foregroundStyle(.secondary) }
            }
            if let detail { Text(detail).font(.subheadline) }
            if canStart {
                Button(action: start) {
                    Label(startTitle, systemImage: "play.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier(primaryID)
            }
            if let day, !day.exercises.isEmpty {
                DisclosureGroup("Exercises (\(day.exercises.count))") {
                    ForEach(day.exercises) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).font(.body.weight(.medium))
                            Text(prescription(row)).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                }
            }
            if move != nil || skip != nil {
                DisclosureGroup("Change schedule", isExpanded: $editingSchedule) {
                    VStack(alignment: .leading, spacing: 10) {
                        DatePicker("Move to", selection: $destination, displayedComponents: .date)
                        if let move {
                            Button("Move this workout") { editingSchedule = false; move(destination) }
                                .disabled(Calendar.current.isDate(destination, inSameDayAs: selected))
                        }
                        if let skip {
                            Button("Skip this scheduled workout") { editingSchedule = false; skip() }
                        }
                    }.padding(.top, 10)
                }
            }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 18))
        .onChange(of: editingSchedule) { _, expanded in if expanded { destination = selected } }
    }
}

private struct SavedWorkoutDetail: View {
    let id: UUID
    let training: TrainingStore
    let plan: WeekPlan?

    var body: some View {
        if let session = training.sessions.first(where: { $0.id == id }) {
            List {
                Section { LabeledContent("Status", value: session.partial ? "Finished partial" : "Finished") }
                TrainingSummaryContent(session: session)
                if session.isCardio ? session.occurrenceID == nil : session.exercises.flatMap(\.sets).contains(where: { $0.confirmedAt != nil && $0.warmup != true && $0.plannedID == nil }) {
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
