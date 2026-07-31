//
//  LibraryView.swift
//  BearTracks
//

import SwiftUI
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var libraries: [Library] = []
    @Published private(set) var fetchedAt: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var searchText = ""
    @Published var openNowOnly = false

    /// Branches matching the search box and the "open now" toggle, sorted with
    /// open ones first and then alphabetically.
    var filtered: [Library] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return libraries
            .filter { library in
                if openNowOnly && !library.isOpen { return false }
                guard !query.isEmpty else { return true }
                return library.name.lowercased().contains(query)
                    || library.address.lowercased().contains(query)
            }
            .sorted { lhs, rhs in
                if lhs.isOpen != rhs.isOpen { return lhs.isOpen && !rhs.isOpen }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var openCount: Int { libraries.filter(\.isOpen).count }

    var updatedText: String? {
        guard let fetchedAt else { return nil }
        return "Updated \(fetchedAt.formatted(date: .omitted, time: .shortened)) · today's hours"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await LibraryService.fetchHours()
            libraries = result.libraries
            fetchedAt = result.fetchedAt
        } catch {
            libraries = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Screen

struct LibraryView: View {
    @StateObject private var model = LibraryViewModel()
    @State private var selected: Library?

    var body: some View {
        NavigationStack {
            Group {
                if model.libraries.isEmpty && model.isLoading {
                    ProgressView("Loading hours")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = model.errorMessage, model.libraries.isEmpty {
                    errorState(errorMessage)
                } else {
                    list
                }
            }
            .navigationTitle("Libraries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .searchable(text: $model.searchText, prompt: "Search libraries")
            .navigationDestination(item: $selected) { library in
                LibraryDetailView(library: library)
            }
            .refreshable { await model.load() }
            .task {
                if model.libraries.isEmpty { await model.load() }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Picker("Show", selection: $model.openNowOnly) {
                    Text("All (\(model.libraries.count))").tag(false)
                    Text("Open now (\(model.openCount))").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(model.filtered) { library in
                    Button {
                        selected = library
                    } label: {
                        row(for: library)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                if let updated = model.updatedText {
                    Text(updated)
                }
            }
        }
    }

    private func row(for library: Library) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryImage(url: library.imageURL, height: 130)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(library.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 5) {
                        Text(library.statusText)
                            .foregroundStyle(library.isOpen ? Color.green : Color.secondary)
                        if !library.hoursToday.isEmpty {
                            Text("· \(library.hoursToday)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(Theme.californiaGold)
            Text("Couldn't reach the Library")
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

// MARK: - Image

/// A branch photo cropped to a uniform size, so every row and header lines up
/// regardless of the source image's dimensions. Shows a themed placeholder
/// while loading or if the image is missing.
struct LibraryImage: View {
    let url: URL?
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Theme.card)
            .frame(height: height)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                    default:
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.californiaGold.opacity(0.6))
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

// MARK: - Detail

struct LibraryDetailView: View {
    let library: Library

    var body: some View {
        List {
            Section {
                LibraryImage(url: library.imageURL, height: 180)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: library.isOpen ? "circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(library.isOpen ? Color.green : Color.secondary)
                    Text(library.statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(library.isOpen ? Color.green : Color.secondary)
                    Spacer()
                    Text(library.hoursDisplay)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Today")
                    .foregroundStyle(Theme.heading)
                    .textCase(nil)
            }

            if !library.address.isEmpty {
                Section {
                    Text(library.address)
                        .font(.subheadline)
                        .textSelection(.enabled)
                } header: {
                    Text("Address")
                        .foregroundStyle(Theme.heading)
                        .textCase(nil)
                }
            }

            Section {
                if let mapsURL = library.mapsURL {
                    linkRow(icon: "map", title: "Directions", url: mapsURL)
                }
                if let phone = library.phone, let telURL = URL(string: "tel:\(phone.filter { $0.isNumber })") {
                    linkRow(icon: "phone", title: phone, url: telURL)
                }
                if let pageURL = library.pageURL {
                    linkRow(icon: "safari", title: "Library page", url: pageURL)
                }
            }
        }
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func linkRow(icon: String, title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.californiaGold)
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    LibraryView()
}
