import SwiftUI

struct WelcomeScreen<Recovery: View>: View {
    let manual: () -> Void
    let starters: () -> Void
    @ViewBuilder var recovery: () -> Recovery

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Weekform")
                    .font(.headline).foregroundStyle(PlannerStyle.blue)
                Image("WeekformMark").resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true).padding(.vertical, 12)
                Text("Plan your\ntraining week.")
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
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

struct NewRoutineScreen: View {
    let manual: () -> Void
    let preset: (WeekPlan) -> Void

    var body: some View {
        List {
            Section {
                Button(action: manual) {
                    HStack(spacing: 8) {
                        choice("Start from scratch", detail: "Choose your days and add exercises.", icon: "plus")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("startFromScratch")
                NavigationLink {
                    StarterPicker(select: preset, title: "Choose a preset", sectionTitle: "Preset routines")
                } label: {
                    choice("Use a preset", detail: "Customize an existing weekly routine.", icon: "rectangle.stack")
                }.accessibilityIdentifier("usePreset")
            }
        }
        .navigationTitle("New routine")
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
    }

    private func choice(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(PlannerStyle.moss)
                .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 12).frame(minHeight: 44)
    }
}

struct StarterPicker: View {
    let select: (WeekPlan) -> Void
    var back: (() -> Void)? = nil
    var title: String = "Choose a starter"
    var sectionTitle: String = "Starter routines"
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
            Section(sectionTitle) {
                starter(Starters.general(), detail: "3 training days · Editable strength template", id: "starterGeneral")
            }
        }
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle(title)
        .toolbar { if let back { ToolbarItem(placement: .topBarLeading) { Button("Back", action: back) } } }
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
    var additionalRoutine = false
    @Binding var activateNew: Bool
    let goBack: () -> Void
    let save: () -> Void

    @State private var selection = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(plan.name).font(.system(.largeTitle, design: .serif, weight: .medium))
                Text("\(plan.days.filter(\.isWorkout).count) training days per week")
                    .font(.headline).foregroundStyle(PlannerStyle.moss)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: typeSize.isAccessibilitySize ? 4 : 7)) {
                    ForEach(plan.days.indices, id: \.self) { index in
                        let day = plan.days[index]
                        Button { selection = index } label: {
                            VStack(spacing: 7) {
                                Text(String(PlannerStyle.weekdays[index].prefix(2))).font(.caption.bold())
                                Image(systemName: day.cardioGoalSeconds != nil ? "figure.run" : (day.isWorkout ? "dumbbell.fill" : "minus"))
                                    .font(.subheadline)
                            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                                .foregroundStyle(index == selection ? Color(uiColor: .systemBackground) : PlannerStyle.moss)
                                .background(index == selection ? PlannerStyle.moss : PlannerStyle.moss.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityIdentifier("reviewDay\(index)")
                        .accessibilityLabel(PlannerStyle.weekdays[index] + ", " + (day.isWorkout ? day.name : "Rest day"))
                        .accessibilityAddTraits(index == selection ? .isSelected : [])
                    }
                }
                if plan.days.indices.contains(selection) {
                    let day = plan.days[selection]
                    VStack(alignment: .leading, spacing: 14) {
                        Text(PlannerStyle.weekdays[selection]).font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss)
                        Text(day.isWorkout ? day.name : "Rest day").font(.system(.title2, design: .serif, weight: .medium))
                        if let seconds = day.cardioGoalSeconds { Label("\(seconds / 60) min cardio", systemImage: "figure.run") }
                        ForEach(Array(day.exercises.enumerated()), id: \.element.id) { offset, row in
                            Divider()
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(offset + 1)").font(.headline.monospacedDigit()).foregroundStyle(PlannerStyle.ochre)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.name).font(.headline)
                                    Text(prescription(row)).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                if additionalRoutine && !editingExisting {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use as my active routine", isOn: $activateNew)
                            .accessibilityIdentifier("activateNewRoutine")
                        Text("When off, your active routine stays unchanged.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(18).background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                Label(plan.restSeconds.map { "\($0)s between sets" } ?? "Rest timer off", systemImage: "timer")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(PlannerStyle.paper)
        .navigationTitle("Review your week")
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Back", action: goBack) } }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) { Text(editingExisting ? "Save changes" : (additionalRoutine && !activateNew ? "Save routine" : "Save and use routine")).frame(maxWidth: .infinity) }
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
