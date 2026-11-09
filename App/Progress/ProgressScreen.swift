import Charts
import SwiftUI
import UIKit

struct ProgressScreen<Recovery: View>: View {
    let store: TrainingStore
    let activePlan: WeekPlan?
    let unit: () -> String
    let setUnit: (String) throws -> Void
    @ViewBuilder var recovery: () -> Recovery
    @State private var catalog: [CatalogEntry] = []
    var body: some View {
        let metrics = ProgressMetrics(sessions: store.sessions, occurrences: store.occurrences, activePlan: activePlan, catalog: catalog)
        let currentUnit = unit()
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
            Section {
                TrainingActivityChart(days: metrics.activityDays, store: store, unit: currentUnit)
                if metrics.sessionCount > 1 || metrics.cardioCount > 0 {
                    let sessions = metrics.sessionCount == 1 ? "1 session" : "\(metrics.sessionCount) sessions"
                    let cardio = metrics.cardioCount > 0
                        ? " · \(metrics.cardioCount) cardio (\(elapsedString(TimeInterval(metrics.cardioSeconds))))"
                        : ""
                    Text("7-day total · \(sessions)\(cardio)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Last 7 days").font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    NavigationLink {
                        List {
                            if metrics.history.isEmpty { Text("No finished workouts").foregroundStyle(.secondary) }
                            ForEach(Array(metrics.history.enumerated()), id: \.element.id) { index, session in
                                NavigationLink { ProgressSession(store: store, id: session.id, unit: currentUnit) } label: {
                                    sessionLabel(session)
                                }.accessibilityIdentifier("historySession\(index)")
                            }
                        }.navigationTitle("Workout history")
                    } label: {
                        Image(systemName: "clock.arrow.circlepath").font(.body.weight(.medium))
                            .foregroundStyle(PlannerStyle.moss)
                            .frame(width: 34, height: 34)
                            .background(PlannerStyle.moss.opacity(0.08), in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Workout history")
                    .accessibilityHint("Shows all saved workouts")
                    .accessibilityIdentifier("progressHistory")
                }.textCase(nil)
            }.listRowBackground(PlannerStyle.surface)
            ForEach(metrics.routineGroups) { group in
                Section {
                    ForEach(group.exercises) { exercise in
                        Group {
                            if exercise.records.isEmpty {
                                ExerciseRecordRow(exercise: exercise, unit: currentUnit)
                                    .accessibilityElement(children: .combine)
                            } else {
                                NavigationLink {
                                    if exercise.records.count == 1, let record = exercise.records.first {
                                        RecordDetail(record: record, unit: currentUnit)
                                    } else {
                                        List {
                                            ForEach(Array(exercise.records.enumerated()), id: \.element.id) { index, record in
                                                NavigationLink { RecordDetail(record: record, unit: currentUnit) } label: {
                                                    RecordOverviewValue(record: record, unit: currentUnit, series: index + 1)
                                                }
                                            }
                                        }.navigationTitle(exercise.prescription.name)
                                            .scrollContentBackground(.hidden).background(PlannerStyle.paper)
                                    }
                                } label: { ExerciseRecordRow(exercise: exercise, unit: currentUnit) }
                            }
                        }
                        .accessibilityIdentifier("progressExerciseRecord-" + exercise.prescription.name)
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 14))
                        .listRowSeparator(.hidden)
                        .listRowBackground(RoundedRectangle(cornerRadius: 17).fill(PlannerStyle.surface)
                            .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(PlannerStyle.rule.opacity(0.28)) }
                            .padding(.vertical, 3))
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 12) {
                        if group.id == metrics.routineGroups.first?.id {
                            Text("Exercise progress").font(.title3.bold()).foregroundStyle(.primary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Text(group.name).font(.headline).foregroundStyle(PlannerStyle.moss)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("progressExerciseMuscle-" + group.name)
                    }.textCase(nil)
                }
            }
            if metrics.routineGroups.isEmpty {
                Section("Exercise progress") {
                    Text("Your routine’s exercises will appear here.").foregroundStyle(.secondary)
                }
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
        .task { catalog = (try? ExerciseCatalog.bundled().entries) ?? [] }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProgressSettings(unit: unit, setUnit: setUnit, recovery: recovery)
                } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("progressSettings")
            }
        }
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
        let peak = days.map { $0.sessions.count }.max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Chart(days.indices, id: \.self) { index in
                let day = days[index]
                // Marks, ticks and touch selection share the center of each day's slot.
                BarMark(x: .value("Day slot", Double(index)), y: .value("Finished sessions", day.sessions.count), width: .fixed(22))
                    .cornerRadius(3).foregroundStyle(PlannerStyle.moss)
                    .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue("\(day.sessions.count) finished sessions")
            }
            .chartXScale(domain: -0.5...(Double(days.count) - 0.5))
            .chartYScale(domain: 0...max(1, peak))
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
            .frame(height: 104)
            .padding(.bottom, 26)
            .accessibilityIdentifier("progressActivityChart")
            if let index = selectedIndex {
                let selected = days[index]
                VStack(alignment: .leading, spacing: 8) {
                    Text(selected.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.caption.weight(.semibold)).foregroundStyle(PlannerStyle.moss)
                        .accessibilityIdentifier("progressSelectedDate")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: select(dayAt: index + 1)
                            case .decrement: select(dayAt: index - 1)
                            @unknown default: break
                            }
                        }
                    if peak > 0 && selected.sessions.isEmpty {
                        Text("No sessions logged.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(selected.sessions.prefix(2).enumerated()), id: \.element.id) { index, session in
                        NavigationLink { ProgressSession(store: store, id: session.id, unit: unit) } label: {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { sessionSummary(session, showTime: selected.sessions.count > 1) }
                                VStack(alignment: .leading, spacing: 4) { sessionSummary(session, showTime: selected.sessions.count > 1) }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("progressDaySession\(index)")
                    }
                    if selected.sessions.count > 2 {
                        NavigationLink {
                            List {
                                ForEach(selected.sessions) { session in
                                    NavigationLink { ProgressSession(store: store, id: session.id, unit: unit) } label: { sessionLabel(session) }
                                }
                            }.navigationTitle(selected.date.formatted(.dateTime.month(.abbreviated).day()))
                        } label: {
                            Label("View all \(selected.sessions.count) sessions", systemImage: "list.bullet")
                                .font(.subheadline.weight(.medium)).foregroundStyle(PlannerStyle.moss)
                                .frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityIdentifier("progressDayHistory")
                    }
                }
            }
        }.padding(.vertical, 6)
    }

    @ViewBuilder private func sessionSummary(_ session: TrainingSession, showTime: Bool) -> some View {
        Text(session.name).font(.headline)
        if session.partial { Text("Partial").font(.caption).foregroundStyle(.secondary) }
        if showTime { Text(session.startedAt, style: .time).font(.caption).foregroundStyle(.secondary) }
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
        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened) + (session.isArchivedDraft ? " · Draft" : (session.partial ? " · Partial" : "")))
            .font(.subheadline).foregroundStyle(.secondary)
    }
}

