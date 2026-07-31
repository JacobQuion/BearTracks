//
//  DiningService.swift
//  BearTracks
//
//  Cal Dining does not publish a JSON API, so we fetch the public menus page
//  and read the structure the site renders:
//
//      <div class="location-name Crossroads">
//          <div class="preiod-name Lunch">        // note: "preiod" is their typo
//              <div class="recip"><span>Item name</span> ... </div>
//
//  The parser reads names out of the CSS classes rather than matching a fixed
//  list, so it survives Cal Dining renaming meal periods between semesters.
//

import Foundation

/// Cal Dining labels meal periods with the semester attached, e.g.
/// "Spring - Brunch", so we bucket them into something stable to filter on.
enum MealKind: String, CaseIterable, Identifiable, Hashable {
    case breakfast = "Breakfast"
    case brunch = "Brunch"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case allDay = "All Day"
    case other = "Other"

    var id: String { rawValue }

    init(periodName: String) {
        let name = periodName.lowercased()
        if name.contains("breakfast") { self = .breakfast }
        else if name.contains("brunch") { self = .brunch }
        else if name.contains("lunch") { self = .lunch }
        else if name.contains("dinner") || name.contains("supper") { self = .dinner }
        else if name.contains("all day") || name.contains("allday") { self = .allDay }
        else { self = .other }
    }

    var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .brunch: return 1
        case .lunch: return 2
        case .dinner: return 3
        case .allDay: return 4
        case .other: return 5
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .brunch: return "sun.haze"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .allDay: return "clock"
        case .other: return "fork.knife"
        }
    }

    /// Best guess at what the user wants to see right now.
    static var currentGuess: MealKind {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<11: return .breakfast
        case 11..<16: return .lunch
        default: return .dinner
        }
    }
}

struct MenuPeriod: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let items: [String]

    var kind: MealKind { MealKind(periodName: name) }

    /// The period name with a leading semester word stripped, so
    /// "Summer - Brunch" reads as "Brunch" and a bare "Summer" reads as empty.
    var cleanedName: String {
        var text = name
        for semester in ["spring", "summer", "fall", "winter"] {
            text = text.replacingOccurrences(
                of: "(?i)\\b\(semester)\\b\\s*[-–—]?\\s*",
                with: "",
                options: .regularExpression
            )
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DiningLocation: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let periods: [MenuPeriod]

    var itemCount: Int { periods.reduce(0) { $0 + $1.items.count } }

    /// A period paired with the label to actually show for it.
    struct LabeledPeriod: Identifiable, Hashable {
        let id: UUID
        let label: String
        let symbol: String
        let period: MenuPeriod
    }

    /// Periods in serving order, each with a display label.
    ///
    /// Cal Dining labels periods by semester ("Summer", "Spring - Brunch"),
    /// which is useless to a student. When the name carries a real meal word
    /// we use that, and when it doesn't we fall back to labelling by position:
    /// three periods become breakfast, lunch and dinner, and two become
    /// breakfast and lunch/dinner.
    var labeledPeriods: [LabeledPeriod] {
        let ordered = periods.enumerated().sorted { lhs, rhs in
            if lhs.element.kind.sortOrder != rhs.element.kind.sortOrder {
                return lhs.element.kind.sortOrder < rhs.element.kind.sortOrder
            }
            // Ties keep the order Cal Dining rendered them in, which is
            // chronological. Swift's sort isn't stable, so this is explicit.
            return lhs.offset < rhs.offset
        }.map(\.element)

        let fallbacks = DiningLocation.positionalLabels(count: ordered.count)

        return ordered.enumerated().map { index, period in
            let label: String
            if period.kind != .other {
                label = period.kind.rawValue
            } else if !period.cleanedName.isEmpty {
                label = period.cleanedName
            } else {
                label = fallbacks[index]
            }
            return LabeledPeriod(
                id: period.id,
                label: label,
                symbol: DiningLocation.symbol(for: label),
                period: period
            )
        }
    }

    /// The meal labels this location is serving, e.g. "Breakfast, Lunch, Dinner".
    var mealSummary: String {
        labeledPeriods.map(\.label).joined(separator: ", ")
    }

    static func positionalLabels(count: Int) -> [String] {
        switch count {
        case 0: return []
        case 1: return ["All Day"]
        case 2: return ["Breakfast", "Lunch/Dinner"]
        case 3: return ["Breakfast", "Lunch", "Dinner"]
        default:
            var labels = ["Breakfast", "Lunch", "Dinner"]
            while labels.count < count {
                labels.append("Meal \(labels.count + 1)")
            }
            return labels
        }
    }

    static func symbol(for label: String) -> String {
        let lowered = label.lowercased()
        if lowered.contains("breakfast") { return "sunrise" }
        if lowered.contains("brunch") { return "sun.haze" }
        if lowered.contains("lunch") && lowered.contains("dinner") { return "sun.and.horizon" }
        if lowered.contains("lunch") { return "sun.max" }
        if lowered.contains("dinner") { return "moon.stars" }
        if lowered.contains("all day") { return "clock" }
        return "fork.knife"
    }

    /// Residential dining commons, which are the ones most students care about.
    var isDiningCommons: Bool {
        let commons = ["crossroads", "cafe 3", "café 3", "foothill", "clark kerr"]
        let lowered = name.lowercased()
        return commons.contains { lowered.contains($0) }
    }
}

/// Everything needed to work out why a parse came back thin, readable from
/// inside the app so we don't have to go spelunking in a terminal.
struct DiningDiagnostics {
    var requestedURL: String = ""
    var statusCode: Int = 0
    var byteCount: Int = 0
    var locationMarkers: Int = 0
    var periodMarkers: Int = 0
    var recipMarkers: Int = 0
    var parsedLocations: Int = 0
    var parsedItems: Int = 0
    /// Verbatim class attributes from the page, which is the ground truth.
    var sampleClasses: [String] = []

    var summary: String {
        """
        URL: \(requestedURL)
        HTTP status: \(statusCode)
        HTML size: \(byteCount) bytes

        Marker counts in the raw HTML
          location-name: \(locationMarkers)
          preiod-name / period-name: \(periodMarkers)
          recip: \(recipMarkers)

        After parsing
          locations: \(parsedLocations)
          menu items: \(parsedItems)

        Class attributes found on the page
        \(sampleClasses.isEmpty ? "  (none matched)" : sampleClasses.map { "  " + $0 }.joined(separator: "\n"))
        """
    }
}

struct DiningFetchResult {
    let locations: [DiningLocation]
    let diagnostics: DiningDiagnostics
}

enum DiningServiceError: LocalizedError {
    case badResponse(Int)
    case unreadable
    case noMenusFound

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "Cal Dining's site returned status \(code)."
        case .unreadable:
            return "Couldn't read the page Cal Dining sent back."
        case .noMenusFound:
            return "Cal Dining's page loaded but no menus were found in it. They may have changed their layout, or menus may not be posted yet."
        }
    }
}

