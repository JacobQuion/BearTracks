//
//  ContentView.swift
//  BearTracks
//
//  Created by Jacob Quion on 7/30/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
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
        // BearTracks is a dark-mode app regardless of the device setting.
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
