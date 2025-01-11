//
//  SlashApp.swift
//  Slash
//
//  Created by Jordan Lejuwaan on 12/29/24.
//

import SwiftUI
import AppKit

@main
struct SlashApp: App {
    @StateObject private var windowManager = WindowManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(windowManager)
                .onAppear {
                    // Set up after a brief delay to ensure window is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("Setting up shortcuts...")
                        GlobalShortcuts.shared.setup(with: windowManager)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 400)
        .windowResizability(.contentSize)
    }
}
