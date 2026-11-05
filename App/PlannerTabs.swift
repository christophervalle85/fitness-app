import SwiftUI

struct TodayScreen: View {
    let plan: WeekPlan?
    let showRoutines: () -> Void
    @State private var selected = Date.now
    private var calendar: Calendar { .autoupdatingCurrent }
    private var weekday: Int { (calendar.component(.weekday, from: selected) + 5) % 7 }
    private var week: [Date] {
        let start = calendar.startOfDay(for: selected)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - weekday, to: start) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DatePicker("Selected date", selection: $selected, displayedComponents: .date)
                    .datePickerStyle(.compact)
                if let plan, plan.days.count == 7 {
                    weekStrip
                    let day = plan.days[weekday]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.name).font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.blue)
                        Text(day.exercises.isEmpty ? "Rest day" : day.name)
                            .font(.system(.title, design: .rounded, weight: .bold))
                        if !day.exercises.isEmpty {
                            Text("\(day.exercises.count) exercises · \(day.exercises.reduce(0) { $0 + $1.sets }) planned sets")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if day.exercises.isEmpty {
                        Label("No workout scheduled for this day.", systemImage: "moon.zzz").foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(day.exercises) { row in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.name).font(.body.weight(.medium))
                                    Text(prescription(row)).font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 12)
                                if row.id != day.exercises.last?.id { Divider() }
                            }
                        }.padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                } else {
                    ContentUnavailableView("No active routine", systemImage: "calendar", description: Text("Choose a saved routine or build a new week."))
                    Button("Open Routines", action: showRoutines).buttonStyle(.bordered)
                }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .background(PlannerStyle.paper).navigationTitle("Today")
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
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

struct RoutinesScreen: View {
    let plans: [WeekPlan]
    let active: UUID?
    let newPlan: () -> Void
    let edit: (WeekPlan) -> Void
    let activate: (UUID) -> Void
    let duplicate: (UUID) -> Void
    let archive: (UUID) -> Void
    @State private var archiving: WeekPlan?

    var body: some View {
        List {
            if plans.allSatisfy(\.archived) {
                Section { Text("Create a routine to plan your training week.").foregroundStyle(.secondary) }
            }
            ForEach(plans.filter { !$0.archived }) { plan in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if plan.id == active {
                            Label("Active routine", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(PlannerStyle.blue)
                        }
                        Text(plan.name).font(.title3.bold())
                        Text("\(plan.days.filter { !$0.exercises.isEmpty }.count) training days per week")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    Button("Edit routine") { edit(plan) }
                    Menu("Manage routine") {
                        if plan.id != active { Button("Make active") { activate(plan.id) } }
                        Button("Duplicate") { duplicate(plan.id) }
                        Button("Archive", role: .destructive) { archiving = plan }
                    }
                }
            }
            let archived = plans.filter(\.archived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { plan in
                        HStack {
                            Text(plan.name)
                            Spacer()
                            Button("Duplicate") { duplicate(plan.id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Routines").scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .safeAreaInset(edge: .bottom) {
            Button(action: newPlan) { Label("New routine", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).padding()
        }
        .confirmationDialog("Archive this routine?", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }
        ), titleVisibility: .visible, presenting: archiving) { plan in
            Button("Archive routine", role: .destructive) { archive(plan.id) }
        } message: { plan in
            Text("\(plan.name) will move to Archived. Its saved plan is kept.")
        }
    }
}
