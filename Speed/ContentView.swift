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
    
    enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, completedAt, isFrog
    }
}

class WindowManager: ObservableObject {
    @Published var isSpeedMode = false
    @Published var isAnimating = false
    @Published var lastSpeedPosition: NSPoint?
    @Published var tasks: [Task] = []
    @Published var shouldFocusInput = false
    @Published var zoomLevel: Double = 1.0
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
            window.minSize = NSSize(width: 400, height: 400)
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
                let frame = NSRect(x: (NSScreen.main?.frame.width ?? 800) / 2 - 200,
                                 y: (NSScreen.main?.frame.height ?? 600) / 2 - 200,
                                 width: 400,
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
        let newTask = Task(title: title, isCompleted: false)
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
                Task(title: cleanTaskTitle(title), isCompleted: false)
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
        if let savedPosition = UserDefaults.standard.string(forKey: "speedPosition")?.components(separatedBy: ","),
           savedPosition.count == 2,
           let x = Double(savedPosition[0]),
           let y = Double(savedPosition[1]) {
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
                
                // Toggle state immediately to hide List Mode UI
                isSpeedMode.toggle()
                
                // Small delay to ensure UI has updated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    withAnimation(.none) {
                        // Configure window properties for Speed Mode
                        let tempFrame = window.frame
                        window.styleMask = [.borderless, .fullSizeContentView]
                        window.setFrame(tempFrame, display: false)
                        
                        window.isMovableByWindowBackground = true
                        window.isMovable = true
                        window.minSize = NSSize(width: 300, height: 50)
                        window.maxSize = NSSize(width: 300, height: 50)
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
                        
                        // Use saved position or default if none saved
                        let position = self.lastSpeedPosition ?? NSPoint(
                            x: (NSScreen.main?.frame.width ?? 800) / 2 - 150,
                            y: 50
                        )
                        
                        // Set the frame
                        self.isSettingFrame = true
                        window.setFrame(NSRect(x: position.x,
                                             y: position.y,
                                             width: 300,
                                             height: 50), display: true, animate: true)
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
                        
                        // Add a delay to match the animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                            self.isAnimating = false
                            self.shouldFocusInput = true
                        }
                    }
                }
            } else {
                // If we're exiting Speed mode, remove the observer FIRST
                if let observer = positionObserver {
                    NotificationCenter.default.removeObserver(observer)
                    positionObserver = nil
                }
                
                // Save the current Speed Mode position before switching back
                let speedPosition = window.frame.origin
                UserDefaults.standard.set("\(speedPosition.x),\(speedPosition.y)", forKey: "speedPosition")
                lastSpeedPosition = speedPosition
                
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
                            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: true)
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
                        .transition(.opacity.animation(.easeIn(duration: 0.1)))
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
            return false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.textColor = .white
        textField.font = .systemFont(ofSize: 16 * windowManager.zoomLevel)
        textField.focusRingType = .none
        textField.drawsBackground = false
        textField.isSelectable = true
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
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: previewIndex)
                    .gesture(
                        DragGesture(coordinateSpace: .named("scroll"))
                            .onChanged { value in
                                if draggingTask == nil {
                                    draggingTask = task
                                }
                                
                                if draggingTask?.id == task.id {
                                    dragOffset = value.translation.height
                                    
                                    if let currentIndex = activeTasks.firstIndex(where: { $0.id == task.id }) {
                                        let taskHeight = taskPositions[task.id]?.height ?? 0
                                        
                                        // Calculate how many positions to move based on drag distance
                                        let dragDistance = value.translation.height
                                        let positionsToMove = Int(round(dragDistance / taskHeight))
                                        
                                        // Calculate target index
                                        let targetIndex = max(0, min(activeTasks.count - 1, currentIndex + positionsToMove))
                                        
                                        // Only update preview if we're actually moving
                                        if targetIndex != currentIndex {
                                            previewIndex = targetIndex
                                        } else {
                                            previewIndex = nil
                                        }
                                    }
                                }
                            }
                            .onEnded { value in
                                if let sourceIndex = activeTasks.firstIndex(where: { $0.id == task.id }),
                                   let targetIndex = previewIndex {
                                    // Move the task first
                                    onMove(IndexSet(integer: sourceIndex), targetIndex)
                                }
                                
                                // Reset all states after the move
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                    draggingTask = nil
                                    previewIndex = nil
                                }
                            }
                    )
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
            // Handle zoom shortcuts
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "=" {  // Command + equals/plus
                    windowManager.adjustZoom(increase: true)
                    return nil
                } else if event.charactersIgnoringModifiers == "-" {  // Command + minus
                    windowManager.adjustZoom(increase: false)
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
                } else if isInputFocused {
                    return event
                } else if case .selected(let taskIds) = uiState {
                    if let currentTaskId = taskIds.first {
                        selectPreviousTask(before: currentTaskId)
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
}

struct TaskRow: View {
    let task: Task
    let isEditing: Bool
    let isSelected: Bool
    let onSelect: (NSEvent?) -> Void
    let onStartEditing: () -> Void
    let onEndEditing: (String?) -> Void
    @State private var editedTitle: String = ""
    @State private var isHovered = false
    @State private var isFrogHovered = false
    @State private var isCheckboxHovered = false
    @ObservedObject var windowManager: WindowManager
    
    var body: some View {
        ZStack {
            // Background layer
            if isSelected {
                Color.white.opacity(0.1)
            } else if isHovered && !isEditing {
                Color.white.opacity(0.05)
            }
            
            // Click handler layer for the entire row except buttons
            if !isEditing {
                ClickView(
                    onClick: { event in onSelect(event) },
                    onDoubleClick: {
                        editedTitle = task.title
                        onStartEditing()
                    }
                )
            }
            
            // Content layer
            HStack(spacing: 8 * windowManager.zoomLevel) {
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
                    .allowsHitTesting(true)
                
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
                    HStack {
                        Text(task.title)
                            .font(.system(size: 16 * windowManager.zoomLevel, weight: task.isFrog ? .bold : .regular, design: .default))
                            .strikethrough(task.isCompleted)
                            .foregroundColor(task.isCompleted ? .gray : (task.isFrog ? Color(hex: "8CFF00") : .white))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                        
                        if isHovered || task.isFrog {
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
                            .allowsHitTesting(true)
                        }
                    }
                }
            }
            .padding(.vertical, 6 * windowManager.zoomLevel)
            .padding(.horizontal, 14 * windowManager.zoomLevel)
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
    }
}

struct ClickView: NSViewRepresentable {
    let onClick: (NSEvent?) -> Void
    let onDoubleClick: () -> Void
    
    func makeNSView(context: Context) -> DoubleClickView {
        let view = DoubleClickView()
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: DoubleClickView, context: Context) {}
}

class DoubleClickView: NSView {
    var onClick: ((NSEvent?) -> Void)?
    var onDoubleClick: () -> Void = {}
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        let singleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        singleClickGesture.numberOfClicksRequired = 1
        self.addGestureRecognizer(singleClickGesture)
        
        let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClickGesture.numberOfClicksRequired = 2
        self.addGestureRecognizer(doubleClickGesture)
        
        // Make single click wait for possible double click
        singleClickGesture.delaysPrimaryMouseButtonEvents = true
        doubleClickGesture.delaysPrimaryMouseButtonEvents = false
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
    
    @objc private func handleClick(_ gesture: NSGestureRecognizer) {
        if let event = NSApplication.shared.currentEvent {
            onClick?(event)
        }
    }
    
    @objc private func handleDoubleClick() {
        onDoubleClick()
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
                        Text((task.isFrog ? "🐸 " : "") + task.title)
                            .font(.system(size: 16 * windowManager.zoomLevel, weight: task.isFrog ? .bold : .medium, design: .default))
                            .lineLimit(1)
                            .foregroundColor(task.isFrog ? Color(hex: "8CFF00") : .white)
                        
                        // Buttons as overlay
                        HStack(spacing: 0) {
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
                            
                            Spacer()
                            
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
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text((task.isFrog ? "🐸 " : "") + task.title)
                        .font(.system(size: 16 * windowManager.zoomLevel, weight: task.isFrog ? .bold : .medium, design: .default))
                        .lineLimit(1)
                        .foregroundColor(task.isFrog ? Color(hex: "8CFF00") : .white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(windowManager.isAnimating ? 0 : 1)
        .animation(.easeIn(duration: 0.2), value: windowManager.isAnimating)
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

#Preview {
    ContentView()
}
