import Foundation
import Observation
import SwiftData

enum PlanningSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Profile.self, Routine.self] }

    @Model
    final class Profile {
        var id: UUID
        var activeID: UUID?
        var draft: Data?
        var step: String

        init() {
            id = UUID()
            step = "welcome"
        }
    }

    @Model
    final class Routine {
        @Attribute(.unique) var id: UUID
        var plan: Data
        var created: Date

        init(id: UUID, plan: Data) {
            self.id = id
            self.plan = plan
            self.created = Date()
        }
    }
}

struct PlanningError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor @Observable
final class PlanningStore {
    private(set) var plans: [WeekPlan] = []
    private(set) var activeID: UUID?
    private(set) var draft: WeekPlan?
    private(set) var step = "welcome"
    private(set) var profileID: UUID?

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let beforeSave: () throws -> Void
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var profile: PlanningSchemaV1.Profile?
    @ObservationIgnored private var routines: [PlanningSchemaV1.Routine] = []

    convenience init() {
        var directory = URL.applicationSupportDirectory.appending(path: "Planning", directoryHint: .isDirectory)
        #if WEEKFORM_DEVELOPMENT
        if let run = ProcessInfo.processInfo.environment["WEEKFORM_UI_TEST_RUN"].flatMap(UUID.init(uuidString:)) {
            directory = directory.appending(path: run.uuidString, directoryHint: .isDirectory)
        }
        #endif
        self.init(directory: directory)
    }

    init(directory: URL, beforeSave: @escaping () throws -> Void = {}) {
        self.directory = directory
        self.beforeSave = beforeSave
    }

    func load() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: PlanningSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: directory.appending(path: "planning.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let profiles = try context.fetch(FetchDescriptor<PlanningSchemaV1.Profile>())
        guard profiles.count <= 1 else { throw PlanningError("The saved profile could not be opened.") }
        let rows = try context.fetch(FetchDescriptor<PlanningSchemaV1.Routine>(sortBy: [SortDescriptor(\.created)]))
        let decoder = JSONDecoder()
        let plans = try rows.map { try decoder.decode(WeekPlan.self, from: $0.plan) }
        let profile: PlanningSchemaV1.Profile
        if let existing = profiles.first {
            profile = existing
        } else {
            guard rows.isEmpty else { throw PlanningError("The routine owner could not be found.") }
            profile = PlanningSchemaV1.Profile()
            context.insert(profile)
            try beforeSave()
            try context.save()
        }
        let draft = try profile.draft.map { try decoder.decode(WeekPlan.self, from: $0) }

        self.container = container
        self.context = context
        self.profile = profile
        routines = rows
        self.plans = plans
        self.draft = draft
        publishProfile(profile)
    }

    func begin(_ plan: WeekPlan, step: String) throws {
        try persistDraft(plan, step: step)
    }

    func update(_ plan: WeekPlan, step: String) throws {
        guard draft?.id == plan.id else { throw PlanningError("This editor is no longer open.") }
        try persistDraft(plan, step: step)
    }

    private func persistDraft(_ plan: WeekPlan, step: String) throws {
        guard ["welcome", "starters", "edit", "review"].contains(step) else {
            throw PlanningError("This setup step could not be saved.")
        }
        guard !plan.archived, !plans.contains(where: { $0.id == plan.id && $0.archived }) else {
            throw PlanningError("Choose an available routine to edit.")
        }
        let data = try JSONEncoder().encode(plan)
        try save { _, profile in
            profile.draft = data
            profile.step = step
        }
        draft = plan
    }

