import AppKit
import SwiftUI

@MainActor
final class FocusShieldController: ObservableObject {
    private var panels: [NSPanel] = []
    private var activityToken: NSObjectProtocol?

    func present(model: DashboardModel) {
        guard panels.isEmpty else { return }

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated, .automaticTerminationDisabled],
            reason: "Flowdock Pomodoro focus session"
        )

        panels = NSScreen.screens.map { screen in
            let panel = FocusShieldPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.setFrame(screen.frame, display: true)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.backgroundColor = NSColor(hex: "121212")
            panel.isOpaque = true
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.canHide = false
            panel.isMovable = false
            panel.animationBehavior = .none
            panel.contentView = NSHostingView(
                rootView: FocusShieldView()
                    .environmentObject(model)
            )
            panel.orderFrontRegardless()
            return panel
        }

        panels.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()

        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }
}

private final class FocusShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct FocusShieldView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: "121212")

                RadialGradient(
                    colors: [Color(hex: "FF8A4C").opacity(0.18), .clear],
                    center: .center,
                    startRadius: 40,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.48
                )

                Circle()
                    .fill(Color(hex: "B8D66D").opacity(0.045))
                    .frame(width: proxy.size.width * 0.48)
                    .blur(radius: 100)
                    .offset(x: -proxy.size.width * 0.36, y: proxy.size.height * 0.36)

                VStack(spacing: 0) {
                    Spacer()

                    Text("FLOW SESSION")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(3.4)
                        .foregroundStyle(Color(hex: "FF8A4C"))
                        .padding(.horizontal, 15)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.055), in: Capsule())

                    Text(model.activePomodoroTitle)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "F5F5F5"))
                        .padding(.top, 22)

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.075), lineWidth: 8)

                        Circle()
                            .trim(from: 0, to: max(model.progress, 0.006))
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color(hex: "FF8A4C"), Color(hex: "F2C36B"),
                                        Color(hex: "FF8A4C"),
                                    ],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Color(hex: "FF8A4C").opacity(0.30), radius: 14)

                        VStack(spacing: 10) {
                            Text(model.formattedTimer)
                                .font(
                                    .system(
                                        size: timerFontSize(for: proxy.size), weight: .medium,
                                        design: .monospaced)
                                )
                                .tracking(-4)
                                .foregroundStyle(Color(hex: "F5F5F5"))
                                .contentTransition(.numericText())

                            Text("STAY WITH THE WORK")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2.2)
                                .foregroundStyle(Color(hex: "A0A19B"))
                        }
                    }
                    .frame(
                        width: timerDiameter(for: proxy.size),
                        height: timerDiameter(for: proxy.size)
                    )
                    .padding(.top, 28)

                    Button(action: model.stopPomodoro) {
                        HStack(spacing: 10) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Stop focus")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30)
                        .frame(height: 48)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "FF5A52"), Color(hex: "D9332B")],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(Color.white.opacity(0.30))
                                .frame(height: 1)
                                .padding(.horizontal, 18)
                        }
                        .shadow(color: Color(hex: "E34138").opacity(0.32), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 34)
                    .accessibilityLabel("Stop Pomodoro and leave focus mode")

                    Text("Flowdock is covering your workspace until you stop this session.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "777972"))
                        .padding(.top, 18)

                    Spacer()
                }
                .padding(36)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private func timerDiameter(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.43, 280), 480)
    }

    private func timerFontSize(for size: CGSize) -> CGFloat {
        min(max(timerDiameter(for: size) * 0.23, 58), 108)
    }
}

extension NSColor {
    fileprivate convenience init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
