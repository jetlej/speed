import SwiftUI
import HotKey
import Carbon

class GlobalShortcuts {
    static let shared = GlobalShortcuts()
    
    private var speedModeHotKey: HotKey?
    private weak var windowManager: WindowManager?
    
    private init() {}
    
    func setup(with windowManager: WindowManager) {
        self.windowManager = windowManager
        setupSpeedModeShortcut()
    }
    
    private func setupSpeedModeShortcut() {
        // Clean up any existing hotkey
        speedModeHotKey = nil
        
        // Option + Command + Enter
        speedModeHotKey = HotKey(key: .return, modifiers: [.command, .option])
        
        speedModeHotKey?.keyDownHandler = { [weak self] in
            guard let self = self,
                  let windowManager = self.windowManager,
                  !windowManager.activeTasks.isEmpty else { return }
            
            DispatchQueue.main.async {
                // If we're in Speed Mode, focus the app when returning to List Mode
                if windowManager.isSpeedMode {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                windowManager.toggleSpeedMode()
            }
        }
    }
} 