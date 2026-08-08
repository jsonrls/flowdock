import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum FlowTheme {
    static let canvas = adaptive(light: "F5F5F5", dark: "121212")
    static let sidebar = adaptive(light: "FFFFFF", dark: "171717")
    static let card = adaptive(light: "FFFFFF", dark: "1C1C1C")
    static let cardRaised = adaptive(light: "EEEEEC", dark: "252525")
    static let stroke = adaptive(light: "DDDDDA", dark: "30302E")
    static let text = adaptive(light: "191A18", dark: "F5F5F5")
    static let secondary = adaptive(light: "686A65", dark: "A0A19B")
    static let accent = Color(hex: "FF8A4C")
    static let lime = adaptive(light: "718D32", dark: "B8D66D")

    private static func adaptive(light: String, dark: String) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return NSColor(hex: match == .darkAqua ? dark : light)
            })
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct FlowdockLogoMark: View {
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let logoURL = Bundle.module.url(forResource: "FlowdockLogo", withExtension: "png"),
                let logoImage = NSImage(contentsOf: logoURL)
            {
                Image(nsImage: logoImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(FlowTheme.accent)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: size * 0.43, weight: .bold))
                        .foregroundStyle(Color(hex: "21160F"))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

struct CardSurface: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(FlowTheme.card.opacity(0.58))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3), FlowTheme.stroke.opacity(0.82),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.055), radius: 14, y: 7)
    }
}

extension View {
    func cardSurface(padding: CGFloat = 20) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

struct SectionEyebrow: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(FlowTheme.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(FlowTheme.secondary.opacity(0.8))
            }
        }
    }
}

struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}
