//
//  SCOPEApp.swift
//  SCOPE
//
//  Created by Tatomir Luca on 13.01.2026.
//

import SwiftUI

@main
struct SCOPEApp: App {
    @State private var showSplash: Bool = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ContentView()
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }
        }
    }
}
