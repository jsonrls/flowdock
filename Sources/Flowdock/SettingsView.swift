import AppKit
import SwiftUI

extension Notification.Name {
    static let flowdockGeneralSettingsRequested = Notification.Name(
        "FlowdockGeneralSettingsRequested")
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesModel
    @State private var selectedTab = SettingsTab.general

    var body: some View {
        ZStack {
            SettingsGlassBackdrop()
                .ignoresSafeArea()

            FlowTheme.canvas.opacity(0.78)
                .ignoresSafeArea()

            settingsGlow

            HStack(spacing: 0) {
                SettingsSidebar(selectedTab: $selectedTab)
                    .environmentObject(preferences)

                Rectangle()
                    .fill(FlowTheme.stroke.opacity(0.75))
                    .frame(width: 1)

                selectedPage
                    .id(selectedTab)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 790, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(FlowTheme.stroke.opacity(0.8), lineWidth: 1)
        }
        .background(SettingsWindowConfigurator(theme: preferences.selectedTheme))
        .preferredColorScheme(preferences.selectedTheme.colorScheme)
        .task { preferences.configurePersistence(PersistenceStore.shared) }
        .onAppear {
            selectedTab = .general
            clearInitialFieldFocus()
        }
        .onDisappear { selectedTab = .general }
        .onReceive(NotificationCenter.default.publisher(for: .flowdockGeneralSettingsRequested)) {
            _ in
            withAnimation(.easeOut(duration: 0.18)) {
                selectedTab = .general
            }
            clearInitialFieldFocus()
        }
        .animation(.easeOut(duration: 0.22), value: selectedTab)
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .focus:
            FocusSettingsView()
        case .ai:
            AISettingsView()
        }
    }

    private var settingsGlow: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(FlowTheme.accent.opacity(0.10))
                    .frame(width: 300, height: 300)
                    .blur(radius: 70)
                    .position(x: proxy.size.width * 0.84, y: 10)

                Circle()
                    .fill(Color(hex: "F2C36B").opacity(0.055))
                    .frame(width: 260, height: 260)
                    .blur(radius: 76)
                    .position(x: proxy.size.width * 0.16, y: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private func clearInitialFieldFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.windows
                .first(where: { $0.identifier?.rawValue == "FlowdockSettingsWindow" })?
                .makeFirstResponder(nil)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case focus
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .focus: "Focus"
        case .ai: "Quick AI"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .appearance: "circle.lefthalf.filled"
        case .focus: "timer"
        case .ai: "sparkles"
        }
    }
}

private struct SettingsSidebar: View {
    @EnvironmentObject private var preferences: PreferencesModel
    @Binding var selectedTab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                FlowdockLogoMark(size: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Flowdock")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                    Text("CONTROL CENTER")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FlowTheme.secondary)
                }
            }
            .padding(.top, 25)
            .padding(.horizontal, 20)

            Text("SETTINGS")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(FlowTheme.secondary.opacity(0.78))
                .padding(.top, 32)
                .padding(.bottom, 10)
                .padding(.horizontal, 22)

            VStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarButton(tab)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 10) {
                SettingsAvatar(initials: initials)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preferences.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("Local workspace")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
            }
            .padding(12)
            .background(
                FlowTheme.card.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FlowTheme.stroke.opacity(0.7), lineWidth: 1)
            }
            .padding(14)
        }
        .frame(width: 205)
        .background(.ultraThinMaterial)
        .background(FlowTheme.card.opacity(0.34))
    }

    private func sidebarButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? FlowTheme.accent : FlowTheme.cardRaised.opacity(0.7))
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(hex: "291A11") : FlowTheme.secondary)
                }
                .frame(width: 29, height: 29)

                Text(tab.title)
                    .font(
                        .system(
                            size: 12, weight: isSelected ? .semibold : .medium, design: .rounded)
                    )
                    .foregroundStyle(isSelected ? FlowTheme.text : FlowTheme.secondary)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(FlowTheme.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 43)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                isSelected ? FlowTheme.accent.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? FlowTheme.accent.opacity(0.20) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var initials: String {
        let letters = preferences.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "FD" : String(letters).uppercased()
    }
}

