//
//  ContentView.swift
//  Speed
//
//  Created by Jordan Lejuwaan on 12/29/24.
//

import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct Task: Identifiable, Equatable, Codable {
    let id = UUID()
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var isFrog: Bool = false
    var priority: Int = 1 // Default priority (1-3 scale)
    
    enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, completedAt, isFrog, priority
    }
    
    // This initializer helps convert any priority value to the valid 1-3 range
    init(title: String, isCompleted: Bool, completedAt: Date? = nil, isFrog: Bool = false, priority: Int = 1) {
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.isFrog = isFrog
        // Ensure priority is within the valid range of 1-3
        self.priority = max(1, min(3, priority))
    }
}

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    @Published var isSpeedMode = false
    @Published var isAnimating = false
    @Published var lastSpeedPosition: NSPoint?
    @Published var tasks: [Task] = []
    @Published var shouldFocusInput = false
    @Published var zoomLevel: Double = 1.0
    @Published var isQuickAddVisible = false
    var quickAddWindow: NSWindow?
    private var isSettingFrame = false
    private var positionObserver: NSObjectProtocol?
    private var undoManager: UndoManager? {
        NSApp.keyWindow?.undoManager
    }
    
    var activeTasks: [Task] {
        let sorted = tasks.filter { !$0.isCompleted }
        return sorted.sorted { (task1, task2) in
            if task1.isFrog && !task2.isFrog { return true }
            if !task1.isFrog && task2.isFrog { return false }
            return false
        }
    }
    
    init() {
        loadTasks()
        loadWindowPosition()
        loadZoomLevel()
        
        // Ensure window setup happens on main thread
        DispatchQueue.main.async { [self] in
            guard let window = NSApplication.shared.windows.first else { return }
            
            // Set basic window properties
            window.backgroundColor = .black
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.masksToBounds = true
            
            // Configure List Mode properties
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isMovable = true
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 300, height: 400)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            window.level = .normal
            
            // Force the correct frame immediately
            if let savedFrame = UserDefaults.standard.string(forKey: "windowFrame")?.components(separatedBy: ","),
               savedFrame.count == 4,
               let x = Double(savedFrame[0]),
               let y = Double(savedFrame[1]),
               let width = Double(savedFrame[2]),
               let height = Double(savedFrame[3]) {
                
                // Set frame without animation
                window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
                
                // Double-check and force position after a tiny delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    let currentFrame = window.frame
                    if currentFrame.origin.x != x || currentFrame.origin.y != y ||
                       currentFrame.width != width || currentFrame.height != height {
                        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
                    }
                }
            } else {
                // Set default frame for new windows
                let frame = NSRect(x: (NSScreen.main?.frame.width ?? 800) / 2 - 150,
                                 y: (NSScreen.main?.frame.height ?? 600) / 2 - 200,
                                 width: 300,
                                 height: 400)
                window.setFrame(frame, display: false)
            }
            
            // Add window frame observer
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.windowDidResize),
                name: NSWindow.didResizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.windowDidMove),
                name: NSWindow.didMoveNotification,
                object: window
            )
        }
    }
    
    deinit {
        if let observer = positionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func registerUndoRedoOperation(oldTasks: [Task], newTasks: [Task], actionName: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                target.tasks = oldTasks
            }
            target.saveTasks()
            target.registerUndoRedoOperation(oldTasks: newTasks, newTasks: oldTasks, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }
    
    func completeTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            let oldTasks = tasks
            var updatedTask = task
            updatedTask.isCompleted = true
            updatedTask.completedAt = Date()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                tasks[index] = updatedTask
            }
            
            saveTasks()
            registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Complete Task")
            
            // If in speed mode and no more active tasks, exit speed mode
            if isSpeedMode && activeTasks.isEmpty {
                toggleSpeedMode()
            }
        }
    }
    
    func addTask(_ title: String) -> UUID {
        let oldTasks = tasks
        let newTask = Task(title: title, isCompleted: false, priority: 1)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tasks.append(newTask)
        }
        saveTasks()
        
        registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Add Task")
        return newTask.id
    }
    
    func addMultipleTasks(_ titles: [String]) {
        let oldTasks = tasks
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let newTasks = titles.map { title in
                Task(title: cleanTaskTitle(title), isCompleted: false, priority: 1)
            }
            tasks.append(contentsOf: newTasks)
        }
        saveTasks()
        
        registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Add Multiple Tasks")
    }
    
    private func cleanTaskTitle(_ title: String) -> String {
        // Remove common list prefixes and trim whitespace
        var cleaned = title.trimmingCharacters(in: .whitespaces)
        
        // Remove markdown list markers
        if cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") || cleaned.hasPrefix("+ ") {
            cleaned = String(cleaned.dropFirst(2))
        }
        
        // Remove checkbox markers like "[ ]", "[x]", etc. and any following date pattern
        if cleaned.hasPrefix("[") {
            // Find the closing bracket
            if let closingBracketIndex = cleaned.firstIndex(of: "]") {
                cleaned = String(cleaned[cleaned.index(after: closingBracketIndex)...])
                
                // After removing brackets, check for and remove date pattern (MM/DD/YYYY)
                let datePattern = "^\\s*\\d{2}/\\d{2}/\\d{4}\\s+"
                if let regex = try? NSRegularExpression(pattern: datePattern) {
                    cleaned = regex.stringByReplacingMatches(
                        in: cleaned,
                        range: NSRange(cleaned.startIndex..., in: cleaned),
                        withTemplate: ""
                    )
                }
            }
        }
        
        // Remove numbered list markers (e.g., "1.", "2.", etc.)
        let numberPrefixPattern = "^\\d+\\.\\s+"
        if let regex = try? NSRegularExpression(pattern: numberPrefixPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    func updateTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            let oldTasks = tasks
            tasks[index] = task
            saveTasks()
            
            registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Edit Task")
        }
    }
    
    func deleteTask(at indexSet: IndexSet) {
        let oldTasks = tasks
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tasks.remove(atOffsets: indexSet)
        }
        
        saveTasks()
        registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Delete Task")
    }
    
    func moveTask(from source: IndexSet, to destination: Int) {
        let oldTasks = tasks
        
        // Get the active task IDs in their current order
        let activeTaskIds = activeTasks.map { $0.id }
        
        // Get the tasks being moved
        let movingTasks = source.map { activeTasks[$0] }
        
        // Remove the tasks from their current positions
        var newActiveTaskIds = activeTaskIds
        source.sorted(by: >).forEach { newActiveTaskIds.remove(at: $0) }
        
        // Calculate the correct destination index, adjusting for removed items
        let adjustedDestination = min(destination, newActiveTaskIds.count)
        
        // Insert all tasks at the new position, maintaining their relative order
        newActiveTaskIds.insert(contentsOf: movingTasks.map { $0.id }, at: adjustedDestination)
        
        // Create a new array with the updated order
        var newTasks = tasks.filter { $0.isCompleted }
        newActiveTaskIds.forEach { id in
            if let task = tasks.first(where: { $0.id == id }) {
                newTasks.append(task)
            }
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tasks = newTasks
        }
        
        saveTasks()
        registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Move Tasks")
    }
    
    func undo() {
        undoManager?.undo()
    }
    
    func redo() {
        undoManager?.redo()
    }
    
    func canUndo() -> Bool {
        return undoManager?.canUndo ?? false
    }
    
    func canRedo() -> Bool {
        return undoManager?.canRedo ?? false
    }
    
    private func loadTasks() {
        if let savedTasks = UserDefaults.standard.data(forKey: "savedTasks"),
           let decodedTasks = try? JSONDecoder().decode([Task].self, from: savedTasks) {
            tasks = decodedTasks
        }
    }
    
    private func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: "savedTasks")
        }
    }
    
    private func loadWindowPosition() {
        if let savedFrame = UserDefaults.standard.string(forKey: "speedFrame")?.components(separatedBy: ","),
           savedFrame.count == 4,
           let x = Double(savedFrame[0]),
           let y = Double(savedFrame[1]),
           let _ = Double(savedFrame[2]),
           let _ = Double(savedFrame[3]) {
            lastSpeedPosition = NSPoint(x: x, y: y)
        }
    }
    
    @objc private func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow, !isSpeedMode {
            let frame = window.frame
            UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)", forKey: "windowFrame")
        }
    }
    
    @objc private func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow, !isSpeedMode {
            let frame = window.frame
            UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)", forKey: "windowFrame")
        }
    }
    
    func toggleSpeedMode() {
        if let window = NSApplication.shared.windows.first {
            // Start animation immediately
            isAnimating = true
            
            if !isSpeedMode {
                // Save the current List Mode frame before switching to Speed Mode
                let frame = window.frame
                UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)", forKey: "windowFrame")
                
                // Configure window properties for Speed Mode before any visual changes
                let tempFrame = window.frame
                window.styleMask = [.borderless, .fullSizeContentView]
                window.setFrame(tempFrame, display: false)
                window.isMovableByWindowBackground = true
                window.isMovable = true
                window.minSize = NSSize(width: 222, height: 35)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                window.level = .floating
                window.backgroundColor = .black
                window.contentView?.layer?.backgroundColor = NSColor.black.cgColor
                window.contentView?.layer?.cornerRadius = 10
                window.contentView?.layer?.masksToBounds = true
                
                // Make sure the window itself has rounded corners
                if let windowView = window.contentView?.superview {
                    windowView.wantsLayer = true
                    windowView.layer?.cornerRadius = 10
                    windowView.layer?.masksToBounds = true
                }
                
                // Toggle state after window is configured but before animation
                isSpeedMode.toggle()
                
                // Use saved position or default if none saved
                let defaultFrame = NSRect(
                    x: (NSScreen.main?.frame.width ?? 800) / 2 - 150,
                    y: 50,
                    width: 300,
                    height: 50
                )
                
                let speedModeFrame: NSRect
                if let savedFrame = UserDefaults.standard.string(forKey: "speedFrame")?.components(separatedBy: ","),
                   savedFrame.count == 4,
                   let x = Double(savedFrame[0]),
                   let y = Double(savedFrame[1]),
                   let width = Double(savedFrame[2]),
                   let height = Double(savedFrame[3]) {
                    speedModeFrame = NSRect(x: x, y: y, width: width, height: height)
                } else {
                    speedModeFrame = defaultFrame
                }
                
                // Set the frame with animation
                self.isSettingFrame = true
                let visibleFrame = self.ensureFrameIsVisible(speedModeFrame)
                window.setFrame(visibleFrame, display: true, animate: true)
                self.isSettingFrame = false
                
                // Set up position tracking AFTER setting initial frame
                self.positionObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main) { [weak self] notification in
                        guard let self = self,
                              !self.isSettingFrame,
                              let window = notification.object as? NSWindow else { return }
                        self.lastSpeedPosition = window.frame.origin
                        UserDefaults.standard.set("\(window.frame.origin.x),\(window.frame.origin.y)", forKey: "speedPosition")
                    }
                
                // End animation after the frame animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.isAnimating = false
                    self.shouldFocusInput = true
                }
            } else {
                // If we're exiting Speed mode, remove the observer FIRST
                if let observer = positionObserver {
                    NotificationCenter.default.removeObserver(observer)
                    positionObserver = nil
                }
                
                // Save the current Speed Mode position before switching back
                let speedFrame = window.frame
                UserDefaults.standard.set("\(speedFrame.origin.x),\(speedFrame.origin.y),\(speedFrame.width),\(speedFrame.height)", forKey: "speedFrame")
                lastSpeedPosition = speedFrame.origin
                
                // Toggle state immediately to hide Speed Mode UI
                isSpeedMode.toggle()
                
                // Small delay to ensure UI has updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    withAnimation(.none) {
                        // First restore the saved List Mode frame
                        if let savedFrame = UserDefaults.standard.string(forKey: "windowFrame")?.components(separatedBy: ","),
                           savedFrame.count == 4,
                           let x = Double(savedFrame[0]),
                           let y = Double(savedFrame[1]),
                           let width = Double(savedFrame[2]),
                           let height = Double(savedFrame[3]) {
                            
                            // Set window properties for List Mode while preserving position
                            let tempFrame = window.frame
                            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                            window.setFrame(tempFrame, display: false)
                            
                            window.isMovableByWindowBackground = false
                            window.minSize = NSSize(width: 400, height: 400)
                            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                            window.level = .normal
                            window.backgroundColor = .black
                            window.contentView?.layer?.cornerRadius = 0
                            
                            // Then set the final frame
                            self.isSettingFrame = true
                            let visibleFrame = self.ensureFrameIsVisible(NSRect(x: x, y: y, width: width, height: height))
                            window.setFrame(visibleFrame, display: true, animate: true)
                            self.isSettingFrame = false
                        }
                        
                        // Add a delay to match the animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            self.isAnimating = false
                            self.shouldFocusInput = true
                        }
                    }
                }
            }
        }
    }
    
    func toggleFrog(for task: Task) {
        let oldTasks = tasks
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            // If we're setting a new frog, remove frog from other incomplete tasks
            if !task.isFrog {
                tasks = tasks.map { t in
                    var updatedTask = t
                    if !t.isCompleted {
                        updatedTask.isFrog = false
                    }
                    return updatedTask
                }
            }
            
            // Toggle the frog state for the target task
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                var updatedTask = task
                updatedTask.isFrog = !task.isFrog
                tasks[index] = updatedTask
            }
        }
        
        saveTasks()
        registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Toggle Frog")
    }
    
    func loadZoomLevel() {
        zoomLevel = UserDefaults.standard.double(forKey: "zoomLevel")
        if zoomLevel == 0 { // If no saved zoom level
            zoomLevel = 1.0
        }
    }
    
    func saveZoomLevel() {
        UserDefaults.standard.set(zoomLevel, forKey: "zoomLevel")
    }
    
    func adjustZoom(increase: Bool) {
        let zoomStep = 0.1
        let minZoom = 0.5
        let maxZoom = 2.0
        
        if increase {
            zoomLevel = min(maxZoom, zoomLevel + zoomStep)
        } else {
            zoomLevel = max(minZoom, zoomLevel - zoomStep)
        }
        saveZoomLevel()
    }
    
    private func ensureFrameIsVisible(_ proposedFrame: NSRect) -> NSRect {
        // Get all available screens
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return proposedFrame }
        
        // Check if the proposed frame is visible on any screen
        let isVisibleOnAnyScreen = screens.contains { screen in
            screen.visibleFrame.intersects(proposedFrame)
        }
        
        if isVisibleOnAnyScreen {
            return proposedFrame
        }
        
        // If not visible, use default position but keep dimensions
        guard let mainScreen = NSScreen.main else { return proposedFrame }
        
        return NSRect(
            x: (mainScreen.frame.width / 2) - (proposedFrame.width / 2),
            y: isSpeedMode ? 50 : (mainScreen.frame.height / 2) - (proposedFrame.height / 2),
            width: proposedFrame.width,
            height: proposedFrame.height
        )
    }
    
    func showQuickAddModal() {
        // If already showing, close it instead
        if isQuickAddVisible {
            closeQuickAddModal()
            return
        }

        // Create a completely detached accessory window
        let panel = FocusableBorderlessPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 140), // Initial height, will be resized
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Basic Panel Setup
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // Remove the panel's shadow
        panel.level = .modalPanel
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua) // Ensure dark appearance
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle] // Removed .fullSizeAuxiliary
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true

        // Setup Blur View (content view)
        let blurView = NSVisualEffectView()
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.material = .hudWindow
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = 10 // Round corners of the blur view itself
        blurView.layer?.masksToBounds = true
        blurView.layer?.borderWidth = 1 // Add a 1pt border
        blurView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.2).cgColor // Subtle white border
        panel.contentView = blurView // Set the blur view AS the content view

        // Setup SwiftUI Hosting View
        let quickAddView = QuickAddView().environmentObject(self)
        let hostingController = NSHostingController(rootView: quickAddView)
        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false // Use constraints
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.5).cgColor // Semi-transparent black
        hostedView.layer?.masksToBounds = true
        
        // Add SwiftUI view to the blur view
        blurView.addSubview(hostedView)

        // Set constraints for the SwiftUI view to fill the blur view
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: blurView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: blurView.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: blurView.trailingAnchor)
        ])

        // Adjust window frame to fit SwiftUI content AFTER setting it up
        panel.setContentSize(hostingController.view.fittingSize)

        // Center the panel on screen AFTER setting size
        if let mainScreen = NSScreen.main {
            let screenFrame = mainScreen.visibleFrame
            let windowFrame = panel.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Store reference and display
        quickAddWindow = panel
        isQuickAddVisible = true
        panel.orderFrontRegardless()
        
        // Focus management
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            panel.makeKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if let textField = blurView.firstTextField() {
                    panel.makeFirstResponder(textField)
                }
            }
        }
    }

    func closeQuickAddModal() {
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            if let window = self.quickAddWindow {
                // Just order out rather than trying to hide or close
                window.resignKey()
                window.orderOut(nil)
                
                // Clear references immediately
                self.quickAddWindow = nil
                self.isQuickAddVisible = false
            } else {
                // Safety in case window is already gone
                self.quickAddWindow = nil
                self.isQuickAddVisible = false
            }
        }
    }

    func addTaskWithPriority(_ title: String, priority: Int) -> UUID {
        let oldTasks = tasks
        // Ensure the priority is within the valid range of 1-3
        let validPriority = max(1, min(3, priority))
        let newTask = Task(title: title, isCompleted: false, priority: validPriority)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            tasks.append(newTask)
        }
        saveTasks()
        
        registerUndoRedoOperation(oldTasks: oldTasks, newTasks: tasks, actionName: "Add Task")
        return newTask.id
    }
}

