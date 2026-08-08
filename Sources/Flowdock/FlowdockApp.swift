import AppKit
import SwiftUI

@MainActor
final class FlowdockAppDelegate: NSObject, NSApplicationDelegate {
    private let globalShortcutController = GlobalShortcutController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyApplicationIcon()
        globalShortcutController.start()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcutController.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func applyApplicationIcon() {
        guard
            let iconURL = Bundle.module.url(forResource: "Flowdock", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }

        NSApp.applicationIconImage = icon
    }
}

@main
struct FlowdockApp: App {
    @NSApplicationDelegateAdaptor(FlowdockAppDelegate.self) private var appDelegate
    @StateObject private var model = DashboardModel()
    @StateObject private var preferences = PreferencesModel()
    @StateObject private var lifecycle = AppLifecycleModel()

    var body: some Scene {
        WindowGroup("Flowdock", id: "main") {
            DashboardView()
                .environmentObject(model)
                .environmentObject(preferences)
                .environmentObject(lifecycle)
                .frame(minWidth: 1040, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1320, height: 850)
        .commands {
            CommandMenu("Flowdock") {
                Button("Search Everything") {
                    model.searchRequested.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Manage Workspaces") {
                    NotificationCenter.default.post(
                        name: .flowdockWorkspaceManagerRequested, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.control, .option])

                Button(model.isTimerRunning ? "Focus Mode Active" : "Start Focus Timer") {
                    if !model.isTimerRunning { model.toggleTimer() }
                }
                .keyboardShortcut(.space, modifiers: [.command, .shift])
                .disabled(model.isTimerRunning)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(preferences)
        }

        MenuBarExtra {
            FlowdockMenuBarMenu(lifecycle: lifecycle)
        } label: {
            FlowdockMenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct FlowdockMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    private static let templateIcon: NSImage? = {
        guard
            let iconURL = Bundle.module.url(
                forResource: "FlowdockMenuBarTemplate",
                withExtension: "png"
            ),
            let icon = NSImage(contentsOf: iconURL)
        else { return nil }

        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = true
        return icon
    }()

    var body: some View {
        Group {
            if let templateIcon = Self.templateIcon {
                Image(nsImage: templateIcon)
            } else {
                Image(systemName: "f.square.fill")
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("Flowdock")
        .onReceive(NotificationCenter.default.publisher(for: .flowdockOpenRequested)) { _ in
            showFlowdock(openWindow: openWindow)
        }
    }
}

private struct FlowdockMenuBarMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var lifecycle: AppLifecycleModel

    var body: some View {
        Button {
            showFlowdock(openWindow: openWindow)
        } label: {
            Label("Open Flowdock", systemImage: "rectangle.on.rectangle")
        }
        .keyboardShortcut(.space, modifiers: .option)

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { lifecycle.wantsLaunchAtLogin },
                set: { enabled in lifecycle.setLaunchAtLogin(enabled) }
            )
        )

        if lifecycle.requiresLaunchAtLoginApproval {
            Button {
                lifecycle.openLoginItemsSettings()
            } label: {
                Label("Approve in System Settings…", systemImage: "exclamationmark.shield")
            }
        }

        if let error = lifecycle.lastErrorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }

        Divider()

        Button {
            NotificationCenter.default.post(name: .flowdockGeneralSettingsRequested, object: nil)
            openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Quit Flowdock", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

}

@MainActor
private func showFlowdock(openWindow: OpenWindowAction) {
    if let window = NSApp.windows.first(where: {
        $0.identifier?.rawValue == "FlowdockMainWindow"
    }) {
        window.makeKeyAndOrderFront(nil)
    } else {
        openWindow(id: "main")
    }
    NSApp.activate(ignoringOtherApps: true)
}
