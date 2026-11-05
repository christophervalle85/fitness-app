import SwiftUI

// An abstract folded training sheet, drawn with the system's scalable paths.
private struct WeekMark: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 306, size.height / 118)
            for index in 0..<7 {
                let x = CGFloat(index) * 40 * unit
                let y = CGFloat(abs(3 - index)) * 8 * unit
                var page = Path()
                page.move(to: .init(x: x, y: y + 24 * unit))
                page.addLine(to: .init(x: x + 40 * unit, y: y))
                page.addLine(to: .init(x: x + 40 * unit, y: y + 72 * unit))
                page.addLine(to: .init(x: x, y: y + 96 * unit))
                page.closeSubpath()
                context.fill(page, with: .color(PlannerStyle.blue.opacity(index == 3 ? 1 : 0.18 + Double(index % 3) * 0.12)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct WelcomeScreen<Recovery: View>: View {
    let manual: () -> Void
    let starters: () -> Void
    @ViewBuilder var recovery: () -> Recovery

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Weekform", systemImage: "square.stack.3d.up.fill")
                    .font(.headline).foregroundStyle(PlannerStyle.blue)
                WeekMark().frame(height: 124).padding(.vertical, 24)
                Text("Plan your\ntraining week.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose your workout days, exercises, and rest days. You can adjust your week as you train.")
                    .font(.body).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    Button(action: manual) {
                        Label("Build my routine", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("buildRoutine")
                    Button(action: starters) {
                        Label("Choose a starter", systemImage: "rectangle.stack").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("chooseStarter")
                    NavigationLink("Restore a backup", destination: recovery)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("welcomeRecovery")
                }
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(PlannerStyle.paper)
    }
}

struct StarterPicker: View {
    let select: (WeekPlan) -> Void
    let back: () -> Void
    #if WEEKFORM_DEVELOPMENT
    @State private var privatePlan: WeekPlan?
    @State private var fixtureError = false
    #endif
    var body: some View {
        List {
            #if WEEKFORM_DEVELOPMENT
            if let privatePlan {
                Section("Development") {
                    starter(privatePlan, detail: "6 training days · Machines and free weights", id: "localStarter")
                }
            } else if fixtureError {
                Text("The local starter could not be opened. Check its development file and rebuild.")
            }
            #endif
            Section("Starter routines") {
                starter(Starters.general(), detail: "3 training days · Editable strength template", id: "starterGeneral")
            }
        }
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle("Choose a starter")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Back", action: back) } }
        #if WEEKFORM_DEVELOPMENT
        .task { do { privatePlan = try Starters.local() } catch { fixtureError = true } }
        #endif
    }

    private func starter(_ plan: WeekPlan, detail: String, id: String) -> some View {
        Button { select(plan) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").accessibilityHidden(true)
            }.padding(.vertical, 8)
        }.accessibilityIdentifier(id)
    }
}

struct ReviewWeek: View {
    let plan: WeekPlan
    let editingExisting: Bool
    let goBack: () -> Void
    let save: () -> Void

    var body: some View {
        List {
            Section {
                Text(plan.name).font(.title2.bold())
                LabeledContent("Rest between sets", value: plan.restSeconds.map { "\($0) seconds" } ?? "No timer")
            }
            ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                Section(PlannerStyle.weekdays[index]) {
                    if let seconds = day.cardioGoalSeconds {
                        LabeledContent(day.name, value: "\(seconds / 60) min cardio")
                    } else if day.exercises.isEmpty {
                        Text("Rest day").foregroundStyle(.secondary)
                    } else {
                        DisclosureGroup(day.name) {
                            ForEach(day.exercises) { row in
                                VStack(alignment: .leading) {
                                    Text(row.name)
                                    Text(prescription(row)).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle("Review your week")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Back", action: goBack) } }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) { Text(editingExisting ? "Save changes" : "Save and use routine").frame(maxWidth: .infinity) }
                .controlSize(.large).buttonStyle(.borderedProminent).padding()
                .background(.regularMaterial).accessibilityIdentifier("confirmRoutine")
        }
    }
}

func prescription(_ row: PlanExercise) -> String {
    let range = row.low == row.high ? "\(row.low)" : "\(row.low)–\(row.high)"
    var parts = ["\(row.sets) × \(range) \(row.timed ? "sec" : "reps")"]
    if let load = row.startingLoad {
        parts.append("\(load.formatted(.number.precision(.fractionLength(0...3)))) \(row.loadUnit)")
    }
    if !row.convention.isEmpty { parts.append(row.convention) }
    return parts.joined(separator: " · ")
}
