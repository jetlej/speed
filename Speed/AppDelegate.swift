import SwiftUI
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotKey: HotKey?
    @StateObject private var updater = SparkleUpdater()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App delegate finished launching")
        
        // Set up menu
        let menu = NSMenu()
        
        // Add Check for Updates menu item
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        
        // Add separator
        menu.addItem(NSMenuItem.separator())
        
        // Add Quit menu item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        // Set the menu
        statusItem?.menu = menu
    }
    
    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }
} 