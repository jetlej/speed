import SwiftUI
import HotKey
import Carbon

class GlobalShortcuts {
    static let shared = GlobalShortcuts()
    
    private var speedModeHotKey: HotKey?
    private var quickAddHotKey: HotKey?
    
    private init() {}
    
    func setup(with windowManager: WindowManager) {
        setupSpeedModeShortcut()
        setupQuickAddShortcut()
    }
    
    private func setupSpeedModeShortcut() {
        // Clean up any existing hotkey
        speedModeHotKey = nil
        
        // Option + Command + Enter
        speedModeHotKey = HotKey(key: .return, modifiers: [.command, .option])
        
        speedModeHotKey?.keyDownHandler = { [weak self] in
            let windowManager = WindowManager.shared
            guard !windowManager.activeTasks.isEmpty else { return }
            
            DispatchQueue.main.async {
                // If we're in Speed Mode, focus the app when returning to List Mode
                if windowManager.isSpeedMode {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                windowManager.toggleSpeedMode()
            }
        }
    }
    
    private func setupQuickAddShortcut() {
        // Clean up any existing hotkey
        quickAddHotKey = nil
        
        // Option + Command + N
        quickAddHotKey = HotKey(key: .n, modifiers: [.command, .option])
        
        quickAddHotKey?.keyDownHandler = { [weak self] in
            let windowManager = WindowManager.shared
            
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                windowManager.showQuickAddModal()
            }
        }
    }
} 