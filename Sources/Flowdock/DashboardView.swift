import AppKit
import SwiftUI

private struct SearchFieldFramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct SearchResultsScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SearchResultsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BalancedDashboardColumn: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width =
            proposal.width ?? subviews.map {
                $0.sizeThatFits(.unspecified).width
            }.max() ?? 0
        let naturalHeight = subviews.reduce(CGFloat.zero) { partial, subview in
            partial + subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: proposal.height ?? naturalHeight + gaps)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let naturalHeights = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        }
        let gapTotal = spacing * CGFloat(max(subviews.count - 1, 0))
        let availableForCards = max(bounds.height - gapTotal, 0)
        let naturalTotal = naturalHeights.reduce(0, +)
        let sharedExtra = max(availableForCards - naturalTotal, 0) / CGFloat(subviews.count)

        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let height = naturalHeights[index] + sharedExtra
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }
}

private struct EnclosingScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> IndicatorHidingView {
        let view = IndicatorHidingView()
        view.hideScrollerOnNextRunLoop()
        return view
    }

    func updateNSView(_ view: IndicatorHidingView, context: Context) {
        view.hideScrollerOnNextRunLoop()
    }

    final class IndicatorHidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideScrollerOnNextRunLoop()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            hideScrollerOnNextRunLoop()
        }

        func hideScrollerOnNextRunLoop() {
            DispatchQueue.main.async { [weak self] in
                var candidate: NSView? = self
                while let view = candidate {
                    if let scrollView = view as? NSScrollView {
                        scrollView.hasVerticalScroller = false
                        scrollView.verticalScroller?.isHidden = true
                        scrollView.hasHorizontalScroller = false
                        scrollView.horizontalScroller?.isHidden = true
                        scrollView.autohidesScrollers = true
                        return
                    }
                    candidate = view.superview
                }
            }
        }
    }
}

private struct EscapeKeyMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.action = action
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var anchorView: NSView?
        var isEnabled: Bool
        var action: () -> Void
        private var monitor: Any?

        init(isEnabled: Bool, action: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.action = action
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard
                    let self,
                    isEnabled,
                    event.keyCode == 53,
                    let window = anchorView?.window,
                    NSApp.keyWindow === window
                else { return event }

                action()
                return nil
            }
        }

        func uninstall() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

extension Notification.Name {
    static let flowdockWorkspaceManagerRequested = Notification.Name(
        "FlowdockWorkspaceManagerRequested")
    static let flowdockWorkspaceAppEditorRequested = Notification.Name(
        "FlowdockWorkspaceAppEditorRequested")
}

private struct LiquidGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}

private struct WindowGlassConfigurator: NSViewRepresentable {
    let theme: AppTheme

    func makeNSView(context: Context) -> GlassConfigurationView {
        let view = GlassConfigurationView()
        view.theme = theme
        return view
    }

    func updateNSView(_ view: GlassConfigurationView, context: Context) {
        view.theme = theme
        view.applyAppearance()
    }

    final class GlassConfigurationView: NSView {
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
            window.identifier = NSUserInterfaceItemIdentifier("FlowdockMainWindow")
            window.title = "Flowdock"

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
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var preferences: PreferencesModel
    @EnvironmentObject private var lifecycle: AppLifecycleModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var now = Date()
    @State private var isAccountMenuPresented = false
    @State private var isWorkspaceManagerPresented = false
    @State private var isWorkspaceAppPickerPresented = false
    @State private var workspaceDraftName = ""
    @State private var workspaceDraftID: UUID?
    @State private var searchFieldFrame = CGRect.zero
    @StateObject private var focusShield = FocusShieldController()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LiquidGlassBackdrop()
                .ignoresSafeArea()

            FlowTheme.canvas
                .opacity(colorScheme == .dark ? 0.67 : 0.72)
                .ignoresSafeArea()

            GeometryReader { proxy in
                Circle()
                    .fill(FlowTheme.accent.opacity(colorScheme == .dark ? 0.11 : 0.13))
                    .frame(width: proxy.size.width * 0.42)
                    .blur(radius: 74)
                    .offset(x: -proxy.size.width * 0.12, y: -proxy.size.height * 0.2)

                Circle()
                    .fill(FlowTheme.lime.opacity(colorScheme == .dark ? 0.055 : 0.075))
                    .frame(width: proxy.size.width * 0.36)
                    .blur(radius: 82)
                    .offset(x: proxy.size.width * 0.72, y: proxy.size.height * 0.61)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            LinearGradient(
                colors: [FlowTheme.accent.opacity(0.07), .clear, FlowTheme.lime.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(FlowTheme.stroke)
                workspace
            }

            if isAccountMenuPresented {
                Color.black.opacity(0.045)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isAccountMenuPresented = false }
                    .transition(.opacity)
                    .zIndex(40)

                AccountPopover(dismiss: { isAccountMenuPresented = false })
                    .padding(.top, 62)
                    .padding(.trailing, 24)
                    .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(50)
            }

            if isWorkspaceManagerPresented || isWorkspaceAppPickerPresented {
                Color.black
                    .opacity(colorScheme == .dark ? 0.42 : 0.2)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissWorkspaceModal() }
                    .transition(.opacity)
                    .zIndex(79)
            }

            if isWorkspaceManagerPresented {
                WorkspaceManagerPopover(
                    chooseApps: presentWorkspaceAppPicker,
                    editApps: presentWorkspaceAppEditor,
                    dismiss: dismissWorkspaceManager
                )
                .environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(28)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(80)
            }

            if isWorkspaceAppPickerPresented {
                WorkspaceAppPickerModal(
                    workspaceID: workspaceDraftID,
                    workspaceName: workspaceDraftName,
                    dismiss: dismissWorkspaceAppPicker
                )
                .environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(28)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(80)
            }

