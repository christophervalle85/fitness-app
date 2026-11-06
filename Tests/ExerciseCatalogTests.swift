import Foundation
import Testing
@testable import Weekform

struct ExerciseCatalogTests {
    private func entry(_ name: String, muscle: String, movement: String, equipment: String) -> CatalogEntry {
        CatalogEntry(id: UUID(), name: name, primary: [muscle], secondary: [], equipment: [equipment], movement: movement,
                     convention: "External load", instructions: [], media: [], source: "Offline test", version: "1")
    }

    @Test func filtersCombineSearchMuscleMovementEquipmentAndFavorite() {
        let press = entry("Incline press", muscle: "Chest", movement: "Push", equipment: "Dumbbells")
        let filter = CatalogFilter(text: "incline DUMB", muscle: "Chest", movement: "Push", equipment: "Dumbbells", favoritesOnly: true)
        #expect(filter.accepts(press, favorites: [press.id]))
        #expect(!filter.accepts(press, favorites: []))
        #expect(!CatalogFilter(equipment: "Machine").accepts(press, favorites: []))
        #expect(!CatalogFilter(muscle: "Back").accepts(press, favorites: []))
    }

    @Test func alternativesExplainAndRankMovementBeforeBroaderTargets() {
        let source = entry("Press", muscle: "Chest", movement: "Push", equipment: "Machine")
        let comparable = entry("Floor press", muscle: "Chest", movement: "Push", equipment: "Dumbbells")
        let broader = entry("Fly", muscle: "Chest", movement: "Adduction", equipment: "Machine")
        let unrelated = entry("Row", muscle: "Back", movement: "Pull", equipment: "Machine")
        let catalog = ExerciseCatalog(entries: [source, broader, unrelated, comparable])
        let options = catalog.alternatives(to: source)
        #expect(options.map(\.entry.id) == [comparable.id, broader.id])
        #expect(options[0].reason.contains("Push"))
        #expect(options[1].reason.contains("Same target"))
        #expect(catalog.alternatives(to: source, filter: CatalogFilter(equipment: "Machine")).map(\.entry.id) == [broader.id])
        #expect(comparable.prescription.variantID == comparable.id)
    }
}
