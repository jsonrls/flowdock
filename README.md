# Flowdock

A native macOS productivity hub designed to stay open all day. The current prototype combines today’s focus, app shortcuts, clipboard context, quick AI actions, recent files, a Pomodoro timer, search, and lightweight system status in one calm workspace.

## Run

Requires macOS 14 or newer and Swift 6.

```sh
swift run Flowdock
```

Or open `Package.swift` in Xcode and run the `Flowdock` executable scheme.

## Local persistence

Flowdock stores tasks, preferences, Flow Sessions, workspaces, and workspace resources in a local SQLite database at:

```text
~/Library/Application Support/Flowdock/Flowdock.sqlite3
```

The database uses WAL journaling, foreign keys, idempotent schema creation, and upserts. Existing preferences from the earlier AppStorage prototype are migrated on first launch. The current Command Line Tools installation does not ship Apple's `SwiftDataMacros` compiler plugin, so the runnable Swift Package uses SQLite directly; the models are structured for a later SwiftData-backed Xcode target without changing product behavior.

Clipboard history is captured locally while Flowdock is running. Text is stored verbatim, images are normalized to PNG data, and only consecutive duplicate content is ignored. The dashboard displays three entries at a time with scrolling for older items; selecting an entry restores it to the system clipboard.

## Product direction

- SwiftUI + AppKit shell
- SwiftData-compatible local SQLite persistence
- Optional Supabase sync
- Apple Foundation Models, Ollama, and API-provider adapters for AI
- Accessibility, ScreenCaptureKit, EventKit, Shortcuts, and Spotlight integrations

The included Quick AI panel is intentionally a local interaction prototype. Its provider boundary is ready to be replaced by the chosen model integration.
