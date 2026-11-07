import ImageIO
import SwiftUI

struct ExercisesScreen: View {
    let planner: PlanningStore
    let training: TrainingStore
    var body: some View { ExerciseDiscovery(planner: planner, training: training) }
}

private struct ExerciseDiscovery: View {
    let planner: PlanningStore
    let training: TrainingStore
    @State private var entries: [CatalogEntry] = []
    @State private var issue: String?
    @State private var filter = CatalogFilter()
    @State private var browseAll = false
    @State private var customOnly = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var all: [CatalogEntry] {
        entries + planner.customExercises.map(CatalogEntry.custom).filter { custom in
            !entries.contains { $0.id == custom.id }
        }
    }
    private var hasSelections: Bool {
        !filter.muscle.isEmpty || !filter.equipment.isEmpty || !filter.movement.isEmpty || filter.favoritesOnly || customOnly
    }
    private var showingResults: Bool {
        browseAll || hasSelections || !filter.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var results: [CatalogEntry] {
        let customIDs = Set(planner.customExercises.map { $0.variantID ?? $0.id })
        return all.filter { (!customOnly || customIDs.contains($0.id)) && filter.accepts($0, favorites: planner.favoriteExerciseIDs) }
    }

    var body: some View {
        let visibleResults = results
        List {
            if let issue { Text(issue).foregroundStyle(.secondary) }
            if showingResults {
                Section {
                    if hasSelections {
                        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 145), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                            if !filter.muscle.isEmpty { removal(filter.muscle) { filter.muscle = "" } }
                            if !filter.equipment.isEmpty { removal("Equipment: \(filter.equipment)") { filter.equipment = "" } }
                            if !filter.movement.isEmpty { removal("Movement: \(filter.movement)") { filter.movement = "" } }
                            if filter.favoritesOnly { removal("Favorites") { filter.favoritesOnly = false } }
                            if customOnly { removal("My exercises") { customOnly = false } }
                        }
                    }
                    Button("Clear search and filters", action: clear)
                        .accessibilityIdentifier("exercisesClearFilters")
                } header: {
                    HStack {
                        Text(visibleResults.count == 1 ? "1 result" : "\(visibleResults.count) results").font(.headline).foregroundStyle(PlannerStyle.ink)
                        Spacer()
                        filters
                    }.textCase(nil)
                }
                if visibleResults.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(filter.favoritesOnly ? "No matching favorites" : customOnly ? "No matching custom exercises" : "No matching exercises")
                                .font(.headline)
                            Text(filter.favoritesOnly ? "Save exercises with the star on their detail page, or clear your filters." : "Try another search, clear your filters, or create a custom exercise.")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                        createCustom
                    }
                } else {
                    Section {
                        ForEach(visibleResults) { entry in
                            NavigationLink {
                                CatalogDetail(entry: entry, catalog: ExerciseCatalog(entries: all), planner: planner, training: training, select: nil)
                            } label: {
                                HStack(spacing: 12) {
                                    if let media = entry.media.first { CatalogThumbnail(media: media) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.name).font(.headline)
                                        Text(entry.source.isEmpty ? "Custom exercise" : (entry.primary + entry.equipment).joined(separator: " · "))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    if planner.favoriteExerciseIDs.contains(entry.id) {
                                        Image(systemName: "star.fill").foregroundStyle(PlannerStyle.moss).accessibilityLabel("Favorite")
                                    }
                                }.padding(.vertical, 3)
                            }.accessibilityIdentifier("catalogRow-" + entry.name)
                        }
                    }
                    if customOnly { Section { createCustom } }
                }
            } else {
                Section {
                    Button { filter.favoritesOnly = true } label: { Label("Favorites", systemImage: "star") }
                        .accessibilityIdentifier("exercisesFavorites")
                    Button { customOnly = true } label: { Label("My exercises", systemImage: "person.crop.rectangle") }
                        .accessibilityIdentifier("exercisesMyExercises")
                    Button { browseAll = true } label: { Label("Browse all", systemImage: "list.bullet") }
                        .accessibilityIdentifier("exercisesBrowseAll")
                }
                Section("Browse by muscle") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                        ForEach(Array(Set(all.flatMap { $0.primary + $0.secondary })).filter { !$0.isEmpty }.sorted(), id: \.self) { muscle in
                            Button { filter.muscle = muscle } label: {
                                Text(muscle).font(.body.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(PlannerStyle.moss.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).foregroundStyle(PlannerStyle.ink)
                                .accessibilityIdentifier("exercisesMuscle-" + muscle)
                        }
                    }.padding(.vertical, 4)
                }
                Section { createCustom }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle("Exercises")
        .searchable(text: $filter.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .task {
            do { entries = try ExerciseCatalog.bundled().entries }
            catch { issue = "The bundled catalog could not be opened. Your custom exercises are still available." }
        }
    }

    private var createCustom: some View {
        NavigationLink {
            NewCustomExercise(planner: planner, onSaved: {
                clear()
                customOnly = true
            })
        } label: { Label("Create custom exercise", systemImage: "plus") }
            .accessibilityIdentifier("newCustomExercise")
    }

    private var filters: some View {
        Menu {
            Toggle("Favorites only", isOn: $filter.favoritesOnly)
            Menu("Muscle") {
                selector("Muscle", values: all.flatMap { $0.primary + $0.secondary }, binding: $filter.muscle)
            }
            Menu("Equipment") {
                selector("Equipment", values: all.flatMap(\.equipment), binding: $filter.equipment)
            }
            Menu("Movement") {
                selector("Movement", values: all.map(\.movement), binding: $filter.movement)
            }
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease")
                .font(.body).frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("exercisesFilters")
    }

    private func selector(_ title: String, values: [String], binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            Text("Any").tag("")
            ForEach(Array(Set(values)).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
        }
    }

    private func removal(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 44)
            .foregroundStyle(PlannerStyle.ink)
            .background(PlannerStyle.moss.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(title) filter")
            .accessibilityIdentifier("exercisesRemove-" + title)
    }

    private func clear() {
        filter = CatalogFilter()
        browseAll = false
        customOnly = false
    }
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
    @FocusState private var searchFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var searchHeight: CGFloat = 38

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
            VStack(alignment: .leading, spacing: 5) {
                Text("Search exercises")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    TextField("", text: Binding(get: { filter.text }, set: { value in
                        if value.contains(where: \.isNewline) {
                            filter.text = value.split(whereSeparator: \.isNewline).joined(separator: " ")
                            searchFocused = false
                        } else { filter.text = value }
                    }), axis: .vertical)
                        .focused($searchFocused)
                        .onSubmit { searchFocused = false }
                        .font(.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .frame(minHeight: searchHeight)
                        .accessibilityLabel("Search exercises")
                        .accessibilityIdentifier("catalogSearch")
                    if !filter.text.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { filter.text = "" }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.5), lineWidth: 1) }
            }
            .padding(.vertical, 3)
            .listRowBackground(PlannerStyle.paper)
            .listRowSeparator(.hidden)
            if base == nil {
                let filterLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                filterLayout { libraryFilters }
                .listRowSeparator(.hidden).listRowBackground(PlannerStyle.paper)
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
                Section {
                if visible.isEmpty { ContentUnavailableView("No matching exercises", systemImage: "magnifyingglass") }
                ForEach(visible) { row($0, reason: nil, all: all) }
                } header: {
                    Text(filter.favoritesOnly ? "Saved exercises" : "Exercise library")
                        .font(.headline).textCase(nil).foregroundStyle(PlannerStyle.moss)
                }
            }
        }
        .listStyle(.plain)
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

    @ViewBuilder private var libraryFilters: some View {
        filterButton("All exercises", favorites: false)
        filterButton("Favorites", favorites: true)
    }

    private func filterButton(_ title: String, favorites: Bool) -> some View {
        let selected = filter.favoritesOnly == favorites
        return Button {
            filter.favoritesOnly = favorites
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text(title).font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(minHeight: 44)
            .foregroundStyle(PlannerStyle.ink)
            .background(selected ? PlannerStyle.moss.opacity(0.16) : PlannerStyle.surface, in: Capsule())
            .overlay { Capsule().stroke(selected ? PlannerStyle.moss : PlannerStyle.rule, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                        .font(.subheadline).foregroundStyle(.primary)
                }
            }.padding(.vertical, 2)
        }
        .listRowBackground(PlannerStyle.surface)
        .listRowSeparatorTint(PlannerStyle.rule)
        .accessibilityIdentifier("catalogRow-" + entry.name)
    }
}

