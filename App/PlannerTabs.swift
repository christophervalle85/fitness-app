import SwiftUI

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
                        Text(plan.name).font(.system(.title, design: .serif, weight: .medium))
                        HStack(spacing: 4) {
                            ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                                VStack(spacing: 4) {
                                    Text(String(PlannerStyle.weekdays[index].prefix(1))).font(.caption2)
                                    Capsule().fill(day.isWorkout ? PlannerStyle.moss : PlannerStyle.rule).frame(height: 5)
                                }.frame(maxWidth: .infinity)
                            }
                        }.accessibilityElement(children: .ignore)
                            .accessibilityLabel(plan.days.enumerated().compactMap { $0.element.isWorkout ? PlannerStyle.weekdays[$0.offset] : nil }.joined(separator: ", "))
                        Text("\(plan.days.filter(\.isWorkout).count) training days per week")
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
