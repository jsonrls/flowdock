import AppKit
import Combine
import Foundation

struct RunningApp: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
}

struct WorkspaceApplication: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL

    var id: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier.lowercased())"
        }
        return "path:\(bundleURL.standardizedFileURL.path.lowercased())"
    }

    init?(runningApp: RunningApp) {
        guard let bundleURL = runningApp.bundleURL,
            bundleURL.pathExtension.lowercased() == "app"
        else {
            return nil
        }
        name = runningApp.name
        bundleIdentifier = runningApp.bundleIdentifier
        self.bundleURL = bundleURL
    }

    init?(resource: WorkspaceResource) {
        guard resource.kind == .application else { return nil }
        name = resource.title
        bundleURL = URL(fileURLWithPath: resource.location)
        bundleIdentifier = resource.bundleIdentifier ?? Bundle(url: bundleURL)?.bundleIdentifier
    }
}

struct RecentFile: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let kind: String
    let lastUsedAt: Date

    var detail: String {
        let folder = url.deletingLastPathComponent().lastPathComponent
        return folder.isEmpty ? kind : "\(kind) · \(folder)"
    }
}

struct ClipboardCopyConfirmation: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isImage: Bool
}

struct PomodoroCompletion: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let minutes: Int
}

enum AIAction: String, CaseIterable, Identifiable {
    case explain = "Explain"
    case rewrite = "Rewrite"
    case summarize = "Summarize"
    case code = "Generate Code"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .explain: "lightbulb.max"
        case .rewrite: "text.badge.star"
        case .summarize: "list.bullet.rectangle"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    private static let workspaceSelectionDefaultsKey = "flowdock.selectedWorkspaceID"
    private static let legacyWorkspaceSelectionDefaultsKeys = [
        "FlowDock.selectedWorkspaceID",
        "Flowdock.selectedWorkspaceID"
    ]

    @Published private(set) var tasks: [FocusTask] = []
    @Published private(set) var pomodoroPresets: [PomodoroPreset] = []
    @Published var searchText = ""
    @Published var searchRequested = false
    @Published var isTimerRunning = false
    @Published var timerSeconds: Int
    @Published private(set) var activePomodoroID: UUID?
    @Published var selectedAIAction: AIAction?
    @Published var isAIPanelPresented = false
    @Published private(set) var clipboardItems: [ClipboardHistoryItem] = []
    @Published private(set) var runningApps: [RunningApp] = []
    @Published private(set) var recentFiles: [RecentFile] = []
    @Published private(set) var isLoadingRecentFiles = true
    @Published private(set) var clipboardCopyConfirmation: ClipboardCopyConfirmation?
    @Published private(set) var systemMetrics = SystemMetrics.empty
    @Published private(set) var workspaces: [WorkspaceSnapshot] = []
    @Published private(set) var selectedWorkspaceID: UUID?
    @Published private(set) var workspaceResources: [UUID: [WorkspaceResource]] = [:]
    @Published private(set) var pendingWorkspaceRestoreID: UUID?
    @Published private(set) var pendingWorkspaceDeletionID: UUID?
    @Published private(set) var pendingTaskDeletionID: UUID?
    @Published private(set) var pendingPomodoroDeletionID: UUID?
    @Published private(set) var pomodoroCompletion: PomodoroCompletion?

    private var timer: AnyCancellable?
    private var alarmSound: NSSound?
    private var focusDurationSeconds: Int
    private var persistenceStore: PersistenceStore?
    private weak var preferences: PreferencesModel?
    private var clipboardChangeCount = NSPasteboard.general.changeCount
    private var recentlyUsedAppIDs: [pid_t] = []
    private var metadataQuery: NSMetadataQuery?
    private var metadataQueryCancellables = Set<AnyCancellable>()
    private var usesRecentFilesFallback = false
    private var isRefreshingRecentFilesFallback = false
    private var recentFilesFallbackTick = 0
    private var openedFileActivity: [URL: RecentFile] = [:]
    private let systemMonitor = SystemMonitor()
    private var systemMetricsTick = 0

