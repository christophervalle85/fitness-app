import SwiftUI

/// Explicit links let extra activity count toward a chosen date without changing when it happened.
struct AssignTrainingWork: View {
    let sessionID: UUID
    let training: TrainingStore
    let plan: WeekPlan?
    @State private var date = Date.now
    @State private var chosenSet: UUID?
    @State private var feedback: String?

    private var session: TrainingSession? { training.sessions.first { $0.id == sessionID } }

    var body: some View {
        List {
            if let session {
                if !session.isCardio {
                    Section("Choose a logged set") {
                        ForEach(session.exercises) { exercise in
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { i, row in
                                if row.confirmedAt != nil, row.warmup != true, row.plannedID == nil {
                                    Button {
                                        chosenSet = row.id
                                        feedback = nil
                                    } label: {
                                        HStack {
                                            Text("\(exercise.prescription.name) · set \(i + 1)")
                                            Spacer()
                                            if row.id == chosenSet { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (session.isCardio && session.occurrenceID == nil) || chosenSet != nil {
                    Section("Planned date") {
                        if let linked = training.occurrences.first(where: { $0.id == session.occurrenceID }) {
                            Text(linked.date.formatted(date: .complete, time: .omitted))
                        } else {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                        }
                    }
                    let existing = training.occurrences.filter {
                        session.occurrenceID == nil ? training.isScheduled($0, on: date) : $0.id == session.occurrenceID
                    }.filter { !$0.skipped && ($0.cardioGoalSeconds != nil) == session.isCardio }
                    ForEach(existing) { item in
                        Section(item.name) {
                            if session.isCardio {
                                Button("Credit confirmed duration") {
                                    apply { try training.assign(sessionID: sessionID, occurrenceID: item.id, setID: nil, plannedSetID: nil) }
                                }
                            } else if let day = item.day {
                                choices(day: day, session: session, occurrence: item)
                            }
                        }
                    }
                    let index = (Calendar.current.component(.weekday, from: date) + 5) % 7
                    if let plan, session.occurrenceID == nil, plan.days.indices.contains(index),
                       !training.occurrences.contains(where: { $0.planID == plan.id && training.isOriginal($0, on: date) }),
                       plan.days[index].isWorkout, (plan.days[index].cardioGoalSeconds != nil) == session.isCardio {
                        let day = plan.days[index]
                        Section(day.name) {
                            if session.isCardio {
                                Button("Credit confirmed duration") {
                                    apply { try training.assign(sessionID: sessionID, plan: plan, date: date, setID: nil, exerciseID: nil, slot: nil) }
                                }
                            } else {
                                choices(day: day, session: session, occurrence: nil)
                            }
                        }
                    } else if existing.isEmpty {
                        Text("No matching workout on this date.").foregroundStyle(.secondary)
                    }
                }
                if let feedback { Section { Text(feedback) } }
            }
        }.navigationTitle("Assign to plan")
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
    }

    @ViewBuilder private func choices(day: PlanDay, session: TrainingSession, occurrence: TrainingOccurrence?) -> some View {
        let source = session.exercises.first { exercise in exercise.sets.contains { $0.id == chosenSet } }
        let matches = day.exercises.filter { source?.matchesPlannedItem($0) == true }
        if matches.isEmpty { Text("This workout has no matching prescribed exercise.").foregroundStyle(.secondary) }
        ForEach(matches) { exercise in
            ForEach(0..<exercise.sets, id: \.self) { index in
                if let occurrence {
                    if let ids = occurrence.plannedSets[exercise.id], ids.indices.contains(index),
                       training.remainingSetIDs(for: occurrence).contains(ids[index]) {
                        Button("Credit \(exercise.name) · set \(index + 1)") {
                            apply { try training.assign(sessionID: sessionID, occurrenceID: occurrence.id, setID: chosenSet, plannedSetID: ids[index]) }
                        }
                    }
                } else if let plan {
                    Button("Credit \(exercise.name) · set \(index + 1)") {
                        apply { try training.assign(sessionID: sessionID, plan: plan, date: date, setID: chosenSet, exerciseID: exercise.id, slot: index) }
                    }
                }
            }
        }
    }

    private func apply(_ operation: () throws -> Void) {
        do {
            try operation()
            chosenSet = nil
            feedback = "Planned work updated."
        } catch { feedback = error.localizedDescription }
    }
}