private func progressResult(_ point: ProgressSet, unit: String) -> String {
    [point.kg.map { weightText($0, unit) }, point.reps.map { "\($0) reps" }, point.seconds.map { "\($0) sec" }]
        .compactMap { $0 }.joined(separator: " · ")
}

func weightText(_ kg: Double, _ unit: String) -> String {
    "\(weightNumber(kg, unit)) \(unit)"
}

private func weightNumber(_ kg: Double, _ unit: String) -> String {
    WeightUnits.convert(kg, from: "kg", to: unit).formatted(.number.precision(.fractionLength(0...3)))
}

func recordContext(_ record: ExerciseRecords) -> String {
    let name: String = switch record.basis {
    case .external: "Weight"
    case .barbell: "Total barbell weight"
    case .dumbbell: "Per dumbbell"
    case .machine: "Machine setting"
    case .bodyweight: "Bodyweight"
    case .added: "Added weight"
    case .assisted: "Assistance"
    case .unilateral: "Per side"
    case .timed: "Duration"
    }
    return [name, record.side?.capitalized].compactMap { $0 }.joined(separator: " · ")
}

private struct ExerciseRecordRow: View {
    let exercise: RoutineExerciseProgress
    let unit: String
    var body: some View {
        HStack(spacing: 12) {
            CatalogThumbnail(media: exercise.catalogEntry?.media.first)
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(PlannerStyle.rule.opacity(0.32)) }
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.prescription.name).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if exercise.records.isEmpty {
                    RecordMeasurement(point: nil, basis: LoadBasis(exercise.prescription), unit: unit)
                } else {
                    ForEach(Array(exercise.records.enumerated()), id: \.element.id) { index, record in
                        RecordOverviewValue(record: record, unit: unit, series: exercise.records.count > 1 ? index + 1 : nil)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6)
    }
}

private struct RecordOverviewValue: View {
    let record: ExerciseRecords
    let unit: String
    let series: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let series {
                let name = recordContext(record)
                Text(record.id.machineProfile == nil ? name : "\(name) · Profile \(series)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RecordMeasurement(point: record.overviewResult, basis: record.basis, unit: unit)
        }
    }
}

