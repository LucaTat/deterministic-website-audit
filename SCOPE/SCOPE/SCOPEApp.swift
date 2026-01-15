//
//  SCOPEApp.swift
//  SCOPE
//
//  Created by Tatomir Luca on 13.01.2026.
//

import SwiftUI
import Combine
import AppKit

final class AppFlowState: ObservableObject {
    enum SplashMode {
        case initialLaunch
        case resumeNoSound
    }

    @Published var showSplash: Bool = false
    @Published var splashMode: SplashMode = .initialLaunch
    @Published var splashTriggerID: UUID = UUID()
    private var splashToken: UUID?

    func triggerSplash(_ mode: SplashMode) {
        let token = UUID()
        splashToken = token
        splashMode = mode
        splashTriggerID = UUID()
        showSplash = true
        let visibleDuration: TimeInterval = mode == .initialLaunch ? 2.4 : 0.85
        let fadeDuration: TimeInterval = mode == .initialLaunch ? 0.9 : 0.55
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration) { [weak self] in
            guard let self, self.splashToken == token else { return }
            withAnimation(.easeInOut(duration: fadeDuration)) {
                self.showSplash = false
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SCOPEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var flow = AppFlowState()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(flow.showSplash ? 0 : 1)
                    .blur(radius: flow.showSplash ? 10 : 0)
                    .scaleEffect(flow.showSplash ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: flow.splashMode == .initialLaunch ? 0.9 : 0.55), value: flow.showSplash)

                SplashView(
                    allowSound: flow.splashMode == .initialLaunch,
                    triggerID: flow.splashTriggerID
                ) {}
                .opacity(flow.showSplash ? 1 : 0)
                .animation(.easeInOut(duration: flow.splashMode == .initialLaunch ? 0.9 : 0.55), value: flow.showSplash)
            }
            .onAppear {
                flow.triggerSplash(.initialLaunch)
            }
            #if os(macOS)
            .background(
                WindowEventObserver {
                    DispatchQueue.main.async {
                        flow.triggerSplash(.resumeNoSound)
                    }
                }
            )
            #endif
        }
    }
}
