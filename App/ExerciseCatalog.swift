import Foundation

struct CatalogMedia: Decodable {
    let file, author, license, source, modifications: String

    var licenseURL: String?

    var localURL: URL? {
        let path = file as NSString
        let allowed = ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"]
        guard path.lastPathComponent == file, allowed.contains(path.pathExtension.lowercased()) else { return nil }
        return Bundle.main.url(forResource: file, withExtension: nil)
    }
}

struct CatalogTextReference: Decodable {
    let source, license, licenseURL, modifications: String
    let authors: [String]
}

struct CatalogEntry: Decodable, Identifiable {
    let id: UUID
    let name: String
    let primary, secondary, equipment: [String]
    let movement, convention: String
    let instructions: [String]
    let media: [CatalogMedia]
    let source, version: String
    var providerID: String?
    var tutorialURL: String?
    var textReference: CatalogTextReference?
    var tutorialCreator: String?
    var timed: Bool?

    var prescription: PlanExercise {
        PlanExercise(variantID: id, name: name, timed: timed ?? (convention.localizedCaseInsensitiveContains("duration") || convention.localizedCaseInsensitiveContains("timed")), convention: convention)
    }

    static func custom(_ plan: PlanExercise) -> Self {
        Self(id: plan.variantID ?? plan.id, name: plan.name, primary: [], secondary: [], equipment: [], movement: "", convention: plan.convention,
             instructions: plan.notes.isEmpty ? [] : [plan.notes], media: [], source: "", version: "")
    }
}

struct CatalogFilter {
    var text = ""
    var muscle = ""
    var movement = ""
    var equipment = ""
    var favoritesOnly = false

    func accepts(_ entry: CatalogEntry, favorites: Set<UUID>) -> Bool {
        let terms = text.split(whereSeparator: \.isWhitespace)
        let searchable = ([entry.name, entry.movement] + entry.primary + entry.secondary + entry.equipment).joined(separator: " ")
        return terms.allSatisfy { searchable.localizedStandardContains(String($0)) }
            && (muscle.isEmpty || (entry.primary + entry.secondary).contains(muscle))
            && (movement.isEmpty || entry.movement == movement)
            && (equipment.isEmpty || entry.equipment.contains(equipment))
            && (!favoritesOnly || favorites.contains(entry.id))
    }
}

struct ExerciseCatalog {
    let entries: [CatalogEntry]

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let entries = try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url))
        guard Set(entries.map(\.id)).count == entries.count else { throw CocoaError(.fileReadCorruptFile) }
        return Self(entries: entries)
    }

    func alternatives(to source: CatalogEntry, filter: CatalogFilter = CatalogFilter(), favorites: Set<UUID> = []) -> [(entry: CatalogEntry, reason: String)] {
        let target = Set(source.primary)
        return entries.compactMap { candidate -> (CatalogEntry, String, Int)? in
            guard candidate.id != source.id, filter.accepts(candidate, favorites: favorites) else { return nil }
            let muscles = target.intersection(candidate.primary).sorted()
            guard !muscles.isEmpty else { return nil }
            let match = !source.movement.isEmpty && source.movement == candidate.movement
            let reason = (match ? source.movement + " · " : "Same target · ") + muscles.joined(separator: ", ")
            return (candidate, reason, match ? 0 : 1)
        }.sorted {
            $0.2 == $1.2 ? $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending : $0.2 < $1.2
        }.map { ($0.0, $0.1) }
    }
}