// Custom NSPanel subclass to allow becoming key even when borderless
class FocusableBorderlessPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    // Prevent this window from bringing the app forward
    override func becomeKey() {
        super.becomeKey()
    }
    
    // Ensure this window can become main without activating the app
    override var canBecomeMain: Bool {
        return true
    }
    
    // Override to prevent activation
    override func makeKeyAndOrderFront(_ sender: Any?) {
        // Just order front without the makeKey part
        self.orderFront(sender)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // Make sure the panel has rounded corners
        self.styleMask = [.borderless, .nonactivatingPanel]
        self.isOpaque = false
        self.backgroundColor = .clear
        
        // Ensure the window itself has rounded corners
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 10
        self.contentView?.layer?.masksToBounds = true
        
        if let windowView = self.contentView?.superview {
            windowView.wantsLayer = true
            windowView.layer?.cornerRadius = 10
            windowView.layer?.masksToBounds = true
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var windowManager: WindowManager
    @State private var newTaskTitle = ""
    
    var body: some View {
        Group {
            if windowManager.isSpeedMode {
                SpeedModeView(tasks: $windowManager.tasks, windowManager: windowManager)
            } else {
                if !windowManager.isAnimating {
                    TaskListView(windowManager: windowManager, newTaskTitle: $newTaskTitle)
                        .frame(minWidth: 300, minHeight: 400)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.easeIn(duration: 0.15)),
                                removal: .opacity.animation(.none)
                            )
                        )
                } else {
                    Color.black
                }
            }
        }
        .background(Color.black)
    }
}