private struct RecordMeasurement: View {
    let point: ProgressSet?
    let basis: LoadBasis
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) { measurement }
                VStack(alignment: .leading, spacing: 1) { measurement }
            }
            Group {
                if let point { Text(point.date, format: .dateTime.month(.abbreviated).day().year()) }
                else { Text("N/A").accessibilityLabel("Date unavailable") }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var measurement: some View {
        let value: String? = switch basis {
        case .bodyweight: point?.reps?.formatted()
        case .timed: point?.seconds?.formatted()
        default: point?.kg.map { weightNumber($0, unit) }
        }
        let qualifier: String = switch basis {
        case .bodyweight: "reps"
        case .timed: "sec"
        case .dumbbell where value != nil: "\(unit) per dumbbell"
        case .machine where value != nil: "\(unit) on machine"
        case .added where value != nil: "\(unit) added"
        case .assisted where value != nil: "\(unit) latest assistance"
        default: value == nil && unit == "lb" ? "lbs" : unit
        }
        Text(value ?? "N/A").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(PlannerStyle.moss)
            .accessibilityLabel(value ?? "No result logged")
        Text(qualifier).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .accessibilityLabel(qualifier == "lbs" ? "pounds" : qualifier)
    }
}

struct ExerciseTrendPlot: View {
    private static let height: CGFloat = 160
    let record: ExerciseRecords
    let unit: String

    var measure: String {
        switch record.basis {
        case .timed: "Longest working set · seconds"
        case .bodyweight: "Most reps in a working set"
        case .assisted: "Latest working set assistance · \(unit)"
        default: "Heaviest working set · \(unit)"
        }
    }

    private static func chart(points: [ExerciseWorkoutPoint], basis: LoadBasis, unit: String, measure: String) -> some View {
        Chart(points) { point in
            let value = trendValue(point, basis: basis, unit: unit)
            if let y = value, y.isFinite {
                if points.count > 1 {
                    LineMark(x: .value("Workout", point.date), y: .value(measure, y))
                        .accessibilityHidden(true)
                }
                PointMark(x: .value("Workout", point.date), y: .value(measure, y))
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue(progressResult(point.result, unit: unit))
            }
        }
        .foregroundStyle(PlannerStyle.moss)
    }

    var body: some View {
        let points = record.workoutPoints
        Self.chart(points: points, basis: record.basis, unit: unit, measure: measure)
            .chartXAxis {
                if points.count > 1 { AxisMarks(values: .automatic(desiredCount: 3)) }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .chartXScale(range: .plotDimension(padding: 5))
            .frame(height: Self.height)
    }
}

private func trendValue(_ point: ExerciseWorkoutPoint, basis: LoadBasis, unit: String) -> Double? {
    switch basis {
    case .timed: point.result.seconds.map(Double.init)
    case .bodyweight: point.result.reps.map(Double.init)
    default: point.result.kg.map { WeightUnits.convert($0, from: "kg", to: unit) }
    }
}

struct CatalogWorkoutTrend: View {
    private static let scaleGutter: CGFloat = 26
    let points: [ExerciseWorkoutPoint]
    let basis: LoadBasis
    let unit: String

    @ScaledMetric(relativeTo: .caption2) private var chartHeight: CGFloat = 104
    @ScaledMetric(relativeTo: .caption2) private var monthLabelWidth: CGFloat = 25
    @ScaledMetric(relativeTo: .caption2) private var monthLabelHeight: CGFloat = 20
    @State private var selectedID: UUID?

    private struct Point: Identifiable {
        let workout: ExerciseWorkoutPoint
        let value: Double
        let monthPosition: Double
        var id: UUID { workout.id }
        var date: Date { workout.date }
    }

    private struct PointCenters: PreferenceKey {
        static var defaultValue: [UUID: CGPoint] { [:] }
        static func reduce(value: inout [UUID: CGPoint], nextValue: () -> [UUID: CGPoint]) {
            value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
        }
    }

    private var axisTitle: String {
        switch basis {
        case .timed: "Time (seconds)"
        case .bodyweight: "Reps"
        case .assisted: "Assistance (\(unit))"
        default: "Weight (\(unit))"
        }
    }