            if let confirmation = model.clipboardCopyConfirmation {
                ClipboardCopyDialog(confirmation: confirmation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                    .transition(clipboardConfirmationTransition)
                    .task(id: confirmation.id) {
                        try? await Task.sleep(for: .seconds(2.2))
                        model.dismissClipboardCopyConfirmation(confirmation.id)
                    }
                    .zIndex(70)
            }

            if let workspace = model.pendingWorkspaceRestore {
                Color.black
                    .opacity(colorScheme == .dark ? 0.34 : 0.16)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.cancelWorkspaceRestore()
                    }
                    .transition(restoreScrimTransition)
                    .zIndex(99)

                WorkspaceRestoreDialog(
                    workspace: workspace,
                    resources: model.workspaceResources[workspace.id] ?? [],
                    restore: model.confirmWorkspaceRestore,
                    cancel: model.cancelWorkspaceRestore
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(restoreDialogTransition)
                .zIndex(100)
            }

            if let workspace = model.pendingWorkspaceDeletion {
                Color.black
                    .opacity(colorScheme == .dark ? 0.42 : 0.2)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.cancelWorkspaceDeletion() }
                    .transition(restoreScrimTransition)
                    .zIndex(109)

                WorkspaceDeleteDialog(
                    workspace: workspace,
                    resources: model.workspaceResources[workspace.id] ?? [],
                    delete: model.confirmWorkspaceDeletion,
                    cancel: model.cancelWorkspaceDeletion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(restoreDialogTransition)
                .zIndex(110)
            }

            if let task = model.pendingTaskDeletion {
                destructiveConfirmationScrim(cancel: model.cancelTaskDeletion)
                    .zIndex(119)

                ItemDeleteDialog(
                    eyebrow: "DELETE FOCUS ITEM",
                    title: task.title,
                    detail: task.note.isEmpty
                        ? "\(task.priority.title) priority · No note"
                        : "\(task.priority.title) priority · \(task.note)",
                    message: "Remove this item from today’s focus list?",
                    confirmTitle: "Delete Item",
                    delete: model.confirmTaskDeletion,
                    cancel: model.cancelTaskDeletion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(restoreDialogTransition)
                .zIndex(120)
            }

            if let preset = model.pendingPomodoroDeletion {
                destructiveConfirmationScrim(cancel: model.cancelPomodoroDeletion)
                    .zIndex(129)

                ItemDeleteDialog(
                    eyebrow: "DELETE POMODORO",
                    title: preset.title,
                    detail: "\(preset.minutes) minute focus session",
                    message: model.activePomodoroID == preset.id
                        ? "This also stops the active focus session."
                        : "Remove this timer preset from Flowdock?",
                    confirmTitle: "Delete Timer",
                    delete: model.confirmPomodoroDeletion,
                    cancel: model.cancelPomodoroDeletion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(restoreDialogTransition)
                .zIndex(130)
            }

            if let completion = model.pomodoroCompletion {
                Color.black
                    .opacity(colorScheme == .dark ? 0.38 : 0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.dismissPomodoroCompletion() }
                    .transition(restoreScrimTransition)
                    .zIndex(139)

                PomodoroCompletionDialog(
                    completion: completion,
                    dismiss: model.dismissPomodoroCompletion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(restoreDialogTransition)
                .zIndex(140)
            }
        }
        .background(WindowGlassConfigurator(theme: preferences.selectedTheme))
        .background(
            EscapeKeyMonitor(
                isEnabled: model.pendingWorkspaceRestoreID != nil
                    || model.pendingWorkspaceDeletionID != nil
                    || model.pendingTaskDeletionID != nil
                    || model.pendingPomodoroDeletionID != nil
                    || model.pomodoroCompletion != nil
                    || isWorkspaceManagerPresented
                    || isWorkspaceAppPickerPresented
                    || !model.searchText.isEmpty
            ) {
                if model.pomodoroCompletion != nil {
                    model.dismissPomodoroCompletion()
                } else if model.pendingWorkspaceRestoreID != nil {
                    model.cancelWorkspaceRestore()
                } else if model.pendingWorkspaceDeletionID != nil {
                    model.cancelWorkspaceDeletion()
                } else if model.pendingTaskDeletionID != nil {
                    model.cancelTaskDeletion()
                } else if model.pendingPomodoroDeletionID != nil {
                    model.cancelPomodoroDeletion()
                } else if isWorkspaceManagerPresented {
                    dismissWorkspaceManager()
                } else if isWorkspaceAppPickerPresented {
                    dismissWorkspaceAppPicker()
                } else {
                    model.searchText = ""
                    searchFocused = false
                }
            }
        )
        .coordinateSpace(name: "flowdockDashboard")
        .onPreferenceChange(SearchFieldFramePreferenceKey.self) { searchFieldFrame = $0 }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { event in
                guard searchFocused, !searchFieldFrame.contains(event.location) else { return }
                searchFocused = false
            }
        )
        .clipped()
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: isAccountMenuPresented)
        .animation(
            .spring(response: 0.3, dampingFraction: 0.86), value: isWorkspaceManagerPresented
        )
        .animation(
            .spring(response: 0.3, dampingFraction: 0.86), value: isWorkspaceAppPickerPresented
        )
        .animation(
            .spring(response: 0.28, dampingFraction: 0.88),
            value: model.pendingWorkspaceDeletionID
        )
        .animation(
            .spring(response: 0.28, dampingFraction: 0.88),
            value: model.pendingTaskDeletionID
        )
        .animation(
            .spring(response: 0.28, dampingFraction: 0.88),
            value: model.pendingPomodoroDeletionID
        )
        .animation(
            .spring(response: 0.28, dampingFraction: 0.88),
            value: model.pomodoroCompletion
        )
        .preferredColorScheme(preferences.selectedTheme.colorScheme)
        .foregroundStyle(FlowTheme.text)
        .onReceive(clock) { now = $0 }
        .onChange(of: model.searchRequested) { _, _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .flowdockWorkspaceManagerRequested)) {
            _ in
            isAccountMenuPresented = false
            searchFocused = false
            workspaceDraftID = nil
            workspaceDraftName = ""
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                isWorkspaceAppPickerPresented = false
                isWorkspaceManagerPresented = true
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .flowdockWorkspaceAppEditorRequested)
        ) { notification in
            guard let workspaceID = notification.object as? UUID else { return }
            isAccountMenuPresented = false
            searchFocused = false
            presentWorkspaceAppEditor(workspaceID: workspaceID)
        }
        .onExitCommand {
            if model.pomodoroCompletion != nil {
                model.dismissPomodoroCompletion()
                return
            }
            if model.pendingWorkspaceRestoreID != nil {
                model.cancelWorkspaceRestore()
                return
            }
            if model.pendingWorkspaceDeletionID != nil {
                model.cancelWorkspaceDeletion()
                return
            }
            if model.pendingTaskDeletionID != nil {
                model.cancelTaskDeletion()
                return
            }
            if model.pendingPomodoroDeletionID != nil {
                model.cancelPomodoroDeletion()
                return
            }
            if isWorkspaceManagerPresented {
                dismissWorkspaceManager()
                return
            }
            if isWorkspaceAppPickerPresented {
                dismissWorkspaceAppPicker()
                return
            }
            guard !model.searchText.isEmpty || searchFocused else { return }
            model.searchText = ""
            searchFocused = false
        }
        .onChange(of: model.isTimerRunning) { _, isRunning in
            if isRunning {
                focusShield.present(model: model)
            } else {
                focusShield.dismiss()
            }
        }
        .task {
            let store = PersistenceStore.shared
            preferences.configurePersistence(store)
            model.configurePersistence(store, preferences: preferences)
            lifecycle.prepareFirstRunPermissionPrompt()
        }
        .alert(item: $lifecycle.activeAlert) { alert in
            switch alert {
            case .launchAtLoginPermission:
                Alert(
                    title: Text("Open Flowdock at Login?"),
                    message: Text(
                        "Flowdock can start automatically so its menu-bar tools are ready without opening it yourself. "
                            + "You can change this later from the menu-bar icon."
                    ),
                    primaryButton: .default(Text("Allow")) {
                        lifecycle.acceptLaunchAtLoginPermission()
                    },
                    secondaryButton: .cancel(Text("Not Now")) {
                        lifecycle.declineLaunchAtLoginPermission()
                    }
                )
            case .launchAtLoginError(let message):
                Alert(
                    title: Text("Launch at Login"),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        lifecycle.dismissAlert()
                    }
                )
            }
        }
        .sheet(isPresented: $model.isAIPanelPresented) {
            QuickAISheet(action: model.selectedAIAction ?? .explain)
                .environmentObject(model)
        }
    }

    private func destructiveConfirmationScrim(cancel: @escaping () -> Void) -> some View {
        Color.black
            .opacity(colorScheme == .dark ? 0.42 : 0.2)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: cancel)
            .transition(restoreScrimTransition)
    }

    private func dismissWorkspaceManager() {
        withAnimation(.easeOut(duration: 0.2)) {
            isWorkspaceManagerPresented = false
        }
    }

    private func presentWorkspaceAppPicker(named workspaceName: String) {
        workspaceDraftID = nil
        workspaceDraftName = workspaceName
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isWorkspaceManagerPresented = false
            isWorkspaceAppPickerPresented = true
        }
    }

    private func presentWorkspaceAppEditor(_ workspace: WorkspaceSnapshot) {
        presentWorkspaceAppEditor(workspaceID: workspace.id)
    }

    private func presentWorkspaceAppEditor(workspaceID: UUID) {
        guard let workspace = model.workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        workspaceDraftID = workspace.id
        workspaceDraftName = workspace.name
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isWorkspaceManagerPresented = false
            isWorkspaceAppPickerPresented = true
        }
    }

    private func dismissWorkspaceAppPicker() {
        withAnimation(.easeOut(duration: 0.2)) {
            isWorkspaceAppPickerPresented = false
        }
        workspaceDraftID = nil
        workspaceDraftName = ""
    }

    private func dismissWorkspaceModal() {
        if isWorkspaceAppPickerPresented {
            dismissWorkspaceAppPicker()
        } else {
            dismissWorkspaceManager()
        }
    }

    private var restoreScrimTransition: AnyTransition {
        .opacity.animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18))
    }

    private var clipboardConfirmationTransition: AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.1))
        }

        return .asymmetric(
            insertion: .scale(scale: 0.96)
                .combined(with: .opacity)
                .animation(.spring(response: 0.24, dampingFraction: 0.88)),
            removal: .scale(scale: 0.99)
                .combined(with: .opacity)
                .animation(.easeIn(duration: 0.14))
        )
    }

    private var restoreDialogTransition: AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.1))
        }

        return .asymmetric(
            insertion: .scale(scale: 0.965)
                .combined(with: .opacity)
                .animation(.spring(response: 0.24, dampingFraction: 0.9)),
            removal: .scale(scale: 0.985)
                .combined(with: .opacity)
                .animation(.easeIn(duration: 0.14))
        )
    }

    private var topBar: some View {
        HStack(spacing: 24) {
            HStack(spacing: 10) {
                FlowdockLogoMark(size: 34)

                Text("Flow")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    + Text("dock")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(FlowTheme.secondary)
            }
            .frame(width: 150, alignment: .leading)

            searchField
                .frame(maxWidth: 650)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(now.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(FlowTheme.secondary)
            }

            AccountMenu(isPresented: $isAccountMenuPresented)
        }
        .padding(.horizontal, 26)
        .frame(height: 70)
        .background(.ultraThinMaterial)
        .background(FlowTheme.sidebar.opacity(0.24))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.28), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(searchFocused ? FlowTheme.accent : FlowTheme.secondary)
            TextField("Search tasks, apps, files, clipboard…", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .focused($searchFocused)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(FlowTheme.secondary)
            } else {
                Text("⌘ K")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FlowTheme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(FlowTheme.cardRaised, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(FlowTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    searchFocused ? FlowTheme.accent.opacity(0.5) : FlowTheme.stroke, lineWidth: 1)
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchFieldFramePreferenceKey.self,
                    value: proxy.frame(in: .named("flowdockDashboard"))
                )
            }
        }
        .animation(.easeOut(duration: 0.18), value: searchFocused)
    }

    private var workspace: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 20) {
                greeting

                HStack(alignment: .top, spacing: 18) {
                    BalancedDashboardColumn(spacing: 18) {
                        FocusCard(fillsAvailableHeight: true)
                        PomodoroCard(fillsAvailableHeight: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    BalancedDashboardColumn(spacing: 18) {
                        AppsCard(fillsAvailableHeight: true)
                        WorkspaceSnapshotCard(fillsAvailableHeight: true)
                        ClipboardCard(fillsAvailableHeight: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    BalancedDashboardColumn(spacing: 18) {
                        RecentFilesCard(fillsAvailableHeight: true)
                        SystemCard(fillsAvailableHeight: true)
                        QuickAICard(fillsAvailableHeight: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if !model.searchText.isEmpty {
                SearchResultsView(query: model.searchText)
                    .environmentObject(model)
                    .frame(maxWidth: 1060)
                    .padding(.horizontal, 12)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var greeting: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR DESK · TODAY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(FlowTheme.accent)
                Text("Good \(greetingPeriod), \(firstName).")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .tracking(-0.7)
                Text("Everything you need, without breaking your flow.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(FlowTheme.lime).frame(width: 7, height: 7)
                Text("Flowdock is ready")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(FlowTheme.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private var firstName: String {
        preferences.displayName.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var greetingPeriod: String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<22: "evening"
        default: "night"
        }
    }
}

private struct AccountMenu: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            AccountAvatar(size: 36)
                .overlay(
                    Circle()
                        .stroke(
                            isPresented ? FlowTheme.accent : FlowTheme.stroke,
                            lineWidth: isPresented ? 2 : 1
                        )
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
        .help("Account and settings")
        .accessibilityLabel("Open account menu")
    }
}

private struct AccountAvatar: View {
    @EnvironmentObject private var preferences: PreferencesModel
    let size: CGFloat

    private var initials: String {
        let letters = preferences.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "FD" : String(letters).uppercased()
    }

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
                .font(.system(size: size * 0.31, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "291A11"))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

private struct AccountPopover: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var preferences: PreferencesModel
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AccountAvatar(size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preferences.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(FlowTheme.text)
                    Text(preferences.email)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(FlowTheme.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("FREE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(FlowTheme.lime)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(FlowTheme.lime.opacity(0.12), in: Capsule())
            }
            .padding(14)

            Divider().overlay(FlowTheme.stroke)

            VStack(spacing: 4) {
                menuButton("Settings…", symbol: "gearshape", shortcut: "⌘,") {
                    dismiss()
                    NotificationCenter.default.post(
                        name: .flowdockGeneralSettingsRequested, object: nil)
                    DispatchQueue.main.async { openSettings() }
                }
                menuButton(
                    "Send feedback", symbol: "bubble.left.and.bubble.right", action: sendFeedback)
            }
            .padding(8)

            Divider().overlay(FlowTheme.stroke)

            menuButton("Quit Flowdock", symbol: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .padding(8)
        }
        .frame(width: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            LinearGradient(
                colors: [FlowTheme.accent.opacity(0.1), .clear, FlowTheme.lime.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), FlowTheme.stroke.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.38))
                .frame(width: 94, height: 1)
                .padding(.top, 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 24, y: 12)
        .foregroundStyle(FlowTheme.text)
    }

    private func menuButton(
        _ title: String,
        symbol: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(FlowTheme.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FlowTheme.cardRaised.opacity(0.001), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sendFeedback() {
        guard let url = URL(string: "mailto:feedback@flowdock.app?subject=Flowdock%20Feedback")
        else { return }
        NSWorkspace.shared.open(url)
        dismiss()
    }
}

private struct ClipboardCopyDialog: View {
    let confirmation: ClipboardCopyConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(FlowTheme.lime.opacity(0.14))
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(FlowTheme.lime)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("COPIED TO CLIPBOARD")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FlowTheme.lime)

                    Text(confirmation.isImage ? "Image ready to paste" : "Text ready to paste")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }

                Spacer(minLength: 10)

                Text("SAVED")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(FlowTheme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(FlowTheme.cardRaised.opacity(0.68), in: Capsule())
            }

            HStack(spacing: 12) {
                Image(systemName: confirmation.isImage ? "photo.fill" : "text.alignleft")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FlowTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        FlowTheme.accent.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(confirmation.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Text(confirmation.isImage ? "IMAGE" : "TEXT")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(FlowTheme.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                FlowTheme.cardRaised.opacity(0.48),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FlowTheme.stroke.opacity(0.82), lineWidth: 1)
            }

            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .semibold))

                Text("Saved in clipboard history")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))

                Spacer()

                Text("⌘V")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        FlowTheme.cardRaised.opacity(0.76), in: RoundedRectangle(cornerRadius: 6))

                Text("to paste")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(FlowTheme.secondary)
        }
        .padding(22)
        .frame(width: 390)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(FlowTheme.card.opacity(0.66))

                LinearGradient(
                    colors: [Color.white.opacity(0.16), .clear, FlowTheme.lime.opacity(0.045)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.46), FlowTheme.stroke.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.27), radius: 24, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Copied to clipboard. \(confirmation.isImage ? "Image" : confirmation.title). Ready to paste."
        )
    }
}

private struct WorkspaceRestoreDialog: View {
    let workspace: WorkspaceSnapshot
    let resources: [WorkspaceResource]
    let restore: () -> Void
    let cancel: () -> Void

    private var applications: [WorkspaceResource] {
        resources.filter { $0.kind == .application }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FlowTheme.accent.opacity(0.14))

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)

                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FlowTheme.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("RESTORE WORKSPACE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(FlowTheme.accent)

                    Text(workspace.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Text("\(applications.count) \(applications.count == 1 ? "APP" : "APPS")")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(FlowTheme.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(FlowTheme.cardRaised.opacity(0.7), in: Capsule())
            }

            HStack(spacing: 14) {
                WorkspaceAppIcons(resources: applications, iconSize: 28, maxVisible: 5)

                Rectangle()
                    .fill(FlowTheme.stroke)
                    .frame(width: 1, height: 30)

                Text(
                    "Flowdock will reopen the saved apps in this workspace. Your currently open apps will stay open."
                )
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(FlowTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                FlowTheme.cardRaised.opacity(0.46),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FlowTheme.stroke.opacity(0.8), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Button(action: cancel) {
                    Text("Cancel")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            FlowTheme.cardRaised.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FlowTheme.stroke, lineWidth: 1)
                        }
                }
                .buttonStyle(RestoreDialogButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(action: restore) {
                    Label("Restore Workspace", systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "291A11"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "FFA064"), FlowTheme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(RestoreDialogButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(FlowTheme.card.opacity(0.66))

                LinearGradient(
                    colors: [Color.white.opacity(0.16), .clear, FlowTheme.accent.opacity(0.045)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.48), FlowTheme.stroke.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Restore workspace \(workspace.name)")
    }
}

private struct PomodoroCompletionDialog: View {
    let completion: PomodoroCompletion
    let dismiss: () -> Void

    private var durationText: String {
        let unit = completion.minutes == 1 ? "minute" : "minutes"
        return "\(completion.minutes) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(FlowTheme.accent.opacity(0.14))
                    Circle()
                        .stroke(FlowTheme.accent.opacity(0.38), lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(FlowTheme.accent)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("FOCUS COMPLETE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(FlowTheme.accent)
                    Text(completion.title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .textSelection(.disabled)
                }

                Spacer(minLength: 0)

                Text(durationText.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(FlowTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(FlowTheme.accent.opacity(0.1), in: Capsule())
                    .overlay {
                        Capsule().stroke(FlowTheme.accent.opacity(0.24), lineWidth: 1)
                    }
            }

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(FlowTheme.accent.opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Nice work. That’s \(durationText) of focused progress.")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Take a breath, reset, and return when you’re ready for the next session.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(
                FlowTheme.accent.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FlowTheme.accent.opacity(0.18), lineWidth: 1)
            }

            Button(action: dismiss) {
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "21160F"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        LinearGradient(
                            colors: [FlowTheme.accent, Color(hex: "FFAA68")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
            .buttonStyle(RestoreDialogButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .frame(width: 398)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FlowTheme.card.opacity(0.76))
                LinearGradient(
                    colors: [FlowTheme.accent.opacity(0.09), .clear, FlowTheme.accent.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [FlowTheme.accent.opacity(0.52), FlowTheme.accent.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .shadow(color: FlowTheme.accent.opacity(0.08), radius: 18, y: 8)
        .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Focus session complete. \(completion.title), \(completion.minutes) minutes."
        )
    }
}

private struct ItemDeleteDialog: View {
    let eyebrow: String
    let title: String
    let detail: String
    let message: String
    let confirmTitle: String
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.14))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.red)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Color.red)
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.disabled)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(message)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                Color.red.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.red.opacity(0.16), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Button(action: cancel) {
                    Text("Cancel")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            FlowTheme.cardRaised.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FlowTheme.stroke, lineWidth: 1)
                        }
                }
                .buttonStyle(RestoreDialogButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(action: delete) {
                    Label(confirmTitle, systemImage: "trash")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "F15A54"), Color(hex: "C93632")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(RestoreDialogButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 410)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(FlowTheme.card.opacity(0.68))
                LinearGradient(
                    colors: [Color.white.opacity(0.14), .clear, Color.red.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.44), Color.red.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.3), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(eyebrow). \(title)")
    }
}

private struct WorkspaceDeleteDialog: View {
    let workspace: WorkspaceSnapshot
    let resources: [WorkspaceResource]
    let delete: () -> Void
    let cancel: () -> Void

    private var applications: [WorkspaceResource] {
        resources.filter { $0.kind == .application }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.14))

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)

                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.red)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("DELETE WORKSPACE")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Color.red)

                    Text(workspace.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Text("\(applications.count) \(applications.count == 1 ? "APP" : "APPS")")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(FlowTheme.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(FlowTheme.cardRaised.opacity(0.7), in: Capsule())
            }

            HStack(spacing: 14) {
                WorkspaceAppIcons(resources: applications, iconSize: 28, maxVisible: 5)

                Rectangle()
                    .fill(FlowTheme.stroke)
                    .frame(width: 1, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Remove this saved workspace?")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("Your applications will remain installed and open.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                Color.red.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.red.opacity(0.16), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Button(action: cancel) {
                    Text("Cancel")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            FlowTheme.cardRaised.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(FlowTheme.stroke, lineWidth: 1)
                        }
                }
                .buttonStyle(RestoreDialogButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(action: delete) {
                    Label("Delete Workspace", systemImage: "trash")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "F15A54"), Color(hex: "C93632")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(RestoreDialogButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(FlowTheme.card.opacity(0.68))

                LinearGradient(
                    colors: [Color.white.opacity(0.14), .clear, Color.red.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.44), Color.red.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.3), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Delete workspace \(workspace.name)")
    }
}

private struct RestoreDialogButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private enum ItemRowPopover: String, Identifiable {
    case actions
    case editor

    var id: String { rawValue }
}

private struct ItemActionsPopover: View {
    let editTitle: String
    let editSubtitle: String
    let deleteTitle: String
    let deleteSubtitle: String
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            WorkspaceActionRow(
                title: editTitle,
                subtitle: editSubtitle,
                systemImage: "pencil",
                action: edit
            )

            Rectangle()
                .fill(FlowTheme.stroke.opacity(0.8))
                .frame(height: 1)
                .padding(.horizontal, 8)

            WorkspaceActionRow(
                title: deleteTitle,
                subtitle: deleteSubtitle,
                systemImage: "trash",
                isDestructive: true,
                action: delete
            )
        }
        .padding(7)
        .frame(width: 218)
        .background {
            ZStack {
                LiquidGlassBackdrop()
                FlowTheme.card.opacity(0.72)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .foregroundStyle(FlowTheme.text)
    }
}

private struct FocusCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var isAddingTask = false
    @State private var scrollOffset: CGFloat = 0
    var fillsAvailableHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionEyebrow(
                    title: "Today's focus", trailing: "\(completedCount)/\(model.tasks.count)")
                compactAddButton(isPresented: $isAddingTask)
                    .popover(isPresented: $isAddingTask, arrowEdge: .bottom) {
                        TaskComposer { title, note, priority in
                            addTask(title: title, note: note, priority: priority)
                        }
                    }
            }

            ScrollerlessViewport(
                contentHeight: focusContentHeight,
                scrollOffset: $scrollOffset,
                content: FocusTaskRows(
                    tasks: model.tasks,
                    toggle: model.toggleTask,
                    edit: updateTask,
                    delete: deleteTask
                )
            )
            .frame(height: 190)
            .overlay(alignment: .trailing) {
                if model.tasks.count > 3 {
                    SlimScrollCue(
                        viewportHeight: 190,
                        contentHeight: focusContentHeight,
                        scrollOffset: scrollOffset
                    )
                    .padding(.trailing, 1)
                }
            }

            HStack(spacing: 10) {
                Capsule()
                    .fill(FlowTheme.stroke)
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(FlowTheme.accent)
                                .frame(width: proxy.size.width * completion)
                        }
                    }
                Text("\(Int(completion * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FlowTheme.secondary)
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface()
        .onChange(of: model.tasks.count) { _, _ in
            withAnimation(.easeInOut(duration: 0.22)) {
                scrollOffset = min(scrollOffset, max(focusContentHeight - 190, 0))
            }
        }
    }

    private var completedCount: Int { model.tasks.filter(\.isComplete).count }
    private var completion: Double { Double(completedCount) / Double(max(model.tasks.count, 1)) }
    private var focusContentHeight: CGFloat {
        CGFloat(model.tasks.count * 60 + max(model.tasks.count - 1, 0) * 5)
    }

    private func addTask(title: String, note: String, priority: TaskPriority) {
        var addedID: UUID?
        withAnimation(.easeOut(duration: 0.28)) {
            addedID = model.addTask(title: title, note: note, priority: priority)
            isAddingTask = false
        }
        guard let addedID else { return }

        DispatchQueue.main.async {
            let index = model.tasks.firstIndex(where: { $0.id == addedID }) ?? 0
            let maximumOffset = max(focusContentHeight - 190, 0)
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollOffset = min(CGFloat(index) * 65, maximumOffset)
            }
        }
    }

    private func updateTask(
        _ task: FocusTask,
        title: String,
        note: String,
        priority: TaskPriority
    ) {
        withAnimation(.easeInOut(duration: 0.22)) {
            _ = model.updateTask(task, title: title, note: note, priority: priority)
        }
    }

    private func deleteTask(_ task: FocusTask) {
        model.requestTaskDeletion(task.id)
    }
}

private struct PomodoroCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var isAddingPomodoro = false
    @State private var scrollOffset: CGFloat = 0
    var fillsAvailableHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionEyebrow(
                    title: "Pomodoro",
                    trailing: model.activePomodoroID == nil
                        ? "\(model.pomodoroPresets.count) presets" : model.formattedTimer
                )
                compactAddButton(isPresented: $isAddingPomodoro)
                    .popover(isPresented: $isAddingPomodoro, arrowEdge: .bottom) {
                        PomodoroComposer { title, minutes in
                            addPomodoro(title: title, minutes: minutes)
                        }
                    }
            }

            ScrollerlessViewport(
                contentHeight: pomodoroContentHeight,
                scrollOffset: $scrollOffset,
                content: PomodoroRows()
                    .environmentObject(model)
            )
            .frame(height: 156)
            .overlay(alignment: .trailing) {
                if model.pomodoroPresets.count > 3 {
                    SlimScrollCue(
                        viewportHeight: 156,
                        contentHeight: pomodoroContentHeight,
                        scrollOffset: scrollOffset
                    )
                    .padding(.trailing, 1)
                }
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface()
        .onChange(of: model.pomodoroPresets.count) { _, _ in
            withAnimation(.easeInOut(duration: 0.22)) {
                scrollOffset = min(scrollOffset, max(pomodoroContentHeight - 156, 0))
            }
        }
    }

    private var pomodoroContentHeight: CGFloat {
        CGFloat(model.pomodoroPresets.count * 48 + max(model.pomodoroPresets.count - 1, 0) * 6)
    }

    private func addPomodoro(title: String, minutes: Int) {
        var addedID: UUID?
        withAnimation(.easeOut(duration: 0.28)) {
            addedID = model.addPomodoro(title: title, minutes: minutes)
            isAddingPomodoro = false
        }
        guard addedID != nil else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollOffset = max(pomodoroContentHeight - 156, 0)
            }
        }
    }
}

