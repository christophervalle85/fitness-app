import ImageIO
import SwiftUI

struct ExercisesScreen: View {
    let planner: PlanningStore
    let training: TrainingStore
    var body: some View { CatalogBrowser(planner: planner, training: training) }
}

struct CatalogPicker: View {
    let planner: PlanningStore
    var replacing: PlanExercise? = nil
    let select: (PlanExercise) -> Void
    var body: some View { CatalogBrowser(planner: planner, training: nil, replacing: replacing, select: select) }
}

private struct CatalogBrowser: View {
    let planner: PlanningStore
    let training: TrainingStore?
    var replacing: PlanExercise? = nil
    var select: ((PlanExercise) -> Void)? = nil
    @State private var entries: [CatalogEntry] = []
    @State private var issue: String?
    @State private var filter = CatalogFilter()
    @State private var showAll = false

    var body: some View {
        let custom = planner.customExercises.map(CatalogEntry.custom)
        let all = entries + custom.filter { item in !entries.contains(where: { $0.id == item.id }) }
        let base = replacing.flatMap { plan in
            if let identified = all.first(where: { $0.id == (plan.variantID ?? plan.id) }) { return identified }
            let candidates = entries.filter { $0.name.localizedCaseInsensitiveCompare(plan.name) == .orderedSame }
            return candidates.count == 1 ? candidates.first : nil
        }
        let ranked = base.map { ExerciseCatalog(entries: all).alternatives(to: $0, filter: filter, favorites: planner.favoriteExerciseIDs) } ?? []
        let visible = all.filter { filter.accepts($0, favorites: planner.favoriteExerciseIDs) }
        List {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search exercises", text: $filter.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("catalogSearch")
                if !filter.text.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { filter.text = "" }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            if let issue { Text(issue).foregroundStyle(.secondary) }
            if base != nil {
                Picker("Exercise selection", selection: $showAll) {
                    Text("Alternatives").tag(false)
                    Text("All exercises").tag(true)
                }.pickerStyle(.segmented)
            }
            if base != nil && !showAll {
                if ranked.isEmpty { Text("No matching alternatives. Browse all exercises or change the filters.") }
                ForEach(ranked, id: \.entry.id) { alternative in
                    row(alternative.entry, reason: alternative.reason, all: all)
                }
            } else {
                if visible.isEmpty { ContentUnavailableView("No matching exercises", systemImage: "magnifyingglass") }
                ForEach(visible) { row($0, reason: nil, all: all) }
            }
        }
        .navigationTitle(select == nil ? "Exercises" : "Choose an exercise")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Favorites only", isOn: $filter.favoritesOnly)
                    selector("Muscle", values: all.flatMap { $0.primary + $0.secondary }, binding: $filter.muscle)
                    selector("Movement", values: all.map(\.movement), binding: $filter.movement)
                    selector("Equipment", values: all.flatMap(\.equipment), binding: $filter.equipment)
                    Button("Clear filters") { filter = CatalogFilter() }
                } label: { Label("Filter exercises", systemImage: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { NewCustomExercise(planner: planner) } label: { Label("New custom exercise", systemImage: "plus") }
                    .accessibilityIdentifier("newCustomExercise")
            }
        }
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .task {
            do { entries = try ExerciseCatalog.bundled().entries }
            catch { issue = "The bundled catalog could not be opened. Your custom exercises are available below." }
        }
    }

    private func selector(_ label: String, values: [String], binding: Binding<String>) -> some View {
        Picker(label, selection: binding) {
            Text("Any").tag("")
            ForEach(Set(values.filter { !$0.isEmpty }).sorted(), id: \.self) { Text($0).tag($0) }
        }
    }

    private func row(_ entry: CatalogEntry, reason: String?, all: [CatalogEntry]) -> some View {
        NavigationLink {
            CatalogDetail(entry: entry, catalog: ExerciseCatalog(entries: all), planner: planner, training: training, select: select)
        } label: {
            HStack(spacing: 12) {
                if let first = entry.media.first {
                    CatalogThumbnail(media: first)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.name).font(.headline)
                        if planner.favoriteExerciseIDs.contains(entry.id) { Image(systemName: "star.fill").accessibilityLabel("Favorite") }
                    }
                    Text(reason ?? (entry.source.isEmpty ? "Custom exercise" : (entry.primary + entry.equipment).joined(separator: " · ")))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 2)
        }
        .accessibilityIdentifier("catalogRow-" + entry.name)
    }
}

private struct CatalogThumbnail: View {
    let media: CatalogMedia
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
        }.task(id: media.file) {
            guard let url = media.localURL,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { thumbnail = nil; return }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: 168]
            thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }
    }
}

