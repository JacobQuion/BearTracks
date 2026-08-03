//
//  DiningView.swift
//  BearTracks
//

import SwiftUI
import Combine

@MainActor
final class DiningViewModel: ObservableObject {
    @Published private(set) var locations: [DiningLocation] = []
    @Published private(set) var diagnostics = DiningDiagnostics()
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var selectedHall: DiningHall = DiningHall.all[0]

    /// Diet chips the user requires; a dish must carry every one of them.
    @Published var activeDiets: Set<DietaryTag> = []

    /// Allergens the user wants to steer clear of; any dish carrying one is
    /// hidden.
    @Published var avoidAllergens: Set<DietaryTag> = []

    /// The diet filters offered, shown as fixed buttons.
    static let dietFilters: [DietaryTag] = [.vegan, .vegetarian, .halal, .kosher]

    /// The allergen filters offered ("No …"), shown as fixed buttons.
    static let allergenFilters: [DietaryTag] = [.dairy, .peanut]

    var hasActiveFilters: Bool { !activeDiets.isEmpty || !avoidAllergens.isEmpty }

    /// Whether a dish satisfies the active diet requirements and carries none
    /// of the avoided allergens.
    func passesFilters(_ item: MenuItem) -> Bool {
        activeDiets.isSubset(of: item.tags) && item.tags.isDisjoint(with: avoidAllergens)
    }

    /// Dish-name fragments hidden from a hall's browsed menu — staples and
    /// sides (bagels, yogurt, plain rice, …) that clutter the list. Matched
    /// as case-insensitive substrings. Only applied to the hall menu browse,
    /// not the cross-hall search, so these can still be searched for by name.
    static let hiddenKeywords: [String] = [
        "bagel", "cream", "capers", "oatmeal", "brown rice", "jasmine rice",
        "sauteed mushroom vegetable blend", "yogurt", "seeds", "dressing",
        "salad", "hummus", "mung bean", "sliced almond", "mini", "base",
        "lettuce", "red beets", "carrots", "cucumbers", "grape tomato",
        "quinoa", "cruton", "crouton", "vinegar", "balsamic", "vegan cheese",
        "green olive", "butter", "granola", "cranberry", "flakes",
        "basmati rice", "basil", "black olive", "olive oil", "pickle",
        "spinach", "sliced cucumber", "cherry tomatoes", "sliced radish",
        "raisins", "vinaigrette"
    ]

    static func isHidden(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return hiddenKeywords.contains { lowered.contains($0) }
    }

    /// Items to show when browsing a hall's menu: the period's dishes with
    /// staple sides hidden to cut clutter and the active diet/allergen filters
    /// applied.
    func displayItems(in period: MenuPeriod) -> [MenuItem] {
        period.items.filter { !Self.isHidden($0.name) && passesFilters($0) }
    }