private struct FocusTaskRows: View {
    let tasks: [FocusTask]
    let toggle: (FocusTask) -> Void
    let edit: (FocusTask, String, String, TaskPriority) -> Void
    let delete: (FocusTask) -> Void

    var body: some View {
        VStack(spacing: 5) {
            ForEach(tasks) { task in
                FocusTaskRow(
                    task: task,
                    toggle: toggle,
                    edit: edit,
                    delete: delete
                )
                .transition(.offset(y: 8).combined(with: .opacity))
            }
        }
        .padding(.trailing, tasks.count > 3 ? 6 : 0)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct FocusTaskRow: View {
    let task: FocusTask
    let toggle: (FocusTask) -> Void
    let edit: (FocusTask, String, String, TaskPriority) -> Void
    let delete: (FocusTask) -> Void

    @State private var presentedPopover: ItemRowPopover?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    toggle(task)
                }
            } label: {
                HStack(spacing: 13) {
                    completionIndicator
                    taskDetails
                    priorityBadge
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                task.isComplete ? "Mark \(task.title) incomplete" : "Mark \(task.title) complete"
            )
            .accessibilityValue(
                "\(task.note.isEmpty ? "No note" : task.note), \(task.priority.title) priority"
            )

            Button {
                presentedPopover = presentedPopover == .actions ? nil : .actions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlowTheme.secondary)
                    .frame(width: 26, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Task actions")
            .accessibilityLabel("Actions for \(task.title)")
            .popover(item: $presentedPopover, arrowEdge: .trailing) { popover in
                switch popover {
                case .actions:
                    ItemActionsPopover(
                        editTitle: "Edit focus item",
                        editSubtitle: "Change its title, note, or priority",
                        deleteTitle: "Delete focus item",
                        deleteSubtitle: "Remove it from today’s list",
                        edit: {
                            presentedPopover = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                presentedPopover = .editor
                            }
                        },
                        delete: {
                            presentedPopover = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                delete(task)
                            }
                        }
                    )
                case .editor:
                    TaskComposer(task: task) { title, note, priority in
                        edit(task, title, note, priority)
                        presentedPopover = nil
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(
            FlowTheme.cardRaised.opacity(0.62), in: RoundedRectangle(cornerRadius: 13)
        )
    }

    private var completionIndicator: some View {
        ZStack {
            Circle()
                .stroke(
                    task.isComplete ? FlowTheme.accent : FlowTheme.secondary.opacity(0.45),
                    lineWidth: 1.5
                )
            if task.isComplete {
                Circle().fill(FlowTheme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(hex: "291A11"))
            }
        }
        .frame(width: 20, height: 20)
    }

    private var taskDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .strikethrough(task.isComplete, color: FlowTheme.secondary)
                .foregroundStyle(task.isComplete ? FlowTheme.secondary : FlowTheme.text)
                .textSelection(.disabled)
            Text(task.note.isEmpty ? "No note" : task.note)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(FlowTheme.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priorityBadge: some View {
        Label(task.priority.title.uppercased(), systemImage: task.priority.symbol)
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .foregroundStyle(task.priority.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(task.priority.tint.opacity(0.11), in: Capsule())
            .opacity(task.isComplete ? 0.5 : 1)
    }
}

private struct PomodoroRows: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.pomodoroPresets) { preset in
                PomodoroRow(preset: preset)
                    .environmentObject(model)
                    .transition(.offset(y: 8).combined(with: .opacity))
            }
        }
        .padding(.trailing, model.pomodoroPresets.count > 3 ? 6 : 0)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct PomodoroRow: View {
    @EnvironmentObject private var model: DashboardModel
    let preset: PomodoroPreset

    @State private var presentedPopover: ItemRowPopover?

    var body: some View {
        HStack(spacing: 8) {
            timerIndicator
            timerDetails
            Spacer(minLength: 0)

            if model.activePomodoroID == preset.id {
                Button(action: model.resetTimer) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(FlowTheme.secondary)
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.plain)
                .help("Reset timer")
            }

            Button {
                model.startPomodoro(preset)
            } label: {
                Image(
                    systemName: model.activePomodoroID == preset.id && model.isTimerRunning
                        ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(
                    model.activePomodoroID == preset.id
                        ? Color(hex: "27180F") : FlowTheme.accent
                )
                .frame(width: 27, height: 27)
                .background(
                    model.activePomodoroID == preset.id
                        ? FlowTheme.accent : FlowTheme.accent.opacity(0.12),
                    in: Circle()
                )
            }
            .buttonStyle(.plain)
            .help(model.activePomodoroID == preset.id && model.isTimerRunning ? "Pause" : "Start")

            Button {
                presentedPopover = presentedPopover == .actions ? nil : .actions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FlowTheme.secondary)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Timer actions")
            .accessibilityLabel("Actions for \(preset.title)")
            .popover(item: $presentedPopover, arrowEdge: .trailing) { popover in
                switch popover {
                case .actions:
                    ItemActionsPopover(
                        editTitle: "Edit timer",
                        editSubtitle: "Change its name or duration",
                        deleteTitle: "Delete timer",
                        deleteSubtitle: "Remove this Pomodoro preset",
                        edit: {
                            presentedPopover = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                presentedPopover = .editor
                            }
                        },
                        delete: {
                            presentedPopover = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                model.requestPomodoroDeletion(preset.id)
                            }
                        }
                    )
                case .editor:
                    PomodoroComposer(preset: preset) { title, minutes in
                        _ = model.updatePomodoro(preset, title: title, minutes: minutes)
                        presentedPopover = nil
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .background(
            FlowTheme.cardRaised.opacity(0.62), in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var timerIndicator: some View {
        ZStack {
            Circle().stroke(FlowTheme.stroke, lineWidth: 3)
            if model.activePomodoroID == preset.id {
                Circle()
                    .trim(from: 0, to: max(0.02, model.progress))
                    .stroke(
                        FlowTheme.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: model.activePomodoroID == preset.id ? "flame.fill" : "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    model.activePomodoroID == preset.id ? FlowTheme.accent : FlowTheme.secondary
                )
        }
        .frame(width: 30, height: 30)
    }

    private var timerDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(preset.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .textSelection(.disabled)
            Text(
                model.activePomodoroID == preset.id
                    ? model.formattedTimer : "\(preset.minutes) minute focus"
            )
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(FlowTheme.secondary)
            .contentTransition(.numericText())
        }
    }
}

@MainActor
private func compactAddButton(isPresented: Binding<Bool>) -> some View {
    Button {
        isPresented.wrappedValue.toggle()
    } label: {
        Image(systemName: "plus")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(FlowTheme.accent)
            .frame(width: 24, height: 24)
            .background(FlowTheme.accent.opacity(0.11), in: Circle())
    }
    .buttonStyle(.plain)
    .help("Add another item")
}

private struct TaskComposer: View {
    private let task: FocusTask?
    private let submit: (String, String, TaskPriority) -> Void

    @State private var title: String
    @State private var note: String
    @State private var priority: TaskPriority

    init(
        task: FocusTask? = nil,
        submit: @escaping (String, String, TaskPriority) -> Void
    ) {
        self.task = task
        self.submit = submit
        _title = State(initialValue: task?.title ?? "")
        _note = State(initialValue: task?.note ?? "")
        _priority = State(initialValue: task?.priority ?? .medium)
    }

    var body: some View {
        ComposerSurface(
            title: task == nil ? "New focus item" : "Edit focus item",
            subtitle: task == nil ? "Give today a clear next move." : "Refine the next move.",
            symbol: task == nil ? "checkmark.circle.fill" : "pencil.circle.fill"
        ) {
            LiquidTextField(
                label: "TASK",
                placeholder: "What needs your focus?",
                text: $title
            )
            LiquidTextField(
                label: "NOTE",
                placeholder: "Add a little context (optional)",
                text: $note
            )
            LiquidPriorityControl(priority: $priority)
            composerButton(task == nil ? "Add to today" : "Save changes") {
                submit(title, note, priority)
            }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            guard task != nil else { return }
            moveFocusedTextInsertionPointToEnd()
        }
    }
}

extension TaskPriority {
    fileprivate var tint: Color {
        switch self {
        case .low: Color(hex: "F2A65A")
        case .medium: Color(hex: "D89938")
        case .high: Color(hex: "E8614F")
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .low: "leaf.fill"
        case .medium: "bolt.fill"
        case .high: "flame.fill"
        }
    }
}

private struct LiquidPriorityControl: View {
    @Binding var priority: TaskPriority

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIORITY · DIFFICULTY")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(FlowTheme.secondary)

            HStack(spacing: 7) {
                ForEach(TaskPriority.allCases) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { priority = option }
                    } label: {
                        VStack(spacing: 3) {
                            Label(option.title, systemImage: option.symbol)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                            Text(option.difficulty.uppercased())
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .tracking(0.5)
                                .opacity(0.72)
                        }
                        .foregroundStyle(priority == option ? option.tint : FlowTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            priority == option
                                ? option.tint.opacity(0.12) : Color.white.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(
                                    priority == option
                                        ? option.tint.opacity(0.35) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PomodoroComposer: View {
    private let preset: PomodoroPreset?
    private let submit: (String, Int) -> Void

    @State private var title: String
    @State private var minutes: Int

    init(preset: PomodoroPreset? = nil, submit: @escaping (String, Int) -> Void) {
        self.preset = preset
        self.submit = submit
        _title = State(initialValue: preset?.title ?? "")
        _minutes = State(initialValue: preset?.minutes ?? 25)
    }

    var body: some View {
        ComposerSurface(
            title: preset == nil ? "New Pomodoro" : "Edit Pomodoro",
            subtitle: preset == nil
                ? "Shape a timer around the work." : "Tune this focus session.",
            symbol: preset == nil ? "timer.circle.fill" : "pencil.circle.fill"
        ) {
            LiquidTextField(
                label: "SESSION",
                placeholder: "Name this focus session",
                text: $title
            )
            LiquidDurationControl(minutes: $minutes)
            composerButton(preset == nil ? "Add timer" : "Save changes") {
                submit(title, minutes)
            }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            guard preset != nil else { return }
            moveFocusedTextInsertionPointToEnd()
        }
    }
}

@MainActor
private func moveFocusedTextInsertionPointToEnd() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    }
}

private struct ComposerSurface<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)

            Circle()
                .fill(FlowTheme.accent.opacity(0.20))
                .frame(width: 170, height: 170)
                .blur(radius: 52)
                .offset(x: 120, y: -100)

            Circle()
                .fill(FlowTheme.lime.opacity(0.10))
                .frame(width: 130, height: 130)
                .blur(radius: 46)
                .offset(x: -130, y: 120)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FlowTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(FlowTheme.secondary)
                    }

                    Spacer()
                }

                content
            }
            .padding(20)
        }
        .frame(width: 330)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34), FlowTheme.accent.opacity(0.22),
                            Color.white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.24), radius: 28, y: 16)
        .foregroundStyle(FlowTheme.text)
        .presentationBackground(.clear)
    }
}