private struct CatalogThumbnail: View {
    let media: CatalogMedia
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit().padding(5)
                    .frame(width: 68, height: 68).background(.white, in: RoundedRectangle(cornerRadius: 9))
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedFrame: Int?
    @State private var equipment = ""
    @State private var issue: String?
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 7) {
                if !entry.movement.isEmpty { Text(entry.movement).font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss) }
                Text(entry.name).font(.system(.title, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                if !entry.primary.isEmpty { Text(entry.primary.joined(separator: " · ")).font(.headline).foregroundStyle(PlannerStyle.ink) }
            }.padding(.vertical, 4).listRowBackground(PlannerStyle.paper)
            if let select {
                Button("Use this exercise") {
                    select(planner.customExercises.first { ($0.variantID ?? $0.id) == entry.id } ?? entry.prescription)
                }.accessibilityIdentifier("useCatalogExercise")
            }
            if !entry.media.isEmpty {
                Section("Demonstration") {
                    LazyVGrid(columns: [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 125), spacing: 8)], spacing: 8) {
                        ForEach(entry.media.indices, id: \.self) { i in
                            Button {
                                selectedFrame = i
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right").accessibilityHidden(true)
                                        Text("Frame \(i + 1)").fixedSize(horizontal: false, vertical: true)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PlannerStyle.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    catalogFrame(i, height: 110)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Enlarge \(entry.name) demonstration, frame \(i + 1)")
                            .accessibilityIdentifier("catalogFrame\(i + 1)")
                        }
                    }.padding(.vertical, 3)
                }
            }
            if !entry.instructions.isEmpty {
                Section("Form cues") {
                    ForEach(entry.instructions.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(String(format: "%02d", i + 1)).font(.caption.monospacedDigit().bold()).foregroundStyle(PlannerStyle.moss)
                            Text(entry.instructions[i]).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Section("Training details") {
                if !entry.equipment.isEmpty { LabeledContent("Equipment", value: entry.equipment.joined(separator: ", ")) }
                if !entry.secondary.isEmpty { LabeledContent("Also works", value: entry.secondary.joined(separator: ", ")) }
                if !entry.convention.isEmpty { LabeledContent("Recording method", value: entry.convention) }
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
        }.scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle("Exercise").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedFrame) { index in
            ScrollView { catalogFrame(index, height: 400).padding() }
                .navigationTitle("Frame \(index + 1) of \(entry.media.count)")
                .navigationBarTitleDisplayMode(.inline)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let favorite = planner.favoriteExerciseIDs.contains(entry.id)
                Button(favorite ? "Remove favorite" : "Add favorite", systemImage: favorite ? "star.fill" : "star") {
                    do { try planner.setExerciseFavorite(entry.id, favorite: !favorite); issue = nil } catch { issue = error.localizedDescription }
                }.accessibilityIdentifier("favoriteExercise")
            }
        }
    }

    @ViewBuilder private func catalogFrame(_ index: Int, height: CGFloat) -> some View {
        if let url = entry.media[index].localURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit().padding(6)
                .frame(maxWidth: .infinity).frame(height: height)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("\(entry.name) demonstration, image \(index + 1)")
        } else {
            Label("Image unavailable offline", systemImage: "photo").font(.footnote)
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
    var onSaved: () -> Void = {}
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
                do { try planner.saveCustomExercise(saved); onSaved(); dismiss() } catch { issue = error.localizedDescription }
            }.accessibilityIdentifier("saveCatalogCustom")
        }.navigationTitle("New custom exercise")
    }
}
