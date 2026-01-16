import SwiftUI

struct NeonOutlineButtonStyle: ButtonStyle {
    let theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        NeonOutlineButton(
            configuration: configuration,
            theme: theme,
            reduceMotion: reduceMotion
        )
    }
}

private struct NeonOutlineButton: View {
    let configuration: ButtonStyle.Configuration
    let theme: Theme
    let reduceMotion: Bool

    @State private var isHovering: Bool = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.panelStrokeGradient, lineWidth: 1)
                    .opacity(isHovering ? 0.85 : 0.55)
            )
            .shadow(
                color: theme.glowColor(for: .secondary).opacity(isHovering && theme.isDark ? 0.35 : 0.0),
                radius: isHovering ? 18 : 0,
                x: 0,
                y: 0
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.18), value: isHovering)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                if reduceMotion {
                    isHovering = false
                } else {
                    isHovering = hovering
                }
            }
    }
}

struct NeonPrimaryButtonStyle: ButtonStyle {
    let theme: Theme
    let isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        NeonPrimaryButton(
            configuration: configuration,
            theme: theme,
            isRunning: isRunning,
            reduceMotion: reduceMotion
        )
    }
}

private struct NeonPrimaryButton: View {
    let configuration: ButtonStyle.Configuration
    let theme: Theme
    let isRunning: Bool
    let reduceMotion: Bool

    @State private var isHovering: Bool = false
    @State private var shimmerPhase: CGFloat = -0.6
    @State private var pulse: Bool = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.neonGradient, lineWidth: 1.5)
                    .opacity(isHovering ? 0.95 : 0.75)
                    .overlay(shimmerOverlay)
            )
            .shadow(
                color: theme.glowColor(for: .primary).opacity(glowOpacity),
                radius: glowRadius,
                x: 0,
                y: 0
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.18), value: isHovering)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                if reduceMotion {
                    isHovering = false
                } else {
                    isHovering = hovering
                    if hovering { startShimmer() }
                }
            }
            .onChange(of: isRunning) { _, newValue in
                if newValue { startPulse() }
            }
            .onAppear {
                if isRunning { startPulse() }
            }
    }

    private var glowOpacity: Double {
        if !theme.isDark { return 0.0 }
        if isRunning { return pulse ? 0.55 : 0.25 }
        return isHovering ? 0.45 : 0.2
    }

    private var glowRadius: CGFloat {
        if isRunning { return pulse ? 22 : 14 }
        return isHovering ? 20 : 10
    }

    private var shimmerOverlay: some View {
        Group {
            if !reduceMotion && isHovering {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(theme.isDark ? 0.25 : 0.15),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
                    .offset(x: shimmerPhase * 120)
                    .mask(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(lineWidth: 1.5)
                    )
            }
        }
    }

    private func startShimmer() {
        shimmerPhase = -0.6
        withAnimation(.easeInOut(duration: 1.2)) {
            shimmerPhase = 0.6
        }
    }

    private func startPulse() {
        guard !reduceMotion else { return }
        pulse = false
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

struct NeonPanel: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.panelStrokeGradient, lineWidth: 1)
            )
            .shadow(
                color: theme.isDark ? theme.glowColor(for: .primary).opacity(0.08) : .clear,
                radius: theme.isDark ? 18 : 0,
                x: 0,
                y: 0
            )
    }
}

struct NeonStatusLine: View {
    let theme: Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    var body: some View {
        Rectangle()
            .fill(theme.neonGradient)
            .frame(height: 2)
            .opacity(pulseOpacity)
            .animation(reduceMotion ? .none : .easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: pulse)
            .onAppear {
                if !reduceMotion && theme.isDark {
                    pulse.toggle()
                }
            }
    }

    private var pulseOpacity: Double {
        if !theme.isDark { return 0.45 }
        return pulse ? 0.9 : 0.5
    }
}