    func confirm(_ plan: WeekPlan) throws {
        // A delayed retry must not close or overwrite a newer editor.
        if draft != plan, plans.contains(plan) { return }
        guard draft == plan else { throw PlanningError("Review the latest saved draft before confirming it.") }
        if let message = plan.validationMessage { throw PlanningError(message) }
        guard !plan.archived else { throw PlanningError("Choose an available routine to confirm.") }

        let bytes = try JSONEncoder().encode(plan)
        let index = routines.firstIndex { $0.id == plan.id }
        var inserted: PlanningSchemaV1.Routine?
        try save { context, profile in
            if let index {
                routines[index].plan = bytes
            } else {
                let row = PlanningSchemaV1.Routine(id: plan.id, plan: bytes)
                context.insert(row)
                inserted = row
            }
            if index == nil || profile.activeID == nil { profile.activeID = plan.id }
            profile.draft = nil
            profile.step = "home"
        }
        if let index {
            plans[index] = plan
        } else if let inserted {
            plans.append(plan)
            routines.append(inserted)
        }
        draft = nil
    }

    func discard() throws {
        try save { _, profile in
            profile.draft = nil
            profile.step = plans.isEmpty ? "welcome" : "home"
        }
        draft = nil
    }

    func activate(_ id: UUID) throws {
        guard plans.contains(where: { $0.id == id && !$0.archived }) else {
            throw PlanningError("Choose an available routine.")
        }
        try save { _, profile in profile.activeID = id }
    }

    func duplicate(_ id: UUID) throws {
        guard let original = plans.first(where: { $0.id == id }) else {
            throw PlanningError("This routine could not be found.")
        }
        var copy = original.independentCopy()
        copy.name += " (copy)"
        let row = try PlanningSchemaV1.Routine(id: copy.id, plan: JSONEncoder().encode(copy))
        try save { context, _ in context.insert(row) }
        plans.append(copy)
        routines.append(row)
    }

    func replaceFutureExercise(planID: UUID, dayID: UUID, original: PlanExercise, replacement: PlanExercise) throws {
        guard let i = plans.firstIndex(where: { $0.id == planID && !$0.archived }),
              let d = plans[i].days.firstIndex(where: { $0.id == dayID }),
              let e = plans[i].days[d].exercises.firstIndex(where: { $0 == original }),
              draft?.id != planID else {
            throw PlanningError("This routine has changed. Open Routines to edit the current week.")
        }
        var plan = plans[i]
        var future = replacement
        future.variantID = replacement.variantID ?? replacement.id
        future.id = UUID()
        // A session replacement contains only the remaining sets. Future weeks keep the full prescription.
        future.sets = original.sets
        plan.days[d].exercises[e] = future
        if let issue = plan.validationMessage { throw PlanningError(issue) }
        let data = try JSONEncoder().encode(plan)
        try save { _, _ in routines[i].plan = data }
        plans[i] = plan
    }

    func archive(_ id: UUID) throws {
        guard let index = plans.firstIndex(where: { $0.id == id }) else {
            throw PlanningError("This routine could not be found.")
        }
        var plan = plans[index]
        plan.archived = true
        let bytes = try JSONEncoder().encode(plan)
        try save { _, profile in
            routines[index].plan = bytes
            if profile.activeID == id { profile.activeID = plans.first { !$0.archived && $0.id != id }?.id }
            if draft?.id == id {
                profile.draft = nil
                profile.step = "home"
            }
        }
        if draft?.id == id { draft = nil }
        plans[index] = plan
    }

    #if WEEKFORM_DEVELOPMENT
    func reset() throws {
        try save { context, profile in
            for row in routines { context.delete(row) }
            profile.activeID = nil
            profile.draft = nil
            profile.step = "welcome"
        }
        routines = []
        plans = []
        draft = nil
    }
    #endif

    // Keep the profile, draft and saved routine in one explicit commit. Publish
    // only after it succeeds so a failed confirmation can be retried in place.
    private func save(_ change: (ModelContext, PlanningSchemaV1.Profile) throws -> Void) throws {
        guard let context, let profile else { throw PlanningError("Open your local profile and try again.") }
        do {
            try change(context, profile)
            try beforeSave()
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        publishProfile(profile)
    }

    private func publishProfile(_ profile: PlanningSchemaV1.Profile) {
        profileID = profile.id
        activeID = profile.activeID
        step = profile.step
    }
}
