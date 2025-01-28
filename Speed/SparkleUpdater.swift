import Foundation
import Sparkle

final class SparkleUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates = false
    
    init() {
        // If you want to start the updater manually, pass false to startingUpdater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        // Automatically check for updates daily
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.updateCheckInterval = 86400 // 24 hours
        
        // Allow automatic download of updates
        updaterController.updater.automaticallyDownloadsUpdates = true
        
        // Enable checking for updates after initialization
        canCheckForUpdates = true
    }
    
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
} 