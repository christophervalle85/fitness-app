import Foundation

struct WorkoutBackup: Codable, Equatable {
    static let byteLimit = 32 * 1024 * 1024
    var format = "Weekform"
    var version = 1
    var owner: UUID
    var unit: String
    var step: String
    var activeID: UUID?
    var plans: [WeekPlan]
    var draft: WeekPlan?
    var sessions: [TrainingSession]
    var occurrences: [TrainingOccurrence]

    @MainActor init(_ planner: PlanningStore, _ training: TrainingStore) throws {
        guard let owner = planner.profileID else { throw PlanningError("Open your profile first.") }
        self.owner = owner
        unit = planner.weightUnit
        step = planner.step
        activeID = planner.activeID
        plans = planner.plans
        draft = planner.draft
        sessions = training.sessions.sorted { $0.id.uuidString < $1.id.uuidString }
        occurrences = training.occurrences.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func read(_ url: URL) throws -> Self {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let bytes = try file.read(upToCount: byteLimit + 1) ?? Data()
        guard bytes.count <= byteLimit else { throw PlanningError("Choose a backup smaller than 32 MB.") }
        let backup = try JSONDecoder().decode(Self.self, from: bytes)
        try backup.validate()
        return backup
    }

    func encoded() throws -> Data {
        try validate()
        let bytes = try JSONEncoder().encode(self)
        guard bytes.count <= Self.byteLimit else { throw PlanningError("This profile exceeds the 32 MB backup limit.") }
        return bytes
    }

    func validate() throws {
        let invalid = PlanningError("This backup has unsupported values or inconsistent workout records.")
        func check(_ condition: Bool) throws { if !condition { throw invalid } }
        func unique<T: Identifiable>(_ values: [T]) -> Bool { Set(values.map(\.id)).count == values.count }
        func date(_ day: CivilTrainingDay) throws {
            try check((1...9999).contains(day.year) && (1...12).contains(day.month) && (1...31).contains(day.day))
            try check(CivilTrainingDay(day.date) == day)
        }
        func exercise(_ e: PlanExercise) throws {
            try check(e.sets > 0 && e.low > 0 && e.high >= e.low)
        }
        func day(_ value: PlanDay) throws {
            try check(unique(value.exercises))
            for e in value.exercises { try exercise(e) }
            if let goal = value.cardioGoalSeconds { try check(goal > 0) }
        }
        try check(format == "Weekform" && version == 1 && ["kg","lb"].contains(unit))
        try check(["home","edit","starters","review","welcome"].contains(step))
        try check(!["edit","review"].contains(step) || draft != nil)
        try check(unique(plans) && unique(sessions) && unique(occurrences) && sessions.filter { $0.finishedAt == nil }.count <= 1)
        try check(activeID == nil || plans.contains { $0.id == activeID && !$0.archived })
        if let draft { try check(draft.days.count == 7 && unique(draft.days) && draft.days.allSatisfy { unique($0.exercises) }) }
        for plan in plans {
            try check(plan.days.count == 7 && unique(plan.days))
            for value in plan.days { try day(value) }
        }
        for plan in plans { try check(plan.validationMessage == nil) }
        let indexed = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
        var allSlots = Set<UUID>()
        var credited = Set<UUID>()
        var allRows = Set<UUID>()
        var scheduledSources = Set<String>()
        for o in occurrences {
            try date(o.sourceDay); try date(o.scheduledDay)
            if let d = o.day {
                try day(d)
                try check(o.planID != nil && o.cardioGoalSeconds == d.cardioGoalSeconds)
                try check(Set(o.plannedSets.keys) == Set(d.exercises.map(\.id)))
                try check((d.cardioGoalSeconds != nil) == d.exercises.isEmpty)
                let key = "\(o.planID!.uuidString)/\(o.sourceDay.year)/\(o.sourceDay.month)/\(o.sourceDay.day)"
                try check(scheduledSources.insert(key).inserted)
            } else {
                try check(o.planID == nil && o.cardioGoalSeconds != nil && o.plannedSets.isEmpty)
            }
            if let goal = o.cardioGoalSeconds { try check(goal > 0) }
            for (id, slots) in o.plannedSets {
                try check(o.day?.exercises.first(where: { $0.id == id })?.sets == slots.count)
                for slot in slots { try check(allSlots.insert(slot).inserted) }
            }
        }
        func validTimestamp(_ t: Date) -> Bool {
            (-63_113_904_000...252_423_993_599).contains(t.timeIntervalSinceReferenceDate)
        }
        for s in sessions {
            try check(validTimestamp(s.startedAt))
            if let end = s.finishedAt { try check(validTimestamp(end) && end >= s.startedAt) }
            try date(s.performedDay)
            let o = s.occurrenceID.flatMap { indexed[$0] }
            try check(s.occurrenceID == nil || o != nil)
            try check(unique(s.exercises) && (0..<Int.max).contains(s.cardioRevision))
            if let o { try check(s.isCardio == (o.cardioGoalSeconds != nil)) }
            try check(s.isCardio ? s.exercises.isEmpty : s.cardio == nil && s.cardioDraft == nil)
            let exerciseIDs = Set(s.exercises.map(\.id))
            if let selected = s.currentExerciseID { try check(exerciseIDs.contains(selected)) }
            let rowIDs = Set(s.exercises.flatMap(\.sets).map(\.id))
            func validInterval(_ timer: TrainingRest) -> Bool {
                timer.targetSeconds > 0 && validTimestamp(timer.startedAt) && timer.pausedSeconds.isFinite && timer.pausedSeconds >= 0
            }
            if let rest = s.rest { try check(validInterval(rest) && rowIDs.contains(rest.sourceSetID)) }
            try check(unique(s.restHistory) && s.restHistory.allSatisfy { validInterval($0.interval) })
            if let undo = s.timerUndo {
                try check(rowIDs.contains(undo.setID))
                if let prev = undo.previous { try check(validInterval(prev)) }
                if let measurement = undo.measurementID { try check(s.restHistory.contains { $0.id == measurement }) }
            }
            // Receipts can outlive their original row after an undo and substitution.
            for receipt in s.receipts.values {
                try check(!s.isCardio && (0..<Int.max).contains(receipt.expectedRevision))
                try check(LoadBasis.allCases.contains { (try? receipt.actual.validate(for: $0)) != nil })
            }
            for receipt in (s.cardioReceipts ?? [:]).values {
                try check(s.isCardio && receipt.revision >= 0 && receipt.revision < s.cardioRevision)
                try receipt.result.validate()
            }
            let slots = Set(o?.plannedSets.values.flatMap { $0 } ?? [])
            if let result = s.cardio { try result.validate() }
            for e in s.exercises {
                try exercise(e.prescription)
                for row in e.sets {
                    try check(allRows.insert(row.id).inserted && (0..<Int.max).contains(row.revision))
                    if let ordinal = row.ordinal { try check(ordinal > 0 && ordinal < Int.max) }
                    if let id = row.plannedID { try check(slots.contains(id)) }
                    if let timestamp = row.confirmedAt {
                        try check(validTimestamp(timestamp) && timestamp >= s.startedAt && timestamp <= (s.finishedAt ?? timestamp))
                        try row.actual.validate(for: e.basis)
                        if let id = row.plannedID { try check(credited.insert(id).inserted) }
                    }
                }
            }
        }
    }
}

// A generation contains both databases. Replacing this single small pointer commits the pair.
struct RecoveryPaths {
    let planning: URL
    let training: URL
    let previous: URL?
    static var root: URL {
        var url = URL.applicationSupportDirectory.appending(path: "Recovery")
        #if WEEKFORM_DEVELOPMENT
        if let run = ProcessInfo.processInfo.environment["WEEKFORM_UI_TEST_RUN"].flatMap(UUID.init(uuidString:)) {
            url = url.appending(path: run.uuidString)
        }
        #endif
        return url
    }

