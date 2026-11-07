import Foundation
import Testing
@testable import Weekform

struct ExerciseCatalogTests {
    private func entry(_ name: String, muscle: String, movement: String, equipment: String, secondary: [String] = []) -> CatalogEntry {
        CatalogEntry(id: UUID(), name: name, primary: [muscle], secondary: secondary, equipment: [equipment], movement: movement,
                     convention: "External load", instructions: [], media: [], source: "Offline test", version: "1")
    }

    @Test func searchMatchesPrimaryMusclesAndCombinesEquipment() {
        let press = entry("Dumbbell bench press", muscle: "Chest", movement: "Push", equipment: "Dumbbell")
        let fly = entry("Cable fly", muscle: "Chest", movement: "Adduction", equipment: "Cable")
        let row = entry("Chest-supported dumbbell row", muscle: "Middle back", movement: "Pull", equipment: "Dumbbell", secondary: ["Chest"])
        let unrelated = entry("Curl", muscle: "Biceps", movement: "Flexion", equipment: "Dumbbell")
        let custom = CatalogEntry.custom(PlanExercise(name: "Band chest press"))
        let catalog = ExerciseCatalog(entries: [unrelated, row, press, fly, custom])
        #expect(Set(catalog.search(" CHEST! ").map(\.id)) == [press.id, fly.id])
        #expect(Set(catalog.search("pecs").map(\.id)) == [press.id, fly.id])
        #expect(catalog.search("dumbbell chest").map(\.id) == [press.id])
        #expect(catalog.search("middle back dumb").map(\.id) == [row.id])
        #expect(catalog.search("chest-supported dumbbell row").map(\.id) == [row.id])
        #expect(catalog.search("band chest").map(\.id) == [custom.id])
        #expect(catalog.search(" … ").isEmpty)
    }

    @Test func searchPrioritizesNamesAndFindsExistingCustomExercises() {
        let bench = entry("Bench press", muscle: "Chest", movement: "Push", equipment: "Barbell")
        let incline = entry("Incline bench press", muscle: "Chest", movement: "Push", equipment: "Dumbbell")
        let metadata = entry("Seated machine", muscle: "Chest", movement: "Press", equipment: "Bench")
        let custom = CatalogEntry.custom(PlanExercise(name: "Café band march"))
        let catalog = ExerciseCatalog(entries: [metadata, incline, custom, bench])
        #expect(catalog.search("bench press").map(\.id) == [bench.id, incline.id, metadata.id])
        #expect(catalog.search("cafe band mar").map(\.id) == [custom.id])
        #expect(catalog.search("inch").isEmpty)
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