struct CustomListStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let tableView = view.enclosingScrollView?.documentView as? NSTableView {
                tableView.backgroundColor = .clear
                tableView.enclosingScrollView?.drawsBackground = false
                tableView.gridColor = .black
                tableView.gridStyleMask = []
                tableView.intercellSpacing = NSSize(width: 0, height: 8)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: (String) -> Void
    var onCancel: () -> Void
    @ObservedObject var windowManager: WindowManager
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomTextField
        var hasInitialFocus = false
        
        init(_ parent: CustomTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit(parent.text)
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            // Let the system handle all other commands (including copy/paste)
            return false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        
        // Appearance
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.textColor = .white
        textField.font = .systemFont(ofSize: 16 * windowManager.zoomLevel)
        textField.focusRingType = .none
        textField.drawsBackground = false
        textField.isSelectable = true
        textField.isEditable = true
        
        textField.placeholderString = "New task"
        textField.placeholderAttributedString = NSAttributedString(
            string: "New task",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.3),
                .font: NSFont.systemFont(ofSize: 16 * windowManager.zoomLevel)
            ]
        )
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.font = .systemFont(ofSize: 16 * windowManager.zoomLevel)
        
        DispatchQueue.main.async {
            if !context.coordinator.hasInitialFocus {
                nsView.window?.makeFirstResponder(nsView)
                if let editor = nsView.currentEditor() as? NSTextView {
                    let length = nsView.stringValue.count
                    editor.selectedRange = NSRange(location: length, length: 0)
                }
                context.coordinator.hasInitialFocus = true
            }
        }
    }
}

struct TaskInputField: View {
    @Binding var newTaskTitle: String
    @FocusState.Binding var isInputFocused: Bool
    let onSubmit: () -> Void
    let onFocusChange: (Bool) -> Void
    let onTextChange: (String) -> Void
    @ObservedObject var windowManager: WindowManager
    
