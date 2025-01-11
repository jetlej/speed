//
//  SpeedApp.swift
//  Speed
//
//  Created by Jordan Lejuwaan on 12/29/24.
//

import SwiftUI
import AppKit

@main
struct SpeedApp: App {
    @StateObject private var windowManager = WindowManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var didSetupShortcuts = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(windowManager)
                .onAppear {
                    if !didSetupShortcuts {
                        // Set up after a brief delay to ensure window is ready
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            GlobalShortcuts.shared.setup(with: windowManager)
                            didSetupShortcuts = true
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 400)
        .windowResizability(.contentSize)
    }
}
