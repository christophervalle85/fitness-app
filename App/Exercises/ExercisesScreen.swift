import ImageIO
import SwiftUI

extension EnvironmentValues {
    @Entry var exerciseTabTopInset: CGFloat?
}

struct ExercisesScreen: View {
    let planner: PlanningStore
    let training: TrainingStore
    var body: some View { ExerciseSearch(planner: planner, training: training) }
}

private struct ExerciseSearch: View {
    let planner: PlanningStore
    let training: TrainingStore
    @State private var entries: [CatalogEntry] = []
    @State private var issue: String?
    @State private var query = ""

    var body: some View {
        let custom = planner.customExercises.map(CatalogEntry.custom)
        let all = entries + custom.filter { item in !entries.contains { $0.id == item.id } }
        let catalog = ExerciseCatalog(entries: all)
        let meaningfulQuery = query.contains { $0.isLetter || $0.isNumber }
        let results = meaningfulQuery ? catalog.search(query) : []
        List {
            if meaningfulQuery {
                if let issue { Text(issue).foregroundStyle(.secondary) }
                if results.isEmpty {
                    Text("No matching exercises").foregroundStyle(.secondary)
                        .accessibilityIdentifier("exercisesNoMatches")
                }
                ForEach(results) { entry in
                    NavigationLink {
                        CatalogDetail(entry: entry, catalog: catalog, planner: planner, training: training, select: nil)
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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden).background(PlannerStyle.paper)
        .navigationTitle("Search Exercises")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task {
            do { entries = try ExerciseCatalog.bundled().entries }
            catch { issue = "The bundled catalog could not be opened. Your custom exercises are still available." }
        }
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

struct CatalogThumbnail: View {
    let media: CatalogMedia?
    var onIllustrationPlate = false
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                let lineArt = onIllustrationPlate && media?.isEverkineticLineArt == true
                CatalogArtwork(image: thumbnail, lineArt: lineArt).padding(5)
                    .frame(width: 68, height: 68)
                    .background(lineArt ? Color.clear : .white, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "dumbbell").font(.title2).foregroundStyle(PlannerStyle.moss)
                    .frame(width: 68, height: 68)
                    .background(PlannerStyle.moss.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
            }
        }.task(id: media?.file) {
            guard let media, let url = media.localURL,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { thumbnail = nil; return }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: 168]
            thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }
    }
}

private extension CatalogMedia {
    var isEverkineticLineArt: Bool { author == "Everkinetic" }
}

private struct CatalogArtwork: View {
    let image: UIImage
    let lineArt: Bool

    var body: some View {
        let artwork = Image(uiImage: image).resizable()
        if lineArt {
            // The bundled Everkinetic assets are monochrome. White becomes
            // transparent, leaving adaptive ink over the existing plate.
            PlannerStyle.ink
                .mask { artwork.colorInvert().contrast(1.04).luminanceToAlpha() }
                .aspectRatio(image.size, contentMode: .fit)
        } else {
            artwork.scaledToFit()
        }
    }
}

private struct CatalogDetail: View {
    let entry: CatalogEntry
    let catalog: ExerciseCatalog
    let planner: PlanningStore
    let training: TrainingStore?
    let select: ((PlanExercise) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.exerciseTabTopInset) private var tabTopInset
    @State private var issue: String?
    @State private var heldCreator: Int?
    @State private var releasedHold: (index: Int, date: Date)?
    @State private var openCreator: Int?

    var body: some View {
        if let tabTopInset {
            detailPage
                .safeAreaPadding(.top, tabTopInset)
                .ignoresSafeArea(.container, edges: .top)
        } else {
            detailPage
        }
    }

    private var detailPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    heading
                    if let issue {
                        Label(issue, systemImage: "exclamationmark.circle").font(.footnote)
                    }
                    if !entry.media.isEmpty { demonstration }
                    muscleTags
                    if let select {
                        Button {
                            select(planner.customExercises.first { ($0.variantID ?? $0.id) == entry.id } ?? entry.prescription)
                        } label: {
                            Text("Use this exercise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("useCatalogExercise")
                    }
                }
                .padding(.horizontal, 20)

                instructions.padding(.horizontal, 20)
                if let training {
                    CatalogWorkoutHistory(entry: entry, training: training, unit: planner.weightUnit)
                        .padding(.horizontal, 20)
                }
                similarExercises
                sourceCredits.padding(.horizontal, 20)
            }
            .padding(.top, 4)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            detailActions
                .padding(.horizontal, 20)
                .background(PlannerStyle.paper)
        }
        .background(PlannerStyle.paper)
        .navigationBarBackButtonHidden(true)
        .toolbarVisibility(.hidden, for: .navigationBar, .tabBar)
    }

