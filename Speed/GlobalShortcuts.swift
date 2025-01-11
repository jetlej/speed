import SwiftUI
import HotKey
import Carbon

class GlobalShortcuts {
    static let shared = GlobalShortcuts()
    
    private var slashModeHotKey: HotKey?
    private weak var windowManager: WindowManager?
    
    private init() {}
    
    func setup(with windowManager: WindowManager) {
        print("Setting up GlobalShortcuts with WindowManager...")
        self.windowManager = windowManager
        setupSlashModeShortcut()
    }
    
    private func setupSlashModeShortcut() {
        print("Setting up global shortcut...")
        
        // Clean up any existing hotkey
        slashModeHotKey = nil
        
        // Option + Command + Enter
        slashModeHotKey = HotKey(key: .return, modifiers: [.command, .option])
        
        print("HotKey created: \(String(describing: slashModeHotKey))")
        
        slashModeHotKey?.keyDownHandler = { [weak self] in
            print("Global shortcut triggered!")
            guard let self = self else {
                print("Self is nil")
                return
            }
            
            guard let windowManager = self.windowManager else {
                print("WindowManager is nil")
                return
            }
            
            if windowManager.activeTasks.isEmpty {
                print("No active tasks")
                return
            }
            
            print("Toggling slash mode...")
            DispatchQueue.main.async {
                // If we're in Slash Mode, focus the app when returning to List Mode
                if windowManager.isSlashMode {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                windowManager.toggleSlashMode()
            }
        }
    }
} 