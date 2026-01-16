import SwiftUI

struct NeonPalette {
    let blue: Color
    let cyan: Color
    let lime: Color
    let amber: Color

    var spectrum: [Color] {
        [blue, cyan, lime, amber, blue]
    }
}

enum NeonRole {
    case primary
    case secondary
    case success
    case warn
}

enum Theme: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }

    var isDark: Bool {
        self == .dark
    }

    var neonPalette: NeonPalette {
        switch self {
        case .light:
            return NeonPalette(
                blue: Color(red: 0.24, green: 0.46, blue: 0.86).opacity(0.75),
                cyan: Color(red: 0.40, green: 0.80, blue: 0.90).opacity(0.65),
                lime: Color(red: 0.62, green: 0.86, blue: 0.52).opacity(0.55),
                amber: Color(red: 0.92, green: 0.76, blue: 0.36).opacity(0.55)
            )
        case .dark:
            return NeonPalette(
                blue: Color(red: 0.20, green: 0.46, blue: 0.98),
                cyan: Color(red: 0.24, green: 0.86, blue: 0.98),
                lime: Color(red: 0.68, green: 0.98, blue: 0.46),
                amber: Color(red: 0.98, green: 0.78, blue: 0.25)
            )
        }
    }

    var neonGradient: AngularGradient {
        AngularGradient(gradient: Gradient(colors: neonPalette.spectrum), center: .center)
    }

    func glowColor(for role: NeonRole) -> Color {
        switch role {
        case .primary: return neonPalette.blue
        case .secondary: return neonPalette.cyan
        case .success: return neonPalette.lime
        case .warn: return neonPalette.amber
        }
    }

    var panelStrokeGradient: LinearGradient {
        let colors = isDark
            ? [neonPalette.blue.opacity(0.35), neonPalette.cyan.opacity(0.20), neonPalette.lime.opacity(0.18)]
            : [neonPalette.blue.opacity(0.18), neonPalette.cyan.opacity(0.12), neonPalette.lime.opacity(0.10)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var background: Color {
        switch self {
        case .light: return Color.white
        case .dark: return Color.black
        }
    }

    var backgroundTop: Color {
        switch self {
        case .light: return Color(red: 0.99, green: 0.99, blue: 1.0)
        case .dark: return Color(red: 0.07, green: 0.07, blue: 0.08)
        }
    }

    var backgroundBottom: Color {
        switch self {
        case .light: return Color(red: 0.96, green: 0.96, blue: 0.98)
        case .dark: return Color(red: 0.04, green: 0.04, blue: 0.05)
        }
    }

    var cardBackground: Color {
        switch self {
        case .light: return Color.black.opacity(0.03)
        case .dark: return Color.white.opacity(0.05)
        }
    }

    var border: Color {
        switch self {
        case .light: return Color.black.opacity(0.08)
        case .dark: return Color.white.opacity(0.10)
        }
    }

    var textPrimary: Color {
        switch self {
        case .light: return Color.black
        case .dark: return Color.white
        }
    }

    var textEditorBackground: Color {
        switch self {
        case .light: return Color.white
        case .dark: return Color.white.opacity(0.06)
        }
    }

    var accent: Color {
        switch self {
        case .light: return neonPalette.blue.opacity(0.7)
        case .dark: return neonPalette.blue
        }
    }

    var palettePrimary: Color { neonPalette.blue }
    var paletteSecondary: Color { neonPalette.cyan }
    var paletteTertiary: Color { neonPalette.lime }
    var paletteWarm: Color { neonPalette.amber }

    var haloGradient: [Color] { neonPalette.spectrum }
}
