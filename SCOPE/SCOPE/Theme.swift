import SwiftUI

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

    var background: Color {
        switch self {
        case .light: return Color.white
        case .dark: return Color.black
        }
    }

    var backgroundTop: Color {
        switch self {
        case .light: return Color.white
        case .dark: return Color(red: 0.08, green: 0.08, blue: 0.09)
        }
    }

    var backgroundBottom: Color {
        switch self {
        case .light: return Color(red: 0.97, green: 0.97, blue: 0.98)
        case .dark: return Color(red: 0.04, green: 0.04, blue: 0.05)
        }
    }

    var isDark: Bool {
        self == .dark
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
        case .light: return Color.blue
        case .dark: return Color.blue
        }
    }
}
