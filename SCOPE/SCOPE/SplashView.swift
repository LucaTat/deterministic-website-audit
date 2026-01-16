import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SplashView: View {
    let allowSound: Bool
    let triggerID: UUID
    let onFinished: () -> Void

    private enum Phase {
        case idle
        case iconIn
        case ringDraw
        case wordmark
        case subtitle
        case done
    }

    @State private var phase: Phase = .idle
    @State private var ringTrim: CGFloat = 0.0
    @State private var ringOpacity: Double = 0.0
    @State private var iconOpacity: Double = 0.0
    @State private var iconScale: CGFloat = 0.92
    @State private var wordmarkOpacity: Double = 0.0
    @State private var wordmarkReveal: CGFloat = 0.0
    @State private var subtitleOpacity: Double = 0.0
    @State private var didPlayChime: Bool = false
    @State private var didStartReveal: Bool = false
    @State private var noiseImage: Image?
    @AppStorage("scopeTheme") private var themeRaw: String = Theme.light.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String = "SCOPE"
    private var theme: Theme { Theme(rawValue: themeRaw) ?? .light }
    private var isFast: Bool { !allowSound }

    private var iconDuration: TimeInterval { isFast ? 0.25 : 0.55 }
    private var ringDuration: TimeInterval { isFast ? 0.25 : 0.9 }
    private var wordmarkDuration: TimeInterval { isFast ? 0.18 : 0.4 }
    private var subtitleDelay: TimeInterval { isFast ? 0.06 : 0.12 }
    private var holdDelay: TimeInterval { isFast ? 0.10 : 0.25 }
    private var heroSize: CGFloat { isFast ? 120 : 140 }

    var body: some View {
        ZStack {
            backgroundLayer
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: ringTrim)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: theme.haloGradient),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: heroSize + 28, height: heroSize + 28)
                        .opacity(ringOpacity)
                        .drawingGroup()

                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: heroSize, height: heroSize)
                            .opacity(iconOpacity)
                            .scaleEffect(iconScale)
                    }
                }

                Text(title)
                    .font(.system(size: 68, weight: .semibold))
                    .tracking(isFast ? 2 : 1)
                    .foregroundColor(theme.textPrimary)
                    .opacity(wordmarkOpacity)
                    .mask(
                        Rectangle()
                            .scaleEffect(x: wordmarkReveal, y: 1.0, anchor: .leading)
                    )

                Text("Deterministic Website Audit")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(theme.textPrimary.opacity(0.6))
                    .opacity(subtitleOpacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .preferredColorScheme(theme.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: themeRaw)
        .onAppear {
            resetAndStart()
        }
        .onChange(of: triggerID) { _, _ in
            resetAndStart()
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [theme.backgroundTop, theme.backgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(theme.isDark ? 0.0 : 0.55),
                    Color.clear
                ]),
                center: .center,
                startRadius: 80,
                endRadius: 420
            )

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.black.opacity(theme.isDark ? 0.45 : 0.10)
                ]),
                center: .center,
                startRadius: 90,
                endRadius: 520
            )

            if let noiseImage {
                noiseImage
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .opacity(theme.isDark ? 0.05 : 0.02)
                    .blendMode(.softLight)
            }
        }
        .compositingGroup()
    }

    private func resetAndStart() {
        ensureNoiseImage()
        withAnimation(nil) {
            phase = .idle
            ringTrim = 0.0
            ringOpacity = 0.0
            iconOpacity = 0.0
            iconScale = 0.92
            wordmarkOpacity = 0.0
            wordmarkReveal = 0.0
            subtitleOpacity = 0.0
            didPlayChime = false
            didStartReveal = false
        }
        startSequence()
    }

    private func startSequence() {
        if reduceMotion {
            iconOpacity = 1.0
            iconScale = 1.0
            ringOpacity = 1.0
            ringTrim = 1.0
            wordmarkOpacity = 1.0
            wordmarkReveal = 1.0
            subtitleOpacity = 1.0
            return
        }

        phase = .iconIn
        withAnimation(.easeInOut(duration: iconDuration)) {
            iconOpacity = 1.0
            iconScale = 1.0
        }

        phase = .ringDraw
        ringOpacity = 1.0
        withAnimation(.easeInOut(duration: ringDuration)) {
            ringTrim = 1.0
        }

        if !didStartReveal {
            didStartReveal = true
            DispatchQueue.main.async {
                playLaunchChimeIfNeeded()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + ringDuration * 0.7) {
            phase = .wordmark
            withAnimation(.easeInOut(duration: wordmarkDuration)) {
                wordmarkOpacity = 1.0
                wordmarkReveal = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + wordmarkDuration + subtitleDelay) {
                phase = .subtitle
                withAnimation(.easeInOut(duration: isFast ? 0.12 : 0.2)) {
                    subtitleOpacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay) {
                    phase = .done
                    onFinished()
                }
            }
        }
    }

    private func ensureNoiseImage() {
        guard noiseImage == nil else { return }
        let size = 96
        let pixelsCount = size * size
        var pixels = [UInt8](repeating: 0, count: pixelsCount * 4)
        var seed: UInt32 = 0x12345678

        for i in 0..<pixelsCount {
            seed = 1664525 &* seed &+ 1013904223
            let value = UInt8((seed >> 24) & 0xFF)
            let offset = i * 4
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = size * 4
        if let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() {
            noiseImage = Image(decorative: cgImage, scale: 1)
        }
    }

    private func playLaunchChimeIfNeeded() {
        guard allowSound else { return }
        guard !didPlayChime else { return }
        guard !reduceMotion else { didPlayChime = true; return }

        defer { didPlayChime = true }
        ChimePlayer.shared.play()
    }
}
