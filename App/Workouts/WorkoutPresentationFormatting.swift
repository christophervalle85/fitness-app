import Foundation

func elapsedString(_ interval: TimeInterval) -> String {
    guard interval.isFinite, interval > 0 else { return "0:00" }
    let seconds = Int(exactly: interval.rounded(.down)) ?? Int.max
    let remainder = seconds % 60
    return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
}

func setTitle(_ row: TrainingSet, index: Int) -> String {
    let ordinal = row.ordinal ?? (index + 1)
    if row.warmup == true { return "Warm-up · Set \(ordinal)" }
    return row.optional == true ? "Extra working set \(ordinal)" : "Set \(ordinal)"
}

func basisTitle(_ basis: LoadBasis) -> String {
    switch basis {
    case .external: "Reps and weight"
    case .added: "Added weight"
    default: basisConvention(basis)
    }
}

func basisConvention(_ basis: LoadBasis) -> String {
    switch basis {
    case .external: "External load"
    case .barbell: "Barbell total"
    case .dumbbell: "Per dumbbell"
    case .machine: "Machine setting"
    case .bodyweight: "Bodyweight"
    case .added: "Added load"
    case .assisted: "Assistance"
    case .unilateral: "Separate sides"
    case .timed: "Duration"
    }
}

func actualDescription(_ actual: SetActual, basis: LoadBasis) -> String {
    func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...3))) }
    if basis == .unilateral {
        let left = [actual.reps.map { "\($0) reps" }, actual.load.map { "\(number($0)) \(actual.unit)" }].compactMap { $0 }.joined(separator: " × ")
        let right = [actual.rightReps.map { "\($0) reps" }, actual.rightLoad.map { "\(number($0)) \(actual.unit)" }].compactMap { $0 }.joined(separator: " × ")
        return "Left \(left) · Right \(right)"
    }
    var components: [String] = []
    if let reps = actual.reps, basis != .timed { components.append("\(reps) reps") }
    if let seconds = actual.seconds, basis == .timed { components.append("\(seconds) sec") }
    if basis != .bodyweight, let load = actual.load {
        let weight = "\(number(load)) \(actual.unit)"
        switch basis {
        case .external, .timed: components.append(weight)
        default: components.append("\(weight) · \(basisTitle(basis).lowercased())")
        }
    }
    return components.joined(separator: " × ")
}
