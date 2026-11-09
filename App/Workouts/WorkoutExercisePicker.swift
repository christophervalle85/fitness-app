import SwiftUI

extension PlanExercise {
    mutating func selectWorkoutLoadUnit(_ newUnit: String) {
        guard newUnit != loadUnit, ["kg", "lb"].contains(newUnit) else { return }
        if let startingLoad {
            self.startingLoad = newUnit == "kg" ? startingLoad * 0.45359237 : startingLoad / 0.45359237
        }
        loadUnit = newUnit
    }

    mutating func changeWorkoutBasis(from previous: LoadBasis, to next: LoadBasis) {
        guard previous != next else { return }
        startingLoad = nil
        convention = basisConvention(next)
        timed = next == .timed
    }
}

struct WorkoutExercisePicker: View {
    let planner: PlanningStore?
    @State private var browsing = false
    let known: [PlanExercise]
    let replacing: TrainingExercise?
    let save: (PlanExercise, LoadBasis) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected = PlanExercise()
    @State private var basis = LoadBasis.external
    @State private var issue: String?
    @State private var pickedExisting = false
    @State private var initialized = false
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            if let planner {
                Button("Browse exercises") { browsing = true }.accessibilityIdentifier("browseCatalog")
                    .fullScreenCover(isPresented: $browsing) {
                        NavigationStack {
                        CatalogPicker(planner: planner, replacing: replacing?.prescription) { choice in
                            selected = choice
                            basis = LoadBasis(choice)
                            pickedExisting = true
                            browsing = false
                        }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close library") { browsing = false } } }
                        }
                    }
            }
            if !known.isEmpty {
                Section {
                    Menu("Choose a saved exercise") {
                        ForEach(known) { prescription in
                            Button(prescription.name) {
                                selected = prescription
                                basis = LoadBasis(prescription)
                                pickedExisting = true
                            }
                        }
                        if pickedExisting {
                            Button("New custom exercise") { makeCustom() }
                        }
                    }
                }
            }
            Section("Exercise") {
                if pickedExisting {
                    Text(selected.name)
                } else {
                    TextField("Exercise name", text: $selected.name)
                        .focused($focused).accessibilityIdentifier("customName")
                }
                Picker("What to track", selection: Binding(get: { basis }, set: { newBasis in
                    selected.changeWorkoutBasis(from: basis, to: newBasis)
                    basis = newBasis
                })) {
                    ForEach(LoadBasis.allCases, id: \.self) { Text(basisTitle($0)).tag($0) }
                }
                if basis != .bodyweight {
                    Picker("Weight unit", selection: Binding(get: { selected.loadUnit }, set: { unit in
                        selected.selectWorkoutLoadUnit(unit)
                    })) {
                        Text("Pounds").tag("lb")
                        Text("Kilograms").tag("kg")
                    }
                }
            }
            Section("Prescription") {
                if let replacing {
                    let remaining = replacing.sets.filter { $0.confirmedAt == nil }.count
                    LabeledContent("Remaining sets", value: "\(remaining)")
                } else {
                    Stepper("\(selected.sets) working sets", value: $selected.sets, in: 1...99)
                }
                numberInput(basis == .timed ? "Minimum seconds" : "Minimum reps", value: $selected.low)
                numberInput(basis == .timed ? "Maximum seconds" : "Maximum reps", value: $selected.high)
            }
            Section {
                if let issue { Label(issue, systemImage: "exclamationmark.circle").font(.footnote) }
                Button(replacing == nil ? "Add to workout" : "Use for remaining sets") {
                    commit()
                }.accessibilityIdentifier("customSave")
            }
        }
        .navigationTitle(replacing == nil ? "Add exercise" : "Swap exercise")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            if !initialized { makeCustom(); initialized = true }
        }
    }

    private func numberInput(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
        }
    }

    private func makeCustom() {
        var fresh = PlanExercise()
        if let replacing {
            fresh.low = replacing.prescription.low
            fresh.high = replacing.prescription.high
            fresh.loadUnit = replacing.prescription.loadUnit
        }
        selected = fresh
        basis = replacing?.basis ?? .external
        pickedExisting = false
    }

    private func commit() {
        guard !selected.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            issue = "Enter an exercise name."
            focused = true
            return
        }
        guard selected.low > 0 && selected.high >= selected.low else {
            issue = "Enter a positive target range."
            return
        }
        var prescription = selected
        prescription.timed = basis == .timed
        if !pickedExisting || LoadBasis(selected) != basis { prescription.convention = basisConvention(basis) }
        if let replacing { prescription.sets = replacing.sets.filter { $0.confirmedAt == nil }.count }
        do { try save(prescription, basis); dismiss() } catch { issue = error.localizedDescription }
    }
}