    var body: some View {
        CustomTextField(
            text: $newTaskTitle,
            onSubmit: { _ in onSubmit() },
            onCancel: {},
            windowManager: windowManager
        )
        .focused($isInputFocused)
        .padding(.bottom, 8 * windowManager.zoomLevel)
        .padding(.leading, 14 * windowManager.zoomLevel)
        .background(
            Rectangle()
                .frame(height: 2 * windowManager.zoomLevel)
                .foregroundColor(Color.white.opacity(0.3))
                .offset(y: 12 * windowManager.zoomLevel)
                .padding(.leading, 14 * windowManager.zoomLevel)
        )
        .padding(.horizontal)
        .onChange(of: isInputFocused) { oldValue, newValue in
            onFocusChange(newValue)
        }
        .onChange(of: newTaskTitle) { oldValue, newValue in
            if oldValue != newValue {
                onTextChange(newValue)
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
                    if let pasteboardString = NSPasteboard.general.string(forType: .string) {
                        let lines = pasteboardString.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        
                        if lines.count > 1 {
                            windowManager.addMultipleTasks(lines)
                            newTaskTitle = ""
                            return nil // Consume the paste event
                        }
                    }
                }
                return event
            }
        }
    }
}

struct TaskListContent: View {
    let activeTasks: [Task]
    let editingTaskId: UUID?
    let selectedTaskIds: Set<UUID>
    let windowManager: WindowManager
    let onTaskSelection: (UUID, NSEvent?) -> Void
    let onStartEditing: (UUID) -> Void
    let onEndEditing: (UUID, String?) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (IndexSet) -> Void
    
    @State private var draggingTask: Task?
    @State private var dragOffset: CGFloat = 0
    @State private var taskPositions: [UUID: CGRect] = [:]
    @State private var previewIndex: Int?
    @State private var isAnimatingDrop: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    let isBeingDragged = draggingTask?.id == task.id
                    let taskHeight = taskPositions[task.id]?.height ?? 0
                    
                    TaskRow(
                        task: task,
                        isEditing: editingTaskId == task.id,
                        isSelected: selectedTaskIds.contains(task.id),
                        onSelect: { event in onTaskSelection(task.id, event) },
                        onStartEditing: { onStartEditing(task.id) },
                        onEndEditing: { onEndEditing(task.id, $0) },
                        onDragChange: { task, deltaY in
                            if draggingTask == nil {
                                draggingTask = task
                                isAnimatingDrop = false
                            }
                            
                            if draggingTask?.id == task.id {
                                dragOffset = deltaY
                                
                                if let currentIndex = activeTasks.firstIndex(where: { $0.id == task.id }) {
                                    let taskHeight = taskPositions[task.id]?.height ?? 0
                                    
                                    // Calculate how many positions to move based on drag distance
                                    let dragDistance = deltaY
                                    let positionsToMove = taskHeight > 0 ? Int(round(dragDistance / taskHeight)) : 0
                                    
                                    // Calculate target index
                                    let targetIndex = max(0, min(activeTasks.count - 1, currentIndex + positionsToMove))
                                    
                                    // Only update preview if we're actually moving and not a frog task
                                    if targetIndex != currentIndex && (!task.isFrog || activeTasks[targetIndex].isFrog) {
                                        previewIndex = targetIndex
                                    } else {
                                        previewIndex = nil
                                    }
                                }
                            }
                        },
                        onDragEnd: { task in
                            if let sourceIndex = activeTasks.firstIndex(where: { $0.id == task.id }),
                               let targetIndex = previewIndex {
                                isAnimatingDrop = true
                                // Move the task first
                                onMove(IndexSet(integer: sourceIndex), targetIndex)
                            }
                            
                            // Reset all states after the move
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = 0
                            }
                            
                            // Reset other states without animation
                            draggingTask = nil
                            previewIndex = nil
                            
                            // Reset animation flag after a delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isAnimatingDrop = false
                            }
                        },
                        windowManager: windowManager
                    )
                    .transition(.scale(scale: 1, anchor: .leading).combined(with: .opacity))
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: TaskPositionPreferenceKey.self,
                                value: [TaskPosition(id: task.id, frame: geometry.frame(in: .named("scroll")))]
                            )
                        }
                    )
                    .offset(y: {
                        // Only apply drag offset to the dragged task
                        if draggingTask?.id == task.id {
                            return dragOffset
                        }
                        
                        // Don't move other tasks if there's no preview or dragging task
                        guard let draggingTask = draggingTask,
                              let previewIndex = previewIndex,
                              let sourceIndex = activeTasks.firstIndex(where: { $0.id == draggingTask.id }) else {
                            return 0
                        }
                        
                        // Never move frog tasks
                        if task.isFrog {
                            return 0
                        }
                        
                        // Don't allow non-frog tasks to move above frog tasks
                        if !draggingTask.isFrog && task.isFrog {
                            return 0
                        }
                        
                        // Only move tasks between source and preview indices
                        if sourceIndex < previewIndex {
                            // Moving down
                            if index > sourceIndex && index <= previewIndex {
                                return -taskHeight
                            }
                        } else if sourceIndex > previewIndex {
                            // Moving up
                            if index >= previewIndex && index < sourceIndex {
                                return taskHeight
                            }
                        }
                        return 0
                    }())
                    .zIndex(isBeingDragged ? 1 : 0)
                    .animation(draggingTask != nil && !isAnimatingDrop ? .easeOut(duration: 0.2) : nil, value: previewIndex)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            onTaskSelection(UUID(), nil)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(TaskPositionPreferenceKey.self) { positions in
            // Update task positions when they change
            for position in positions {
                taskPositions[position.id] = position.frame
            }
        }
    }
}

struct TaskPosition: Equatable {
    let id: UUID
    let frame: CGRect
}

struct TaskPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [TaskPosition] = []
    
    static func reduce(value: inout [TaskPosition], nextValue: () -> [TaskPosition]) {
        value.append(contentsOf: nextValue())
    }
}

