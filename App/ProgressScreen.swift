import Charts
import SwiftUI
import UIKit

struct ProgressScreen<Recovery: View>: View {
    let store: TrainingStore
    let activePlan: WeekPlan?
    let unit: () -> String
    let setUnit: (String) throws -> Void
    @ViewBuilder var recovery: () -> Recovery
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let metrics = ProgressMetrics(sessions: store.sessions, occurrences: store.occurrences, activePlan: activePlan)
        let currentUnit = unit()
        let latestRecord = metrics.records.max { ($0.trend.last?.date ?? .distantPast) < ($1.trend.last?.date ?? .distantPast) }
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This week’s schedule").font(.headline)
                    if metrics.adherence.scheduled == 0 {
                        Text("No workouts scheduled").font(.title2.bold())
                        Text("Your planned workouts will appear here.").font(.subheadline)
                    } else {
                        Text("\(metrics.adherence.fulfilled) of \(metrics.adherence.scheduled) workouts complete")
                            .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.25))
                                Capsule().fill(Color.white)
                                    .frame(width: geometry.size.width * min(1, Double(metrics.adherence.fulfilled) / Double(metrics.adherence.scheduled)))
                            }
                        }.frame(height: 12).accessibilityHidden(true)
                    }
                }.foregroundStyle(.white).padding(.vertical, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(metrics.adherence.scheduled == 0 ? "No workouts scheduled this week" : "Planned workouts fulfilled this week")
                    .accessibilityValue("\(metrics.adherence.fulfilled) of \(metrics.adherence.scheduled)")
                    .accessibilityIdentifier("adherence")
            }
            .listRowBackground(PlannerStyle.forest)
            Section("Last 7 days") {
                TrainingActivityChart(days: metrics.activityDays, store: store, unit: currentUnit)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    total("Sessions", value: String(metrics.sessionCount))
                    total("Cardio sessions", value: String(metrics.cardioCount))
                    total("Cardio time", value: elapsedString(TimeInterval(metrics.cardioSeconds)))
                }.padding(.vertical, 6)
            }.listRowBackground(PlannerStyle.surface)
            Section("Recent workouts") {
                if metrics.history.isEmpty { Text("Finish a workout to see it here.").foregroundStyle(.secondary) }
                ForEach(Array(metrics.history.prefix(2).enumerated()), id: \.element.id) { index, session in
                    NavigationLink { ProgressSession(store: store, id: session.id, unit: currentUnit) } label: {
                        sessionLabel(session)
                    }.accessibilityIdentifier("recentSession\(index)")
                }
                NavigationLink {
                    List {
                        if metrics.history.isEmpty { Text("No finished workouts").foregroundStyle(.secondary) }
                        ForEach(Array(metrics.history.enumerated()), id: \.element.id) { index, session in
                            NavigationLink { ProgressSession(store: store, id: session.id, unit: currentUnit) } label: {
                                sessionLabel(session)
                            }.accessibilityIdentifier("historySession\(index)")
                        }
                    }.navigationTitle("Workout history")
                } label: { Label("View history", systemImage: "clock.arrow.circlepath") }
                .accessibilityIdentifier("progressHistory")
            }
            Section("Exercise records") {
                if let latest = latestRecord, let point = latest.trend.last {
                    NavigationLink { RecordDetail(record: latest, unit: currentUnit) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(latest.name).font(.headline)
                            Text(recordContext(latest)).font(.subheadline).foregroundStyle(.secondary)
                            Text(progressResult(point, unit: currentUnit)).font(.body)
                            Text(point.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("latestExerciseRecord")
                } else { Text("Confirm working sets to see your exercise records.").foregroundStyle(.secondary) }
                NavigationLink { RecordSearch(records: metrics.records, unit: currentUnit) } label: {
                    Label("Find an exercise", systemImage: "magnifyingglass")
                }.accessibilityIdentifier("progressRecords")
            }
            if !metrics.suggestions.isEmpty {
                Section("Progression suggestions") {
                    ForEach(metrics.suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(suggestion.name).font(.headline)
                            Text("All prescribed working sets reached the upper target at \(weightText(suggestion.kg, currentUnit)). Choose your next available increment.")
                            Text(suggestion.date, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle("Progress")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProgressSettings(unit: unit, setUnit: setUnit, recovery: recovery)
                } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("progressSettings")
            }
        }
    }

    private func total(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

private struct ProgressSettings<Recovery: View>: View {
    let unit: () -> String
    let setUnit: (String) throws -> Void
    @ViewBuilder var recovery: () -> Recovery
    @State private var issue: String?
    var body: some View {
        let displayUnit = unit()
        Form {
            Section("Record display unit") {
                Picker("Record display unit", selection: Binding(get: { displayUnit }, set: { value in
                    do { try setUnit(value); issue = nil } catch { issue = error.localizedDescription }
                })) {
                    Text("lb").tag("lb")
                    Text("kg").tag("kg")
                }.pickerStyle(.segmented).accessibilityIdentifier("weightUnit")
                if let issue { Text(issue) }
            }
            Section {
                NavigationLink("Lock Screen privacy") { WorkoutPrivacySettings() }
                NavigationLink { recovery() } label: { Label("Backup and export", systemImage: "externaldrive") }
                    .accessibilityIdentifier("backupRecovery")
            }
        }.navigationTitle("Settings")
            .scrollContentBackground(.hidden).background(PlannerStyle.paper)
    }
}

private struct RecordSearch: View {
    let records: [ExerciseRecords]
    let unit: String
    @State private var query = ""
    var body: some View {
        let terms = query.split(whereSeparator: \.isWhitespace)
        let matches = records.enumerated().filter { _, record in
            let text = record.name + " " + recordContext(record) + " " + record.id.convention
            return terms.allSatisfy { text.localizedStandardContains(String($0)) }
        }
        List {
            if matches.isEmpty { Text(records.isEmpty ? "No exercise records yet" : "No matching exercise records").foregroundStyle(.secondary) }
            ForEach(matches, id: \.element.id) { index, record in
                NavigationLink { RecordDetail(record: record, unit: unit) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.name).font(.headline)
                        Text(recordContext(record)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("recordGroup\(index)")
            }
        }.navigationTitle("Exercise records")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find an exercise")
            .scrollContentBackground(.hidden).background(PlannerStyle.paper)
    }
}

private struct TrainingActivityChart: View {
    let days: [ProgressActivityDay]
    let store: TrainingStore
    let unit: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDate: Date?
    private var selectedIndex: Int? {
        days.firstIndex { $0.date == selectedDate } ?? days.indices.last
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if days.contains(where: { !$0.sessions.isEmpty }) {
                Chart(days.indices, id: \.self) { index in
                    let day = days[index]
                    // Marks, ticks and touch selection share the center of each day's slot.
                    BarMark(x: .value("Day slot", Double(index)), y: .value("Finished sessions", day.sessions.count), width: .fixed(22))
                        .cornerRadius(3).foregroundStyle(PlannerStyle.moss)
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(day.sessions.count) finished sessions")
                }
                .chartXScale(domain: -0.5...(Double(days.count) - 0.5))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            let plot = geometry[plotFrame]
                            Color.clear.contentShape(Rectangle())
                                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                                    select(at: value.location, in: plot, proxy: proxy)
                                })
                                .gesture(ChartDayDrag { location in
                                    select(at: location, in: plot, proxy: proxy)
                                })
                                .accessibilityHidden(true)
                            ForEach(days.indices, id: \.self) { index in
                                if let x = proxy.position(forX: Double(index)) {
                                    Text(days[index].date.formatted(.dateTime.weekday(typeSize.isAccessibilitySize ? .narrow : .abbreviated)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                        .position(x: plot.minX + x, y: plot.maxY + 13)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 140)
                .padding(.bottom, 26)
                .accessibilityIdentifier("progressActivityChart")
                if let index = selectedIndex {
                    let selected = days[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selected.date.formatted(date: .complete, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("progressSelectedDate")
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: select(dayAt: index + 1)
                                case .decrement: select(dayAt: index - 1)
                                @unknown default: break
                                }
                            }
                        Text(selected.sessions.count == 1 ? "1 finished session" : "\(selected.sessions.count) finished sessions")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(Array(selected.sessions.enumerated()), id: \.element.id) { index, session in
                            NavigationLink { ProgressSession(store: store, id: session.id, unit: unit) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.name).font(.headline)
                                    if session.partial {
                                        Text("Partial").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("progressDaySession\(index)")
                        }
                    }
                }
            } else {
                Text("No finished workouts in the last seven days.").font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }

    private func select(at location: CGPoint, in plot: CGRect, proxy: ChartProxy) {
        guard plot.contains(location), let slot = proxy.value(atX: location.x - plot.minX, as: Double.self) else { return }
        select(dayAt: Int(slot.rounded()))
    }

    private func select(dayAt index: Int) {
        guard days.indices.contains(index) else { return }
        selectedDate = days[index].date
    }
}

private struct ChartDayDrag: UIGestureRecognizerRepresentable {
    let onSelection: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        if [.began, .changed, .ended].contains(recognizer.state) {
            onSelection(context.converter.localLocation)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

private func sessionLabel(_ session: TrainingSession) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(session.name).font(.headline)
        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened) + (session.partial ? " · Partial" : ""))
            .font(.subheadline).foregroundStyle(.secondary)
    }
}

private func progressResult(_ point: ProgressSet, unit: String) -> String {
    [point.kg.map { weightText($0, unit) }, point.reps.map { "\($0) reps" }, point.seconds.map { "\($0) sec" }]
        .compactMap { $0 }.joined(separator: " · ")
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
    var body: some View {
        List {
            Section(recordContext(record)) {
                if let best = record.heaviest {
                    LabeledContent("Heaviest working set", value: progressResult(best, unit: unit))
                    Text(best.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                } else {
                    Text("\(record.trend.count) confirmed working sets")
                }
            }
            if !record.repBests.isEmpty {
                Section("Best by rep count") {
                    ForEach(record.repBests, id: \.id) { point in
                        VStack(alignment: .leading) {
                            Text(progressResult(point, unit: unit))
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
                    LabeledContent(point.date.formatted(date: .abbreviated, time: .shortened), value: progressResult(point, unit: unit))
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
