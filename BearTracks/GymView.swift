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

// MARK: - Occupancy scraper

/// Whether the meter page reached the network and yielded a reading.
enum MeterLoadState {
    case loading, loaded, failed
}

/// An offscreen web view that loads Density's crowd-meter widget and scrapes
/// the occupancy percentage out of its rendered page, reporting it back so the
/// app can draw a native circular gauge instead of embedding the whole widget.
///
/// Density's SAFE display is an undocumented JavaScript app, so this reads the
/// first "NN%" it finds in the page text. It's inherently best-effort: if their
/// markup changes and no percentage is found, `loadState` falls back to
/// `.failed` and the gauge shows a graceful note.
struct OccupancyScraper: UIViewRepresentable {
    let url: URL
    /// Bumping this from the parent triggers a reload + re-scrape.
    var reloadCount: Int
    @Binding var occupancy: Int?
    @Binding var loadState: MeterLoadState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OccupancyScraper
        var lastReloadCount = 0
        weak var webView: WKWebView?
        private var timer: Timer?
        /// Scrapes to run at these delays after a load, to catch the JS render.
        private let scrapeDelays: [TimeInterval] = [1.5, 3.5, 7.0]

        init(_ parent: OccupancyScraper) { self.parent = parent }

        deinit { timer?.invalidate() }

        private func report(_ state: MeterLoadState) {
            DispatchQueue.main.async { self.parent.loadState = state }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            scheduleScrapes()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(.failed)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(.failed)
        }

        /// A burst of scrapes right after load (the widget renders async), then
        /// a slow repeating refresh to keep the reading live.
        func scheduleScrapes() {
            for delay in scrapeDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.scrape()
                }
            }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.scrape()
            }
            // If none of the burst scrapes find a number, surface the failure.
            DispatchQueue.main.asyncAfter(deadline: .now() + scrapeDelays.last! + 2) { [weak self] in
                guard let self else { return }
                if self.parent.occupancy == nil { self.report(.failed) }
            }
        }

        func scrape() {
            let js = "(function(){var m=document.body.innerText.match(/(\\d{1,3})\\s*%/);return m?m[1]:null;})();"
            webView?.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, let text = result as? String, let value = Int(text),
                      (0...100).contains(value) else { return }
                DispatchQueue.main.async {
                    self.parent.occupancy = value
                    self.parent.loadState = .loaded
                }
            }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.load(URLRequest(url: url))
        context.coordinator.lastReloadCount = reloadCount
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastReloadCount != reloadCount else { return }
        context.coordinator.lastReloadCount = reloadCount
        DispatchQueue.main.async {
            self.occupancy = nil
            self.loadState = .loading
        }
        webView.load(URLRequest(url: url))
    }
}

// MARK: - Crowd ring

/// A native circular occupancy gauge: a ring that fills with the percentage,
/// colored green → yellow → orange as it gets busier, with the number centered.
struct CrowdRing: View {
    let percent: Int?

    private func color(_ p: Int) -> Color {
        switch p {
        case ..<50: return .green
        case 50..<80: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 20)

            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                    .stroke(color(percent),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: percent)

                VStack(spacing: 2) {
                    Text("\(percent)%")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("full")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .frame(width: 210, height: 210)
    }
}

// MARK: - Screen

struct GymView: View {
    @State private var reloadCount = 0
    @State private var meterState: MeterLoadState = .loading
    @State private var occupancy: Int?

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
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                reloadCount += 1
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

            ZStack {
                // Offscreen data source: loads Density's widget and scrapes the
                // percentage. Kept in the hierarchy (opacity 0) so its JS runs.
                OccupancyScraper(url: RSF.weightRoomMeter, reloadCount: reloadCount,
                                 occupancy: $occupancy, loadState: $meterState)
                    .frame(width: 240, height: 240)
                    .opacity(0)
                    .allowsHitTesting(false)

                if meterState == .failed && occupancy == nil {
                    meterUnavailable
                } else {
                    CrowdRing(percent: occupancy)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)

            Text("Live weight room occupancy · pull down to refresh")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Shown over the meter when its embedded page can't reach the network.
    private var meterUnavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.californiaGold)
            Text("Couldn't load the crowd meter")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Check your connection and try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                reloadCount += 1
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.control)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