/// The Cal Dining locations, hardcoded so the picker always lists every hall
/// even when the menus page only renders a few of them.
struct DiningHall: Identifiable, Hashable {
    let id: String
    let name: String
    let isResidential: Bool

    static let all: [DiningHall] = [
        .init(id: "crossroads", name: "Crossroads", isResidential: true),
        .init(id: "cafe3", name: "Café 3", isResidential: true),
        .init(id: "clarkkerr", name: "Clark Kerr Campus", isResidential: true),
        .init(id: "foothill", name: "Foothill", isResidential: true),
        .init(id: "goldenbear", name: "The Golden Bear Café", isResidential: false),
        .init(id: "studentunion", name: "The Eateries at Student Union", isResidential: false),
        .init(id: "browns", name: "Brown's", isResidential: false),
        .init(id: "bearmarket", name: "Bear Market", isResidential: false),
        .init(id: "cubmarket", name: "Cub Market", isResidential: false),
        .init(id: "localxdesign", name: "Local x Design", isResidential: false),
        .init(id: "theden", name: "The Den", isResidential: false)
    ]

    /// Loose comparison so "Clark_Kerr_Campus" from the page matches "Clark Kerr Campus".
    func matches(_ parsedName: String) -> Bool {
        let a = DiningHall.normalize(name)
        let b = DiningHall.normalize(parsedName)
        return a == b || a.contains(b) || b.contains(a)
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "the", with: "")
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

struct DiningService {

    private static let menusPath = "https://dining.berkeley.edu/menus/"

    /// Cal Dining's menus page takes a date. We send it under the couple of
    /// parameter names their front end has used; extras are ignored harmlessly.
    static func menusURL(for date: Date) -> URL {
        var components = URLComponents(string: menusPath)!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let text = f.string(from: date)

        if !Calendar.current.isDateInToday(date) {
            components.queryItems = [
                URLQueryItem(name: "date", value: text),
                URLQueryItem(name: "menu_date", value: text)
            ]
        }
        return components.url ?? URL(string: menusPath)!
    }

    static func fetchMenus(for date: Date = Date()) async throws -> DiningFetchResult {
        let url = menusURL(for: date)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Some WordPress front ends serve a stripped page to unknown clients.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if !(200...299).contains(status) {
            throw DiningServiceError.badResponse(status)
        }

        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw DiningServiceError.unreadable
        }

        let locations = parse(html: html)

