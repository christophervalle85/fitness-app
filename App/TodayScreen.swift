import SwiftUI

struct TodayScreen: View {
    let plan: WeekPlan?
    let training: TrainingStore
    @Binding var selected: Date
    let finishPulse: Int
    let openWorkout: () -> Void
    let showRoutines: () -> Void
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
    private var standaloneSessions: [TrainingSession] {
        let displayed = Set(datedWork.map(\.id))
        return training.sessions.filter { session in
            training.isPerformed(session, on: selected) && session.finishedAt != nil && session.occurrenceID.map(displayed.contains) != true
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private var templateOccurrence: TrainingOccurrence? {
        guard let plan else { return nil }
        return training.occurrences.first { $0.planID == plan.id && training.isOriginal($0, on: selected) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(selected.formatted(.dateTime.month(.wide).year()))
                        .font(.system(.title, design: .serif, weight: .medium))
                    Spacer()
                    DatePicker("Selected date", selection: $selected, displayedComponents: .date).labelsHidden()
                }
                weekStrip
                if let running = training.active {
                    Button(action: openWorkout) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill").font(.title)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Resume workout").font(.caption.weight(.semibold))
                                Text(running.name).font(.headline)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }.padding(14).foregroundStyle(PlannerStyle.moss)
                        .background(PlannerStyle.moss.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityIdentifier("resumeWorkout")
                }
                if let plan { Label(plan.name, systemImage: "calendar").font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss) }
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
                                       status: status, detail: detail(entry), credited: training.slotProgress(for: entry), canStart: available && training.active == nil,
                                       startTitle: status == "Partial" ? "Continue planned workout" : startTitle,
                                       primaryID: "startOccurrence", selected: selected,
                                       start: { run { try training.startOccurrence(entry.id); openWorkout() } },
                                       move: available ? { date in run { try training.move(entry.id, to: date) } } : nil,
                                       skip: available ? { run { try training.skip(entry.id) } } : nil)
                    let contributions = training.sessions.filter { $0.occurrenceID == entry.id && $0.finishedAt != nil }
                        .sorted { $0.startedAt < $1.startedAt }
                    if !contributions.isEmpty {
                        SessionLogGroup(sessions: contributions, title: "Workout sessions (\(contributions.count))", training: training, plan: plan)

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
                            Text("No workout scheduled. You can still log an extra session.").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            .background(PlannerStyle.moss.opacity(0.085), in: RoundedRectangle(cornerRadius: 20))
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
                if !standaloneSessions.isEmpty {
                    Text("Activity on this date").font(.system(.title2, design: .serif))
                    ForEach(standaloneSessions) { session in
                        if let id = session.occurrenceID, let occurrence = training.occurrences.first(where: { $0.id == id }) {
                            let parts = standaloneSessions.filter { $0.occurrenceID == id }
                            if parts.first?.id == session.id {
                                SessionLogGroup(sessions: parts, title: "\(occurrence.name) · \(occurrence.date.formatted(date: .abbreviated, time: .omitted))", training: training, plan: plan)
                            }
                        } else {
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
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(PlannerStyle.paper)
        .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
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
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @ViewBuilder private var weekStrip: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: typeSize.isAccessibilitySize ? 4 : 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(week, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selected)
                let entries = training.occurrences.filter { training.isScheduled($0, on: date) }
                let index = CivilTrainingDay(date).mondayIndex
                let templateScheduled = (plan?.days[safe: index]?.isWorkout == true) &&
                    !training.occurrences.contains { $0.planID == plan?.id && training.isOriginal($0, on: date) && !training.isScheduled($0, on: date) }
                let pendingTemplate = templateScheduled && !entries.contains { $0.planID == plan?.id && training.isOriginal($0, on: date) }
                let complete = !pendingTemplate && !entries.isEmpty && entries.allSatisfy { training.status(for: $0).hasPrefix("Done") }
                let planned = templateScheduled || !entries.isEmpty
                Button { selected = date } label: {
                    VStack(spacing: 4) {
                        Text(date, format: .dateTime.weekday(.abbreviated)).font(.caption2)
                        Text(date, format: .dateTime.day()).font(.system(.headline, design: .rounded).monospacedDigit())
                        Image(systemName: complete ? "checkmark.circle.fill" : planned ? "dumbbell.fill" : "minus")
                            .font(.caption2)
                            .symbolEffect(.bounce, value: reducedMotion || !isSelected || !complete ? 0 : finishPulse)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : PlannerStyle.moss)
                    .background(isSelected ? PlannerStyle.moss : PlannerStyle.moss.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("weekday\(index)")
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(complete ? "Complete" : planned ? "Workout" : "Rest day")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

private struct SessionLogGroup: View {
    let sessions: [TrainingSession]
    let title: String
    let training: TrainingStore
    let plan: WeekPlan?
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
                        SavedWorkoutDetail(id: item.id, training: training, plan: plan)
                    } label: {
                        HStack {
                            Text("Session \(index + 1)").font(.headline)
                            Spacer()
                            Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label(status, systemImage: status.hasPrefix("Done") ? "checkmark.circle.fill" : "calendar")
                    .font(.subheadline.weight(.semibold))
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
            if canStart {
                Button(action: start) {
                    Label(startTitle, systemImage: "play.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).padding(14).accessibilityIdentifier(primaryID)
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
                }.padding(14)
            }
        }
        .background(PlannerStyle.surface).clipShape(RoundedRectangle(cornerRadius: 20))
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