private struct SettingsAvatar: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FlowTheme.accent, Color(hex: "F2C36B")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "291A11"))
        }
        .frame(width: 32, height: 32)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesModel

    var body: some View {
        SettingsPage(
            eyebrow: "Workspace identity",
            title: "General",
            subtitle: "Personalize your desk and choose how Flowdock handles local context.",
            symbol: "slider.horizontal.3"
        ) {
            SettingsGlassCard(
                title: "Profile",
                subtitle: "Used only for your local Flowdock experience.",
                symbol: "person.crop.circle"
            ) {
                SettingsFieldRow(title: "Display name", detail: "Shown in your greeting") {
                    settingsTextField("Your name", text: $preferences.displayName)
                }

                SettingsDivider()

                SettingsFieldRow(title: "Email", detail: "Stored on this Mac") {
                    settingsTextField("you@example.com", text: $preferences.email)
                }
            }

            SettingsGlassCard(
                title: "Clipboard",
                subtitle: "Keep copied content close without interrupting your flow.",
                symbol: "doc.on.clipboard"
            ) {
                SettingsToggleRow(
                    title: "Refresh clipboard on launch",
                    detail: "Show the latest copied content when Flowdock opens.",
                    isOn: $preferences.refreshClipboardOnLaunch
                )
            }
        }
    }

    private func settingsTextField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 12)
            .frame(width: 245, height: 34)
            .background(
                FlowTheme.cardRaised.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(FlowTheme.stroke, lineWidth: 1)
            }
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesModel

    var body: some View {
        SettingsPage(
            eyebrow: "Visual comfort",
            title: "Appearance",
            subtitle: "Choose a theme that stays comfortable throughout your day.",
            symbol: "circle.lefthalf.filled"
        ) {
            SettingsGlassCard(
                title: "Interface theme",
                subtitle: "System automatically follows your current macOS appearance.",
                symbol: "paintbrush"
            ) {
                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases) { theme in
                        themeOption(theme)
                    }
                }
            }
        }
    }

    private func themeOption(_ theme: AppTheme) -> some View {
        let isSelected = preferences.appearanceMode == theme.rawValue
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                preferences.appearanceMode = theme.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(previewBackground(for: theme))

                    VStack(spacing: 5) {
                        HStack(spacing: 4) {
                            Circle().fill(FlowTheme.accent).frame(width: 5, height: 5)
                            Capsule().fill(previewText(for: theme).opacity(0.5)).frame(
                                width: 34, height: 4)
                            Spacer()
                        }
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(previewCard(for: theme))
                            .overlay(alignment: .leading) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Capsule().fill(previewText(for: theme).opacity(0.6)).frame(
                                        width: 48, height: 4)
                                    Capsule().fill(previewText(for: theme).opacity(0.22)).frame(
                                        width: 74, height: 3)
                                }
                                .padding(9)
                            }
                    }
                    .padding(10)

                    if theme == .system {
                        Rectangle()
                            .fill(Color(hex: "121212").opacity(0.94))
                            .frame(width: 62)
                            .offset(x: 42)
                            .mask(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                HStack(spacing: 7) {
                    Image(systemName: theme.symbol)
                    Text(theme.title)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            isSelected ? FlowTheme.accent : FlowTheme.secondary.opacity(0.55))
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(
                FlowTheme.cardRaised.opacity(isSelected ? 0.74 : 0.36),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? FlowTheme.accent : FlowTheme.stroke.opacity(0.75),
                        lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(theme.title) appearance")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func previewBackground(for theme: AppTheme) -> Color {
        theme == .dark ? Color(hex: "121212") : Color(hex: "F5F5F5")
    }

    private func previewCard(for theme: AppTheme) -> Color {
        theme == .dark ? Color(hex: "292929") : .white
    }

    private func previewText(for theme: AppTheme) -> Color {
        theme == .dark ? Color(hex: "F5F5F5") : Color(hex: "191A18")
    }
}

private struct FocusSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesModel
    private let durations = [15, 25, 45, 60]

    var body: some View {
        SettingsPage(
            eyebrow: "Deep work",
            title: "Focus",
            subtitle: "Choose a rhythm that protects momentum without exhausting it.",
            symbol: "timer"
        ) {
            SettingsGlassCard(
                title: "Pomodoro rhythm",
                subtitle: "The new duration applies the next time you begin a session.",
                symbol: "timer"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("FOCUS DURATION")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FlowTheme.secondary)

                    HStack(spacing: 9) {
                        ForEach(durations, id: \.self) { minutes in
                            durationButton(minutes)
                        }
                    }
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: "Completion sound",
                    detail: "Play a sound when your focus session finishes.",
                    isOn: $preferences.timerCompletionSound
                )
            }
        }
    }

    private func durationButton(_ minutes: Int) -> some View {
        let isSelected = preferences.focusMinutes == minutes
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                preferences.focusMinutes = minutes
            }
        } label: {
            VStack(spacing: 3) {
                Text("\(minutes)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("MIN")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .opacity(0.72)
            }
            .foregroundStyle(isSelected ? Color(hex: "291A11") : FlowTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                isSelected ? FlowTheme.accent : FlowTheme.cardRaised.opacity(0.65),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? FlowTheme.accent : FlowTheme.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minute focus duration")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AISettingsView: View {
    @EnvironmentObject private var preferences: PreferencesModel
    private let providers = ["Apple Intelligence", "Ollama", "OpenAI", "Claude", "Gemini"]

    var body: some View {
        SettingsPage(
            eyebrow: "Model routing",
            title: "Quick AI",
            subtitle: "Choose how Flowdock routes explain, rewrite, and code requests.",
            symbol: "sparkles"
        ) {
            SettingsGlassCard(
                title: "Preferred provider",
                subtitle: "Flowdock will use this provider first when it is available.",
                symbol: "point.3.connected.trianglepath.dotted"
            ) {
                SettingsFieldRow(title: "Provider", detail: "Default model route") {
                    Menu {
                        ForEach(providers, id: \.self) { provider in
                            Button {
                                preferences.preferredAIProvider = provider
                            } label: {
                                if preferences.preferredAIProvider == provider {
                                    Label(provider, systemImage: "checkmark")
                                } else {
                                    Text(provider)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(FlowTheme.accent)
                                .frame(width: 6, height: 6)
                            Text(preferences.preferredAIProvider)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(FlowTheme.secondary)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(FlowTheme.text)
                        .padding(.horizontal, 12)
                        .frame(width: 205, height: 34)
                        .background(
                            FlowTheme.cardRaised.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(FlowTheme.stroke, lineWidth: 1)
                        }
                    }
                    .menuStyle(.borderlessButton)
                }

                SettingsDivider()

                SettingsToggleRow(
                    title: "Prefer on-device AI",
                    detail: "Use local processing when a compatible model is available.",
                    isOn: $preferences.preferLocalAI
                )
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(FlowTheme.accent.opacity(0.13))
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlowTheme.accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Provider credentials are not configured yet")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    Text("Local preferences are saved securely on this Mac.")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(FlowTheme.accent.opacity(0.13))
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(FlowTheme.accent.opacity(0.18), lineWidth: 1)
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FlowTheme.accent)
                    }
                    .frame(width: 45, height: 45)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(eyebrow.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(FlowTheme.accent)
                        Text(title)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .tracking(-0.4)
                        Text(subtitle)
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(FlowTheme.secondary)
                    }
                }

                content
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SettingsGlassCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FlowTheme.cardRaised.opacity(0.76))
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlowTheme.accent)
                }
                .frame(width: 31, height: 31)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
            }

            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            FlowTheme.card.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FlowTheme.stroke.opacity(0.82), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 5)
    }
}

