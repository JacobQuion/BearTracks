//
//  GymView.swift
//  BearTracks
//
//  RecWell publishes the RSF weight room's live occupancy through a Density
//  SAFE display, embedded on their own page with a public share token:
//
//      https://recwell.berkeley.edu/facilities/recreational-sports-facility-rsf/
//          rsf-weight-room-crowd-meter/
//
//  Density's SAFE display is a JavaScript app and its underlying API isn't
//  publicly documented, so rather than guess at an endpoint we embed the exact
//  display RecWell embeds. It always shows whatever their own page shows.
//

import SwiftUI
import WebKit

enum RSF {
    /// The live weight room meter, taken verbatim from RecWell's page.
    static let weightRoomMeter = URL(string: "https://safe.density.io/#/displays/dsp_956223069054042646?token=shr_o69HxjQ0BYrY2FPD9HxdirhJYcFDCeRolEd744Uj88e")!

    static let virtualLine = URL(string: "https://417804.waitwell.us/join/48")!
    static let hoursPage = URL(string: "https://recwell.berkeley.edu/facilities/recreational-sports-facility-rsf/rsf-hours/")!
    static let cardioMeterPage = URL(string: "https://recwell.berkeley.edu/facilities/recreational-sports-facility-rsf/rsf-cardio-equipment-usage-meter/")!
    static let facilityPage = URL(string: "https://recwell.berkeley.edu/facilities/recreational-sports-facility-rsf/")!
    static let maps = URL(string: "https://maps.apple.com/?q=Recreational+Sports+Facility&ll=37.868578,-122.265017")!

    static let address = "2301 Bancroft Way, Berkeley, CA 94720"
}

// MARK: - Web view

/// Whether the embedded meter page reached the network and loaded.
enum MeterLoadState {
    case loading, loaded, failed
}

struct MeterWebView: UIViewRepresentable {
    let url: URL
    /// Bumping this from the parent triggers a reload.
    var reloadCount: Int
    /// Reported back so the parent can show a graceful note on failure.
    @Binding var loadState: MeterLoadState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MeterWebView
        var lastReloadCount = 0

        init(_ parent: MeterWebView) { self.parent = parent }

        /// Delegate callbacks can land mid-update, so bounce state changes to
        /// the next runloop tick to avoid "modifying state during view update".
        private func report(_ state: MeterLoadState) {
            DispatchQueue.main.async { self.parent.loadState = state }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            report(.loaded)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(.failed)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(.failed)
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))

        context.coordinator.lastReloadCount = reloadCount
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastReloadCount != reloadCount else { return }
        context.coordinator.lastReloadCount = reloadCount
        DispatchQueue.main.async { self.loadState = .loading }
        webView.load(URLRequest(url: url))
    }
}

// MARK: - Screen

struct GymView: View {
    @State private var reloadCount = 0
    @State private var lastRefreshed = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    meterCard
                    lineCard
                    infoCard
                }
                .padding(16)
            }
            .navigationTitle("RSF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reloadCount += 1
                        lastRefreshed = Date()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                reloadCount += 1
                lastRefreshed = Date()
            }
        }
    }

    // MARK: Live meter

    private var meterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Theme.californiaGold)
                Text("Crowd Meter")
                    .font(.headline)
                    .foregroundStyle(Theme.heading)
            }

            MeterWebView(url: RSF.weightRoomMeter, reloadCount: reloadCount)
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened)) · pull down to refresh")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Virtual line

    private var lineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Theme.californiaGold)
                Text("Packed?")
                    .font(.headline)
                    .foregroundStyle(Theme.heading)
            }

            Text("RecWell opens a virtual line whenever the weight room hits 95% capacity. Join from here and you'll get a text when it's your turn.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Link(destination: RSF.virtualLine) {
                Label("Join the virtual line", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // Matches the game tab's "Start round" Berkeley-blue button.
                    .background(Color(red: 0.075, green: 0.157, blue: 0.447),
                                in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Links

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(icon: "figure.run", title: "Cardio equipment meter", url: RSF.cardioMeterPage)
            Divider().padding(.leading, 44)
            row(icon: "clock", title: "RSF hours", url: RSF.hoursPage)
            Divider().padding(.leading, 44)
            row(icon: "mappin.and.ellipse", title: RSF.address, url: RSF.maps)
            Divider().padding(.leading, 44)
            row(icon: "building.2", title: "About the facility", url: RSF.facilityPage)
        }
        .padding(.vertical, 4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(icon: String, title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.californiaGold)
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    GymView()
}
