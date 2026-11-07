import SwiftUI

struct RoutinesScreen: View {
    let plans: [WeekPlan]
    let active: UUID?
    let newPlan: () -> Void
    let usePreset: (WeekPlan) -> Void
    let edit: (WeekPlan) -> Void
    let activate: (UUID) -> Void
    let duplicate: (UUID) -> Void
    let archive: (UUID) -> Void
    let delete: (UUID) -> Void
    @State private var archiving: WeekPlan?
    @State private var deleting: WeekPlan?

    var body: some View {
        List {
            if plans.allSatisfy(\.archived) {
                Section { Text("Create a routine to plan your training week.").foregroundStyle(.secondary) }
            }
            ForEach(plans.filter { !$0.archived }) { plan in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if plan.id == active {
                            HStack {
                                Label("Active routine", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(PlannerStyle.blue)
                                Spacer(minLength: 8)
                                routineMenu(plan)
                            }
                        }
                        HStack(alignment: .top) {
                            Text(plan.name).font(.system(.title, design: .serif, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            if plan.id != active {
                                Spacer(minLength: 8)
                                routineMenu(plan)
                            }
                        }
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
                }
            }
            let archived = plans.filter(\.archived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { plan in
                        HStack(alignment: .top) {
                            Text(plan.name).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            routineMenu(plan)
                        }
                    }
                }
            }
        }
        .navigationTitle("Routines")
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                NewRoutineScreen(manual: newPlan, preset: usePreset)
            } label: { Label("New routine", systemImage: "plus").frame(maxWidth: .infinity) }
                .accessibilityIdentifier("newRoutine")
                .buttonStyle(.borderedProminent).controlSize(.large).padding()
        }
        .confirmationDialog("Archive this routine?", isPresented: Binding(
            get: { archiving != nil }, set: { if !$0 { archiving = nil } }
        ), titleVisibility: .visible, presenting: archiving) { plan in
            Button("Archive routine", role: .destructive) { archive(plan.id) }
        } message: { plan in
            Text("\(plan.name) will move to Archived. Its saved plan is kept.")
        }
        .alert("Delete this routine?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { plan in
            Button("Delete routine", role: .destructive) { delete(plan.id) }
                .accessibilityIdentifier("confirmDeleteRoutine")
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text("This permanently deletes \(plan.name) and its repeating schedule. Logged workouts and date-specific schedule entries are kept."
                 + (plan.id == active ? " Plan will have no active routine until you choose one." : ""))
        }
    }

    private func routineMenu(_ plan: WeekPlan) -> some View {
        Menu {
            if !plan.archived {
                Button { edit(plan) } label: { Label("Edit", systemImage: "pencil") }
                    .accessibilityIdentifier("editRoutine")
                if plan.id != active {
                    Button { activate(plan.id) } label: { Label("Make active", systemImage: "checkmark.circle") }
                }
            }
            Button { duplicate(plan.id) } label: { Label("Duplicate", systemImage: "doc.on.doc") }
            if !plan.archived {
                Button(role: .destructive) { archiving = plan } label: { Label("Archive", systemImage: "archivebox") }
            }
            Button(role: .destructive) { deleting = plan } label: { Label("Delete", systemImage: "trash") }
                .accessibilityIdentifier("deleteRoutine")
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("More actions for \(plan.name)")
        .accessibilityIdentifier("routineActions")
    }
}
