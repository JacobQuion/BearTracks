//
//  ContentView.swift
//  BearTracks
//
//  Created by Jacob Quion on 7/30/26.
//

import SwiftUI

struct ContentView: View {
    /// Shows the branded launch screen briefly on startup, then reveals the app.
    @State private var showingSplash = true

    /// App-wide appearance, toggled from the Dining tab's top-right menu.
    /// Defaults to dark; persisted across launches.
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some View {
        ZStack {
            tabs

            if showingSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.45)) { showingSplash = false }
        }
    }

    private var tabs: some View {
        TabView {
            DiningView()
                .tabItem {
                    Label("Dining", systemImage: "fork.knife")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            GymView()
                .tabItem {
                    Label("Gym", systemImage: "dumbbell")
                }

            EventsView()
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }

            GameView()
                .tabItem {
                    Label("Game", systemImage: "gamecontroller.fill")
                }
        }
        .tint(Theme.californiaGold)
    }
}

/// The branded launch screen: the BearTracks logo centered on its own navy,
/// with a small "not affiliated" disclaimer pinned to the bottom.
struct SplashView: View {
    /// Sampled from the logo artwork so the page and logo blend seamlessly.
    private static let logoNavy = Color(red: 0.098, green: 0.153, blue: 0.294)

    var body: some View {
        ZStack {
            Self.logoNavy.ignoresSafeArea()

            VStack {
                Spacer()
                Image("BearTracksLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                Spacer()
                Text("This app is not affiliated with UC Berkeley")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    ContentView()
}