private struct CatalogDetail: View {
    let entry: CatalogEntry
    let catalog: ExerciseCatalog
    let planner: PlanningStore
    let training: TrainingStore?
    let select: ((PlanExercise) -> Void)?
    @State private var equipment = ""
    @State private var issue: String?
    var body: some View {
        List {
            if let select {
                Button("Use this exercise") {
                    select(planner.customExercises.first { ($0.variantID ?? $0.id) == entry.id } ?? entry.prescription)
                }.accessibilityIdentifier("useCatalogExercise")
            }
            if !entry.media.isEmpty {
                Section("Demonstration") {
                    ForEach(entry.media.indices, id: \.self) { i in
                        let media = entry.media[i]
                        if let url = media.localURL, let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("\(entry.name) demonstration, image \(i + 1)")
                        } else { Label("Image unavailable offline", systemImage: "photo") }
                    }
                }
            }
            Section {
                if !entry.movement.isEmpty { LabeledContent("Movement", value: entry.movement) }
                if !entry.primary.isEmpty { LabeledContent("Primary muscles", value: entry.primary.joined(separator: ", ")) }
                if !entry.secondary.isEmpty { LabeledContent("Secondary muscles", value: entry.secondary.joined(separator: ", ")) }
                if !entry.equipment.isEmpty { LabeledContent("Equipment", value: entry.equipment.joined(separator: ", ")) }
                if !entry.convention.isEmpty { LabeledContent("Recording method", value: entry.convention) }
            }
            if !entry.instructions.isEmpty {
                Section("Instructions") { ForEach(entry.instructions.indices, id: \.self) { Text(entry.instructions[$0]) } }
            }
            if let url = entry.tutorialURL.flatMap(safeLink), let creator = entry.tutorialCreator, !creator.isEmpty {
                Link("Tutorial by \(creator)", destination: url)
            }
            if let training {
                Section("Your history") {
                    let results = training.sessions.sorted { $0.startedAt > $1.startedAt }.flatMap { session in
                        session.exercises.filter { ($0.prescription.variantID ?? $0.prescription.id) == entry.id }
                            .flatMap { exercise in exercise.sets.compactMap { set -> (UUID, Date, String)? in
                                guard let date = set.confirmedAt else { return nil }
                                return (set.id, date, actualDescription(set.actual.converted(to: planner.weightUnit), basis: exercise.basis))
                            } }
                    }.sorted { $0.1 > $1.1 }
                    if results.isEmpty { Text("No sets recorded yet.").foregroundStyle(.secondary) }
                    ForEach(results, id: \.0) { item in LabeledContent(item.1.formatted(date: .abbreviated, time: .shortened), value: item.2) }
                }
            }
            if !entry.primary.isEmpty {
                Section("Alternatives") {
                    Picker("Equipment", selection: $equipment) {
                        Text("Any").tag("")
                        ForEach(Set(catalog.entries.flatMap(\.equipment)).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    let alternatives = catalog.alternatives(to: entry, filter: CatalogFilter(equipment: equipment))
                    if alternatives.isEmpty { Text("No matching alternatives.").foregroundStyle(.secondary) }
                    ForEach(alternatives, id: \.entry.id) { candidate in
                        NavigationLink {
                            CatalogDetail(entry: candidate.entry, catalog: catalog, planner: planner, training: training, select: select)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(candidate.entry.name)
                                Text(candidate.reason).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("catalogAlternative-" + candidate.entry.name)
                    }
                }
            }
            if !entry.source.isEmpty || entry.textReference != nil || !entry.media.isEmpty {
                Section {
                    DisclosureGroup("Sources and licenses") {
                        if let text = entry.textReference {
                            credit(title: "Instructions", author: text.authors.joined(separator: ", "),
                                   license: text.license, licenseURL: text.licenseURL,
                                   changes: text.modifications, source: text.source)
                        }
                        ForEach(entry.media.indices, id: \.self) { index in
                            let media = entry.media[index]
                            credit(title: "Illustration \(index + 1)", author: media.author,
                                   license: media.license.components(separatedBy: " · ").first ?? media.license,
                                   licenseURL: media.licenseURL, changes: media.modifications, source: media.source)
                        }
                        if let source = safeLink(entry.source) { Link("Exercise source", destination: source) }
                    }
                }
            }
            if let issue { Text(issue) }
        }.navigationTitle(entry.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let favorite = planner.favoriteExerciseIDs.contains(entry.id)
                Button(favorite ? "Remove favorite" : "Add favorite", systemImage: favorite ? "star.fill" : "star") {
                    do { try planner.setExerciseFavorite(entry.id, favorite: !favorite); issue = nil } catch { issue = error.localizedDescription }
                }.accessibilityIdentifier("favoriteExercise")
            }
        }
    }

    private func credit(title: String, author: String, license: String, licenseURL: String?, changes: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(author)
            if !changes.isEmpty { Text(changes).foregroundStyle(.secondary) }
            if let url = licenseURL.flatMap(safeLink) {
                Link(license, destination: url)
            } else { Text(license) }
            if let url = safeLink(source) { Link("View source", destination: url) }
        }
        .font(.footnote)
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
    }

    private func safeLink(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}

private struct NewCustomExercise: View {
    let planner: PlanningStore
    @State private var plan = PlanExercise()
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Exercise name", text: $plan.name).accessibilityIdentifier("customCatalogName")
            TextField("Load convention", text: $plan.convention)
            Toggle("Time in seconds", isOn: $plan.timed)
            TextField("Instructions or notes", text: $plan.notes, axis: .vertical)
            if let issue { Text(issue) }
            Button("Save exercise") {
                var saved = plan
                saved.variantID = saved.id
                do { try planner.saveCustomExercise(saved); dismiss() } catch { issue = error.localizedDescription }
            }.accessibilityIdentifier("saveCatalogCustom")
        }.navigationTitle("New custom exercise")
    }
}