    private var detailActions: some View {
        let favorite = planner.favoriteExerciseIDs.contains(entry.id)
        return HStack {
            Button {
                dismiss()
            } label: {
                Label("Back", systemImage: "chevron.backward")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("exerciseDetailBack")
            Spacer()
            Button {
                do {
                    try planner.setExerciseFavorite(entry.id, favorite: !favorite)
                    issue = nil
                } catch {
                    issue = error.localizedDescription
                }
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(favorite ? "Remove favorite" : "Add favorite")
            .accessibilityIdentifier("favoriteExercise")
        }
        .buttonStyle(.plain)
        .foregroundStyle(PlannerStyle.moss)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.name).font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !entry.equipment.isEmpty {
                Text(entry.equipment.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if !entry.convention.isEmpty {
                Text(entry.convention).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var demonstration: some View {
        // Only source labels that identify the motion order justify an arrow.
        let sequence = entry.media.count > 1
            && entry.media[0].source.hasSuffix("-relaxation.png")
            && entry.media[1].source.hasSuffix("-tension.png")
            && entry.media.prefix(2).allSatisfy { $0.localURL != nil }
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(spacing: 8) {
            if entry.media.count == 1 {
                catalogFrame(0, height: 210)
            } else {
                layout {
                    catalogFrame(0, height: typeSize.isAccessibilitySize ? 200 : 155)
                    if sequence {
                        Image(systemName: typeSize.isAccessibilitySize ? "arrow.down" : "arrow.forward")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(PlannerStyle.moss)
                            .accessibilityHidden(true)
                    }
                    catalogFrame(1, height: typeSize.isAccessibilitySize ? 200 : 155)
                }
                if entry.media.count > 2 {
                    LazyVGrid(columns: [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(2..<entry.media.count, id: \.self) { index in
                            catalogFrame(index, height: 155)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(PlannerStyle.moss.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private func catalogFrame(_ index: Int, height: CGFloat) -> some View {
        let media = entry.media[index]
        if let url = media.localURL, let image = UIImage(contentsOfFile: url.path) {
            CatalogArtwork(image: image, lineArt: media.isEverkineticLineArt).padding(4)
                .frame(maxWidth: .infinity).frame(height: height)
                .background(media.isEverkineticLineArt ? Color.clear : .white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.name) demonstration, image \(index + 1)")
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("catalogFrame\(index + 1)")
        } else {
            Label("Image unavailable offline", systemImage: "photo").font(.footnote)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    @ViewBuilder private var muscleTags: some View {
        if !entry.primary.isEmpty || !entry.secondary.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 6) { muscleTagContents }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) { muscleTagContents }
            }
        }
    }

    @ViewBuilder private var muscleTagContents: some View {
        if !entry.primary.isEmpty { muscleTag("Primary", muscles: entry.primary, emphasized: true) }
        if !entry.secondary.isEmpty { muscleTag("Secondary", muscles: entry.secondary, emphasized: false) }
    }

    private func muscleTag(_ role: String, muscles: [String], emphasized: Bool) -> some View {
        let names = muscles.joined(separator: ", ")
        return Text("\(Text(role).foregroundStyle(.secondary)) \(Text(names).fontWeight(.semibold))")
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(emphasized ? PlannerStyle.moss.opacity(0.12) : PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("\(role): \(names)")
    }

    @ViewBuilder private var instructions: some View {
        if !entry.instructions.isEmpty || entry.tutorialURL != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Instructions").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(entry.instructions.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit().bold())
                            .foregroundStyle(PlannerStyle.moss)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(PlannerStyle.moss.opacity(0.10), in: Capsule())
                        Text(entry.instructions[index]).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let url = entry.tutorialURL.flatMap(safeLink), let creator = entry.tutorialCreator, !creator.isEmpty {
                    Link("Tutorial by \(creator)", destination: url).font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder private var similarExercises: some View {
        if !entry.primary.isEmpty {
            let alternatives = catalog.alternatives(to: entry)
            VStack(alignment: .leading, spacing: 9) {
                Text("Similar exercises").font(.headline).accessibilityAddTraits(.isHeader).padding(.horizontal, 20)
                if alternatives.isEmpty {
                    Text("No matching alternatives.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 10) {
                            ForEach(alternatives, id: \.entry.id) { candidate in
                                let subtitle = candidate.entry.equipment.isEmpty ? candidate.reason : candidate.entry.equipment.joined(separator: ", ")
                                NavigationLink {
                                    CatalogDetail(entry: candidate.entry, catalog: catalog, planner: planner, training: training, select: select)
                                } label: {
                                    similarCard(candidate.entry, subtitle: subtitle)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(candidate.entry.name)
                                .accessibilityValue(subtitle)
                                .accessibilityIdentifier("catalogAlternative-" + candidate.entry.name)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("similarExerciseCards")
                }
            }
        }
    }

    private func similarCard(_ candidate: CatalogEntry, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CatalogThumbnail(media: candidate.media.first, onIllustrationPlate: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(PlannerStyle.moss.opacity(0.10), in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.name).font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
        }
        .frame(width: typeSize.isAccessibilitySize ? 240 : 150)
        .background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(PlannerStyle.rule.opacity(0.42)).allowsHitTesting(false) }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var sourceCredits: some View {
        let credits = creatorCredits
        if !credits.isEmpty || safeLink(entry.source) != nil {
            VStack(alignment: .leading, spacing: 1) {
                if credits.isEmpty, let source = safeLink(entry.source) {
                    Link("Exercise source", destination: source)
                }
                ForEach(Array(credits.enumerated()), id: \.offset) { index, credit in
                    creatorCredit(credit, index: index)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .tint(PlannerStyle.moss)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("exerciseSourceCredits")
        }
    }

    private var creatorCredits: [CreatorCredit] {
        let media = mediaCreditGroups.compactMap(\.first).map { entry.media[$0] }
        if let reference = entry.textReference, media.count == 1, let art = media.first,
           reference.authors.joined(separator: ", ") == art.author, reference.licenseURL == art.licenseURL {
            return [CreatorCredit(prefix: "Instructions and illustrations by", name: art.author,
                                  license: reference.license, licenseURL: reference.licenseURL,
                                  note: reference.modifications)]
        }

        var credits: [CreatorCredit] = []
        if let reference = entry.textReference {
            credits.append(CreatorCredit(prefix: "Instructions adapted from", name: reference.authors.joined(separator: ", "),
                                         license: reference.license, licenseURL: reference.licenseURL,
                                         note: reference.modifications))
        }
        for art in media {
            credits.append(CreatorCredit(prefix: "Illustrations by", name: art.author,
                                         license: art.license, licenseURL: art.licenseURL,
                                         note: art.isEverkineticLineArt ? "Displayed as tinted line art." : art.modifications))
        }
        return credits
    }

    private func creatorCredit(_ credit: CreatorCredit, index: Int) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        return layout {
            Text(credit.prefix).fixedSize(horizontal: false, vertical: true)
            Button {
                // A native button can deliver its release action before or
                // after the style reports that the press ended.
                guard heldCreator != index else { return }
                if let releasedHold, releasedHold.index == index, Date.now.timeIntervalSince(releasedHold.date) < 0.15 {
                    return
                }
                openCreator = openCreator == index ? nil : index
            } label: {
                Text(credit.name).underline()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 24, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CreatorPressStyle(onPress: { pressed in
                if pressed {
                    releasedHold = nil
                } else if heldCreator == index {
                    releasedHold = (index, .now)
                    showCreatorPreview(nil)
                }
            }, onHold: { showCreatorPreview(index) }))
            .foregroundStyle(PlannerStyle.moss)
            .accessibilityHint("Opens source credits")
            .accessibilityIdentifier(index == 0 ? "exerciseSourceCreator" : "exerciseSourceCreator-\(index)")
            .anchorPreference(key: CreatorBounds.self, value: .bounds) { $0 }
            .popover(isPresented: Binding(get: { openCreator == index }, set: { presented in
                if !presented, openCreator == index { openCreator = nil }
            }), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                creditPopover
                    .presentationCompactAdaptation(.popover)
            }
            if !typeSize.isAccessibilitySize { Text("·").accessibilityHidden(true) }
            licenseCredit(credit.license, url: credit.licenseURL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlayPreferenceValue(CreatorBounds.self) { anchor in
            GeometryReader { geometry in
                Color.clear.overlay(alignment: .bottomLeading) {
                    if heldCreator == index, let anchor {
                        let bounds = geometry[anchor]
                        let width = min(typeSize.isAccessibilitySize ? 240 : 180, geometry.size.width)
                        let left = min(max(0, bounds.midX - width / 2), geometry.size.width - width)
                        let offset = layoutDirection == .leftToRight ? left : left + width - geometry.size.width
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credit.name).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                            Text(credit.license.components(separatedBy: " · ").first ?? credit.license)
                            if !credit.note.isEmpty { Text(credit.note).font(.caption2) }
                        }
                        .padding(10)
                        .frame(width: width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(PlannerStyle.rule.opacity(0.45)) }
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                        .offset(x: offset, y: bounds.minY - geometry.size.height - 6)
                        .transition(.opacity)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .zIndex(heldCreator == index ? 1 : 0)
    }

    private func showCreatorPreview(_ index: Int?) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { heldCreator = index }
    }

    private var creditPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Credits").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { openCreator = nil }
                }
                sourceDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .frame(idealWidth: 280, maxWidth: 300, idealHeight: 240, maxHeight: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exerciseSourcePopup")
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reference = entry.textReference {
                credit(title: "Instructions", author: reference.authors.joined(separator: ", "),
                       license: reference.license, licenseURL: reference.licenseURL,
                       changes: reference.modifications, source: reference.source)
            }
            ForEach(mediaCreditGroups, id: \.self) { group in
                if let index = group.first {
                    let media = entry.media[index]
                    Text("Illustrations: \(media.author)")
                    licenseCredit(media.license, url: media.licenseURL)
                    if !media.modifications.isEmpty { Text(media.modifications) }
                    if media.isEverkineticLineArt { Text("Displayed as tinted line art in Weekform.") }
                    ForEach(group, id: \.self) { index in
                        if let source = safeLink(entry.media[index].source) {
                            Link("Illustration \(index + 1) source", destination: source)
                        }
                    }
                }
            }
            if let source = safeLink(entry.source) { Link("Exercise source", destination: source) }
            if !catalog.alternatives(to: entry).isEmpty {
                Text("Credits for similar exercise illustrations appear on each exercise page.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var mediaCreditGroups: [[Int]] {
        var groups: [[Int]] = []
        for index in entry.media.indices {
            let media = entry.media[index]
            if let group = groups.firstIndex(where: { group in
                let existing = entry.media[group[0]]
                return existing.author == media.author && existing.license == media.license
                    && existing.licenseURL == media.licenseURL && existing.modifications == media.modifications
            }) {
                groups[group].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups
    }

    @ViewBuilder private func licenseCredit(_ license: String, url: String?) -> some View {
        if let url = url.flatMap(safeLink) {
            Link(license.components(separatedBy: " · ").first ?? license, destination: url)
        } else {
            Text(license)
        }
    }

    private func credit(title: String, author: String, license: String, licenseURL: String?, changes: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(author)")
            licenseCredit(license, url: licenseURL)
            if !changes.isEmpty { Text(changes) }
            if let url = safeLink(source) { Link("\(title) source", destination: url) }
        }
    }

    private func safeLink(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    private struct CreatorCredit {
        let prefix: String
        let name: String
        let license: String
        let licenseURL: String?
        let note: String
    }

    private struct CreatorBounds: PreferenceKey {
        static var defaultValue: Anchor<CGRect>? { nil }

        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = nextValue() ?? value
        }
    }

    private struct CreatorPressStyle: ButtonStyle {
        let onPress: (Bool) -> Void
        let onHold: () -> Void

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
                .task(id: configuration.isPressed) {
                    guard configuration.isPressed else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    onHold()
                }
                .onDisappear { onPress(false) }
        }
    }
}

private struct CatalogWorkoutHistory: View {
    let entry: CatalogEntry
    let training: TrainingStore
    let unit: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedSeries: RecordIdentity?

    var body: some View {
        let records = ProgressMetrics.exerciseRecords(variantID: entry.id, sessions: training.sessions).sorted {
            ($0.trend.last?.date ?? .distantPast) > ($1.trend.last?.date ?? .distantPast)
        }
        let record = records.first { $0.id == selectedSeries } ?? records.first
        let latest = training.sessions.lazy.flatMap(\.exercises)
            .filter { ($0.prescription.variantID ?? $0.prescription.id) == entry.id }
            .flatMap(\.sets).compactMap(\.confirmedAt).max()
        let metric = metric(for: record)
        let metricLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
        VStack(alignment: .leading, spacing: 10) {
            Text("Workout history").font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("exerciseHistory")
            if records.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, series in
                            let current = series.id == record?.id
                            Button {
                                selectedSeries = series.id
                            } label: {
                                Text(seriesName(series, at: index, among: records))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9).frame(minHeight: 44)
                                    .background(current ? PlannerStyle.moss.opacity(0.14) : PlannerStyle.paper, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(current ? .isSelected : [])
                        }
                    }
                }
                .accessibilityLabel("Workout history series")
            } else if let record {
                Text(recordContext(record)).font(.caption).foregroundStyle(.secondary)
            }
            metricLayout {
                historyMetric(metric.title, value: metric.value, id: "exerciseHistoryMax")
                let seriesDate = record?.trend.last?.date ?? latest
                historyMetric("Last logged", value: seriesDate?.formatted(.dateTime.month(.abbreviated).day().year()),
                              id: "exerciseHistoryLastLogged")
            }
            CatalogWorkoutTrend(points: record?.workoutPoints ?? [], basis: record?.basis ?? LoadBasis(entry.prescription), unit: unit)
                .id(record?.id)
            if latest != nil {
                NavigationLink("View logged sets") {
                    CatalogLoggedSets(entry: entry, training: training, unit: unit)
                }
                .font(.subheadline)
            }
        }
        .padding(13)
        .background(PlannerStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(PlannerStyle.rule.opacity(0.42)).allowsHitTesting(false) }
    }

    private func metric(for record: ExerciseRecords?) -> (title: String, value: String?) {
        let result = record?.overviewResult
        switch record?.basis ?? LoadBasis(entry.prescription) {
        case .bodyweight: return ("Most reps", result?.reps?.formatted())
        case .timed: return ("Longest set", result?.seconds.map { "\($0.formatted()) sec" })
        case .assisted: return ("Latest assistance", result?.kg.map { weightText($0, unit) })
        default: return ("Max weight", result?.kg.map { weightText($0, unit) })
        }
    }

    private func seriesName(_ record: ExerciseRecords, at index: Int, among records: [ExerciseRecords]) -> String {
        let context = recordContext(record)
        let peers = records.filter { recordContext($0) == context }
        guard peers.count > 1 else { return context }
        let number = peers.firstIndex { $0.id == record.id }.map { $0 + 1 } ?? index + 1
        return "\(context) · Series \(number)"
    }

    private func historyMetric(_ title: String, value: String?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "N/A").font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(PlannerStyle.paper, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "N/A")
        .accessibilityIdentifier(id)
    }
}

private struct CatalogLoggedSets: View {
    let entry: CatalogEntry
    let training: TrainingStore
    let unit: String

    var body: some View {
        let results = training.sessions.lazy.flatMap(\.exercises)
            .filter { ($0.prescription.variantID ?? $0.prescription.id) == entry.id }
            .flatMap { exercise in
                exercise.sets.compactMap { set -> (id: UUID, date: Date, value: String)? in
                    guard let date = set.confirmedAt else { return nil }
                    return (set.id, date, actualDescription(set.actual.converted(to: unit), basis: exercise.basis))
                }
            }.sorted { $0.date > $1.date }
        List(results, id: \.id) { result in
            LabeledContent(result.date.formatted(date: .abbreviated, time: .shortened), value: result.value)
        }
        .navigationTitle("Logged sets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .scrollContentBackground(.hidden)
        .background(PlannerStyle.paper)
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