private struct SettingsFieldRow<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
            }
            Spacer()
            content
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(FlowTheme.accent)
                .controlSize(.small)
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(FlowTheme.stroke.opacity(0.75))
            .frame(height: 1)
    }
}

private struct SettingsGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    let theme: AppTheme

    func makeNSView(context: Context) -> SettingsConfigurationView {
        let view = SettingsConfigurationView()
        view.theme = theme
        return view
    }

    func updateNSView(_ view: SettingsConfigurationView, context: Context) {
        view.theme = theme
        view.applyAppearance()
    }

    final class SettingsConfigurationView: NSView {
        var theme = AppTheme.system
        private var hasClearedInitialFirstResponder = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
            clearInitialFirstResponderIfNeeded()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateTitlebarColor()
        }

        func applyAppearance() {
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            window.collectionBehavior.remove(.fullScreenAllowsTiling)
            window.collectionBehavior.insert(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenDisallowsTiling)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.isMovableByWindowBackground = true
            window.identifier = NSUserInterfaceItemIdentifier("FlowdockSettingsWindow")

            switch theme {
            case .system:
                window.appearance = nil
            case .light:
                window.appearance = NSAppearance(named: .aqua)
            case .dark:
                window.appearance = NSAppearance(named: .darkAqua)
            }

            updateTitlebarColor()
        }

        private func updateTitlebarColor() {
            guard let window else { return }
            let isDark =
                window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let titlebarColor =
                isDark
                ? NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1)
                : NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
            if let trafficLightContainer = window.standardWindowButton(.closeButton)?.superview {
                trafficLightContainer.wantsLayer = true
                trafficLightContainer.layer?.backgroundColor = titlebarColor.cgColor
            }
        }

        private func clearInitialFirstResponderIfNeeded() {
            guard !hasClearedInitialFirstResponder else { return }
            hasClearedInitialFirstResponder = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
        }
    }
}
