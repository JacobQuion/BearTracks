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

    /// Diet chips the user has switched on; an item must satisfy all of them.
    @Published var activeDiets: Set<DietaryTag> = []

    func items(in period: MenuPeriod) -> [MenuItem] {
        guard !activeDiets.isEmpty else { return period.items }
        return period.items.filter { activeDiets.isSubset(of: $0.tags) }
    }

    /// Every dish across every hall whose name matches `query`, grouped by hall
    /// (dining commons first), honoring the active diet chips.
    func dishSections(matching query: String) -> [(hall: DiningHall, hits: [DishHit])] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var sections: [(DiningHall, [DishHit])] = []
        for hall in DiningHall.all {
            guard let location = location(for: hall) else { continue }
            var hits: [DishHit] = []
            for period in location.labeledPeriods {
                for item in items(in: period.period) where item.name.lowercased().contains(q) {
                    hits.append(DishHit(item: item, hall: hall, meal: period.label))
                }
            }
            if !hits.isEmpty { sections.append((hall, hits)) }
        }
        return sections
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
    @State private var showingDiagnostics = false
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    searchResults
                } else {
                    hallBrowser
                }
            }
            .navigationTitle("Dining")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search dishes across halls")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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

    // MARK: Hall browser

    @ViewBuilder
    private var hallBrowser: some View {
        Section {
            Picker("Day", selection: $model.selectedDate) {
                ForEach(model.selectableDates, id: \.self) { date in
                    Text(DiningViewModel.label(for: date)).tag(date)
                }
            }
        }

        Section {
            ForEach(DiningHall.all) { hall in
                Button {
                    model.selectedHall = hall
                    showingMenu = true
                } label: {
                    hallCard(for: hall)
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text("Tap a hall to see every meal it's serving on \(model.dateLabel.lowercased()).")
        }
    }

    // MARK: Cross-hall search

    @ViewBuilder
    private var searchResults: some View {
        let sections = model.dishSections(matching: searchText)

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hit.item.name)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(hit.meal)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.californiaGold)
            }

            if !hit.item.diets.isEmpty || hit.item.carbon != nil {
                HStack(spacing: 6) {
                    ForEach(hit.item.diets) { DietBadge(tag: $0) }
                    if let carbon = hit.item.carbon { CarbonBadge(rating: carbon) }
                }
            }
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
                dietFilterBar
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            ForEach(periods) { entry in
                let items = model.items(in: entry.period)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            MenuItemRow(item: item)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: entry.symbol)
                            Text(entry.label)
                            Spacer()
                            Text("\(items.count)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.heading)
                        .textCase(nil)
                    }
                }
            }

            if noItemsAfterFilter {
                Text("Nothing here matches those filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// True when a filter is on and it's hidden every dish in every period.
    private var noItemsAfterFilter: Bool {
        !model.activeDiets.isEmpty
            && periods.allSatisfy { model.items(in: $0.period).isEmpty }
    }

    private var dietFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DietaryTag.diets) { diet in
                    let isOn = model.activeDiets.contains(diet)
                    Button {
                        if isOn { model.activeDiets.remove(diet) }
                        else { model.activeDiets.insert(diet) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: diet.symbol).font(.system(size: 10))
                            Text(diet.label)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(isOn ? Theme.control : Color.primary.opacity(0.10))
                        )
                        .foregroundStyle(isOn ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

// MARK: - Menu item row

struct MenuItemRow: View {
    let item: MenuItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.subheadline)

            if !item.diets.isEmpty || item.carbon != nil || !item.allergens.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.diets) { DietBadge(tag: $0) }
                    if let carbon = item.carbon { CarbonBadge(rating: carbon) }
                    if !item.allergens.isEmpty {
                        Label(item.allergens.map(\.label).joined(separator: ", "),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct DietBadge: View {
    let tag: DietaryTag

    private var color: Color {
        switch tag {
        case .vegan, .vegetarian: return .green
        case .halal, .kosher: return Theme.lawrence
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: tag.symbol).font(.system(size: 9))
            Text(tag.label).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.22)))
        .foregroundStyle(color)
    }
}

struct CarbonBadge: View {
    let rating: CarbonRating

    private var color: Color {
        switch rating {
        case .low: return .green
        case .med: return .yellow
        case .high: return .orange
        }
    }

    private var text: String {
        switch rating {
        case .low: return "Low CO₂"
        case .med: return "Med CO₂"
        case .high: return "High CO₂"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "leaf.fill").font(.system(size: 9))
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.20)))
        .foregroundStyle(color)
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