private struct LiquidTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(FlowTheme.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    .thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
    }
}

private struct LiquidDurationControl: View {
    @Binding var minutes: Int
    private let quickValues = [15, 25, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("DURATION")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(FlowTheme.secondary)

            HStack(spacing: 10) {
                durationButton(symbol: "minus") {
                    minutes = max(5, minutes - 5)
                }

                VStack(spacing: 1) {
                    Text("\(minutes)")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                    Text("MIN")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(FlowTheme.secondary)
                }
                .frame(maxWidth: .infinity)

                durationButton(symbol: "plus") {
                    minutes = min(120, minutes + 5)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 56)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14)))

            HStack(spacing: 7) {
                ForEach(quickValues, id: \.self) { value in
                    Button {
                        minutes = value
                    } label: {
                        Text("\(value)m")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(
                                minutes == value ? Color(hex: "27180F") : FlowTheme.secondary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 25)
                            .background(
                                minutes == value ? FlowTheme.accent : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func durationButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FlowTheme.text)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private func composerButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            Text(title)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(Color(hex: "27180F"))
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            LinearGradient(
                colors: [Color(hex: "FFA36F"), FlowTheme.accent],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.34))
                .frame(height: 1)
                .padding(.horizontal, 14)
        }
    }
    .buttonStyle(.plain)
}

private struct SlimScrollCue: View {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let scrollOffset: CGFloat

