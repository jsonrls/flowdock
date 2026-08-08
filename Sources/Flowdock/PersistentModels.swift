import Combine
import Foundation

enum TaskPriority: Int, CaseIterable, Identifiable, Codable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var difficulty: String {
        switch self {
        case .low: "Easy"
        case .medium: "Moderate"
        case .high: "Hard"
        }
    }
}

struct FocusTask: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var note: String
    var isComplete: Bool
    var priority: TaskPriority
    var sortOrder: Int
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        isComplete: Bool = false,
        priority: TaskPriority = .medium,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.isComplete = isComplete
        self.priority = priority
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

struct PomodoroPreset: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var minutes: Int
    var sortOrder: Int
    var createdAt = Date.now
}

struct FlowdockSettings: Codable {
    var key = "primary"
    var displayName = "Jayson Reales"
    var email = "jayson@flowdock.app"
    var appearanceMode = AppTheme.system.rawValue
    var refreshClipboardOnLaunch = true
    var focusMinutes = 25
    var timerCompletionSound = true
    var preferredAIProvider = "Apple Intelligence"
    var preferLocalAI = true
    var updatedAt = Date.now
}

struct FlowSession: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var taskID: UUID?
    var workspaceID: UUID?
    var startedAt = Date.now
    var endedAt: Date?
    var plannedMinutes = 25
    var completed = false
    var notes = ""
}

struct WorkspaceSnapshot: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var symbol = "square.grid.2x2"
    var accentHex = "FF8A4C"
    var isFavorite = false
    var createdAt = Date.now
    var updatedAt = Date.now
}

enum WorkspaceResourceKind: String, Codable, CaseIterable {
    case application
    case file
    case folder
    case webPage
}

struct WorkspaceResource: Identifiable, Hashable, Codable {
    var id = UUID()
    var workspaceID: UUID
    var kind: WorkspaceResourceKind
    var title: String
    var location: String
    var bundleIdentifier: String?
    var sortOrder = 0
}

enum ClipboardContentKind: String, Codable {
    case text
    case image
}

struct ClipboardHistoryItem: Identifiable, Hashable, Codable {
    var id = UUID()
    var kind: ClipboardContentKind
    var text: String?
    var imageData: Data?
    var copiedAt = Date.now

    var displayTitle: String {
        switch kind {
        case .text: text ?? "Copied text"
        case .image: text?.isEmpty == false ? text! : "Copied image"
        }
    }

    var detail: String {
        switch kind {
        case .text:
            let count = text?.count ?? 0
            return "Text · \(count) \(count == 1 ? "character" : "characters")"
        case .image:
            return "PNG image"
        }
    }

    var searchText: String {
        switch kind {
        case .text: text ?? ""
        case .image: displayTitle
        }
    }

    func hasSameContent(as other: ClipboardHistoryItem) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text: return text == other.text
        case .image: return imageData == other.imageData
        }
    }
}

@MainActor
final class PreferencesModel: ObservableObject {
    @Published var displayName = "Jayson Reales" { didSet { persist() } }
    @Published var email = "jayson@flowdock.app" { didSet { persist() } }
    @Published var appearanceMode = AppTheme.system.rawValue { didSet { persist() } }
    @Published var refreshClipboardOnLaunch = true { didSet { persist() } }
    @Published var focusMinutes = 25 { didSet { persist() } }
    @Published var timerCompletionSound = true { didSet { persist() } }
    @Published var preferredAIProvider = "Apple Intelligence" { didSet { persist() } }
    @Published var preferLocalAI = true { didSet { persist() } }

    private var store: PersistenceStore?
    private var isHydrating = false

    var selectedTheme: AppTheme {
        AppTheme(rawValue: appearanceMode) ?? .system
    }

    func configurePersistence(_ store: PersistenceStore) {
        guard self.store == nil else { return }
        self.store = store

        if let stored = store.loadSettings() {
            hydrate(from: stored)
        } else {
            let migrated = makeMigratedSettings()
            store.saveSettings(migrated)
            hydrate(from: migrated)
        }
    }

    private func hydrate(from settings: FlowdockSettings) {
        isHydrating = true
        displayName = settings.displayName
        email = settings.email
        appearanceMode = settings.appearanceMode
        refreshClipboardOnLaunch = settings.refreshClipboardOnLaunch
        focusMinutes = settings.focusMinutes
        timerCompletionSound = settings.timerCompletionSound
        preferredAIProvider = settings.preferredAIProvider
        preferLocalAI = settings.preferLocalAI
        isHydrating = false
    }

    private func persist() {
        guard !isHydrating, let store else { return }
        store.saveSettings(
            FlowdockSettings(
                displayName: displayName,
                email: email,
                appearanceMode: appearanceMode,
                refreshClipboardOnLaunch: refreshClipboardOnLaunch,
                focusMinutes: focusMinutes,
                timerCompletionSound: timerCompletionSound,
                preferredAIProvider: preferredAIProvider,
                preferLocalAI: preferLocalAI,
                updatedAt: .now
            )
        )
    }

    private func makeMigratedSettings() -> FlowdockSettings {
        let defaults = UserDefaults.standard
        return FlowdockSettings(
            displayName: defaults.string(forKey: "userDisplayName") ?? displayName,
            email: defaults.string(forKey: "userEmail") ?? email,
            appearanceMode: defaults.string(forKey: "appearanceMode") ?? appearanceMode,
            refreshClipboardOnLaunch: defaults.object(forKey: "refreshClipboardOnLaunch") as? Bool
                ?? refreshClipboardOnLaunch,
            focusMinutes: defaults.object(forKey: "focusMinutes") as? Int ?? focusMinutes,
            timerCompletionSound: defaults.object(forKey: "timerCompletionSound") as? Bool
                ?? timerCompletionSound,
            preferredAIProvider: defaults.string(forKey: "preferredAIProvider")
                ?? preferredAIProvider,
            preferLocalAI: defaults.object(forKey: "preferLocalAI") as? Bool ?? preferLocalAI,
            updatedAt: .now
        )
    }
}