struct SpeedButton: View {
    let isDisabled: Bool
    let action: () -> Void
    @ObservedObject var windowManager: WindowManager
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14 * windowManager.zoomLevel, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(14 * windowManager.zoomLevel)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(10 * windowManager.zoomLevel)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(.horizontal, 14 * windowManager.zoomLevel)
        .padding(.bottom, 14 * windowManager.zoomLevel)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct TaskListView: View {
    @ObservedObject var windowManager: WindowManager
    @Binding var newTaskTitle: String
    
    // Single source of truth for UI state
    enum UIState {
        case normal
        case selected(taskIds: Set<UUID>)
        case editing(taskId: UUID)
    }
    
    @State private var uiState: UIState = .normal
    @State private var eventMonitor: Any? = nil
    @FocusState private var isInputFocused: Bool
    @State private var lastSelectedTaskId: UUID? = nil
    
    private var selectedTaskIds: Set<UUID> {
        if case .selected(let taskIds) = uiState { return taskIds }
        return []
    }
    
    private var editingTaskId: UUID? {
        if case .editing(let taskId) = uiState { return taskId }
        return nil
    }
    
    private func handleTaskSelection(taskId: UUID, event: NSEvent? = nil, shouldUnfocusInput: Bool = true) {
        // If the taskId doesn't exist in our tasks, treat it as a deselection
        if !windowManager.tasks.contains(where: { $0.id == taskId }) {
            uiState = .normal
            return
        }

        switch uiState {
        case .normal:
            uiState = .selected(taskIds: [taskId])
            lastSelectedTaskId = taskId
            if shouldUnfocusInput {
                isInputFocused = false
            }
            
        case .selected(let currentIds):
            if let event = event {
                if event.modifierFlags.contains(.command) {
                    // Command+click: toggle selection
                    var newSelection = currentIds
                    if currentIds.contains(taskId) {
                        newSelection.remove(taskId)
                    } else {
                        newSelection.insert(taskId)
                        lastSelectedTaskId = taskId
                    }
                    uiState = newSelection.isEmpty ? .normal : .selected(taskIds: newSelection)
                    
                } else if event.modifierFlags.contains(.shift), let lastId = lastSelectedTaskId {
                    // Shift+click: select range
                    let activeTasks = windowManager.activeTasks
                    if let lastIndex = activeTasks.firstIndex(where: { $0.id == lastId }),
                       let currentIndex = activeTasks.firstIndex(where: { $0.id == taskId }) {
                        let range = lastIndex < currentIndex ? 
                            activeTasks[lastIndex...currentIndex] : 
                            activeTasks[currentIndex...lastIndex]
                        let newSelection = Set(range.map { $0.id })
                        uiState = .selected(taskIds: newSelection)
                    }
                } else {
                    // Normal click: select single
                    uiState = .selected(taskIds: [taskId])
                    lastSelectedTaskId = taskId
                }
                if shouldUnfocusInput {
                    isInputFocused = false
                }
            } else {
                // Programmatic selection (e.g., keyboard navigation)
                uiState = .selected(taskIds: [taskId])
                lastSelectedTaskId = taskId
                if shouldUnfocusInput {
                    isInputFocused = false
                }
            }
            
        case .editing:
            // Do nothing while editing
            break
        }
    }
    
    private func handleStartEditing(taskId: UUID) {
        isInputFocused = false
        uiState = .editing(taskId: taskId)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            TaskInputField(
                newTaskTitle: $newTaskTitle,
                isInputFocused: $isInputFocused,
                onSubmit: addTask,
                onFocusChange: { focused in
                    if focused {
                        uiState = .normal
                    }
                },
                onTextChange: { newValue in
                    if case .selected = uiState, !newValue.isEmpty {
                        uiState = .normal
                    }
                },
                windowManager: windowManager
            )
            
            TaskListContent(
                activeTasks: windowManager.activeTasks,
                editingTaskId: editingTaskId,
                selectedTaskIds: selectedTaskIds,
                windowManager: windowManager,
                onTaskSelection: { taskId, event in handleTaskSelection(taskId: taskId, event: event) },
                onStartEditing: handleStartEditing,
                onEndEditing: handleEndEditing,
                onMove: { source, destination in
                    uiState = .normal
                    moveTask(from: source, to: destination)
                },
                onDelete: handleDelete
            )
            
            SpeedButton(
                isDisabled: windowManager.activeTasks.isEmpty,
                action: {
                    uiState = .normal
                    windowManager.toggleSpeedMode()
                },
                windowManager: windowManager
            )
        }
        .padding()
        .onAppear {
            setupKeyboardMonitor()
            isInputFocused = true
        }
        .onDisappear {
            cleanupKeyboardMonitor()
        }
        .onChange(of: windowManager.shouldFocusInput) { oldValue, newValue in
            if newValue {
                isInputFocused = true
                windowManager.shouldFocusInput = false
            }
        }
    }
    
    private func handleEndEditing(taskId: UUID, newTitle: String?) {
        if let title = newTitle,
           let task = windowManager.tasks.first(where: { $0.id == taskId }),
           !title.isEmpty {
            var updatedTask = task
            updatedTask.title = title
            windowManager.updateTask(updatedTask)
        }
        uiState = .normal
    }
    
    private func handleDelete(at indexSet: IndexSet) {
        if case .selected(let taskIds) = uiState, taskIds.count > 1 {
            // Delete multiple selected tasks
            let selectedIndices = IndexSet(windowManager.tasks.enumerated()
                .filter { taskIds.contains($0.element.id) }
                .map { $0.offset })
            windowManager.deleteTask(at: selectedIndices)
            uiState = .normal
        } else {
            // Delete single task
            guard let currentIndex = indexSet.first else { return }
            windowManager.deleteTask(at: indexSet)
            
            // Update selection if there are remaining tasks
            if !windowManager.tasks.isEmpty {
                if currentIndex < windowManager.tasks.count {
                    handleTaskSelection(taskId: windowManager.tasks[currentIndex].id)
                } else {
                    handleTaskSelection(taskId: windowManager.tasks[windowManager.tasks.count - 1].id)
                }
            } else {
                uiState = .normal
            }
        }
    }
    
    private func addTask() {
        guard !newTaskTitle.isEmpty else { return }
        let newTaskId = windowManager.addTask(newTaskTitle)
        newTaskTitle = ""
        handleTaskSelection(taskId: newTaskId, shouldUnfocusInput: false)
    }
    
    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Skip any keyboard event handling completely when in editing mode
            if case .editing = uiState {
                return event
            }
            
            // Handle zoom shortcuts
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "=" {  // Command + equals/plus
                    windowManager.adjustZoom(increase: true)
                    return nil
                } else if event.charactersIgnoringModifiers == "-" {  // Command + minus
                    windowManager.adjustZoom(increase: false)
                    return nil
                } else if event.charactersIgnoringModifiers == "c" {  // Command + C
                    copySelectedTasks()
                    return nil
                }
            }
            
            if event.keyCode == 51 { // Delete key
                if case .selected(let taskIds) = uiState {
                    // Get all indices of selected tasks
                    let selectedIndices = IndexSet(windowManager.tasks.enumerated()
                        .filter { taskIds.contains($0.element.id) }
                        .map { $0.offset })
                    if !selectedIndices.isEmpty {
                        handleDelete(at: selectedIndices)
                        return nil
                    }
                }
            } else if event.keyCode == 125 { // Down arrow
                if event.modifierFlags.contains(.command) {
                    if case .selected(let taskIds) = uiState {
                        let selectedIndices = IndexSet(windowManager.activeTasks.enumerated()
                            .filter { taskIds.contains($0.element.id) }
                            .map { $0.offset })
                        if !selectedIndices.isEmpty {
                            if event.modifierFlags.contains(.option) {
                                // Move to bottom
                                moveTask(from: selectedIndices, to: windowManager.activeTasks.count)
                            } else {
                                // Move down one position
                                let maxIndex = selectedIndices.max() ?? 0
                                if maxIndex < windowManager.activeTasks.count - 1 {
                                    // When moving down, we need to adjust the destination index
                                    // to account for the removal of items before insertion
                                    moveTask(from: selectedIndices, to: maxIndex + 2 - selectedIndices.count)
                                }
                            }
                            return nil
                        }
                    }
                } else if isInputFocused {
                    if !windowManager.activeTasks.isEmpty {
                        isInputFocused = false
                        if let firstTask = windowManager.activeTasks.first {
                            handleTaskSelection(taskId: firstTask.id)
                        }
                        return nil
                    }
                } else if case .selected(let taskIds) = uiState {
                    if let currentTaskId = taskIds.first {
                        selectNextTask(after: currentTaskId)
                    }
                    return nil
                }
            } else if event.keyCode == 126 { // Up arrow
                if event.modifierFlags.contains(.command) {
                    if case .selected(let taskIds) = uiState {
                        let selectedIndices = IndexSet(windowManager.activeTasks.enumerated()
                            .filter { taskIds.contains($0.element.id) }
                            .map { $0.offset })
                        if !selectedIndices.isEmpty {
                            if event.modifierFlags.contains(.option) {
                                // Move to top
                                moveTask(from: selectedIndices, to: 0)
                            } else {
                                // Move up one position
                                let minIndex = selectedIndices.min() ?? 0
                                if minIndex > 0 {
                                    // When moving up, we want to insert before the previous non-selected item
                                    let prevIndex = minIndex - 1
                                    let destinationIndex = selectedIndices.contains(prevIndex) ? prevIndex : prevIndex
                                    moveTask(from: selectedIndices, to: destinationIndex)
                                }
                            }
                            return nil
                        }
                    }
                } else if case .selected(let taskIds) = uiState {
                    if let currentTaskId = taskIds.first,
                       let currentIndex = windowManager.activeTasks.firstIndex(where: { $0.id == currentTaskId }) {
                        if currentIndex == 0 {
                            // If we're on the first task, focus the input field
                            isInputFocused = true
                            return nil
                        } else {
                            selectPreviousTask(before: currentTaskId)
                        }
                    }
                    return nil
                } else if isInputFocused && !windowManager.activeTasks.isEmpty {
                    // If input is focused and there are tasks, allow selecting the last task
                    if let lastTask = windowManager.activeTasks.last {
                        handleTaskSelection(taskId: lastTask.id, shouldUnfocusInput: false)
                    }
                    return nil
                }
            }
            return event
        }
    }
    
    private func selectNextTask(after currentTaskId: UUID) {
        let activeTasks = windowManager.activeTasks
        guard let currentIndex = activeTasks.firstIndex(where: { $0.id == currentTaskId }),
              currentIndex < activeTasks.count - 1 else { return }
        
        let nextTask = activeTasks[currentIndex + 1]
        handleTaskSelection(taskId: nextTask.id)
    }
    
    private func selectPreviousTask(before currentTaskId: UUID) {
        let activeTasks = windowManager.activeTasks
        guard let currentIndex = activeTasks.firstIndex(where: { $0.id == currentTaskId }),
              currentIndex > 0 else { return }
        
        let previousTask = activeTasks[currentIndex - 1]
        handleTaskSelection(taskId: previousTask.id)
    }
    
    private func cleanupKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func moveTask(from source: IndexSet, to destination: Int) {
        windowManager.moveTask(from: source, to: destination)
    }
    
    private func copySelectedTasks() {
        if case .selected(let taskIds) = uiState {
            // Get all selected tasks
            let selectedTasks = windowManager.tasks.filter { taskIds.contains($0.id) }
            
            // Create text with each task title on a new line
            let textToCopy = selectedTasks.map { $0.title }.joined(separator: "\n")
            
            // Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(textToCopy, forType: .string)
        }
    }
}