    var body: some View {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let start = calendar.dateInterval(of: .year, for: today)?.start ?? today
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let visible = points.compactMap { point -> Point? in
            guard point.date >= start, point.date < endOfToday,
                  let value = trendValue(point, basis: basis, unit: unit), value.isFinite,
                  let month = calendar.dateInterval(of: .month, for: point.date) else { return nil }
            // Every month gets the same width, with each workout placed within its own month.
            let index = calendar.component(.month, from: point.date) - 1
            let fraction = point.date.timeIntervalSince(month.start) / month.duration
            return Point(workout: point, value: value, monthPosition: Double(index) + fraction)
        }
        let scale = scaleValues(for: visible)
        let selected = visible.first { $0.id == selectedID }
        VStack(alignment: .leading, spacing: 5) {
            Text(axisTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let plotWidth = max(0, geometry.size.width - Self.scaleGutter)
                chart(visible, scale: scale, yearStart: start, ticks: monthTicks(width: plotWidth), calendar: calendar)
                    .frame(height: chartHeight - monthLabelHeight)
                    .padding(.bottom, monthLabelHeight)
                    .accessibilityLabel("Workout trend")
                    .accessibilityIdentifier("exerciseWorkoutTrend")
            }
            .frame(height: chartHeight)
            if let selected {
                Text("\(selected.date.formatted(date: .abbreviated, time: .omitted)) · \(progressResult(selected.workout.result, unit: unit))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PlannerStyle.ochre)
                    .accessibilityIdentifier("exerciseTrendSelection")
            }
        }
    }

    private func chart(_ points: [Point], scale: [Double], yearStart: Date,
                       ticks: [Double], calendar: Calendar) -> some View {
        let baseline = scale[0]
        let monthFormat = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated)
        return Chart(points) { point in
            if points.count > 1 {
                AreaMark(x: .value("Month position", point.monthPosition), yStart: .value("Baseline", baseline), yEnd: .value(axisTitle, point.value))
                    .foregroundStyle(PlannerStyle.moss.opacity(0.12))
                    .accessibilityHidden(true)
                LineMark(x: .value("Month position", point.monthPosition), y: .value(axisTitle, point.value))
                    .foregroundStyle(PlannerStyle.moss)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
            }
            PointMark(x: .value("Month position", point.monthPosition), y: .value(axisTitle, point.value))
                .foregroundStyle(point.id == selectedID ? PlannerStyle.ochre : PlannerStyle.moss)
                .symbolSize(point.id == selectedID ? 50 : 24)
                .accessibilityHidden(true)
        }
        .chartXScale(domain: 0.0...12.0, range: .plotDimension(padding: 4))
        .chartYScale(domain: baseline...scale[3], range: .plotDimension(padding: 4))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: scale) { tick in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(PlannerStyle.rule)
                if let value = tick.as(Double.self) {
                    AxisValueLabel {
                        Text(value, format: .number.precision(.fractionLength(0...2)))
                            .font(.caption2).monospacedDigit().foregroundStyle(PlannerStyle.ink.opacity(0.65))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    ForEach(ticks, id: \.self) { position in
                        if let x = proxy.position(forX: position),
                           let month = calendar.date(byAdding: .month, value: Int(position), to: yearStart) {
                            Text(month, format: monthFormat)
                                .font(.caption2.monospaced()).foregroundStyle(PlannerStyle.ink.opacity(0.65))
                                .fixedSize()
                                .position(x: frame.minX + x, y: frame.maxY + monthLabelHeight / 2)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    let centers = points.reduce(into: [UUID: CGPoint]()) { centers, point in
                        if let x = proxy.position(forX: point.monthPosition), let y = proxy.position(forY: point.value) {
                            centers[point.id] = CGPoint(x: frame.minX + x, y: frame.minY + y)
                        }
                    }
                    Color.clear.preference(key: PointCenters.self, value: centers)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        .overlayPreferenceValue(PointCenters.self) { centers in
            if !centers.isEmpty { selectionOverlay(points, centers: centers) }
        }
        .accessibilityElement(children: .contain)
    }

    private func selectionOverlay(_ points: [Point], centers: [UUID: CGPoint]) -> some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(points) { point in
                    if let center = centers[point.id] {
                        pointButton(point)
                            .position(x: clampedCenter(center.x, within: geometry.size.width),
                                      y: clampedCenter(center.y, within: geometry.size.height))
                    }
                }
                // Keep focusable buttons separate from Charts' virtual accessibility marks.
                // Physical taps choose the nearest dot even when targets overlap.
                Color.clear.contentShape(Rectangle())
                    .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                        let nearest = points.compactMap { point -> (id: UUID, distance: CGFloat)? in
                            guard let center = centers[point.id] else { return nil }
                            return (point.id, hypot(center.x - tap.location.x, center.y - tap.location.y))
                        }.min { $0.distance < $1.distance }
                        selectedID = nearest.flatMap { $0.distance <= 32 ? $0.id : nil }
                    })
                    .accessibilityHidden(true)
            }
        }
    }

