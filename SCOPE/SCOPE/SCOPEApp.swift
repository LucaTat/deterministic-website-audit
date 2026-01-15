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
                ContentView()
                    .opacity(showSplash ? 0 : 1)
                    .blur(radius: showSplash ? 10 : 0)
                    .scaleEffect(showSplash ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.6), value: showSplash)

                SplashView {
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            showSplash = false
                        }
                    }
                }
                .opacity(showSplash ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: showSplash)
            }
        }
    }
}