struct TaskRow: View {
    let task: Task
    let isEditing: Bool
    let isSelected: Bool
    let onSelect: (NSEvent?) -> Void
    let onStartEditing: () -> Void
    let onEndEditing: (String?) -> Void
    let onDragChange: ((Task, CGFloat) -> Void)?
    let onDragEnd: ((Task) -> Void)?
    @State private var editedTitle: String = ""
    @State private var isHovered = false
    @State private var isFrogHovered = false
    @State private var isCheckboxHovered = false
    @ObservedObject var windowManager: WindowManager
    
    // Function to get color based on priority
    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 3: return .white // 100% opacity
        case 2: return Color.white.opacity(0.40) // 40% opacity
        case 1: return Color.white.opacity(0.20) // 10% opacity
        default: return Color.white.opacity(0.20) // Default to lowest opacity
        }
    }
    
    // Function to get text opacity based on priority and hover state
    private func textOpacity(_ priority: Int, isHovered: Bool) -> Double {
        if isHovered || isSelected || task.isFrog {
            return 1.0 // Full opacity when hovered, selected, or is a frog task
        }
        
        switch priority {
        case 3: return 1.0 // 100% opacity
        case 2: return 0.40 // 40% opacity
        case 1: return 0.20 // 10% opacity
        default: return 0.20 // Default to lowest opacity
        }
    }
    
    var body: some View {
        ZStack {
            // Background layer
            if isSelected {
                Color.white.opacity(0.1)
            } else if isHovered && !isEditing {
                Color.white.opacity(0.05)
            }
            
            HStack(spacing: 8 * windowManager.zoomLevel) {
                // Checkbox area
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : (isCheckboxHovered ? .green : .gray))
                    .font(.system(size: 16 * windowManager.zoomLevel))
                    .onTapGesture {
                        if !task.isCompleted {
                            windowManager.completeTask(task)
                        }
                    }
                    .onHover { hovering in
                        isCheckboxHovered = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                
                // Main content area with drag handling
                if isEditing {
                    CustomTextField(
                        text: $editedTitle,
                        onSubmit: { newText in
                            if !newText.isEmpty {
                                var updatedTask = task
                                updatedTask.title = newText
                                windowManager.updateTask(updatedTask)
                            }
                            onEndEditing(newText)
                        },
                        onCancel: {
                            editedTitle = task.title
                            onEndEditing(nil)
                        },
                        windowManager: windowManager
                    )
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        editedTitle = task.title
                    }
                } else {
                    ZStack {
                        // Click and drag handler
                        ClickView(
                            onClick: { event in onSelect(event) },
                            onDoubleClick: {
                                editedTitle = task.title
                                onStartEditing()
                            },
                            onDragChange: { deltaY in
                                onDragChange?(task, deltaY)
                            },
                            onDragEnd: {
                                onDragEnd?(task)
                            }
                        )
                        
                        // Task title
                        Text(task.title)
                            .font(.system(size: 16 * windowManager.zoomLevel, weight: task.isFrog ? .bold : .regular, design: .default))
                            .strikethrough(task.isCompleted)
                            .foregroundColor(task.isCompleted ? .gray : (task.isFrog ? Color(hex: "8CFF00") : .white))
                            .opacity(task.isCompleted ? 1.0 : textOpacity(task.priority, isHovered: isHovered))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                }
                
                // Priority number (no background circle, just colored text)
                Text("\(task.priority)")
                    .font(.system(size: 14 * windowManager.zoomLevel, weight: .bold))
                    .foregroundColor(priorityColor(task.priority))
            }
            .padding(.vertical, 6 * windowManager.zoomLevel)
            .padding(.horizontal, 14 * windowManager.zoomLevel)
            
            // Frog button as overlay in absolute position to the right of task text and left of priority
            if isHovered || task.isFrog {
                HStack {
                    Spacer()
                    Button(action: {
                        windowManager.toggleFrog(for: task)
                    }) {
                        Text("🐸")
                            .opacity(task.isFrog ? (isFrogHovered ? 0.7 : 1) : (isFrogHovered ? 0.5 : 0.1))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20 * windowManager.zoomLevel)
                    .onHover { hovering in
                        isFrogHovered = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .padding(.trailing, 30 * windowManager.zoomLevel) // Increase padding to position it to the left of priority
                }
                .padding(.vertical, 6 * windowManager.zoomLevel)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6 * windowManager.zoomLevel))
        .padding(.horizontal, 8 * windowManager.zoomLevel)
        .onHover { hovering in
            isHovered = hovering
            if hovering && !isEditing {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .contentShape(Rectangle())
    }
}

struct ClickView: NSViewRepresentable {
    let onClick: (NSEvent?) -> Void
    let onDoubleClick: () -> Void
    let onDragChange: ((CGFloat) -> Void)?
    let onDragEnd: (() -> Void)?
    
    func makeNSView(context: Context) -> DoubleClickView {
        let view = DoubleClickView()
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onDragChange = onDragChange
        view.onDragEnd = onDragEnd
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: DoubleClickView, context: Context) {
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onDragChange = onDragChange
        nsView.onDragEnd = onDragEnd
    }
}

class DoubleClickView: NSView {
    var onClick: ((NSEvent?) -> Void)?
    var onDoubleClick: () -> Void = {}
    var onDragChange: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    
    private var isDragging = false
    private var initialClickLocation: NSPoint?
    private var dragThreshold: CGFloat = 3 // pixels to move before considering it a drag
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func mouseDown(with event: NSEvent) {
        initialClickLocation = event.locationInWindow
        isDragging = false
        
        // Handle double click immediately
        if event.clickCount == 2 {
            onDoubleClick()
            initialClickLocation = nil
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let initial = initialClickLocation else { return }
        
        let current = event.locationInWindow
        let deltaY = -(current.y - initial.y) // Invert the delta to match expected direction
        
        // Check if we've moved past the drag threshold
        if !isDragging && abs(deltaY) > dragThreshold {
            isDragging = true
        }
        
        if isDragging {
            onDragChange?(deltaY)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        defer {
            initialClickLocation = nil
            if isDragging {
                isDragging = false
                onDragEnd?()
            }
        }
        
        // Only trigger click if we haven't dragged and it's a single click
        if !isDragging && event.clickCount == 1 {
            onClick?(event)
        }
    }
}

struct SpeedModeView: View {
    @Binding var tasks: [Task]
    @ObservedObject var windowManager: WindowManager
    @State private var isHovered = false
    @State private var isHoveringComplete = false
    @State private var isHoveringStop = false
    
    var currentTask: Task? {
        windowManager.activeTasks.first
    }
    
    var body: some View {
        ZStack {
            Color.black
                .contentShape(Rectangle())
            
            if let task = currentTask {
                if isHovered {
                    ZStack {
                        // Task title in the middle, visible through transparent buttons
                        HStack(spacing: 8 * windowManager.zoomLevel) {
                            Text((task.isFrog ? "🐸 " : "") + task.title)
                                .font(.system(size: 16 * windowManager.zoomLevel, weight: task.isFrog ? .bold : .medium, design: .default))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundColor(task.isFrog ? Color(hex: "8CFF00") : .white)
                        }
                        
                        // Buttons as overlay
                        HStack(spacing: 0) {
                            Button(action: {
                                windowManager.toggleSpeedMode()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14 * windowManager.zoomLevel))
                                    .foregroundColor(isHoveringStop ? .white : .red)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.red.opacity(isHoveringStop ? 0.5 : 0.1))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringStop = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .frame(width: 50)
                            
                            Spacer()
                            
                            Button(action: {
                                windowManager.completeTask(task)
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14 * windowManager.zoomLevel))
                                    .foregroundColor(isHoveringComplete ? .white : .green)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.green.opacity(isHoveringComplete ? 0.5 : 0.1))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                isHoveringComplete = hovering
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .frame(width: 50)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text((task.isFrog ? "🐸 " : "") + task.title)
                        .font(.system(size: 16 * windowManager.zoomLevel, weight: task.isFrog ? .bold : .medium, design: .default))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(task.isFrog ? Color(hex: "8CFF00") : .white)
                }
            }
        }
        .frame(minWidth: 222, minHeight: 35)
        .opacity(windowManager.isAnimating ? 0 : 1)
        .animation(.easeIn(duration: 0.15), value: windowManager.isAnimating)
        .background(MouseTrackingView(isHovered: $isHovered, onHoverChange: { hovering in
            if !hovering {
                isHoveringComplete = false
                isHoveringStop = false
            }
        }))
        .onAppear {
            // Reset all hover states when entering Speed Mode
            isHovered = false
            isHoveringComplete = false
            isHoveringStop = false
        }
    }
}

struct DraggableView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

struct MouseTrackingView: NSViewRepresentable {
    @Binding var isHovered: Bool
    var onHoverChange: ((Bool) -> Void)?
    
    class MouseTrackingNSView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        var isHovered: Bool = false {
            didSet {
                onHoverChange?(isHovered)
            }
        }
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            
            for trackingArea in trackingAreas {
                removeTrackingArea(trackingArea)
            }
            
            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
            let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea)
        }
        
        override func mouseEntered(with event: NSEvent) {
            isHovered = true
        }
        
        override func mouseExited(with event: NSEvent) {
            isHovered = false
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = MouseTrackingNSView()
        view.onHoverChange = { hovering in
            isHovered = hovering
            onHoverChange?(hovering)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? MouseTrackingNSView {
            view.onHoverChange = { hovering in
                isHovered = hovering
                onHoverChange?(hovering)
            }
        }
    }
}

struct HoverView: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void
    
    class HoverViewImpl: NSView {
        var onHoverChange: ((Bool) -> Void)?
        var trackingArea: NSTrackingArea?
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            
            if let existingTrackingArea = trackingArea {
                removeTrackingArea(existingTrackingArea)
            }
            
            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            
            if let trackingArea = trackingArea {
                addTrackingArea(trackingArea)
            }
        }
        
        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }
        
        override func mouseExited(with event: NSEvent) {
            onHoverChange?(false)
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = HoverViewImpl()
        view.onHoverChange = onHoverChange
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? HoverViewImpl {
            view.onHoverChange = onHoverChange
        }
    }
}

// Priority selection button with updated styling
struct PriorityButton: View {
    let number: Int
    let isSelected: Bool
    let hasFocus: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isSelected ? .white : .gray)
                .frame(maxWidth: .infinity)
                .frame(height: 34) // Separate height modifier
                .background(isSelected ? Color.white.opacity(0.15) : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// Helper shape to create specific rounded corners
struct RoundedCornerShape: Shape {
    let bottomLeft: CGFloat
    let bottomRight: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start at top left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        
        // Right edge and bottom right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                radius: bottomRight,
                startAngle: Angle(degrees: 0),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        
        // Bottom left corner and left edge
        if bottomLeft > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                radius: bottomLeft,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 180),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        
        // Close the path
        path.closeSubpath()
        
        return path
    }
}