    var body: some View {
        let thumbHeight = max(24, viewportHeight * min(viewportHeight / max(contentHeight, 1), 1))
        let maximumOffset = max(contentHeight - viewportHeight, 1)
        let progress = min(max(scrollOffset / maximumOffset, 0), 1)

        ZStack(alignment: .top) {
            Capsule()
                .fill(FlowTheme.stroke)
                .frame(width: 1, height: viewportHeight)
            Capsule()
                .fill(FlowTheme.secondary.opacity(0.72))
                .frame(width: 2, height: thumbHeight)
                .offset(y: (viewportHeight - thumbHeight) * progress)
        }
        .frame(width: 3, height: viewportHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScrollerlessViewport<Content: View>: NSViewRepresentable {
    let contentHeight: CGFloat
    @Binding var scrollOffset: CGFloat
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = HiddenScrollerNSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let hostingView = NSHostingView(rootView: content)
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView
        context.coordinator.observe(scrollView)
        scrollView.onLayout = { [weak scrollView, weak coordinator = context.coordinator] in
            guard let scrollView, let coordinator else { return }
            coordinator.sizeDocument(in: scrollView)
        }
        DispatchQueue.main.async { context.coordinator.sizeDocument(in: scrollView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingView?.rootView = content
        scrollView.hasVerticalScroller = false
        DispatchQueue.main.async { context.coordinator.sizeDocument(in: scrollView) }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving(scrollView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScrollerlessViewport
        var hostingView: NSHostingView<Content>?

        init(parent: ScrollerlessViewport) {
            self.parent = parent
        }

        func observe(_ scrollView: NSScrollView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func stopObserving(_ scrollView: NSScrollView) {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func sizeDocument(in scrollView: NSScrollView) {
            guard let hostingView else { return }
            let width = max(scrollView.contentSize.width, 1)
            let height = max(parent.contentHeight, scrollView.contentSize.height)
            let targetFrame = NSRect(x: 0, y: 0, width: width, height: height)
            if hostingView.frame != targetFrame { hostingView.frame = targetFrame }
            scrollView.hasVerticalScroller = false
            scrollView.verticalScroller?.isHidden = true
            applyRequestedScrollOffset(in: scrollView)
        }

        private func applyRequestedScrollOffset(in scrollView: NSScrollView) {
            let maximumOffset = max(parent.contentHeight - scrollView.contentSize.height, 0)
            let requestedOffset = min(max(parent.scrollOffset, 0), maximumOffset)
            guard abs(scrollView.contentView.bounds.minY - requestedOffset) > 0.5 else { return }
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: requestedOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            let offset = max(clipView.bounds.minY, 0)
            guard abs(parent.scrollOffset - offset) > 0.5 else { return }
            parent.scrollOffset = offset
        }
    }

    private final class HiddenScrollerNSScrollView: NSScrollView {
        var onLayout: (() -> Void)?

        override func layout() {
            super.layout()
            hasVerticalScroller = false
            verticalScroller?.isHidden = true
            onLayout?()
        }
    }
}

private struct ScrollerlessHorizontalViewport<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let content: Content

    init(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HiddenHorizontalScrollerNSScrollView {
        let scrollView = HiddenHorizontalScrollerNSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.contentView.drawsBackground = false
        scrollView.enableDragScrolling()

        let hostingView = NSHostingView(rootView: content)
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView
        scrollView.onLayout = { [weak scrollView, weak coordinator = context.coordinator] in
            guard let scrollView, let coordinator else { return }
            coordinator.sizeDocument(in: scrollView)
        }
        DispatchQueue.main.async { context.coordinator.sizeDocument(in: scrollView) }
        return scrollView
    }

    func updateNSView(_ scrollView: HiddenHorizontalScrollerNSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingView?.rootView = content
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        DispatchQueue.main.async { context.coordinator.sizeDocument(in: scrollView) }
    }

    @MainActor
    final class Coordinator {
        var parent: ScrollerlessHorizontalViewport
        var hostingView: NSHostingView<Content>?

        init(parent: ScrollerlessHorizontalViewport) {
            self.parent = parent
        }

        func sizeDocument(in scrollView: NSScrollView) {
            guard let hostingView else { return }
            let targetFrame = NSRect(
                x: 0,
                y: 0,
                width: max(parent.contentWidth, scrollView.contentSize.width),
                height: parent.contentHeight
            )
            if hostingView.frame != targetFrame { hostingView.frame = targetFrame }
            scrollView.hasVerticalScroller = false
            scrollView.verticalScroller?.isHidden = true
            scrollView.hasHorizontalScroller = false
            scrollView.horizontalScroller?.isHidden = true
        }
    }

    final class HiddenHorizontalScrollerNSScrollView: NSScrollView, NSGestureRecognizerDelegate {
        var onLayout: (() -> Void)?
        private var dragStartOrigin = NSPoint.zero
        private var dragRecognizer: NSPanGestureRecognizer?

        func enableDragScrolling() {
            guard dragRecognizer == nil else { return }
            let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
            recognizer.buttonMask = 0x1
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
            dragRecognizer = recognizer
        }

        @objc private func handleDrag(_ recognizer: NSPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                dragStartOrigin = contentView.bounds.origin
                NSCursor.closedHand.push()

            case .changed:
                guard let documentView else { return }
                let translation = recognizer.translation(in: self)
                let maximumX = max(documentView.frame.width - contentSize.width, 0)
                let targetX = min(max(dragStartOrigin.x - translation.x, 0), maximumX)
                contentView.scroll(to: NSPoint(x: targetX, y: contentView.bounds.minY))
                reflectScrolledClipView(contentView)

            case .ended, .cancelled, .failed:
                NSCursor.pop()

            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }

        override func layout() {
            super.layout()
            hasVerticalScroller = false
            verticalScroller?.isHidden = true
            hasHorizontalScroller = false
            horizontalScroller?.isHidden = true
            onLayout?()
        }
    }
}

private struct AppsCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var isShowingAllApps = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var fillsAvailableHeight = false

    private var visibleApps: [RunningApp] {
        Array(model.runningApps.prefix(model.runningApps.count > 4 ? 3 : 4))
    }

    private var overflowApps: [RunningApp] {
        guard model.runningApps.count > 4 else { return [] }
        return Array(model.runningApps.dropFirst(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(
                title: "Current apps",
                trailing: model.runningApps.isEmpty
                    ? "None active" : "\(model.runningApps.count) active"
            )
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(visibleApps) { app in
                    RunningAppButton(app: app) {
                        model.activate(app)
                    }
                }

                if !overflowApps.isEmpty {
                    Button {
                        isShowingAllApps.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            AppFolderIcon(apps: overflowApps)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("More apps")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text("\(overflowApps.count) running")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(FlowTheme.secondary)
                            }
                            .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(FlowTheme.accent.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isShowingAllApps, arrowEdge: .bottom) {
                        RunningAppsFolder(apps: overflowApps)
                            .environmentObject(model)
                    }
                }
            }

            if model.runningApps.isEmpty {
                Text("Open an app and it will appear here automatically.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        FlowTheme.cardRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface()
    }
}

private struct RunningAppButton: View {
    let app: RunningApp
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RunningApplicationIcon(app: app, size: 32)
                Text(app.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .contentShape(Rectangle())
            .background(
                FlowTheme.cardRaised.opacity(0.62),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(FlowTheme.stroke)
            )
        }
        .buttonStyle(.plain)
        .help("Switch to \(app.name)")
    }
}

private struct RunningApplicationIcon: View {
    let app: RunningApp
    let size: CGFloat

    private var icon: NSImage {
        if let bundleURL = app.bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: app.name)
            ?? NSImage(size: NSSize(width: size, height: size))
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(app.name)
    }
}

private struct AppFolderIcon: View {
    let apps: [RunningApp]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(FlowTheme.accent.opacity(0.38))
                .frame(width: 17, height: 7)
                .offset(x: 3, y: -2)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FlowTheme.accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 0.7)
                )

            HStack(spacing: -3) {
                ForEach(Array(apps.prefix(3))) { app in
                    RunningApplicationIcon(app: app, size: 14)
                        .background(
                            FlowTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 4)
            .frame(width: 34, height: 32)
        }
        .frame(width: 34, height: 32)
    }
}

private struct RunningAppsFolder: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0

    let apps: [RunningApp]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    private let tileHeight: CGFloat = 84
    private let rowSpacing: CGFloat = 10
    private let maximumViewportHeight: CGFloat = 272

    private var rowCount: Int {
        max(Int(ceil(Double(apps.count) / 4)), 1)
    }

    private var contentHeight: CGFloat {
        CGFloat(rowCount) * tileHeight + CGFloat(max(rowCount - 1, 0)) * rowSpacing
    }

    private var viewportHeight: CGFloat {
        min(contentHeight, maximumViewportHeight)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [FlowTheme.accent.opacity(0.14), .clear, FlowTheme.lime.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AppFolderIcon(apps: apps)
                        .scaleEffect(1.18)
                        .frame(width: 42, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Running apps")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("\(apps.count) more open · select one to switch")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(FlowTheme.secondary)
                    }
                    Spacer()
                }

                Divider().overlay(FlowTheme.stroke)

                ScrollerlessViewport(
                    contentHeight: contentHeight,
                    scrollOffset: $scrollOffset,
                    content: LazyVGrid(columns: columns, spacing: rowSpacing) {
                        ForEach(apps) { app in
                            Button {
                                model.activate(app)
                                dismiss()
                            } label: {
                                VStack(spacing: 7) {
                                    RunningApplicationIcon(app: app, size: 44)
                                    Text(app.name)
                                        .font(
                                            .system(size: 10, weight: .semibold, design: .rounded)
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity)
                                .frame(height: tileHeight)
                                .contentShape(Rectangle())
                                .background(
                                    FlowTheme.cardRaised.opacity(0.62),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Switch to \(app.name)")
                        }
                    }
                    .frame(height: contentHeight, alignment: .top)
                    .padding(.trailing, contentHeight > viewportHeight ? 10 : 0)
                )
                .frame(height: viewportHeight)
                .overlay(alignment: .trailing) {
                    if contentHeight > viewportHeight {
                        SlimScrollCue(
                            viewportHeight: viewportHeight,
                            contentHeight: contentHeight,
                            scrollOffset: scrollOffset
                        )
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 520)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.34), FlowTheme.stroke.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 28, y: 14)
        .presentationBackground(.clear)
    }
}

private struct QuickAICard: View {
    @EnvironmentObject private var model: DashboardModel
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var fillsAvailableHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(title: "Quick AI")
                Spacer()
                Text("LOCAL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(FlowTheme.lime)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(FlowTheme.lime.opacity(0.1), in: Capsule())
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AIAction.allCases) { action in
                    Button {
                        model.runAI(action)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(FlowTheme.accent)
                                .frame(width: 18)
                            Text(action.rawValue)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(FlowTheme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface()
    }
}

private struct ClipboardCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var topVisibleItemID: UUID?
    var fillsAvailableHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(
                title: "Clipboard",
                trailing: model.clipboardItems.isEmpty
                    ? "Live" : "\(model.clipboardItems.count) saved"
            )

            if model.clipboardItems.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(FlowTheme.accent)
                    Text("Copy text or an image to begin your history.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .background(
                    FlowTheme.cardRaised.opacity(0.45), in: RoundedRectangle(cornerRadius: 11))
            } else {
                ScrollerlessClipboardView(
                    items: model.clipboardItems,
                    topVisibleItemID: $topVisibleItemID,
                    restore: model.restoreClipboardItem
                )
                .frame(height: 132)
                .overlay(alignment: .trailing) {
                    if model.clipboardItems.count > 3 {
                        GeometryReader { proxy in
                            thinScrollCue(height: proxy.size.height)
                        }
                        .frame(width: 3)
                        .padding(.trailing, 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface(padding: 16)
    }

    private func thinScrollCue(height: CGFloat) -> some View {
        let itemCount = model.clipboardItems.count
        let visibleCount = 3
        let thumbHeight = max(24, height * CGFloat(visibleCount) / CGFloat(itemCount))
        let currentIndex =
            model.clipboardItems.firstIndex(where: { $0.id == topVisibleItemID }) ?? 0
        let maximumIndex = max(itemCount - visibleCount, 1)
        let progress = min(max(CGFloat(currentIndex) / CGFloat(maximumIndex), 0), 1)

        return ZStack(alignment: .top) {
            Capsule()
                .fill(FlowTheme.stroke)
                .frame(width: 1, height: height)

            Capsule()
                .fill(FlowTheme.secondary.opacity(0.72))
                .frame(width: 2, height: thumbHeight)
                .offset(y: (height - thumbHeight) * progress)
        }
        .frame(width: 3, height: height)
    }
}

private struct ScrollerlessClipboardView: NSViewRepresentable {
    let items: [ClipboardHistoryItem]
    @Binding var topVisibleItemID: UUID?
    let restore: (ClipboardHistoryItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ScrollerlessNSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let hostingView = NSHostingView(rootView: rows)
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView
        context.coordinator.observe(scrollView)

        scrollView.onLayout = { [weak scrollView, weak coordinator = context.coordinator] in
            guard let scrollView, let coordinator else { return }
            coordinator.sizeDocument(in: scrollView)
        }

        DispatchQueue.main.async {
            context.coordinator.sizeDocument(in: scrollView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingView?.rootView = rows
        scrollView.hasVerticalScroller = false
        scrollView.verticalScroller?.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.sizeDocument(in: scrollView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving(scrollView)
    }

    private var rows: ClipboardRows {
        ClipboardRows(items: items, restore: restore)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScrollerlessClipboardView
        var hostingView: NSHostingView<ClipboardRows>?

        init(parent: ScrollerlessClipboardView) {
            self.parent = parent
        }

        func observe(_ scrollView: NSScrollView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func stopObserving(_ scrollView: NSScrollView) {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func sizeDocument(in scrollView: NSScrollView) {
            guard let hostingView else { return }
            let width = max(scrollView.contentSize.width, 1)
            let count = parent.items.count
            let height = CGFloat(count * 42 + max(count - 1, 0))
            let targetFrame = NSRect(
                x: 0, y: 0, width: width, height: max(height, scrollView.contentSize.height))
            if hostingView.frame != targetFrame {
                hostingView.frame = targetFrame
            }
            scrollView.hasVerticalScroller = false
            scrollView.verticalScroller?.isHidden = true
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                !parent.items.isEmpty
            else { return }
            let rowStride: CGFloat = 43
            let index = min(
                max(Int(floor(clipView.bounds.minY / rowStride)), 0), parent.items.count - 1)
            let id = parent.items[index].id
            guard parent.topVisibleItemID != id else { return }
            parent.topVisibleItemID = id
        }
    }

    private final class ScrollerlessNSScrollView: NSScrollView {
        var onLayout: (() -> Void)?

        override func layout() {
            super.layout()
            hasVerticalScroller = false
            verticalScroller?.isHidden = true
            onLayout?()
        }
    }
}

private struct ClipboardRows: View {
    let items: [ClipboardHistoryItem]
    let restore: (ClipboardHistoryItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ClipboardHistoryRow(item: item) {
                    restore(item)
                }
                if index < items.count - 1 {
                    Divider()
                        .overlay(FlowTheme.stroke)
                        .padding(.leading, 39)
                }
            }
        }
        .padding(.trailing, items.count > 3 ? 6 : 0)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                preview

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(
                            .system(
                                size: 10.5, weight: .semibold,
                                design: item.kind == .text ? .monospaced : .rounded)
                        )
                        .foregroundStyle(FlowTheme.text)
                        .lineLimit(1)

                    Text(item.detail)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondary)
                    .frame(width: 24, height: 24)
                    .background(FlowTheme.cardRaised, in: Circle())
            }
            .padding(.horizontal, 6)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy this item again")
        .accessibilityLabel(
            item.kind == .image ? "Restore copied image" : "Restore copied text")
    }

    @ViewBuilder
    private var preview: some View {
        if item.kind == .image,
            let data = item.imageData,
            let image = NSImage(data: data)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(FlowTheme.stroke))
        } else {
            IconBadge(symbol: "text.alignleft", tint: FlowTheme.accent, size: 30)
        }
    }
}

private struct RecentFilesCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var scrollOffset: CGFloat = 0
    var fillsAvailableHeight = false

    private let viewportHeight: CGFloat = 155

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionEyebrow(
                    title: "Recent files",
                    trailing: model.recentFiles.isEmpty ? nil : "\(model.recentFiles.count) found"
                )
                Spacer()
                Button("Browse") { model.chooseFile() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlowTheme.accent)
            }

            if model.recentFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(
                        systemName: model.isLoadingRecentFiles
                            ? "sparkle.magnifyingglass" : "doc.badge.clock"
                    )
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(FlowTheme.accent)
                    Text(
                        model.isLoadingRecentFiles
                            ? "Finding your recent files…" : "No recent file activity found."
                    )
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 151)
                .background(
                    FlowTheme.cardRaised.opacity(0.42), in: RoundedRectangle(cornerRadius: 13))
            } else {
                ScrollerlessViewport(
                    contentHeight: recentFilesContentHeight,
                    scrollOffset: $scrollOffset,
                    content: RecentFileRows(
                        files: model.recentFiles,
                        open: model.open
                    )
                )
                .frame(height: viewportHeight)
                .overlay(alignment: .trailing) {
                    if model.recentFiles.count > 3 {
                        SlimScrollCue(
                            viewportHeight: viewportHeight,
                            contentHeight: recentFilesContentHeight,
                            scrollOffset: scrollOffset
                        )
                        .padding(.trailing, 1)
                    }
                }
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface()
    }

    private var recentFilesContentHeight: CGFloat {
        CGFloat(model.recentFiles.count * 49 + max(model.recentFiles.count - 1, 0) * 4)
    }
}

private struct RecentFileRows: View {
    let files: [RecentFile]
    let open: (RecentFile) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(files) { file in
                Button {
                    open(file)
                } label: {
                    HStack(spacing: 11) {
                        RecentFileIcon(file: file, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(file.detail)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(FlowTheme.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(file.lastUsedAt, style: .relative)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(FlowTheme.secondary.opacity(0.72))
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(FlowTheme.secondary.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 49)
                    .contentShape(Rectangle())
                    .background(
                        FlowTheme.cardRaised.opacity(0.001),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .help("Open \(file.name)")
            }
        }
        .padding(.trailing, files.count > 3 ? 7 : 0)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent files, scroll for more")
    }
}

private struct RecentFileIcon: View {
    let file: RecentFile
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct SystemCard: View {
    @EnvironmentObject private var model: DashboardModel
    var fillsAvailableHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionEyebrow(title: "System", trailing: model.systemMetrics.healthLabel)
            HStack(spacing: 12) {
                metric(
                    symbol: model.systemMetrics.batterySymbol,
                    label: model.systemMetrics.isCharging ? "Charging" : "Battery",
                    value: percentage(model.systemMetrics.batteryLevel),
                    progress: model.systemMetrics.batteryLevel ?? 0,
                    tint: FlowTheme.lime
                )
                metric(
                    symbol: "cpu",
                    label: "CPU",
                    value: percentage(model.systemMetrics.cpuUsage),
                    progress: model.systemMetrics.cpuUsage,
                    tint: Color(hex: "63B4FF")
                )
                metric(
                    symbol: "memorychip",
                    label: "RAM",
                    value: percentage(model.systemMetrics.memoryUsage),
                    progress: model.systemMetrics.memoryUsage,
                    tint: FlowTheme.accent
                )
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface()
    }

    private func metric(symbol: String, label: String, value: String, progress: Double, tint: Color)
        -> some View
    {
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(FlowTheme.stroke, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(FlowTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.35), value: progress)
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}

private struct WorkspaceSnapshotCard: View {
    @EnvironmentObject private var model: DashboardModel
    var fillsAvailableHeight = false

    private var workspaceShelfWidth: CGFloat {
        let cardWidths = CGFloat(model.workspaces.count) * 170
        let spacingCount = max(model.workspaces.count - 1, 0)
        return cardWidths + CGFloat(spacingCount) * 12 + 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FlowTheme.accent.opacity(0.12))
                    Image(systemName: "square.3.layers.3d.top.filled")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FlowTheme.accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKSPACES")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(1.05)
                    Text(
                        model.workspaces.isEmpty
                            ? "Save app sets · restore anytime"
                            : "\(model.workspaces.count) saved folders"
                    )
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Button {
                    requestWorkspaceManager()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(FlowTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(FlowTheme.accent.opacity(0.11), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Manage workspaces")
            }

            if model.workspaces.isEmpty {
                Button {
                    requestWorkspaceManager()
                } label: {
                    EmptyWorkspaceFolder()
                }
                .buttonStyle(WorkspaceFolderButtonStyle())
                .help("Create your first workspace")
            } else {
                ScrollerlessHorizontalViewport(
                    contentWidth: workspaceShelfWidth,
                    contentHeight: 62
                ) {
                    HStack(spacing: 12) {
                        ForEach(model.workspaces) { workspace in
                            WorkspaceFolderTile(
                                workspace: workspace,
                                resources: model.workspaceResources[workspace.id] ?? [],
                                isSelected: model.selectedWorkspaceID == workspace.id,
                                restore: { model.requestWorkspaceRestore(workspace.id) },
                                edit: { requestWorkspaceEditor(workspace.id) },
                                update: { model.updateWorkspace(workspace.id) },
                                delete: { model.requestWorkspaceDeletion(workspace.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }
                .frame(height: 62)
                .help("Drag left or right to view more workspaces")
                .overlay(alignment: .trailing) {
                    if model.workspaces.count > 1 {
                        LinearGradient(
                            colors: [.clear, FlowTheme.card.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 16)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .center)
        .cardSurface(padding: 15)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.selectedWorkspaceID)
        .animation(.easeOut(duration: 0.2), value: model.workspaces.count)
    }

    private func requestWorkspaceManager() {
        NotificationCenter.default.post(name: .flowdockWorkspaceManagerRequested, object: nil)
    }

    private func requestWorkspaceEditor(_ workspaceID: UUID) {
        NotificationCenter.default.post(
            name: .flowdockWorkspaceAppEditorRequested,
            object: workspaceID
        )
    }
}

private struct WorkspaceFolderTile: View {
    let workspace: WorkspaceSnapshot
    let resources: [WorkspaceResource]
    let isSelected: Bool
    let restore: () -> Void
    let edit: () -> Void
    let update: () -> Void
    let delete: () -> Void
    @State private var isActionsPresented = false

    private var tint: Color { Color(hex: workspace.accentHex) }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: restore) {
                HStack(spacing: 10) {
                    WorkspaceFolderIcon(resources: resources, tint: tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text("\(resources.count) saved \(resources.count == 1 ? "app" : "apps")")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(FlowTheme.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .padding(.trailing, 38)
                .frame(width: 170, height: 56)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .background(
                    .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(tint.opacity(isSelected ? 0.1 : 0.035))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(isSelected ? tint.opacity(0.42) : FlowTheme.stroke, lineWidth: 1)
                }
            }
            .buttonStyle(WorkspaceFolderButtonStyle())
            .help("Restore \(workspace.name)")
            .accessibilityLabel("\(workspace.name), \(resources.count) saved apps")
            .accessibilityHint("Restores this workspace")

            Button {
                isActionsPresented.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? tint : FlowTheme.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Workspace actions")
            .accessibilityLabel("Actions for \(workspace.name)")
            .popover(isPresented: $isActionsPresented, arrowEdge: .trailing) {
                WorkspaceActionsPopover(
                    editApps: {
                        isActionsPresented = false
                        DispatchQueue.main.async { edit() }
                    },
                    useCurrentApps: {
                        isActionsPresented = false
                        update()
                    },
                    delete: {
                        isActionsPresented = false
                        DispatchQueue.main.async { delete() }
                    }
                )
            }
        }
    }
}

private struct WorkspaceFolderIcon: View {
    let resources: [WorkspaceResource]
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.38))
                .frame(width: 17, height: 7)
                .offset(x: 3, y: -2)

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.1))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 0.7)
                }

            HStack(spacing: -3) {
                ForEach(Array(resources.prefix(3))) { resource in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: resource.location))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .background(
                            FlowTheme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 4)
                        )
                        .accessibilityHidden(true)
                }

                if resources.isEmpty {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FlowTheme.secondary)
                }
            }
            .padding(.horizontal, 4)
            .frame(width: 34, height: 32)
        }
        .frame(width: 34, height: 32)
        .accessibilityHidden(true)
    }
}

private struct EmptyWorkspaceFolder: View {
    var body: some View {
        ZStack {
            WorkspaceFolderShape()
                .fill(FlowTheme.cardRaised.opacity(0.26))
                .overlay {
                    WorkspaceFolderShape()
                        .stroke(
                            FlowTheme.stroke,
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                }

            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlowTheme.accent)
                    .frame(width: 26, height: 26)
                    .background(FlowTheme.accent.opacity(0.11), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create workspace")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Text("Save the apps open now")
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .contentShape(WorkspaceFolderShape())
    }
}

private struct WorkspaceFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let tabEnd = min(width * 0.54, 92)
        var path = Path()

        path.move(to: CGPoint(x: 14, y: 14))
        path.addLine(to: CGPoint(x: 20, y: 14))
        path.addQuadCurve(
            to: CGPoint(x: 31, y: 3),
            control: CGPoint(x: 23, y: 3)
        )
        path.addLine(to: CGPoint(x: tabEnd - 11, y: 3))
        path.addQuadCurve(
            to: CGPoint(x: tabEnd, y: 14),
            control: CGPoint(x: tabEnd - 3, y: 3)
        )
        path.addLine(to: CGPoint(x: width - 14, y: 14))
        path.addQuadCurve(
            to: CGPoint(x: width, y: 28),
            control: CGPoint(x: width, y: 14)
        )
        path.addLine(to: CGPoint(x: width, y: height - 14))
        path.addQuadCurve(
            to: CGPoint(x: width - 14, y: height),
            control: CGPoint(x: width, y: height)
        )
        path.addLine(to: CGPoint(x: 14, y: height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: height - 14),
            control: CGPoint(x: 0, y: height)
        )
        path.addLine(to: CGPoint(x: 0, y: 28))
        path.addQuadCurve(
            to: CGPoint(x: 14, y: 14),
            control: CGPoint(x: 0, y: 14)
        )
        path.closeSubpath()
        return path
    }
}

private struct WorkspaceFolderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct WorkspaceManagerPopover: View {
    @EnvironmentObject private var model: DashboardModel
    let chooseApps: (String) -> Void
    let editApps: (WorkspaceSnapshot) -> Void
    let dismiss: () -> Void
    @State private var workspaceName = ""
    @State private var openActionsWorkspaceID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(FlowTheme.accent)
                    Image(systemName: "square.3.layers.3d.top.filled")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "291A11"))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workspace Library")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Save and restore groups of open apps")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
                Spacer()
                Text("\(model.workspaces.count) SAVED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(FlowTheme.secondary)
            }
            .padding(16)

            Divider().overlay(FlowTheme.stroke)

            if model.workspaces.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(FlowTheme.accent.opacity(0.8))
                    Text("Your workspace library is empty")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Create one from the apps open right now.")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 115)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(model.workspaces) { workspace in
                            workspaceRow(workspace)
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 230)
            }

            Divider().overlay(FlowTheme.stroke)

            VStack(alignment: .leading, spacing: 8) {
                Text("NEW WORKSPACE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(FlowTheme.secondary)

                HStack(spacing: 9) {
                    TextField("e.g. Client Project", text: $workspaceName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(
                            FlowTheme.cardRaised.opacity(0.68),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(FlowTheme.stroke, lineWidth: 1)
                        }

                    Button(action: openAppPicker) {
                        Label("Choose apps", systemImage: "plus")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "291A11"))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(FlowTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(
                        workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? 0.48 : 1)
                }
            }
            .padding(14)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
        .background(FlowTheme.card.opacity(0.62))
        .foregroundStyle(FlowTheme.text)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 30, y: 14)
        .onExitCommand(perform: dismiss)
    }

    private func workspaceRow(_ workspace: WorkspaceSnapshot) -> some View {
        let resources = model.workspaceResources[workspace.id] ?? []
        let isSelected = model.selectedWorkspaceID == workspace.id

        return HStack(spacing: 10) {
            Button {
                model.selectWorkspace(workspace.id)
            } label: {
                HStack(spacing: 10) {
                    WorkspaceAppIcons(resources: resources, iconSize: 23)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(
                            "\(resources.count) apps · \(workspace.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.requestWorkspaceRestore(workspace.id)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color(hex: "291A11"))
                    .frame(width: 29, height: 29)
                    .background(FlowTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Restore \(workspace.name)")

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    openActionsWorkspaceID =
                        openActionsWorkspaceID == workspace.id ? nil : workspace.id
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FlowTheme.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Workspace actions")
            .accessibilityLabel("Actions for \(workspace.name)")
            .popover(
                isPresented: Binding(
                    get: { openActionsWorkspaceID == workspace.id },
                    set: { isPresented in
                        if !isPresented, openActionsWorkspaceID == workspace.id {
                            openActionsWorkspaceID = nil
                        }
                    }
                ),
                arrowEdge: .trailing
            ) {
                WorkspaceActionsPopover(
                    editApps: {
                        openActionsWorkspaceID = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            editApps(workspace)
                        }
                    },
                    useCurrentApps: {
                        openActionsWorkspaceID = nil
                        model.updateWorkspace(workspace.id)
                    },
                    delete: {
                        openActionsWorkspaceID = nil
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            model.requestWorkspaceDeletion(workspace.id)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(
            isSelected ? FlowTheme.accent.opacity(0.10) : FlowTheme.cardRaised.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? FlowTheme.accent.opacity(0.28) : FlowTheme.stroke.opacity(0.72),
                    lineWidth: 1)
        }
    }

    private func openAppPicker() {
        let cleanName = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        chooseApps(cleanName)
    }
}

private struct WorkspaceAppPickerModal: View {
    @EnvironmentObject private var model: DashboardModel
    let workspaceID: UUID?
    let workspaceName: String
    let dismiss: () -> Void
    @State private var selectedAppIDs: Set<String> = []

    private var isEditing: Bool { workspaceID != nil }

    private var savedApps: [WorkspaceApplication] {
        guard let workspaceID else { return [] }
        return (model.workspaceResources[workspaceID] ?? []).compactMap(
            WorkspaceApplication.init(resource:)
        )
    }

    private var selectableApps: [WorkspaceApplication] {
        var applications: [WorkspaceApplication] = []
        var indexByID: [String: Int] = [:]

        for application in savedApps where indexByID[application.id] == nil {
            indexByID[application.id] = applications.count
            applications.append(application)
        }

        for application in model.runningApps.compactMap(WorkspaceApplication.init(runningApp:)) {
            if let index = indexByID[application.id] {
                applications[index] = application
            } else {
                indexByID[application.id] = applications.count
                applications.append(application)
            }
        }
        return applications
    }

    var body: some View {
        WorkspaceAppSelectionContainer(
            workspaceName: workspaceName,
            apps: selectableApps,
            isEditing: isEditing,
            selectedAppIDs: $selectedAppIDs,
            save: saveWorkspace,
            cancel: dismiss
        )
        .frame(width: 680)
        .shadow(color: Color.black.opacity(0.3), radius: 30, y: 14)
        .onAppear {
            selectedAppIDs = Set((isEditing ? savedApps : selectableApps).map(\.id))
        }
    }

    private func saveWorkspace() {
        let selectedApps = selectableApps.filter { selectedAppIDs.contains($0.id) }
        if let workspaceID {
            if model.updateWorkspace(workspaceID, applications: selectedApps) {
                dismiss()
            }
        } else if model.addWorkspace(named: workspaceName, applications: selectedApps) != nil {
            dismiss()
        }
    }
}

private struct WorkspaceAppSelectionContainer: View {
    let workspaceName: String
    let apps: [WorkspaceApplication]
    let isEditing: Bool
    @Binding var selectedAppIDs: Set<String>
    let save: () -> Void
    let cancel: () -> Void
    @State private var scrollOffset: CGFloat = 0

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]
    private let appViewportHeight: CGFloat = 276
    private let appTileHeight: CGFloat = 58
    private let rowSpacing: CGFloat = 10

    private var appRowCount: Int {
        max(Int(ceil(Double(apps.count) / 3)), 1)
    }

    private var appGridContentHeight: CGFloat {
        CGFloat(appRowCount) * appTileHeight
            + CGFloat(max(appRowCount - 1, 0)) * rowSpacing
            + 28
    }

    private var allAppsAreSelected: Bool {
        !apps.isEmpty && apps.allSatisfy { selectedAppIDs.contains($0.id) }
    }

    private var availableSelectionCount: Int {
        apps.reduce(into: 0) { count, app in
            if selectedAppIDs.contains(app.id) { count += 1 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FlowTheme.accent.opacity(0.14))
                    Image(systemName: isEditing ? "slider.horizontal.3" : "folder.badge.plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FlowTheme.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? "Edit workspace apps" : "Choose workspace apps")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(workspaceName)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(allAppsAreSelected ? "Clear" : "Select all") {
                    if allAppsAreSelected {
                        selectedAppIDs.removeAll()
                    } else {
                        selectedAppIDs = Set(apps.map(\.id))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(FlowTheme.accent)
                .disabled(apps.isEmpty)
            }
            .padding(18)

            Rectangle()
                .fill(FlowTheme.stroke)
                .frame(height: 1)

            if apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(FlowTheme.secondary)
                    Text("No apps available to save")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("Open an app, then return to this picker.")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollerlessViewport(
                    contentHeight: appGridContentHeight,
                    scrollOffset: $scrollOffset,
                    content:
                        LazyVGrid(columns: columns, spacing: rowSpacing) {
                            ForEach(apps) { app in
                                WorkspaceSelectableAppTile(
                                    app: app,
                                    isSelected: selectedAppIDs.contains(app.id),
                                    toggle: { toggle(app) }
                                )
                            }
                        }
                        .padding(14)
                )
                .frame(height: appViewportHeight)
                .overlay(alignment: .trailing) {
                    if appGridContentHeight > appViewportHeight {
                        SlimScrollCue(
                            viewportHeight: appViewportHeight,
                            contentHeight: appGridContentHeight,
                            scrollOffset: scrollOffset
                        )
                        .padding(.trailing, 5)
                    }
                }
            }

            Rectangle()
                .fill(FlowTheme.stroke)
                .frame(height: 1)

            HStack(spacing: 9) {
                Text("\(availableSelectionCount) selected")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        availableSelectionCount == 0 ? Color.red : FlowTheme.secondary
                    )

                Spacer()

                Button("Cancel", action: cancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
                    .frame(height: 32)
                    .padding(.horizontal, 8)

                Button(action: save) {
                    Label(
                        isEditing ? "Save changes" : "Save workspace",
                        systemImage: "checkmark"
                    )
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "291A11"))
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(FlowTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedAppIDs.isEmpty)
                .opacity(selectedAppIDs.isEmpty ? 0.42 : 1)
            }
            .padding(16)
        }
        .background {
            ZStack {
                LiquidGlassBackdrop()
                FlowTheme.card.opacity(0.76)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 22, y: 10)
        .foregroundStyle(FlowTheme.text)
        .accessibilityElement(children: .contain)
        .onExitCommand(perform: cancel)
    }

    private func toggle(_ app: WorkspaceApplication) {
        if selectedAppIDs.contains(app.id) {
            selectedAppIDs.remove(app.id)
        } else {
            selectedAppIDs.insert(app.id)
        }
    }
}

private struct WorkspaceSelectableAppTile: View {
    let app: WorkspaceApplication
    let isSelected: Bool
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 31, height: 31)

                Text(app.name)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(isSelected ? FlowTheme.accent : FlowTheme.cardRaised.opacity(0.7))
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundStyle(Color(hex: "291A11"))
                    }
                }
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(isSelected ? FlowTheme.accent : FlowTheme.stroke, lineWidth: 1)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background(
                FlowTheme.accent.opacity(isSelected ? 0.13 : (isHovered ? 0.07 : 0.025)),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isSelected ? FlowTheme.accent.opacity(0.5) : FlowTheme.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityLabel(app.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles this app in the workspace")
    }
}

private struct WorkspaceActionsPopover: View {
    let editApps: () -> Void
    let useCurrentApps: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            WorkspaceActionRow(
                title: "Edit apps",
                subtitle: "Add or remove saved apps",
                systemImage: "slider.horizontal.3",
                action: editApps
            )

            WorkspaceActionRow(
                title: "Use current apps",
                subtitle: "Replace this saved app set",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                action: useCurrentApps
            )

            Rectangle()
                .fill(FlowTheme.stroke.opacity(0.8))
                .frame(height: 1)
                .padding(.horizontal, 8)

            WorkspaceActionRow(
                title: "Delete workspace",
                subtitle: "Remove this saved app set",
                systemImage: "trash",
                isDestructive: true,
                action: delete
            )
        }
        .padding(7)
        .frame(width: 218)
        .background {
            ZStack {
                LiquidGlassBackdrop()
                FlowTheme.card.opacity(0.72)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .foregroundStyle(FlowTheme.text)
    }
}

private struct WorkspaceActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isDestructive = false
    let action: () -> Void

    @State private var isHovered = false

    private var actionColor: Color {
        isDestructive ? .red : FlowTheme.text
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDestructive ? Color.red : FlowTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(
                        (isDestructive ? Color.red : FlowTheme.accent).opacity(
                            isHovered ? 0.16 : 0.09),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(actionColor)
                    Text(subtitle)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
                .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 44)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background(
                (isDestructive ? Color.red : FlowTheme.accent).opacity(isHovered ? 0.1 : 0),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

private struct WorkspaceAppIcons: View {
    let resources: [WorkspaceResource]
    let iconSize: CGFloat
    var maxVisible: Int = 3

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(resources.prefix(maxVisible))) { resource in
                Image(nsImage: NSWorkspace.shared.icon(forFile: resource.location))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .padding(3)
                    .background(
                        FlowTheme.cardRaised,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FlowTheme.stroke, lineWidth: 1)
                    }
            }

            if resources.count > maxVisible {
                Text("+\(resources.count - maxVisible)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .frame(width: iconSize + 6, height: iconSize + 6)
                    .background(
                        FlowTheme.cardRaised,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(FlowTheme.stroke, lineWidth: 1)
                    }
            }
        }
    }
}

private struct SearchResultsView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0
    let query: String

    private let viewportHeight: CGFloat = 430

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 330), spacing: 24, alignment: .leading)
    ]

    private var searchTerm: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var matchingTasks: [FocusTask] {
        guard !searchTerm.isEmpty else { return [] }
        return model.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchTerm)
                || $0.note.localizedCaseInsensitiveContains(searchTerm)
                || $0.priority.title.localizedCaseInsensitiveContains(searchTerm)
        }
    }
    var matchingPomodoros: [PomodoroPreset] {
        guard !searchTerm.isEmpty else { return [] }
        return model.pomodoroPresets.filter {
            $0.title.localizedCaseInsensitiveContains(searchTerm)
                || "\($0.minutes) min".localizedCaseInsensitiveContains(searchTerm)
        }
    }
    var matchingApps: [RunningApp] {
        guard !searchTerm.isEmpty else { return [] }
        return model.runningApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchTerm)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchTerm) ?? false)
        }
    }
    var matchingFiles: [RecentFile] {
        guard !searchTerm.isEmpty else { return [] }
        return model.recentFiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchTerm)
                || $0.url.path.localizedCaseInsensitiveContains(searchTerm)
        }
    }
    var matchingClipboard: [ClipboardHistoryItem] {
        guard !searchTerm.isEmpty else { return [] }
        return model.clipboardItems.filter {
            $0.searchText.localizedCaseInsensitiveContains(searchTerm)
        }
    }
    var matchingWorkspaces: [WorkspaceSnapshot] {
        guard !searchTerm.isEmpty else { return [] }
        return model.workspaces.filter { workspace in
            workspace.name.localizedCaseInsensitiveContains(searchTerm)
                || (model.workspaceResources[workspace.id] ?? []).contains { resource in
                    resource.title.localizedCaseInsensitiveContains(searchTerm)
                        || resource.location.localizedCaseInsensitiveContains(searchTerm)
                }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            resultsHeader

            Divider()
                .overlay(FlowTheme.stroke.opacity(0.82))

            if hasMatches {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 22) {
                        resultSection(
                            title: "To-do", symbol: "checkmark.circle", count: matchingTasks.count
                        ) {
                            ForEach(matchingTasks) { task in
                                resultRow(
                                    task.title,
                                    detail: task.isComplete
                                        ? "Completed · \(task.priority.title) priority"
                                        : "\(task.priority.title) priority",
                                    symbol: task.isComplete ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }

                        resultSection(
                            title: "Pomodoro", symbol: "timer", count: matchingPomodoros.count
                        ) {
                            ForEach(matchingPomodoros) { preset in
                                resultRow(
                                    preset.title,
                                    detail: "\(preset.minutes)-minute focus preset",
                                    symbol: "timer"
                                )
                            }
                        }

                        resultSection(title: "Files", symbol: "doc", count: matchingFiles.count) {
                            ForEach(matchingFiles) { file in
                                resultRow(
                                    file.name,
                                    detail: file.detail,
                                    symbol: "doc",
                                    actionHint: "Open \(file.name)"
                                ) {
                                    model.open(file)
                                }
                            }
                        }

                        resultSection(title: "Apps", symbol: "app.fill", count: matchingApps.count)
                        {
                            ForEach(matchingApps) { app in
                                resultRow(
                                    app.name,
                                    detail: app.bundleIdentifier ?? "Running now",
                                    symbol: "app.fill",
                                    actionHint: "Switch to \(app.name)"
                                ) {
                                    model.activate(app)
                                }
                            }
                        }

                        resultSection(
                            title: "Clipboard", symbol: "clipboard", count: matchingClipboard.count
                        ) {
                            ForEach(matchingClipboard) { item in
                                resultRow(
                                    String(item.displayTitle.prefix(48)),
                                    detail: item.detail,
                                    symbol: item.kind == .image ? "photo" : "doc.on.clipboard",
                                    actionHint: "Copy this item back to the clipboard"
                                ) {
                                    model.restoreClipboardItem(item)
                                }
                            }
                        }

                        resultSection(
                            title: "Workspaces", symbol: "square.grid.2x2",
                            count: matchingWorkspaces.count
                        ) {
                            ForEach(matchingWorkspaces) { workspace in
                                let resourceCount = (model.workspaceResources[workspace.id] ?? [])
                                    .count
                                resultRow(
                                    workspace.name,
                                    detail:
                                        "\(resourceCount) saved \(resourceCount == 1 ? "item" : "items")",
                                    symbol: workspace.symbol,
                                    actionHint: "Restore \(workspace.name)"
                                ) {
                                    model.requestWorkspaceRestore(workspace.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .padding(.trailing, 5)
                    .background(EnclosingScrollIndicatorHider())
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: SearchResultsScrollOffsetPreferenceKey.self,
                                    value: max(
                                        -proxy.frame(in: .named("searchResultsScroll")).minY, 0)
                                )
                                .preference(
                                    key: SearchResultsContentHeightPreferenceKey.self,
                                    value: proxy.size.height
                                )
                        }
                    }
                }
                .coordinateSpace(name: "searchResultsScroll")
                .frame(maxHeight: viewportHeight)
                .scrollIndicators(.hidden)
                .onPreferenceChange(SearchResultsScrollOffsetPreferenceKey.self) {
                    scrollOffset = $0
                }
                .onPreferenceChange(SearchResultsContentHeightPreferenceKey.self) {
                    scrollContentHeight = $0
                }
                .overlay(alignment: .trailing) {
                    if scrollContentHeight > viewportHeight {
                        SlimScrollCue(
                            viewportHeight: viewportHeight,
                            contentHeight: scrollContentHeight,
                            scrollOffset: scrollOffset
                        )
                        .padding(.trailing, 1)
                    }
                }
                .overlay(alignment: .bottom) {
                    if scrollContentHeight > viewportHeight {
                        LinearGradient(
                            colors: [.clear, FlowTheme.card.opacity(0.76)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 18)
                        .allowsHitTesting(false)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(FlowTheme.accent)
                    Text("No matches for “\(searchTerm)”")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Try a to-do, pomodoro, file, app, clipboard item, or workspace.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(FlowTheme.card.opacity(0.7))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(FlowTheme.stroke.opacity(0.86), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.13), radius: 24, y: 12)
    }

    private var resultsHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FlowTheme.accent)
                .frame(width: 32, height: 32)
                .background(FlowTheme.accent.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Search results")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Matches for “\(searchTerm)” across Flowdock")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(FlowTheme.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(totalMatches) \(totalMatches == 1 ? "match" : "matches")")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(FlowTheme.secondary)

            Label("Esc", systemImage: "escape")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(FlowTheme.secondary.opacity(0.82))
                .accessibilityLabel("Press Escape to close search results")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var totalMatches: Int {
        matchingTasks.count
            + matchingPomodoros.count
            + matchingFiles.count
            + matchingApps.count
            + matchingClipboard.count
            + matchingWorkspaces.count
    }

    private var hasMatches: Bool {
        totalMatches > 0
    }

    @ViewBuilder
    private func resultSection<Content: View>(
        title: String,
        symbol: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FlowTheme.accent)
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(FlowTheme.secondary)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(FlowTheme.secondary)

                    Rectangle()
                        .fill(FlowTheme.stroke.opacity(0.82))
                        .frame(height: 1)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                    content()
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(
        _ title: String,
        detail: String,
        symbol: String,
        actionHint: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        if let action, let actionHint {
            Button {
                action()
                model.searchText = ""
            } label: {
                resultRowContent(title, detail: detail, symbol: symbol, showsChevron: true)
            }
            .buttonStyle(SearchResultButtonStyle())
            .help(actionHint)
            .accessibilityHint(actionHint)
        } else {
            resultRowContent(title, detail: detail, symbol: symbol, showsChevron: false)
        }
    }

    private func resultRowContent(
        _ title: String,
        detail: String,
        symbol: String,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FlowTheme.text.opacity(0.9))
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlowTheme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(FlowTheme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondary.opacity(0.68))
                    .frame(width: 12, height: 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SearchResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.58 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct QuickAISheet: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    let action: AIAction
    @State private var input = ""
    @State private var output = ""
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                IconBadge(symbol: action.symbol, tint: FlowTheme.accent, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.rawValue)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("On-device workspace")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(FlowTheme.secondary)
                }
                Spacer()
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .background(FlowTheme.cardRaised, in: Circle())
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $input)
                .font(.system(size: 13, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(height: 140)
                .background(FlowTheme.cardRaised, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text(
                            "Paste or type the content you want to \(action.rawValue.lowercased())…"
                        )
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(FlowTheme.secondary)
                        .padding(18)
                        .allowsHitTesting(false)
                    }
                }

            if !output.isEmpty {
                Text(output)
                    .font(.system(size: 12, design: action == .code ? .monospaced : .rounded))
                    .foregroundStyle(FlowTheme.text)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        FlowTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                Button("Use clipboard") {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(FlowTheme.secondary)

                Spacer()

                Button {
                    generatePreview()
                } label: {
                    HStack(spacing: 8) {
                        if isWorking { ProgressView().controlSize(.small) }
                        Text(isWorking ? "Working…" : action.rawValue)
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "28180E"))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(FlowTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(
                    input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking
                )
                .opacity(input.isEmpty ? 0.45 : 1)
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 390)
        .background(FlowTheme.canvas)
    }

    private func generatePreview() {
        isWorking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            switch action {
            case .explain:
                output = "In plain language: \(input.prefix(180))\(input.count > 180 ? "…" : "")"
            case .rewrite:
                output = input.trimmingCharacters(in: .whitespacesAndNewlines)
            case .summarize:
                let firstSentence = input.split(separator: ".").first.map(String.init) ?? input
                output = "Summary — \(firstSentence)."
            case .code:
                output =
                    "// Connect Apple Foundation Models, Ollama, or your preferred API here.\nfunc generate() async throws -> String {\n    // \(input.prefix(80))\n    return \"Generated result\"\n}"
            }
            isWorking = false
        }
    }
}
