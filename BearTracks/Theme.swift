//
//  Theme.swift
//  BearTracks
//

import SwiftUI
import CoreLocation

enum Theme {
    /// Official UC Berkeley "Berkeley Blue". Dark, so it's used for fills that
    /// sit behind white text rather than for text itself.
    static let berkeleyBlue = Color(red: 0.0, green: 0.196, blue: 0.384)

    /// Official UC Berkeley "California Gold". The app runs in dark mode, so
    /// this carries headings and labels where the blue would disappear.
    static let californiaGold = Color(red: 0.992, green: 0.710, blue: 0.082)

    /// "Founders Rock", Berkeley's mid blue. Readable on a dark background,
    /// so it drives buttons and controls.
    static let foundersRock = Color(red: 0.231, green: 0.494, blue: 0.631)

    /// "Lawrence", the bright accent blue.
    static let lawrence = Color(red: 0.0, green: 0.690, blue: 0.855)

    // Semantic roles, so intent is obvious at the call site.
    static let heading = californiaGold
    static let control = foundersRock
    static let card = Color(red: 0.11, green: 0.12, blue: 0.14)
}

enum Campus {
    /// Roughly the center of the UC Berkeley campus, near the Campanile.
    static let center = CLLocationCoordinate2D(latitude: 37.8719, longitude: -122.2585)
}