// Define KeyDirection enum outside of FocusableTextField
enum KeyDirection {
    case left, right, up, down
}

// QuickAddView - Command K-style modal for quick task entry
struct QuickAddView: View {
    @EnvironmentObject var windowManager: WindowManager
    @State private var taskText: String = ""
    @State private var isSubmitting = false
    @State private var selectedPriority: Int = 1 // Default priority changed to 1
    @State private var focusState: FocusState = .textField
    
    enum FocusState {
        case textField
        case priorityButtons
    }
    
    // Reference to the dummy view
    private let dummyViewId = "quickAddDummy"
    
    var body: some View {
        ZStack {
            // Make the entire view draggable
            DraggableView()
            
            // Input field and priority buttons
            VStack(spacing: 0) { // Ensure spacing is zero
                // Text input field
                FocusableTextField(
                    text: $taskText,
                    onSubmit: { submitTask() },
                    onCancel: { windowManager.closeQuickAddModal() },
                    onTab: {
                        focusState = .priorityButtons
                        focusDummyElement()
                    }
                )
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.horizontal, 10)
                // Removed all vertical padding
                
                // Invisible dummy view for focus
                DummyView()
                    .id(dummyViewId)
                    .frame(width: 0, height: 0)
                    .accessibility(identifier: dummyViewId)
                
                // Priority buttons container
                VStack {
                    HStack(spacing: 0) {
                        ForEach(1...3, id: \.self) { priority in
                            PriorityButton(
                                number: priority,
                                isSelected: selectedPriority == priority,
                                hasFocus: focusState == .priorityButtons,
                                action: { selectedPriority = priority }
                            )
                        }
                    }
                    .padding(6) // Keep internal padding for buttons
                }
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                // Apply padding only horizontally and at the bottom
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(width: 400)
        }
        .frame(width: 400)
        .onAppear {
            selectedPriority = 1
            focusState = .textField
        }
        .onKeyPress(.leftArrow) {
            if focusState == .priorityButtons && selectedPriority > 1 {
                selectedPriority -= 1
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if focusState == .priorityButtons && selectedPriority < 3 {
                selectedPriority += 1
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.tab) {
            // Tab cycles between text field and priority buttons
            if focusState == .priorityButtons {
                focusState = .textField
                focusTextField()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            DispatchQueue.main.async {
                submitTask()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            DispatchQueue.main.async {
                windowManager.closeQuickAddModal()
            }
            return .handled
        }
    }
    
    // Focus the text field
    private func focusTextField() {
        if let window = windowManager.quickAddWindow,
           let textField = window.contentView?.firstTextField() {
            window.makeFirstResponder(textField)
        }
    }
    
    // Focus the dummy element to shift focus away from text field
    private func focusDummyElement() {
        if let window = windowManager.quickAddWindow,
           let dummyView = window.contentView?.findDummyNSView() {
            window.makeFirstResponder(dummyView)
        }
    }
    
    private func submitTask() {
        guard !isSubmitting else { return }
        isSubmitting = true
        
        let trimmedText = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            // Create a new task with the selected priority
            _ = windowManager.addTaskWithPriority(trimmedText, priority: selectedPriority)
            
            // Close first, then clear text - avoids visual glitches
            windowManager.closeQuickAddModal()
            taskText = ""
            isSubmitting = false
        } else {
            // Just close the modal if empty
            windowManager.closeQuickAddModal()
            isSubmitting = false
        }
    }
}

// Text field specifically for the Quick Add modal
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onTab: () -> Void
    
    class AutoFocusTextField: NSTextField {
        // Disable field editor to avoid remote view controller issues
        override var allowsVibrancy: Bool { return false }
        
        // Ensure this field accepts first responder status
        override var acceptsFirstResponder: Bool { return true }
        
        // Callback for Tab key press
        var onTab: (() -> Void)?
        
        // Keep track of event monitor for cleanup
        var eventMonitor: Any?
        
        deinit {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        
        // Override to prevent default selection behavior
        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result, let currentEditor = currentEditor() {
                // Move cursor to end instead of selecting all text
                let length = stringValue.count
                currentEditor.selectedRange = NSRange(location: length, length: 0)
            }
            return result
        }
        
        // Override keyDown to catch Tab key
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48 && !event.modifierFlags.contains(.shift) { // Tab key without shift
                onTab?()
                return // Consume the event
            }
            
            // Pass other keys to default handler
            super.keyDown(with: event)
        }
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = AutoFocusTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.onTab = onTab
        
        // Appearance
        textField.font = .systemFont(ofSize: 24, weight: .medium)
        textField.textColor = .white
        textField.backgroundColor = .black
        textField.drawsBackground = false
        textField.isBordered = false
        textField.focusRingType = .none
        
        // Make text field taller - adjust height
        let cellHeight: CGFloat = 40 // Increase height to 80px
        textField.frame = NSRect(x: 0, y: 0, width: 380, height: cellHeight)
        
        // Center text vertically with the taller height
        if let cell = textField.cell as? NSTextFieldCell {
            cell.titleRect(forBounds: NSRect(x: 0, y: 0, width: 380, height: cellHeight))
            // Set vertical alignment
            cell.setAccessibilityFrame(NSRect(x: 0, y: 0, width: 380, height: cellHeight))
        }
        
        // Placeholder
        textField.placeholderString = "Add a new task..."
        textField.placeholderAttributedString = NSAttributedString(
            string: "Add a new task...",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.3),
                .font: NSFont.systemFont(ofSize: 24, weight: .medium)
            ]
        )
        