    private func pointButton(_ point: Point) -> some View {
        Button {
            selectedID = point.id
        } label: {
            Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
        .accessibilityValue(progressResult(point.workout.result, unit: unit))
        .accessibilityAddTraits(point.id == selectedID ? .isSelected : [])
        .accessibilityIdentifier("exerciseTrendPoint")
    }

    private func clampedCenter(_ coordinate: CGFloat, within size: CGFloat) -> CGFloat {
        let halfTarget = min(22, size / 2)
        return min(max(coordinate, halfTarget), size - halfTarget)
    }

    private func monthTicks(width: CGFloat) -> [Double] {
        let count = min(12, max(2, Int(width / monthLabelWidth)))
        return (0..<count).map { Double($0 * 11 / (count - 1)) + 0.5 }
    }

    private func scaleValues(for points: [Point]) -> [Double] {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else {
            let step: Double = switch basis {
            case .timed: 20
            case .bodyweight: 5
            default: unit == "kg" ? 25 : 50
            }
            return (0...3).map { Double($0) * step }
        }
        let roughStep = max((high - low) / 3, high * 0.08, 1)
        let magnitude = pow(10, floor(log10(roughStep)))
        for multiple in [1.0, 2, 2.5, 5, 10, 20] {
            let step = multiple * magnitude
            guard step.isFinite, step >= roughStep else { continue }
            let first = max(0, floor(low / step) * step)
            let last = first + 3 * step
            if last.isFinite, last >= high {
                return (0...3).map { first + Double($0) * step }
            }
        }
        return (0...3).map { (Double($0) / 3) * high }
    }
}

struct RecordDetail: View {
    let record: ExerciseRecords
    let unit: String
    var body: some View {
        List {
            Section("Workout trend") {
                let chart = ExerciseTrendPlot(record: record, unit: unit)
                VStack(alignment: .leading, spacing: 10) {
                    Text(chart.measure).font(.subheadline.weight(.medium))
                    chart.accessibilityIdentifier("exerciseWorkoutTrend")
                    if record.workoutPoints.count == 1 {
                        Text("One logged session").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                ForEach(record.workoutPoints.reversed()) { point in
                    LabeledContent(point.date.formatted(date: .abbreviated, time: .shortened),
                                   value: progressResult(point.result, unit: unit))
                }
            }
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
                ForEach(record.trend.reversed(), id: \.id) { point in
                    LabeledContent(point.date.formatted(date: .abbreviated, time: .shortened), value: progressResult(point, unit: unit))
                }
            }
        }.navigationTitle(record.name)
            .scrollContentBackground(.hidden).background(PlannerStyle.paper)
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
                    LabeledContent("Status", value: session.isArchivedDraft ? "Closed draft" : (session.partial ? "Partial" : "Finished"))
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
                if (session.isArchivedDraft || session.closedAtWeekBoundary == true),
                   let draft = session.cardioDraft, draft != session.cardio {
                    Section("Unconfirmed cardio") {
                        if draft.seconds > 0 {
                            LabeledContent("Activity duration", value: elapsedString(TimeInterval(draft.seconds)))
                        }
                        if let distance = draft.distance { LabeledContent("Distance", value: "\(distance.formatted()) \(draft.unit)") }
                        if !draft.notes.isEmpty { Text(draft.notes) }
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
                            } else if (session.isArchivedDraft || session.closedAtWeekBoundary == true), row.revision > 0 {
                                let result = actualDescription(row.actual.converted(to: unit), basis: exercise.basis)
                                if !result.isEmpty {
                                    LabeledContent("Unconfirmed set \(row.ordinal ?? i + 1)", value: result)
                                }
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
                    let weightLabel = switch exercise.basis {
                    case .assisted: "Assistance"
                    case .unilateral: "Left weight"
                    default: "Weight"
                    }
                    CorrectionField("\(weightLabel) (\(actual.unit))") {
                        TextField(weightLabel, value: $actual.load, format: .number).keyboardType(.decimalPad).accessibilityIdentifier("correctLoad")
                    }
                }
                if exercise.basis == .unilateral {
                    CorrectionField("Right reps") { TextField("Right reps", value: $actual.rightReps, format: .number).keyboardType(.numberPad) }
                    CorrectionField("Right weight (\(actual.unit))") { TextField("Right weight", value: $actual.rightLoad, format: .number).keyboardType(.decimalPad) }
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