        var diagnostics = DiningDiagnostics()
        diagnostics.requestedURL = url.absoluteString
        diagnostics.statusCode = status
        diagnostics.byteCount = data.count
        diagnostics.locationMarkers = occurrences(of: "location-name", in: html)
        diagnostics.periodMarkers = occurrences(of: "preiod-name", in: html)
            + occurrences(of: "period-name", in: html)
        diagnostics.recipMarkers = occurrences(of: "recip", in: html)
        diagnostics.parsedLocations = locations.count
        diagnostics.parsedItems = locations.reduce(0) { $0 + $1.itemCount }
        diagnostics.sampleClasses = interestingClassAttributes(in: html)

        return DiningFetchResult(locations: locations, diagnostics: diagnostics)
    }

    // MARK: - Diagnostics helpers

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var range = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, options: .caseInsensitive, range: range) {
            count += 1
            range = found.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Pulls distinct class attributes that look menu related, so we can see
    /// the real markup instead of guessing at it.
    private static func interestingClassAttributes(in html: String) -> [String] {
        let pattern = "class\\s*=\\s*[\"']([^\"']{0,120})[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let keywords = ["location", "period", "preiod", "recip", "menu", "meal", "hall", "date", "day"]
        let ns = html as NSString

        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let value = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = value.lowercased()
            guard keywords.contains(where: { lowered.contains($0) }) else { continue }
            guard !seen.contains(lowered) else { continue }
            seen.insert(lowered)
            result.append(value)
            if result.count >= 40 { break }
        }
        return result
    }

    // MARK: - Parsing

    static func parse(html: String) -> [DiningLocation] {
        let locationBlocks = blocks(in: html, markerClass: "location-name")

        return locationBlocks.compactMap { block in
            let periodBlocks = blocks(in: block.body, markerClass: "preiod-name")
                + blocks(in: block.body, markerClass: "period-name")

            let periods: [MenuPeriod] = periodBlocks.compactMap { periodBlock in
                let items = recipeItems(in: periodBlock.body)
                guard !items.isEmpty else { return nil }
                return MenuPeriod(name: periodBlock.name, items: items)
            }

            guard !periods.isEmpty else { return nil }
            return DiningLocation(name: block.name, periods: periods)
        }
    }

    private struct Block {
        let name: String
        let body: String
    }

    /// Finds every element carrying `markerClass` and returns its readable name
    /// (the other class token) plus everything up to the next such element.
    private static func blocks(in html: String, markerClass: String) -> [Block] {
        let pattern = "class\\s*=\\s*[\"']([^\"']*\\b\(markerClass)\\b[^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [] }

        var result: [Block] = []
        for (index, match) in matches.enumerated() {
            let classAttribute = ns.substring(with: match.range(at: 1))
            let name = readableName(from: classAttribute, excluding: markerClass)
            guard !name.isEmpty else { continue }

            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count
                ? matches[index + 1].range.location
                : ns.length
            guard end > start else { continue }

            result.append(Block(name: name, body: ns.substring(with: NSRange(location: start, length: end - start))))
        }
        return result
    }

    private static func readableName(from classAttribute: String, excluding marker: String) -> String {
        let ignored: Set<String> = [
            marker.lowercased(), "location-name", "preiod-name", "period-name",
            "active", "open", "closed", "col", "row", "hidden", "show", "menu", "item"
        ]
        let tokens = classAttribute
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { !ignored.contains($0.lowercased()) }

        // Join every remaining token, not just the first. Cal Dining splits
        // names across classes ("preiod-name Summer Brunch"), so taking only
        // the first token loses the part that actually identifies the meal.
        guard !tokens.isEmpty else { return "" }
        let spaced = decodeEntities(tokens.joined(separator: " ").replacingOccurrences(of: "_", with: " "))
        // Collapse any runs of whitespace, e.g. "Spring - Brunch".
        return spaced
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Pulls the dish names out of `<div class="recip"><span>Name</span>...`.
    private static func recipeItems(in html: String) -> [String] {
        let pattern = "class\\s*=\\s*[\"'][^\"']*\\brecip\\b[^\"']*[\"'][^>]*>\\s*<span[^>]*>([^<]{2,120})</span>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        var seen = Set<String>()
        var items: [String] = []
        for match in matches {
            let raw = ns.substring(with: match.range(at: 1))
            let name = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count > 1, !seen.contains(name.lowercased()) else { continue }
            seen.insert(name.lowercased())
            items.append(name)
        }
        return items
    }

    private static func decodeEntities(_ text: String) -> String {
        var out = text
        let map: [String: String] = [
            "&amp;": "&", "&#038;": "&", "&quot;": "\"", "&#034;": "\"",
            "&apos;": "'", "&#039;": "'", "&#8217;": "\u{2019}", "&#8216;": "\u{2018}",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#8211;": "-", "&#8212;": "\u{2014}",
            "&eacute;": "é", "&#233;": "é"
        ]
        for (entity, replacement) in map {
            out = out.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        return out
    }
}
