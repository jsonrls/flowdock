import CSQLite
import Foundation

@MainActor
final class PersistenceStore {
    static let shared = PersistenceStore()

    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        do {
            let url = try Self.databaseURL()
            guard
                sqlite3_open_v2(
                    url.path,
                    &database,
                    SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                    nil
                ) == SQLITE_OK
            else {
                throw StoreError.open(message: lastError)
            }
            try execute("PRAGMA journal_mode = WAL;")
            try execute("PRAGMA foreign_keys = ON;")
            try migrate()
        } catch {
            assertionFailure("Unable to open Flowdock database: \(error)")
        }
    }

    func loadTasks() -> [FocusTask] {
        query(
            """
            SELECT id, title, note, is_complete, priority, sort_order, created_at, completed_at
            FROM focus_tasks
            ORDER BY is_complete ASC, priority DESC, sort_order ASC, created_at ASC;
            """
        ) { statement in
            FocusTask(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                title: text(statement, 1),
                note: text(statement, 2),
                isComplete: sqlite3_column_int(statement, 3) == 1,
                priority: TaskPriority(rawValue: Int(sqlite3_column_int(statement, 4))) ?? .medium,
                sortOrder: Int(sqlite3_column_int(statement, 5)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                completedAt: optionalDate(statement, 7)
            )
        }
    }

    func saveTask(_ task: FocusTask) {
        withStatement(
            """
            INSERT INTO focus_tasks
                (id, title, note, is_complete, priority, sort_order, created_at, completed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                note = excluded.note,
                is_complete = excluded.is_complete,
                priority = excluded.priority,
                sort_order = excluded.sort_order,
                completed_at = excluded.completed_at;
            """
        ) { statement in
            bind(task.id.uuidString, to: 1, in: statement)
            bind(task.title, to: 2, in: statement)
            bind(task.note, to: 3, in: statement)
            sqlite3_bind_int(statement, 4, task.isComplete ? 1 : 0)
            sqlite3_bind_int(statement, 5, Int32(task.priority.rawValue))
            sqlite3_bind_int(statement, 6, Int32(task.sortOrder))
            sqlite3_bind_double(statement, 7, task.createdAt.timeIntervalSince1970)
            bind(task.completedAt, to: 8, in: statement)
        }
    }

    func deleteTask(_ taskID: UUID) {
        withStatement("DELETE FROM focus_tasks WHERE id = ?;") { statement in
            bind(taskID.uuidString, to: 1, in: statement)
        }
    }

    func loadPomodoroPresets() -> [PomodoroPreset] {
        query(
            """
            SELECT id, title, minutes, sort_order, created_at
            FROM pomodoro_presets
            ORDER BY sort_order ASC, created_at ASC;
            """
        ) { statement in
            PomodoroPreset(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                title: text(statement, 1),
                minutes: Int(sqlite3_column_int(statement, 2)),
                sortOrder: Int(sqlite3_column_int(statement, 3)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            )
        }
    }

    func savePomodoroPreset(_ preset: PomodoroPreset) {
        withStatement(
            """
            INSERT INTO pomodoro_presets
                (id, title, minutes, sort_order, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                minutes = excluded.minutes,
                sort_order = excluded.sort_order;
            """
        ) { statement in
            bind(preset.id.uuidString, to: 1, in: statement)
            bind(preset.title, to: 2, in: statement)
            sqlite3_bind_int(statement, 3, Int32(preset.minutes))
            sqlite3_bind_int(statement, 4, Int32(preset.sortOrder))
            sqlite3_bind_double(statement, 5, preset.createdAt.timeIntervalSince1970)
        }
    }

    func deletePomodoroPreset(_ presetID: UUID) {
        withStatement("DELETE FROM pomodoro_presets WHERE id = ?;") { statement in
            bind(presetID.uuidString, to: 1, in: statement)
        }
    }

    func loadClipboardHistory() -> [ClipboardHistoryItem] {
        query(
            """
            SELECT id, kind, text_content, image_data, copied_at
            FROM clipboard_items
            ORDER BY copied_at DESC;
            """
        ) { statement in
            ClipboardHistoryItem(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                kind: ClipboardContentKind(rawValue: text(statement, 1)) ?? .text,
                text: optionalText(statement, 2),
                imageData: optionalData(statement, 3),
                copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            )
        }
    }

    func saveClipboardItem(_ item: ClipboardHistoryItem) {
        withStatement(
            """
            INSERT INTO clipboard_items
                (id, kind, text_content, image_data, copied_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING;
            """
        ) { statement in
            bind(item.id.uuidString, to: 1, in: statement)
            bind(item.kind.rawValue, to: 2, in: statement)
            bind(item.text, to: 3, in: statement)
            bind(item.imageData, to: 4, in: statement)
            sqlite3_bind_double(statement, 5, item.copiedAt.timeIntervalSince1970)
        }
    }

    func loadSettings() -> FlowdockSettings? {
        query(
            """
            SELECT key, display_name, email, appearance_mode, refresh_clipboard,
                   focus_minutes, timer_sound, ai_provider, prefer_local_ai, updated_at
            FROM settings WHERE key = 'primary' LIMIT 1;
            """
        ) { statement in
            FlowdockSettings(
                key: text(statement, 0),
                displayName: text(statement, 1),
                email: text(statement, 2),
                appearanceMode: text(statement, 3),
                refreshClipboardOnLaunch: sqlite3_column_int(statement, 4) == 1,
                focusMinutes: Int(sqlite3_column_int(statement, 5)),
                timerCompletionSound: sqlite3_column_int(statement, 6) == 1,
                preferredAIProvider: text(statement, 7),
                preferLocalAI: sqlite3_column_int(statement, 8) == 1,
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
            )
        }.first
    }

    func saveSettings(_ settings: FlowdockSettings) {
        withStatement(
            """
            INSERT INTO settings
                (key, display_name, email, appearance_mode, refresh_clipboard,
                 focus_minutes, timer_sound, ai_provider, prefer_local_ai, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                display_name = excluded.display_name,
                email = excluded.email,
                appearance_mode = excluded.appearance_mode,
                refresh_clipboard = excluded.refresh_clipboard,
                focus_minutes = excluded.focus_minutes,
                timer_sound = excluded.timer_sound,
                ai_provider = excluded.ai_provider,
                prefer_local_ai = excluded.prefer_local_ai,
                updated_at = excluded.updated_at;
            """
        ) { statement in
            bind(settings.key, to: 1, in: statement)
            bind(settings.displayName, to: 2, in: statement)
            bind(settings.email, to: 3, in: statement)
            bind(settings.appearanceMode, to: 4, in: statement)
            sqlite3_bind_int(statement, 5, settings.refreshClipboardOnLaunch ? 1 : 0)
            sqlite3_bind_int(statement, 6, Int32(settings.focusMinutes))
            sqlite3_bind_int(statement, 7, settings.timerCompletionSound ? 1 : 0)
            bind(settings.preferredAIProvider, to: 8, in: statement)
            sqlite3_bind_int(statement, 9, settings.preferLocalAI ? 1 : 0)
            sqlite3_bind_double(statement, 10, settings.updatedAt.timeIntervalSince1970)
        }
    }

    func loadSessions() -> [FlowSession] {
        query(
            """
            SELECT id, title, task_id, workspace_id, started_at, ended_at,
                   planned_minutes, completed, notes
            FROM flow_sessions ORDER BY started_at DESC;
            """
        ) { statement in
            FlowSession(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                title: text(statement, 1),
                taskID: optionalUUID(statement, 2),
                workspaceID: optionalUUID(statement, 3),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                endedAt: optionalDate(statement, 5),
                plannedMinutes: Int(sqlite3_column_int(statement, 6)),
                completed: sqlite3_column_int(statement, 7) == 1,
                notes: text(statement, 8)
            )
        }
    }

    func saveSession(_ session: FlowSession) {
        withStatement(
            """
            INSERT INTO flow_sessions
                (id, title, task_id, workspace_id, started_at, ended_at,
                 planned_minutes, completed, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                task_id = excluded.task_id,
                workspace_id = excluded.workspace_id,
                ended_at = excluded.ended_at,
                planned_minutes = excluded.planned_minutes,
                completed = excluded.completed,
                notes = excluded.notes;
            """
        ) { statement in
            bind(session.id.uuidString, to: 1, in: statement)
            bind(session.title, to: 2, in: statement)
            bind(session.taskID?.uuidString, to: 3, in: statement)
            bind(session.workspaceID?.uuidString, to: 4, in: statement)
            sqlite3_bind_double(statement, 5, session.startedAt.timeIntervalSince1970)
            bind(session.endedAt, to: 6, in: statement)
            sqlite3_bind_int(statement, 7, Int32(session.plannedMinutes))
            sqlite3_bind_int(statement, 8, session.completed ? 1 : 0)
            bind(session.notes, to: 9, in: statement)
        }
    }

    func loadWorkspaces() -> [WorkspaceSnapshot] {
        query(
            """
            SELECT id, name, symbol, accent_hex, is_favorite, created_at, updated_at
            FROM workspaces ORDER BY is_favorite DESC, updated_at DESC;
            """
        ) { statement in
            WorkspaceSnapshot(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                name: text(statement, 1),
                symbol: text(statement, 2),
                accentHex: text(statement, 3),
                isFavorite: sqlite3_column_int(statement, 4) == 1,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            )
        }
    }

    func saveWorkspace(_ workspace: WorkspaceSnapshot) {
        withStatement(
            """
            INSERT INTO workspaces
                (id, name, symbol, accent_hex, is_favorite, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                symbol = excluded.symbol,
                accent_hex = excluded.accent_hex,
                is_favorite = excluded.is_favorite,
                updated_at = excluded.updated_at;
            """
        ) { statement in
            bind(workspace.id.uuidString, to: 1, in: statement)
            bind(workspace.name, to: 2, in: statement)
            bind(workspace.symbol, to: 3, in: statement)
            bind(workspace.accentHex, to: 4, in: statement)
            sqlite3_bind_int(statement, 5, workspace.isFavorite ? 1 : 0)
            sqlite3_bind_double(statement, 6, workspace.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, workspace.updatedAt.timeIntervalSince1970)
        }
    }

    func resources(for workspaceID: UUID) -> [WorkspaceResource] {
        query(
            """
            SELECT id, workspace_id, kind, title, location, bundle_identifier, sort_order
            FROM workspace_resources WHERE workspace_id = ? ORDER BY sort_order ASC;
            """,
            bind: { statement in bind(workspaceID.uuidString, to: 1, in: statement) }
        ) { statement in
            WorkspaceResource(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                workspaceID: UUID(uuidString: text(statement, 1)) ?? workspaceID,
                kind: WorkspaceResourceKind(rawValue: text(statement, 2)) ?? .file,
                title: text(statement, 3),
                location: text(statement, 4),
                bundleIdentifier: optionalText(statement, 5),
                sortOrder: Int(sqlite3_column_int(statement, 6))
            )
        }
    }

    func saveResource(_ resource: WorkspaceResource) {
        withStatement(
            """
            INSERT INTO workspace_resources
                (id, workspace_id, kind, title, location, bundle_identifier, sort_order)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                workspace_id = excluded.workspace_id,
                kind = excluded.kind,
                title = excluded.title,
                location = excluded.location,
                bundle_identifier = excluded.bundle_identifier,
                sort_order = excluded.sort_order;
            """
        ) { statement in
            bind(resource.id.uuidString, to: 1, in: statement)
            bind(resource.workspaceID.uuidString, to: 2, in: statement)
            bind(resource.kind.rawValue, to: 3, in: statement)
            bind(resource.title, to: 4, in: statement)
            bind(resource.location, to: 5, in: statement)
            bind(resource.bundleIdentifier, to: 6, in: statement)
            sqlite3_bind_int(statement, 7, Int32(resource.sortOrder))
        }
    }

    func replaceResources(for workspaceID: UUID, with resources: [WorkspaceResource]) {
        withStatement("DELETE FROM workspace_resources WHERE workspace_id = ?;") { statement in
            bind(workspaceID.uuidString, to: 1, in: statement)
        }
        resources.forEach(saveResource)
    }

    func deleteWorkspace(_ workspaceID: UUID) {
        withStatement("DELETE FROM workspace_resources WHERE workspace_id = ?;") { statement in
            bind(workspaceID.uuidString, to: 1, in: statement)
        }
        withStatement("DELETE FROM workspaces WHERE id = ?;") { statement in
            bind(workspaceID.uuidString, to: 1, in: statement)
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS focus_tasks (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                is_complete INTEGER NOT NULL DEFAULT 0,
                priority INTEGER NOT NULL DEFAULT 1,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                completed_at REAL
            );

            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY NOT NULL,
                display_name TEXT NOT NULL,
                email TEXT NOT NULL,
                appearance_mode TEXT NOT NULL,
                refresh_clipboard INTEGER NOT NULL DEFAULT 1,
                focus_minutes INTEGER NOT NULL DEFAULT 25,
                timer_sound INTEGER NOT NULL DEFAULT 1,
                ai_provider TEXT NOT NULL,
                prefer_local_ai INTEGER NOT NULL DEFAULT 1,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS pomodoro_presets (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                minutes INTEGER NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS flow_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                task_id TEXT,
                workspace_id TEXT,
                started_at REAL NOT NULL,
                ended_at REAL,
                planned_minutes INTEGER NOT NULL DEFAULT 25,
                completed INTEGER NOT NULL DEFAULT 0,
                notes TEXT NOT NULL DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                symbol TEXT NOT NULL,
                accent_hex TEXT NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS workspace_resources (
                id TEXT PRIMARY KEY NOT NULL,
                workspace_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                location TEXT NOT NULL,
                bundle_identifier TEXT,
                sort_order INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                text_content TEXT,
                image_data BLOB,
                copied_at REAL NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_sessions_started_at
                ON flow_sessions(started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_workspace_resources_workspace
                ON workspace_resources(workspace_id, sort_order);
            CREATE INDEX IF NOT EXISTS idx_clipboard_items_copied_at
                ON clipboard_items(copied_at DESC);
            """
        )

        let focusTaskColumns = query("PRAGMA table_info(focus_tasks);") { statement in
            text(statement, 1)
        }
        if !focusTaskColumns.contains("priority") {
            try execute(
                "ALTER TABLE focus_tasks ADD COLUMN priority INTEGER NOT NULL DEFAULT 1;"
            )
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastError
            sqlite3_free(errorMessage)
            throw StoreError.execute(message: message)
        }
    }

    private func withStatement(_ sql: String, bind values: (OpaquePointer) -> Void) {
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }
        values(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            assertionFailure("SQLite write failed: \(lastError)")
            return
        }
    }

    private func query<T>(
        _ sql: String,
        bind values: (OpaquePointer) -> Void = { _ in },
        map: (OpaquePointer) -> T
    ) -> [T] {
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        values(statement)

        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(map(statement))
        }
        return results
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("SQLite prepare failed: \(lastError)")
            return nil
        }
        return statement
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func bind(_ value: Date?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    }

    private func bind(_ value: Data?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), transient)
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(statement, index)
    }

    private func optionalData(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
            let bytes = sqlite3_column_blob(statement, index)
        else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func optionalUUID(_ statement: OpaquePointer, _ index: Int32) -> UUID? {
        optionalText(statement, index).flatMap(UUID.init(uuidString:))
    }

    private func optionalDate(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private var lastError: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
    }

    private static func databaseURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Flowdock", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appendingPathComponent("Flowdock.sqlite3")
        guard !fileManager.fileExists(atPath: databaseURL.path) else { return databaseURL }

        // Preserve data created before the FlowDock → Flowdock branding change on
        // case-sensitive volumes. Default macOS volumes resolve these paths to the
        // same file, so this migration only runs when a distinct legacy file exists.
        let legacyDirectory = applicationSupport.appendingPathComponent("FlowDock", isDirectory: true)
        let legacyDatabaseURLs = [
            legacyDirectory.appendingPathComponent("FlowDock.sqlite3"),
            legacyDirectory.appendingPathComponent("Flowdock.sqlite3")
        ]

        if let legacyURL = legacyDatabaseURLs.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) {
            try fileManager.copyItem(at: legacyURL, to: databaseURL)
            for suffix in ["-wal", "-shm"] {
                let legacySidecar = URL(fileURLWithPath: legacyURL.path + suffix)
                let newSidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                if fileManager.fileExists(atPath: legacySidecar.path) {
                    try? fileManager.copyItem(at: legacySidecar, to: newSidecar)
                }
            }
        }

        return databaseURL
    }
}

private enum StoreError: LocalizedError {
    case open(message: String)
    case execute(message: String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open database: \(message)"
        case .execute(let message): "Could not execute migration: \(message)"
        }
    }
}
