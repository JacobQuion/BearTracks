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
            EventsView()
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }

            DiningView()
                .tabItem {
                    Label("Dining", systemImage: "fork.knife")
                }

            GymView()
                .tabItem {
                    Label("Gym", systemImage: "dumbbell")
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