    static func current(at root: URL = root) throws -> Self {
        let pointer = root.appending(path: "active")
        do {
            let id = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: pointer))
            let dir = root.appending(path: id.uuidString)
            let paths = staged(dir)
            for url in [paths.planning.appending(path: "planning.store"), paths.previous!] {
                guard try url.checkResourceIsReachable() else { throw PlanningError("The restored profile is unavailable.") }
            }
            let listing = try FileManager.default.contentsOfDirectory(at: paths.training, includingPropertiesForKeys: nil)
            guard try listing.contains(where: { try $0.appending(path: "training.store").checkResourceIsReachable() }) else {
                throw PlanningError("The restored workouts are unavailable.")
            }
            return paths
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            guard !FileManager.default.fileExists(atPath: pointer.path) else { throw error }
            let suffix = root.lastPathComponent
            let base = (suffix == "Recovery" ? root : root.deletingLastPathComponent()).deletingLastPathComponent()
            func legacy(_ name: String) -> URL {
                let url = base.appending(path: name)
                return suffix == "Recovery" ? url : url.appending(path: suffix)
            }
            return Self(planning: legacy("Planning"), training: legacy("Training"), previous: nil)
        }
    }

    static func staged(_ dir: URL) -> Self {
        Self(planning: dir.appending(path: "Planning"), training: dir.appending(path: "Training"), previous: dir.appending(path: "previous.json"))
    }

    @MainActor static func replace(with backup: WorkoutBackup, planner: PlanningStore, training: TrainingStore,
                                   at root: URL = root, beforeSwitch: () throws -> Void = {}) throws {
        try backup.validate()
        let old = try WorkoutBackup(planner, training).encoded()
        let id = UUID()
        let directory = root.appending(path: id.uuidString)
        let paths = staged(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var switched = false
        defer { if !switched { try? FileManager.default.removeItem(at: directory) } }
        try old.write(to: paths.previous!, options: .atomic)
        try PlanningStore(directory: paths.planning).stage(backup)
        try TrainingStore(directory: paths.training).stage(backup)
        let p = PlanningStore(directory: paths.planning), t = TrainingStore(directory: paths.training)
        try p.load(); try t.load(profileID: backup.owner)
        let reopened = try WorkoutBackup(p, t)
        guard reopened == backup else { throw PlanningError("The restored copy could not be verified.") }
        try beforeSwitch()
        try JSONEncoder().encode(id).write(to: root.appending(path: "active"), options: .atomic)
        switched = true
    }
}