    init() {
        let minutes = 25
        focusDurationSeconds = minutes * 60
        timerSeconds = minutes * 60
        systemMetrics = systemMonitor.sample()
        refreshRunningApplications()
        startRecentFilesQuery()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.refreshRecentFilesFallbackIfNeeded()
        }

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleTick()
            }
    }

    var formattedTimer: String {
        String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60)
    }

    var progress: Double {
        1 - Double(timerSeconds) / Double(max(focusDurationSeconds, 1))
    }

    var activePomodoroTitle: String {
        guard let activePomodoroID,
            let preset = pomodoroPresets.first(where: { $0.id == activePomodoroID })
        else {
            return "Focus session"
        }
        return preset.title
    }

    func toggleTask(_ task: FocusTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isComplete.toggle()
        tasks[index].completedAt = tasks[index].isComplete ? .now : nil
        persistenceStore?.saveTask(tasks[index])
        sortTasks()
    }

    @discardableResult
    func addTask(title: String, note: String, priority: TaskPriority) -> UUID? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let task = FocusTask(
            title: cleanTitle,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            sortOrder: (tasks.map(\.sortOrder).max() ?? -1) + 1
        )
        persistenceStore?.saveTask(task)
        tasks.append(task)
        sortTasks()
        return task.id
    }

    @discardableResult
    func updateTask(
        _ task: FocusTask,
        title: String,
        note: String,
        priority: TaskPriority
    ) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !cleanTitle.isEmpty,
            let index = tasks.firstIndex(where: { $0.id == task.id })
        else { return false }

        tasks[index].title = cleanTitle
        tasks[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks[index].priority = priority
        persistenceStore?.saveTask(tasks[index])
        sortTasks()
        return true
    }

    func deleteTask(_ task: FocusTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        persistenceStore?.deleteTask(task.id)
        tasks.remove(at: index)
    }

    var pendingTaskDeletion: FocusTask? {
        guard let pendingTaskDeletionID else { return nil }
        return tasks.first(where: { $0.id == pendingTaskDeletionID })
    }

    func requestTaskDeletion(_ taskID: UUID) {
        guard tasks.contains(where: { $0.id == taskID }) else { return }
        pendingTaskDeletionID = taskID
    }

    func cancelTaskDeletion() {
        pendingTaskDeletionID = nil
    }

    func confirmTaskDeletion() {
        guard let task = pendingTaskDeletion else { return }
        pendingTaskDeletionID = nil
        deleteTask(task)
    }

    @discardableResult
    func addPomodoro(title: String, minutes: Int) -> UUID? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let preset = PomodoroPreset(
            title: cleanTitle,
            minutes: max(minutes, 1),
            sortOrder: (pomodoroPresets.map(\.sortOrder).max() ?? -1) + 1
        )
        persistenceStore?.savePomodoroPreset(preset)
        pomodoroPresets.append(preset)
        return preset.id
    }

    @discardableResult
    func updatePomodoro(_ preset: PomodoroPreset, title: String, minutes: Int) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !cleanTitle.isEmpty,
            let index = pomodoroPresets.firstIndex(where: { $0.id == preset.id })
        else { return false }

        pomodoroPresets[index].title = cleanTitle
        pomodoroPresets[index].minutes = max(minutes, 1)
        persistenceStore?.savePomodoroPreset(pomodoroPresets[index])
        return true
    }

    func deletePomodoro(_ preset: PomodoroPreset) {
        guard let index = pomodoroPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        if activePomodoroID == preset.id {
            isTimerRunning = false
            activePomodoroID = nil
            applyConfiguredFocusDuration()
        }
        persistenceStore?.deletePomodoroPreset(preset.id)
        pomodoroPresets.remove(at: index)
    }

    var pendingPomodoroDeletion: PomodoroPreset? {
        guard let pendingPomodoroDeletionID else { return nil }
        return pomodoroPresets.first(where: { $0.id == pendingPomodoroDeletionID })
    }

    func requestPomodoroDeletion(_ presetID: UUID) {
        guard pomodoroPresets.contains(where: { $0.id == presetID }) else { return }
        pendingPomodoroDeletionID = presetID
    }

    func cancelPomodoroDeletion() {
        pendingPomodoroDeletionID = nil
    }

    func confirmPomodoroDeletion() {
        guard let preset = pendingPomodoroDeletion else { return }
        pendingPomodoroDeletionID = nil
        deletePomodoro(preset)
    }

    func startPomodoro(_ preset: PomodoroPreset) {
        dismissPomodoroCompletion()
        if activePomodoroID == preset.id {
            toggleTimer()
            return
        }
        activePomodoroID = preset.id
        focusDurationSeconds = preset.minutes * 60
        timerSeconds = focusDurationSeconds
        isTimerRunning = true
    }

    func toggleTimer() {
        dismissPomodoroCompletion()
        if activePomodoroID == nil, let first = pomodoroPresets.first {
            startPomodoro(first)
            return
        }
        if timerSeconds == 0 { applyConfiguredFocusDuration() }
        isTimerRunning.toggle()
    }

    func resetTimer() {
        dismissPomodoroCompletion()
        applyConfiguredFocusDuration()
        isTimerRunning = false
    }

    func stopPomodoro() {
        dismissPomodoroCompletion()
        isTimerRunning = false
        activePomodoroID = nil
        applyConfiguredFocusDuration()
    }

    func dismissPomodoroCompletion() {
        pomodoroCompletion = nil
        alarmSound?.stop()
        alarmSound = nil
    }

    private func applyConfiguredFocusDuration() {
        let minutes =
            activePomodoroID
            .flatMap { id in pomodoroPresets.first(where: { $0.id == id })?.minutes }
            ?? max(preferences?.focusMinutes ?? 25, 1)
        focusDurationSeconds = minutes * 60
        timerSeconds = focusDurationSeconds
    }

    func configurePersistence(_ store: PersistenceStore, preferences: PreferencesModel) {
        guard persistenceStore == nil else { return }
        persistenceStore = store
        self.preferences = preferences

        workspaces = store.loadWorkspaces()
        workspaceResources = Dictionary(
            uniqueKeysWithValues: workspaces.map { ($0.id, store.resources(for: $0.id)) }
        )
        let defaults = UserDefaults.standard
        let storedSelectionString = defaults.string(forKey: Self.workspaceSelectionDefaultsKey)
            ?? Self.legacyWorkspaceSelectionDefaultsKeys.lazy.compactMap {
                defaults.string(forKey: $0)
            }.first
        let storedSelection = storedSelectionString.flatMap(UUID.init(uuidString:))
        if let storedSelectionString,
           defaults.string(forKey: Self.workspaceSelectionDefaultsKey) == nil {
            defaults.set(storedSelectionString, forKey: Self.workspaceSelectionDefaultsKey)
        }
        selectedWorkspaceID =
            workspaces.contains(where: { $0.id == storedSelection })
            ? storedSelection
            : workspaces.first?.id

        applyConfiguredFocusDuration()

        clipboardItems = store.loadClipboardHistory()
        clipboardChangeCount = NSPasteboard.general.changeCount
        if preferences.refreshClipboardOnLaunch { captureCurrentClipboard(force: true) }

        let taskSeedKey = "flowdock.didSeedDefaultTasks"
        let storedTasks = store.loadTasks()
        if storedTasks.isEmpty, !defaults.bool(forKey: taskSeedKey) {
            let defaultTasks = [
                FocusTask(
                    title: "Finish client project", note: "Polish final handoff", isComplete: true,
                    priority: .high, sortOrder: 0, completedAt: .now),
                FocusTask(
                    title: "Gym", note: "Upper body · 45 min", priority: .medium, sortOrder: 1),
                FocusTask(
                    title: "Read for 20 minutes", note: "Continue chapter seven", priority: .low,
                    sortOrder: 2),
            ]
            defaultTasks.forEach(store.saveTask)
            tasks = defaultTasks
            defaults.set(true, forKey: taskSeedKey)
            sortTasks()
        } else {
            tasks = storedTasks
            defaults.set(true, forKey: taskSeedKey)
            sortTasks()
        }

        let pomodoroSeedKey = "flowdock.didSeedDefaultPomodoros"
        let storedPresets = store.loadPomodoroPresets()
        if storedPresets.isEmpty, !defaults.bool(forKey: pomodoroSeedKey) {
            let defaultPresets = [
                PomodoroPreset(title: "Deep work", minutes: preferences.focusMinutes, sortOrder: 0),
                PomodoroPreset(title: "Quick sprint", minutes: 15, sortOrder: 1),
                PomodoroPreset(title: "Long focus", minutes: 45, sortOrder: 2),
            ]
            defaultPresets.forEach(store.savePomodoroPreset)
            pomodoroPresets = defaultPresets
            defaults.set(true, forKey: pomodoroSeedKey)
        } else {
            pomodoroPresets = storedPresets
            defaults.set(true, forKey: pomodoroSeedKey)
        }
    }

    private func sortTasks() {
        tasks.sort { lhs, rhs in
            if lhs.isComplete != rhs.isComplete { return !lhs.isComplete }
            if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func activate(_ app: RunningApp) {
        recentlyUsedAppIDs.removeAll { $0 == app.id }
        recentlyUsedAppIDs.insert(app.id, at: 0)

        if let application = NSRunningApplication(processIdentifier: app.id),
            application.activate(options: [.activateAllWindows])
        {
            refreshRunningApplications()
            return
        }

        guard let url = app.bundleURL else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    var selectedWorkspace: WorkspaceSnapshot? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.first(where: { $0.id == selectedWorkspaceID })
    }

    @discardableResult
    func addWorkspace(named name: String) -> UUID? {
        addWorkspace(
            named: name,
            applications: runningApps.compactMap(WorkspaceApplication.init(runningApp:))
        )
    }

    @discardableResult
    func addWorkspace(named name: String, apps: [RunningApp]) -> UUID? {
        addWorkspace(
            named: name,
            applications: apps.compactMap(WorkspaceApplication.init(runningApp:))
        )
    }

    @discardableResult
    func addWorkspace(named name: String, applications: [WorkspaceApplication]) -> UUID? {
        guard let persistenceStore else { return nil }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        let workspace = WorkspaceSnapshot(name: cleanName)
        let resources = applicationResources(from: applications, for: workspace.id)
        guard !resources.isEmpty else {
            NSSound.beep()
            return nil
        }

        persistenceStore.saveWorkspace(workspace)
        persistenceStore.replaceResources(for: workspace.id, with: resources)
        workspaces.insert(workspace, at: 0)
        workspaceResources[workspace.id] = resources
        selectWorkspace(workspace.id)
        return workspace.id
    }

    func updateWorkspace(_ workspaceID: UUID) {
        let applications = runningApps.compactMap(WorkspaceApplication.init(runningApp:))
        _ = updateWorkspace(workspaceID, applications: applications)
    }

    @discardableResult
    func updateWorkspace(
        _ workspaceID: UUID,
        applications: [WorkspaceApplication]
    ) -> Bool {
        guard let persistenceStore,
            let index = workspaces.firstIndex(where: { $0.id == workspaceID })
        else {
            return false
        }

        let resources = applicationResources(from: applications, for: workspaceID)
        guard !resources.isEmpty else {
            NSSound.beep()
            return false
        }

        workspaces[index].updatedAt = .now
        persistenceStore.saveWorkspace(workspaces[index])
        persistenceStore.replaceResources(for: workspaceID, with: resources)
        workspaceResources[workspaceID] = resources
        workspaces.sort { $0.updatedAt > $1.updatedAt }
        selectWorkspace(workspaceID)
        return true
    }

    func selectWorkspace(_ workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else { return }
        selectedWorkspaceID = workspaceID
        UserDefaults.standard.set(
            workspaceID.uuidString,
            forKey: Self.workspaceSelectionDefaultsKey
        )
    }

    var pendingWorkspaceRestore: WorkspaceSnapshot? {
        guard let pendingWorkspaceRestoreID else { return nil }
        return workspaces.first { $0.id == pendingWorkspaceRestoreID }
    }

    func requestWorkspaceRestore(_ workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else { return }
        pendingWorkspaceRestoreID = workspaceID
    }

    func confirmWorkspaceRestore() {
        guard let workspaceID = pendingWorkspaceRestoreID else { return }
        pendingWorkspaceRestoreID = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            self?.restoreWorkspace(workspaceID)
        }
    }

    func cancelWorkspaceRestore() {
        pendingWorkspaceRestoreID = nil
    }

    var pendingWorkspaceDeletion: WorkspaceSnapshot? {
        guard let pendingWorkspaceDeletionID else { return nil }
        return workspaces.first { $0.id == pendingWorkspaceDeletionID }
    }

    func requestWorkspaceDeletion(_ workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else { return }
        pendingWorkspaceDeletionID = workspaceID
    }

    func confirmWorkspaceDeletion() {
        guard let workspaceID = pendingWorkspaceDeletionID else { return }
        pendingWorkspaceDeletionID = nil
        deleteWorkspace(workspaceID)
    }

    func cancelWorkspaceDeletion() {
        pendingWorkspaceDeletionID = nil
    }

    private func restoreWorkspace(_ workspaceID: UUID) {
        guard let resources = workspaceResources[workspaceID] else {
            NSSound.beep()
            return
        }

        selectWorkspace(workspaceID)
        for resource in resources where resource.kind == .application {
            let url = URL(fileURLWithPath: resource.location)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func deleteWorkspace(_ workspaceID: UUID) {
        if pendingWorkspaceRestoreID == workspaceID {
            pendingWorkspaceRestoreID = nil
        }
        if pendingWorkspaceDeletionID == workspaceID {
            pendingWorkspaceDeletionID = nil
        }
        persistenceStore?.deleteWorkspace(workspaceID)
        workspaces.removeAll { $0.id == workspaceID }
        workspaceResources.removeValue(forKey: workspaceID)

        if selectedWorkspaceID == workspaceID {
            selectedWorkspaceID = workspaces.first?.id
            if let selectedWorkspaceID {
                UserDefaults.standard.set(
                    selectedWorkspaceID.uuidString,
                    forKey: Self.workspaceSelectionDefaultsKey
                )
            } else {
                UserDefaults.standard.removeObject(forKey: Self.workspaceSelectionDefaultsKey)
            }
        }
    }

    private func applicationResources(
        from applications: [WorkspaceApplication],
        for workspaceID: UUID
    ) -> [WorkspaceResource] {
        var seenApplicationIDs = Set<String>()
        let uniqueApplications = applications.filter { application in
            seenApplicationIDs.insert(application.id).inserted
        }

        return uniqueApplications.enumerated().map { index, app in
            return WorkspaceResource(
                workspaceID: workspaceID,
                kind: .application,
                title: app.name,
                location: app.bundleURL.path,
                bundleIdentifier: app.bundleIdentifier,
                sortOrder: index
            )
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard NSWorkspace.shared.open(url) else {
                NSSound.beep()
                return
            }
            self.recordFileActivity(at: url)
        }
    }

    func open(_ file: RecentFile) {
        guard NSWorkspace.shared.open(file.url) else {
            NSSound.beep()
            return
        }

        recordFileActivity(at: file.url, name: file.name, kind: file.kind)
    }

    func restoreClipboardItem(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let didCopy: Bool

        switch item.kind {
        case .text:
            guard let value = item.text else { return }
            didCopy = pasteboard.setString(value, forType: .string)
        case .image:
            guard let data = item.imageData, let image = NSImage(data: data) else { return }
            didCopy = pasteboard.writeObjects([image])
        }

        guard didCopy else {
            NSSound.beep()
            return
        }
        clipboardChangeCount = pasteboard.changeCount
        let imageTitle = item.text.flatMap { $0.isEmpty ? nil : $0 } ?? "Image"
        let title =
            item.kind == .image
            ? imageTitle
            : String((item.text ?? "Text").prefix(54))
        clipboardCopyConfirmation = ClipboardCopyConfirmation(
            title: title,
            isImage: item.kind == .image
        )
    }

    func dismissClipboardCopyConfirmation(_ id: UUID) {
        guard clipboardCopyConfirmation?.id == id else { return }
        clipboardCopyConfirmation = nil
    }

    private func handleTick() {
        refreshRunningApplications()
        captureCurrentClipboard()

        systemMetricsTick += 1
        if systemMetricsTick >= 2 {
            systemMetricsTick = 0
            systemMetrics = systemMonitor.sample()
        }

        if usesRecentFilesFallback {
            recentFilesFallbackTick += 1
            if recentFilesFallbackTick >= 15 {
                recentFilesFallbackTick = 0
                refreshRecentFilesFallbackIfNeeded(force: true)
            }
        }

        guard isTimerRunning else { return }
        guard timerSeconds > 0 else {
            finishPomodoro()
            return
        }

        timerSeconds -= 1
        if timerSeconds == 0 { finishPomodoro() }
    }

    private func finishPomodoro() {
        guard isTimerRunning else { return }
        isTimerRunning = false

        let preset = activePomodoroID.flatMap { id in
            pomodoroPresets.first(where: { $0.id == id })
        }
        pomodoroCompletion = PomodoroCompletion(
            title: preset?.title ?? "Focus session",
            minutes: preset?.minutes ?? max(focusDurationSeconds / 60, 1)
        )

        guard preferences?.timerCompletionSound ?? true else { return }
        guard let soundURL = Bundle.module.url(forResource: "alarm", withExtension: "mp3"),
            let sound = NSSound(contentsOf: soundURL, byReference: false)
        else {
            NSSound.beep()
            return
        }

        alarmSound?.stop()
        alarmSound = sound
        sound.play()
    }

    private func refreshRunningApplications() {
        let workspace = NSWorkspace.shared
        let currentProcessID = ProcessInfo.processInfo.processIdentifier

        if let frontmost = workspace.frontmostApplication,
            frontmost.processIdentifier != currentProcessID,
            frontmost.activationPolicy == .regular,
            !frontmost.isTerminated
        {
            recentlyUsedAppIDs.removeAll { $0 == frontmost.processIdentifier }
            recentlyUsedAppIDs.insert(frontmost.processIdentifier, at: 0)
        }

        let applications = workspace.runningApplications.filter { application in
            application.processIdentifier != currentProcessID
                && application.activationPolicy == .regular
                && !application.isTerminated
                && application.localizedName?.isEmpty == false
        }
        let activeIDs = Set(applications.map(\.processIdentifier))
        recentlyUsedAppIDs.removeAll { !activeIDs.contains($0) }
        let recentRank = Dictionary(
            uniqueKeysWithValues: recentlyUsedAppIDs.enumerated().map { ($0.element, $0.offset) }
        )

        let sorted = applications.sorted { lhs, rhs in
            let lhsRank = recentRank[lhs.processIdentifier] ?? Int.max
            let rhsRank = recentRank[rhs.processIdentifier] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return (lhs.localizedName ?? "").localizedCaseInsensitiveCompare(
                rhs.localizedName ?? "") == .orderedAscending
        }

        var seenApps = Set<String>()
        let refreshed = sorted.compactMap { application -> RunningApp? in
            guard let name = application.localizedName else { return nil }
            let identity =
                application.bundleIdentifier
                ?? application.bundleURL?.standardizedFileURL.path
                ?? name
            guard seenApps.insert(identity).inserted else { return nil }
            return RunningApp(
                id: application.processIdentifier,
                name: name,
                bundleIdentifier: application.bundleIdentifier,
                bundleURL: application.bundleURL
            )
        }

        if refreshed != runningApps { runningApps = refreshed }
    }

    private func startRecentFilesQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(
            format: "%K >= %@",
            "kMDItemLastUsedDate",
            Date(timeIntervalSince1970: 0) as NSDate
        )
        query.sortDescriptors = [
            NSSortDescriptor(key: "kMDItemLastUsedDate", ascending: false)
        ]

        let center = NotificationCenter.default
        center.publisher(for: .NSMetadataQueryDidFinishGathering, object: query)
            .merge(with: center.publisher(for: .NSMetadataQueryDidUpdate, object: query))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.consumeRecentFilesQuery()
            }
            .store(in: &metadataQueryCancellables)

        metadataQuery = query
        if !query.start() { isLoadingRecentFiles = false }
    }

    private func consumeRecentFilesQuery() {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let homePath = homeURL.path + "/"
        let libraryPath = homeURL.appendingPathComponent("Library", isDirectory: true).path + "/"
        var seenURLs = Set<URL>()
        var refreshed: [RecentFile] = []

        for index in 0..<min(query.resultCount, 500) {
            guard refreshed.count < 30,
                let item = query.result(at: index) as? NSMetadataItem,
                let path = item.value(forAttribute: "kMDItemPath") as? String,
                let lastUsedAt = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
            else {
                continue
            }

            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.path.hasPrefix(homePath),
                !url.path.hasPrefix(libraryPath),
                seenURLs.insert(url).inserted
            else {
                continue
            }

            let relativeComponents = url.path.dropFirst(homePath.count).split(separator: "/")
            guard !relativeComponents.contains(where: { $0.hasPrefix(".") }) else { continue }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                continue
            }

            let name =
                (item.value(forAttribute: "kMDItemDisplayName") as? String)
                ?? url.lastPathComponent
            let kind =
                (item.value(forAttribute: "kMDItemKind") as? String)
                ?? url.pathExtension.uppercased()
            refreshed.append(
                RecentFile(
                    url: url,
                    name: name,
                    kind: kind.isEmpty ? "File" : kind,
                    lastUsedAt: lastUsedAt
                )
            )
        }

        if !refreshed.isEmpty {
            usesRecentFilesFallback = false
            recentFiles = mergingRecordedFileActivity(into: refreshed)
        }
        isLoadingRecentFiles = false
    }

    private func refreshRecentFilesFallbackIfNeeded(force: Bool = false) {
        guard recentFiles.isEmpty || usesRecentFilesFallback || force,
            !isRefreshingRecentFilesFallback
        else {
            return
        }

        isRefreshingRecentFilesFallback = true
        Task { [weak self] in
            let files = await Task.detached(priority: .utility) {
                DashboardModel.scanRecentlyModifiedFiles()
            }.value

            guard let self else { return }
            self.isRefreshingRecentFilesFallback = false
            guard self.recentFiles.isEmpty || self.usesRecentFilesFallback else { return }
            self.usesRecentFilesFallback = true
            self.recentFiles = self.mergingRecordedFileActivity(into: files)
            self.isLoadingRecentFiles = false
        }
    }

    private func recordFileActivity(at url: URL, name: String? = nil, kind: String? = nil) {
        let normalizedURL = url.standardizedFileURL
        let fileExtension = normalizedURL.pathExtension.uppercased()
        let file = RecentFile(
            url: normalizedURL,
            name: name ?? normalizedURL.lastPathComponent,
            kind: kind ?? (fileExtension.isEmpty ? "File" : "\(fileExtension) file"),
            lastUsedAt: .now
        )
        openedFileActivity[normalizedURL] = file
        recentFiles = mergingRecordedFileActivity(into: recentFiles)
    }

    private func mergingRecordedFileActivity(into files: [RecentFile]) -> [RecentFile] {
        var filesByURL = Dictionary(
            uniqueKeysWithValues: files.map { ($0.url.standardizedFileURL, $0) })
        openedFileActivity = openedFileActivity.filter {
            FileManager.default.fileExists(atPath: $0.key.path)
        }

        for (url, openedFile) in openedFileActivity {
            if let existing = filesByURL[url], existing.lastUsedAt > openedFile.lastUsedAt {
                continue
            }
            filesByURL[url] = openedFile
        }

        return Array(filesByURL.values.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(30))
    }

    nonisolated private static func scanRecentlyModifiedFiles() -> [RecentFile] {
        let fileManager = FileManager.default
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let roots = ["Desktop", "Documents", "Downloads"].map {
            homeURL.appendingPathComponent($0, isDirectory: true)
        }
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .creationDateKey,
            .localizedNameKey,
        ]
        var files: [RecentFile] = []

        for root in roots {
            guard
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                )
            else {
                continue
            }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: resourceKeys),
                    values.isRegularFile == true,
                    let activityDate = values.contentModificationDate ?? values.creationDate
                else {
                    continue
                }

                let fileExtension = url.pathExtension.uppercased()
                files.append(
                    RecentFile(
                        url: url.standardizedFileURL,
                        name: values.localizedName ?? url.lastPathComponent,
                        kind: fileExtension.isEmpty ? "File" : "\(fileExtension) file",
                        lastUsedAt: activityDate
                    )
                )

                if files.count > 600 {
                    files.sort { $0.lastUsedAt > $1.lastUsedAt }
                    files.removeSubrange(100..<files.count)
                }
            }
        }

        return Array(files.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(30))
    }

    private func captureCurrentClipboard(force: Bool = false) {
        guard let persistenceStore else { return }
        let pasteboard = NSPasteboard.general
        guard force || pasteboard.changeCount != clipboardChangeCount else { return }
        clipboardChangeCount = pasteboard.changeCount

        guard let item = makeClipboardItem(from: pasteboard) else { return }
        guard clipboardItems.first?.hasSameContent(as: item) != true else { return }

        persistenceStore.saveClipboardItem(item)
        clipboardItems.insert(item, at: 0)
    }

    private func makeClipboardItem(from pasteboard: NSPasteboard) -> ClipboardHistoryItem? {
        if let image = NSImage(pasteboard: pasteboard),
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        {
            let filename = pasteboard.string(forType: .fileURL)
                .flatMap(URL.init(string:))?
                .lastPathComponent
            return ClipboardHistoryItem(kind: .image, text: filename, imageData: png)
        }

        if let value = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return ClipboardHistoryItem(kind: .text, text: value)
        }

        return nil
    }

    func runAI(_ action: AIAction) {
        selectedAIAction = action
        isAIPanelPresented = true
    }
}