    /// Every dish across every hall whose name matches `query`, grouped by hall
    /// (dining commons first), with the same staple-hiding truncation as the
    /// browsed hall menu.
    func dishSections(matching query: String) -> [(hall: DiningHall, hits: [DishHit])] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var sections: [(DiningHall, [DishHit])] = []
        for hall in DiningHall.all {
            guard let location = location(for: hall) else { continue }
            var hits: [DishHit] = []
            for period in location.labeledPeriods {
                for item in displayItems(in: period.period) where item.name.lowercased().contains(q) {
                    hits.append(DishHit(item: item, hall: hall, meal: period.label))
                }
            }
            if !hits.isEmpty { sections.append((hall, hits)) }
        }
        return sections
    }

    // MARK: Notable items

    /// Standout dishes worth surfacing at the top of the tab. Each entry is
    /// matched loosely: a multi-word keyword only needs every word to appear
    /// somewhere in the dish name, so "pesto pasta" catches "Penne Pasta with
    /// Pesto" and "tri tip" catches both "Tri-Tip" and "TriTip".
    static let notableKeywords: [String] = [
        "baked pork bacon", "tri tip", "salmon", "lobster", "pesto", "alfredo", "fettucini", "marinara"
    ]

    /// Words that disqualify a dish even if it matches a notable keyword, so a
    /// "salmon sandwich" or "pesto sauce" doesn't get surfaced as a standout.
    static let notableExclusions: [String] = ["sandwich", "sauce", "bisque", "meatball"]

    static func isNotable(_ name: String) -> Bool {
        let lowered = name.lowercased()
        guard !notableExclusions.contains(where: { lowered.contains($0) }) else { return false }
        return notableKeywords.contains { keyword in
            keyword.split(separator: " ").allSatisfy { lowered.contains($0) }
        }
    }

    /// Every notable dish on the selected day, across the residential dining
    /// commons, sorted by when it's served — breakfast first, then lunch, then
    /// dinner — with halls kept in their canonical order within a meal.
    /// Duplicates of the same dish at the same hall and meal are collapsed.
    func notableDishes() -> [DishHit] {
        var hits: [DishHit] = []
        var seen = Set<String>()
        // Only the residential dining commons (Crossroads, Café 3, Clark Kerr,
        // Foothill); the retail cafés aren't where standout meals show up.
        for hall in DiningHall.all where hall.isResidential {
            guard let location = location(for: hall) else { continue }
            for period in location.labeledPeriods {
                for item in period.period.items where Self.isNotable(item.name) {
                    let key = "\(hall.id)|\(item.name.lowercased())|\(period.label)"
                    guard seen.insert(key).inserted else { continue }
                    hits.append(DishHit(item: item, hall: hall, meal: period.label))
                }
            }
        }
        return hits.sorted { lhs, rhs in
            let lhsMeal = MealKind(periodName: lhs.meal).sortOrder
            let rhsMeal = MealKind(periodName: rhs.meal).sortOrder
            if lhsMeal != rhsMeal { return lhsMeal < rhsMeal }
            return hallOrder(lhs.hall) < hallOrder(rhs.hall)
        }
    }

    /// Position of a hall in the canonical `DiningHall.all` order.
    private func hallOrder(_ hall: DiningHall) -> Int {
        DiningHall.all.firstIndex { $0.id == hall.id } ?? Int.max
    }

    // MARK: Lookups

    func location(for hall: DiningHall) -> DiningLocation? {
        locations.first { hall.matches($0.name) }
    }

    var menuForSelection: DiningLocation? { location(for: selectedHall) }

    /// Every meal the selected hall is serving that day, in serving order and
    /// already labelled breakfast / lunch / dinner.
    var labeledPeriods: [DiningLocation.LabeledPeriod] {
        menuForSelection?.labeledPeriods ?? []
    }

    /// Halls the page actually returned a menu for.
    var hallsWithMenus: [DiningHall] {
        DiningHall.all.filter { hall in locations.contains { hall.matches($0.name) } }
    }

    /// The residential dining commons, shown as their own cards.
    var diningCommons: [DiningHall] { DiningHall.all.filter(\.isResidential) }

    /// Everything else — the retail cafés and markets — grouped under a single
    /// "Campus Eateries" entry.
    var campusEateries: [DiningHall] { DiningHall.all.filter { !$0.isResidential } }

    // MARK: Dates

    var selectableDates: [Date] {
        (-1...6).compactMap {
            Calendar.current.date(byAdding: .day, value: $0,
                                  to: Calendar.current.startOfDay(for: Date()))
        }
    }

    var dateLabel: String { Self.label(for: selectedDate) }

    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await DiningService.fetchMenus(for: selectedDate)
            locations = result.locations
            diagnostics = result.diagnostics
        } catch {
            locations = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// A single matching dish from a cross-hall search: the dish, which hall it's
/// at, and which meal it's served in.
struct DishHit: Identifiable, Hashable {
    let id = UUID()
    let item: MenuItem
    let hall: DiningHall
    let meal: String
}

// MARK: - Picker screen

struct DiningView: View {
    @StateObject private var model = DiningViewModel()
    @State private var showingMenu = false
    @State private var showingEateries = false
    @State private var showingDiagnostics = false
    @State private var searchText = ""

    /// Shared app-wide appearance setting, toggled from the top-right menu.
    @AppStorage("isDarkMode") private var isDarkMode = true

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                searchDayBar

                if isSearching {
                    searchResults
                } else {
                    hallBrowser
                }
            }
            .navigationTitle("Dining")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isDarkMode.toggle()
                        } label: {
                            Label(isDarkMode ? "Light Mode" : "Dark Mode",
                                  systemImage: isDarkMode ? "sun.max" : "moon")
                        }
                        Button {
                            Task { await model.load() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button {
                            showingDiagnostics = true
                        } label: {
                            Label("Diagnostics", systemImage: "stethoscope")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showingMenu) {
                MenuResultView(model: model)
            }
            .navigationDestination(isPresented: $showingEateries) {
                CampusEateriesView(model: model, showMenu: $showingMenu)
            }
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsView(text: model.diagnostics.summary)
            }
            .refreshable { await model.load() }
            .onChange(of: model.selectedDate) { _, _ in
                Task { await model.load() }
            }
            .task {
                if model.locations.isEmpty { await model.load() }
            }
        }
    }

    // MARK: Search + day bar

    /// A single top row: a compact day selector on the left and a dish search
    /// field on the right. Persists across both the hall browser and search
    /// results so the search field never disappears mid-query.
    private var searchDayBar: some View {
        Section {
            HStack(spacing: 10) {
                Menu {
                    Picker("Day", selection: $model.selectedDate) {
                        ForEach(model.selectableDates, id: \.self) { date in
                            Text(DiningViewModel.label(for: date)).tag(date)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.footnote)
                        Text(model.dateLabel)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.primary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Search dishes", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if isSearching {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Hall browser

    @ViewBuilder
    private var hallBrowser: some View {
        notableSection

        Section {
            ForEach(model.diningCommons) { hall in
                Button {
                    model.selectedHall = hall
                    showingMenu = true
                } label: {
                    hallCard(for: hall)
                }
                .buttonStyle(.plain)
            }

            Button {
                showingEateries = true
            } label: {
                eateriesCard
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Campus eateries card

    /// A single entry standing in for every retail café and market, tapped to
    /// open the full list.
    private var eateriesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiningImage(url: nil, assetName: "CampusEateriesBanner", height: 130)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Campus Restaurants")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(eateriesSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// A short teaser of the eateries, e.g. "Golden Bear Café, Brown's & 5 more".
    private var eateriesSubtitle: String {
        let names = model.campusEateries.map(\.name)
        guard names.count > 2 else { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) & \(names.count - 2) more"
    }

    // MARK: Notable items

    /// Standout dishes (steak, salmon, lobster, …) across every hall for the
    /// selected day, shown above the hall list. Falls back to a gentle note
    /// when nothing notable is being served.
    private var notableSection: some View {
        let dishes = model.notableDishes()
        return Section {
            if dishes.isEmpty {
                Text("Nothing much. It's a Flex/Flex+ day!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dishes) { hit in
                    Button {
                        model.selectedHall = hit.hall
                        showingMenu = true
                    } label: {
                        notableRow(hit)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Label("Notable Dining Hall Dishes", systemImage: "star.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.californiaGold)
                .textCase(nil)
        } footer: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                Text("Cal Dining: \"menus are subject to change.\"")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func notableRow(_ hit: DishHit) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.item.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text("\(hit.hall.name) · \(hit.meal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: Cross-hall search

    @ViewBuilder
    private var searchResults: some View {
        let sections = model.dishSections(matching: searchText)

        TruncationNotice()

        if model.locations.isEmpty && model.isLoading {
            Section { ProgressView("Loading menus") }
        } else if sections.isEmpty {
            Section {
                Text("No dishes match “\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))” on \(model.dateLabel.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(sections, id: \.hall.id) { section in
                Section {
                    ForEach(section.hits) { hit in
                        Button {
                            model.selectedHall = hit.hall
                            showingMenu = true
                        } label: {
                            dishHitRow(hit)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(section.hall.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.heading)
                        .textCase(nil)
                }
            }
        }
    }

    private func dishHitRow(_ hit: DishHit) -> some View {
        HStack {
            Text(hit.item.name)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(hit.meal)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.californiaGold)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: Hall card

    private func hallCard(for hall: DiningHall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DiningImage(url: hall.imageURL, assetName: hall.assetName, height: 130)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hall.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle(for: hall))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// What to show under the hall name: the meals it's serving today, or a
    /// gentle note when nothing's posted.
    private func subtitle(for hall: DiningHall) -> String {
        if model.isLoading && model.locations.isEmpty { return "Loading menu…" }
        if let summary = model.location(for: hall)?.mealSummary, !summary.isEmpty {
            return summary
        }
        return "No menu posted"
    }
}

// MARK: - Campus eateries

/// The full list of retail cafés and markets, reached from the single
/// "Campus Eateries" card on the Dining screen. Tapping one opens its menu.
struct CampusEateriesView: View {
    @ObservedObject var model: DiningViewModel
    @Binding var showMenu: Bool

    var body: some View {
        List {
            Section {
                ForEach(model.campusEateries) { hall in
                    Button {
                        model.selectedHall = hall
                        showMenu = true
                    } label: {
                        card(for: hall)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Campus Restaurants")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(for hall: DiningHall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DiningImage(url: hall.imageURL, assetName: hall.assetName, height: 130)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hall.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle(for: hall))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func subtitle(for hall: DiningHall) -> String {
        if model.isLoading && model.locations.isEmpty { return "Loading menu…" }
        if let summary = model.location(for: hall)?.mealSummary, !summary.isEmpty {
            return summary
        }
        return "No menu posted"
    }
}

// MARK: - Image

/// A hall photo cropped to a uniform size, mirroring the Library tab's cards.
struct DiningImage: View {
    let url: URL?
    var assetName: String? = nil
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Theme.card)
            .frame(height: height)
            .overlay {
                if let assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                        default:
                            Image(systemName: "fork.knife")
                                .font(.system(size: 30))
                                .foregroundStyle(Theme.californiaGold.opacity(0.6))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - Menu result

struct MenuResultView: View {
    @ObservedObject var model: DiningViewModel

    private var periods: [DiningLocation.LabeledPeriod] { model.labeledPeriods }

    /// The meals that actually have something to show once staples are hidden
    /// and diet filters applied, each paired with its visible items. Filtering
    /// here — rather than inside the `ForEach` — keeps SwiftUI from leaving a
    /// blank ghost section behind when a meal's items are all filtered out.
    private var visiblePeriods: [(entry: DiningLocation.LabeledPeriod, items: [MenuItem])] {
        periods.compactMap { entry in
            let items = model.displayItems(in: entry.period)
            return items.isEmpty ? nil : (entry, items)
        }
    }

    /// A fingerprint of exactly what the menu list is showing. Applied as the
    /// List's `.id`, it forces a clean rebuild whenever the hall, date, or the
    /// filtered item set changes — so SwiftUI never diffs a shrinking `ForEach`
    /// and leaves phantom blank rows where hidden items used to be.
    private var menuSignature: String {
        let shape = visiblePeriods
            .map { "\($0.entry.id):\($0.items.count)" }
            .joined(separator: ",")
        let filters = model.activeDiets.map(\.rawValue).sorted().joined(separator: "+")
            + "/" + model.avoidAllergens.map(\.rawValue).sorted().joined(separator: "+")
        return "\(model.selectedHall.id)|\(model.selectedDate.timeIntervalSince1970)|\(filters)|\(shape)"
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Loading menu")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage {
                errorState(errorMessage)
            } else if periods.isEmpty {
                emptyState
            } else {
                menuList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(model.selectedHall.name)
                        .font(.headline)
                    Text(model.dateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Menu

    private var menuList: some View {
        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                TruncationNoticeRow()
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filters")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.heading)
                .textCase(nil)
            }

            ForEach(visiblePeriods, id: \.entry.id) { entry, items in
                Section {
                    ForEach(items) { item in
                        MenuItemRow(item: item)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: entry.symbol)
                        Text(entry.label)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.heading)
                    .textCase(nil)
                }
            }

            if model.hasActiveFilters && visiblePeriods.isEmpty {
                Text("Nothing here matches those filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .id(menuSignature)
    }

    // MARK: Filters

    private static let filterColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 3
    )

    private static let avoidRed = Color(red: 0.78, green: 0.22, blue: 0.22)

    /// A fixed grid of six always-visible filter buttons: diet buttons narrow
    /// the menu to dishes that carry the tag; "No …" allergen buttons hide any
    /// dish that carries the tag.
    private var filterBar: some View {
        LazyVGrid(columns: Self.filterColumns, spacing: 8) {
            ForEach(DiningViewModel.dietFilters) { diet in
                filterButton(diet.label, symbol: diet.symbol,
                             isOn: model.activeDiets.contains(diet),
                             onColor: .green) {
                    toggle(diet, in: \.activeDiets)
                }
            }
            ForEach(DiningViewModel.allergenFilters) { allergen in
                filterButton("No \(allergen.label)", symbol: "nosign",
                             isOn: model.avoidAllergens.contains(allergen),
                             onColor: Self.avoidRed) {
                    toggle(allergen, in: \.avoidAllergens)
                }
            }
        }
    }

    private func toggle(_ tag: DietaryTag,
                        in keyPath: ReferenceWritableKeyPath<DiningViewModel, Set<DietaryTag>>) {
        if model[keyPath: keyPath].contains(tag) {
            model[keyPath: keyPath].remove(tag)
        } else {
            model[keyPath: keyPath].insert(tag)
        }
    }

    private func filterButton(_ text: String, symbol: String, isOn: Bool,
                              onColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(isOn ? onColor : Color.primary.opacity(0.10)))
            .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty

    /// Never a dead end. If the exact pick has nothing, show what Cal Dining
    /// is actually serving so there's always a way forward.
    private var emptyState: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.californiaGold)
                    Text("Nothing posted for \(model.selectedHall.name)")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Cal Dining hasn't published a menu here for \(model.dateLabel.lowercased()).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            if !model.hallsWithMenus.isEmpty {
                Section {
                    ForEach(model.hallsWithMenus) { hall in
                        Button {
                            model.selectedHall = hall
                        } label: {
                            HStack {
                                Text(hall.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Open elsewhere")
                } footer: {
                    Text("Tap a location to jump to its menu.")
                }
            }

            Section {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Link(destination: URL(string: "https://dining.berkeley.edu/menus/")!) {
                    Label("Open Cal Dining site", systemImage: "safari")
                }
            }
        }
    }

    // MARK: Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.californiaGold)
            Text("Couldn't reach Cal Dining")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await model.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.control)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Truncation notice

/// A short note explaining the menu is trimmed to standout dishes. Pinned at
/// the top of both the cross-hall search and each hall's menu.
struct TruncationNotice: View {
    var body: some View {
        Section {
            TruncationNoticeRow()
        }
        .listRowBackground(Color.clear)
    }
}

/// The bare notice row, so it can also sit inside another section (e.g. right
/// under the filter buttons) without the extra inter-section spacing.
struct TruncationNoticeRow: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.californiaGold)
            Text("Staples like yogurt and salads are hidden for brevity.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Menu item row

struct MenuItemRow: View {
    let item: MenuItem

    var body: some View {
        Text(item.name)
            .font(.subheadline)
            .padding(.vertical, 2)
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Copy") { UIPasteboard.general.string = text }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DiningView()
}