        // Custom behaviors
        textField.refusesFirstResponder = false
        textField.isEditable = true
        textField.isSelectable = true
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update text value from binding if it's actually different
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        // Update callback
        if let textField = nsView as? AutoFocusTextField {
            textField.onTab = onTab
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        var isSubmitting = false
        
        init(_ parent: FocusableTextField) {
            self.parent = parent
            super.init()
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if !isSubmitting {
                    isSubmitting = true
                    DispatchQueue.main.async { [weak self] in
                        self?.parent.onSubmit()
                        self?.isSubmitting = false
                    }
                }
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if !isSubmitting {
                    isSubmitting = true
                    DispatchQueue.main.async { [weak self] in
                        self?.parent.onCancel()
                        self?.isSubmitting = false
                    }
                }
                return true
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                // Shift+Tab is handled at the QuickAddView level
                return false
            }
            return false // Allow other commands
        }
    }
}

struct NSWindowDragHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        // Make the window draggable
        DispatchQueue.main.async {
            view.window?.standardWindowButton(.closeButton)?.isHidden = true
            view.window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
            view.window?.standardWindowButton(.zoomButton)?.isHidden = true
            view.window?.isMovableByWindowBackground = true
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension NSView {
    func firstTextField() -> NSTextField? {
        // If this is a text field, return it
        if let textField = self as? NSTextField {
            return textField
        }
        
        // Search subviews recursively
        for subview in subviews {
            if let textField = subview.firstTextField() {
                return textField
            }
        }
        
        return nil
    }
    
    // Helper to find the dummy view
    func findDummyNSView() -> DummyView.DummyNSView? {
        // If this is a dummy view, return it
        if let dummyView = self as? DummyView.DummyNSView {
            return dummyView
        }
        
        // Search recursively
        for subview in subviews {
            if let dummyView = subview.findDummyNSView() {
                return dummyView
            }
        }
        
        return nil
    }
}

// Dummy NSViewRepresentable to act as an inert focus target
struct DummyView: NSViewRepresentable {
    class DummyNSView: NSView {
        // Accept first responder status
        override var acceptsFirstResponder: Bool { return true }
        
        // Draw nothing
        override func draw(_ dirtyRect: NSRect) {}
        
        // Zero size by default
        override var intrinsicContentSize: NSSize { return .zero }
        
        // Override to handle key events when focused
        override func keyDown(with event: NSEvent) {
            // Don't need to handle anything here - we want the SwiftUI view's .onKeyPress handlers to catch the events
            // Just don't pass to super to avoid beeps
        }
        
        // Focus ring is hidden
        override var focusRingType: NSFocusRingType {
            get { return .none }
            set { }
        }
        
        // Handle when becoming first responder
        override func becomeFirstResponder() -> Bool {
            // Accept becoming first responder, but don't show any visual indicators
            return super.becomeFirstResponder()
        }
    }

    func makeNSView(context: Context) -> DummyNSView {
        let view = DummyNSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: DummyNSView, context: Context) {}
}

#Preview {
    ContentView()
}
