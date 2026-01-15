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
