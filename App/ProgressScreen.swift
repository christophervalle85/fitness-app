import Charts
import SwiftUI

struct ProgressScreen<Recovery: View>: View {
    let store: TrainingStore
    let activePlan: WeekPlan?
    let unit: String
    let setUnit: (String) throws -> Void
    @ViewBuilder var recovery: () -> Recovery
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var issue: String?

    var body: some View {
        let metrics = ProgressMetrics(sessions: store.sessions, occurrences: store.occurrences, activePlan: activePlan)
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This week’s schedule").font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(metrics.adherence.fulfilled)").font(.system(.largeTitle, design: .rounded, weight: .heavy)).monospacedDigit()
                        Text("of \(metrics.adherence.scheduled) fulfilled").font(.headline)
                    }
                    ProgressView(value: Double(metrics.adherence.fulfilled), total: Double(max(1, metrics.adherence.scheduled)))
                        .tint(Color.white)
                }.foregroundStyle(Color.white).padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Planned workouts fulfilled this week")
                    .accessibilityValue("\(metrics.adherence.fulfilled) of \(metrics.adherence.scheduled)")
                    .accessibilityIdentifier("adherence")
            } footer: { Text("Includes dated workouts and upcoming days in your current routine.") }
            .listRowBackground(PlannerStyle.forest)
            Section("Training activity") {
                TrainingActivityChart(sessions: metrics.history)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    total("Workouts", value: String(metrics.sessionCount))
                    total("Cardio sessions", value: String(metrics.cardioCount))
                    total("Cardio time", value: elapsedString(TimeInterval(metrics.cardioSeconds)))
                }.padding(.vertical, 6)

            }.listRowBackground(PlannerStyle.surface)
            if let latest = metrics.history.first {
                Section("Last workout") {
                    NavigationLink {
                        ProgressSession(store: store, id: latest.id, unit: unit)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(latest.name).font(.title3.bold())
                            Text(latest.startedAt.formatted(date: .abbreviated, time: .shortened) + (latest.partial ? " · Partial" : ""))
                                .font(.subheadline)
                        }.padding(.vertical, 4)
                    }
                }.listRowBackground(PlannerStyle.surface)
            }
            Section {
                NavigationLink {
                    List {
                        if metrics.history.isEmpty {
                            ContentUnavailableView("No finished workouts", systemImage: "calendar", description: Text("Finish a workout to see its results here."))
                        }
                        ForEach(Array(metrics.history.enumerated()), id: \.element.id) { i, session in
                            NavigationLink {
                                ProgressSession(store: store, id: session.id, unit: unit)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.name).font(.headline)
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened) + (session.partial ? " · Partial" : ""))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("historySession\(i)")
                        }
                    }.navigationTitle("Workout history")
                } label: { Label("Workout history", systemImage: "clock.arrow.circlepath") }
                .accessibilityIdentifier("progressHistory")
                NavigationLink {
                    List {
                        if metrics.records.isEmpty {
                            ContentUnavailableView("No exercise records", systemImage: "chart.xyaxis.line", description: Text("Confirm working sets to see your exercise history."))
                        }
                        ForEach(Array(metrics.records.enumerated()), id: \.element.id) { i, record in
                            NavigationLink {
                                RecordDetail(record: record, unit: unit)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(record.name).font(.headline)
                                    Text(recordContext(record)).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("recordGroup\(i)")
                        }
                    }.navigationTitle("Exercise records")
                } label: { Label("Exercise records", systemImage: "chart.xyaxis.line") }
                .accessibilityIdentifier("progressRecords")
            }
            if !metrics.suggestions.isEmpty {
                Section("Progression suggestions") {
                    ForEach(metrics.suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(suggestion.name).font(.headline)
                            Text("All prescribed working sets reached the upper target at \(weightText(suggestion.kg, unit)). Choose your next available increment.")
                            Text(suggestion.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Settings") {
                Text("Record display unit").font(.subheadline)
                Picker("Record display unit", selection: Binding(get: { unit }, set: { value in
                    do { try setUnit(value); issue = nil } catch { issue = error.localizedDescription }
                })) {
                    Text("lb").tag("lb")
                    Text("kg").tag("kg")
                }.pickerStyle(.segmented).accessibilityIdentifier("weightUnit")
                if let issue { Text(issue) }
                NavigationLink("Lock Screen privacy") { WorkoutPrivacySettings() }
                NavigationLink { recovery() } label: { Label("Backup and export", systemImage: "externaldrive") }
                    .accessibilityIdentifier("backupRecovery")
            }
        }
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle("Progress")
    }
    private func total(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

}

private struct TrainingActivityChart: View {
    let sessions: [TrainingSession]
    private struct DayCount: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    var body: some View {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let days = (0..<7).compactMap { offset -> DayCount? in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return nil }
            return DayCount(date: day, count: sessions.filter { $0.performedDay == CivilTrainingDay(day) }.count)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days").font(.headline)
            if days.contains(where: { $0.count > 0 }) {
                Chart(days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Finished workouts", day.count), width: .ratio(0.55))
                        .cornerRadius(3).foregroundStyle(calendar.isDate(day.date, inSameDayAs: today) ? PlannerStyle.ochre : PlannerStyle.moss)
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(day.count) workouts")
                }
                .chartXAxis { AxisMarks(values: days.map(\.date)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .chartYAxis { AxisMarks(position: .leading, values: .stride(by: max(1, Double(days.map(\.count).max() ?? 1) / 3).rounded(.up))) }
                .frame(height: 104)
            } else {
                Text("No finished workouts in the last seven days.").font(.subheadline)
            }
        }.padding(.vertical, 6)
    }
}

private func weightText(_ kg: Double, _ unit: String) -> String {
    let value = WeightUnits.convert(kg, from: "kg", to: unit)
    return "\(value.formatted(.number.precision(.fractionLength(0...3)))) \(unit)"
}

private func recordContext(_ record: ExerciseRecords) -> String {
    let name: String = switch record.basis {
    case .external: "External load"
    case .barbell: "Total barbell weight"
    case .dumbbell: "Per dumbbell"
    case .machine: "Machine setting"
    case .bodyweight: "Bodyweight"
    case .added: "Added load"
    case .assisted: "Assistance"
    case .unilateral: "Per side"
    case .timed: "Duration"
    }
    return [name, record.side?.capitalized].compactMap { $0 }.joined(separator: " · ")
}

private struct RecordDetail: View {
    let record: ExerciseRecords
    let unit: String
    private func result(_ point: ProgressSet) -> String {
        [point.kg.map { weightText($0, unit) }, point.reps.map { "\($0) reps" }, point.seconds.map { "\($0) sec" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        List {
            Section(recordContext(record)) {
                if let best = record.heaviest {
                    LabeledContent("Heaviest working set", value: result(best))
                    Text(best.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                } else {
                    Text("\(record.trend.count) confirmed working sets")
                }
            }
            if !record.repBests.isEmpty {
                Section("Best by rep count") {
                    ForEach(record.repBests, id: \.id) { point in
                        VStack(alignment: .leading) {
                            Text(result(point))
                            Text(point.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Working set history") {
                if record.trend.count > 1 {
                    let loaded = record.trend.allSatisfy { $0.kg != nil } && record.basis != .timed
                    let timed = record.basis == .timed
                    let axis = loaded ? (record.basis == .assisted ? "Assistance (\(unit))" : "Load (\(unit))") : (timed ? "Seconds" : "Reps")
                    Chart(record.trend, id: \.id) { point in
                        let value = loaded ? point.kg.map { WeightUnits.convert($0, from: "kg", to: unit) } : (timed ? point.seconds : point.reps).map(Double.init)
                        if let value {
                            PointMark(x: .value("Performed", point.date), y: .value(axis, value))
                        }
                    }
                    .foregroundStyle(PlannerStyle.moss).chartYAxisLabel(axis).frame(height: 150).accessibilityLabel(axis + " over time")
                }
                ForEach(record.trend.reversed(), id: \.id) { point in
                    LabeledContent(point.date.formatted(date: .abbreviated, time: .shortened), value: result(point))
                }
            }
        }.navigationTitle(record.name)
    }
}

private struct ProgressSession: View {
    let store: TrainingStore
    let id: UUID
    let unit: String
    var body: some View {
        List {
            if let session = store.sessions.first(where: { $0.id == id }) {
                Section(session.name) {
                    LabeledContent("Status", value: session.partial ? "Partial" : "Finished")
                    NavigationLink {
                        SessionDateEditor(store: store, session: session)
                    } label: { LabeledContent("Performed", value: session.startedAt.formatted(date: .abbreviated, time: .shortened)) }
                    if !session.notes.isEmpty { Text(session.notes) }
                }
                if let cardio = session.cardio {
                    Section("Cardio") {
                        NavigationLink {
                            CardioCorrection(store: store, session: session, result: cardio)
                        } label: { LabeledContent("Activity duration", value: elapsedString(TimeInterval(cardio.seconds))) }
                        if let distance = cardio.distance { LabeledContent("Distance", value: "\(distance.formatted()) \(cardio.unit)") }
                        if !cardio.notes.isEmpty { Text(cardio.notes) }
                    }
                }
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { e, exercise in
                    Section(exercise.prescription.name) {
                        if let replaced = exercise.replacedPrescription { Text("In place of \(replaced.name)").font(.caption) }
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { i, row in
                            if let date = row.confirmedAt {
                                NavigationLink {
                                    SetCorrection(store: store, sessionID: id, exercise: exercise, row: row, date: date)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text("\(row.warmup == true ? "Warm-up" : "Set") \(row.ordinal ?? i + 1)")
                                        Text(actualDescription(row.actual.converted(to: unit), basis: exercise.basis)).foregroundStyle(.secondary)
                                    }
                                }.accessibilityIdentifier("historySet\(e)-\(i)")
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Workout details")
    }
}

private struct SessionDateEditor: View {
    let store: TrainingStore
    let session: TrainingSession
    @State private var date: Date
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    init(store: TrainingStore, session: TrainingSession) {
        self.store = store; self.session = session; _date = State(initialValue: session.startedAt)
    }
    var body: some View {
        Form {
            DatePicker("Workout start", selection: $date, in: ...Date.now)
            Text("Set times move by the same amount. The planned date stays in your schedule.").font(.footnote)
            if let issue { Text(issue) }
            Button("Save date") {
                do { try store.redate(sessionID: session.id, startedAt: date); dismiss() }
                catch { issue = error.localizedDescription }
            }
        }.navigationTitle("Correct date")
    }
}

private struct CorrectionField<Field: View>: View {
    let label: String
    @ViewBuilder var field: () -> Field
    init(_ label: String, @ViewBuilder field: @escaping () -> Field) {
        self.label = label
        self.field = field
    }
    var body: some View {
        HStack {
            Text(label).accessibilityHidden(true)
            Spacer(minLength: 10)
            field().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .frame(maxWidth: 130).accessibilityLabel(label)
        }
    }
}

private struct SetCorrection: View {
    let store: TrainingStore
    let sessionID: UUID
    let exercise: TrainingExercise
    let row: TrainingSet
    @State private var actual: SetActual
    @State private var date: Date
    @State private var revision: Int
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    init(store: TrainingStore, sessionID: UUID, exercise: TrainingExercise, row: TrainingSet, date: Date) {
        self.store = store; self.sessionID = sessionID; self.exercise = exercise; self.row = row
        _revision = State(initialValue: row.revision)
        _actual = State(initialValue: row.actual); _date = State(initialValue: date)
    }
    private var sessionBounds: ClosedRange<Date> {
        guard let session = store.sessions.first(where: { $0.id == sessionID }) else { return date...date }
        return session.startedAt...max(session.startedAt, session.finishedAt ?? Date.now)
    }

    var body: some View {
        Form {
            Section(exercise.prescription.name) {
                if exercise.basis == .timed {
                    CorrectionField("Seconds") { TextField("Seconds", value: $actual.seconds, format: .number).keyboardType(.numberPad) }
                } else {
                    CorrectionField(exercise.basis == .unilateral ? "Left reps" : "Reps") { TextField("Reps", value: $actual.reps, format: .number).keyboardType(.numberPad).accessibilityIdentifier("correctReps") }
                }
                if exercise.basis != .bodyweight {
                    CorrectionField(exercise.basis == .assisted ? "Assistance (\(actual.unit))" : "Load (\(actual.unit))") {
                        TextField("Load", value: $actual.load, format: .number).keyboardType(.decimalPad).accessibilityIdentifier("correctLoad")
                    }
                }
                if exercise.basis == .unilateral {
                    CorrectionField("Right reps") { TextField("Right reps", value: $actual.rightReps, format: .number).keyboardType(.numberPad) }
                    CorrectionField("Right load (\(actual.unit))") { TextField("Right load", value: $actual.rightLoad, format: .number).keyboardType(.decimalPad) }
                }
                DatePicker("Performed", selection: $date, in: sessionBounds)
            }
            if let issue { Text(issue) }
            Button("Save correction") {
                do { try store.correct(sessionID: sessionID, setID: row.id, actual: actual, performedAt: date, revision: revision); dismiss() }
                catch { issue = error.localizedDescription }
            }.accessibilityIdentifier("saveCorrection")
            Button("Undo set confirmation", role: .destructive) {
                do { try store.undo(sessionID: sessionID, setID: row.id, revision: revision); dismiss() }
                catch { issue = error.localizedDescription }
            }.accessibilityIdentifier("undoHistorySet")
        }.multilineTextAlignment(.trailing).navigationTitle("Correct set")
    }
}

private struct CardioCorrection: View {
    let store: TrainingStore
    let session: TrainingSession
    @State var result: CardioResult
    @State private var revision: Int
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    init(store: TrainingStore, session: TrainingSession, result: CardioResult) {
        self.store = store; self.session = session; _result = State(initialValue: result)
        _revision = State(initialValue: session.cardioRevision)
    }
    var body: some View {
        Form {
            CorrectionField("Seconds") { TextField("Duration", value: $result.seconds, format: .number).keyboardType(.numberPad) }
            CorrectionField("Distance (\(result.unit))") { TextField("Distance", value: $result.distance, format: .number).keyboardType(.decimalPad) }
            TextField("Activity notes", text: $result.notes, axis: .vertical)
            if let issue { Text(issue) }
            Button("Save correction") {
                do { try store.recordCardio(sessionID: session.id, result: result, revision: revision, commandID: UUID()); dismiss() }
                catch { issue = error.localizedDescription }
            }
        }.navigationTitle("Correct cardio")
    }
}
