import SwiftUI
import HotKey
import Carbon

class GlobalShortcuts {
    static let shared = GlobalShortcuts()
    
    private var slashModeHotKey: HotKey?
    private weak var windowManager: WindowManager?
    
    private init() {}
    
    func setup(with windowManager: WindowManager) {
        self.windowManager = windowManager
        setupSlashModeShortcut()
    }
    
    private func setupSlashModeShortcut() {
        // Clean up any existing hotkey
        slashModeHotKey = nil
        
        // Option + Command + Enter
        slashModeHotKey = HotKey(key: .return, modifiers: [.command, .option])
        
        slashModeHotKey?.keyDownHandler = { [weak self] in
            guard let self = self,
                  let windowManager = self.windowManager,
                  !windowManager.activeTasks.isEmpty else { return }
            
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