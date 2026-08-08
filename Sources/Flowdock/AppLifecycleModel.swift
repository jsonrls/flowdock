import AppKit
import Combine
import ServiceManagement

enum AppLifecycleAlert: Identifiable {
    case launchAtLoginPermission
    case launchAtLoginError(String)

    var id: String {
        switch self {
        case .launchAtLoginPermission: "launch-at-login-permission"
        case .launchAtLoginError(let message): "launch-at-login-error-\(message)"
        }
    }
}

@MainActor
final class AppLifecycleModel: ObservableObject {
    @Published private(set) var launchAtLoginStatus = SMAppService.mainApp.status
    @Published var activeAlert: AppLifecycleAlert?
    @Published private(set) var lastErrorMessage: String?

    private let permissionPromptKey = "hasAskedForLaunchAtLoginPermission"

    var wantsLaunchAtLogin: Bool {
        launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    var requiresLaunchAtLoginApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    func prepareFirstRunPermissionPrompt() {
        refreshStatus()
        guard !UserDefaults.standard.bool(forKey: permissionPromptKey),
            launchAtLoginStatus == .notRegistered,
            activeAlert == nil
        else {
            return
        }
        activeAlert = .launchAtLoginPermission
    }

    func acceptLaunchAtLoginPermission() {
        UserDefaults.standard.set(true, forKey: permissionPromptKey)
        activeAlert = nil
        setLaunchAtLogin(true)
    }

    func declineLaunchAtLoginPermission() {
        UserDefaults.standard.set(true, forKey: permissionPromptKey)
        activeAlert = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        lastErrorMessage = nil

        guard Bundle.main.bundleURL.pathExtension == "app" else {
            presentError(
                "Launch at Login becomes available when Flowdock is installed as a signed macOS app. "
                    + "It cannot be registered from a swift run development build."
            )
            return
        }

        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            refreshStatus()

            if launchAtLoginStatus == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            refreshStatus()
            presentError(error.localizedDescription)
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refreshStatus() {
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    func dismissAlert() {
        activeAlert = nil
    }

    private func presentError(_ message: String) {
        lastErrorMessage = message
        activeAlert = .launchAtLoginError(message)
    }
}
