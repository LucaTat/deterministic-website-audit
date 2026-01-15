import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

struct SplashView: View {
    let allowSound: Bool
    let triggerID: UUID
    let onFinished: () -> Void

    @State private var didFinish: Bool = false
    @State private var revealProgress: CGFloat = 0.0
    @State private var trackingValue: CGFloat = 6.0
    @State private var textOpacity: Double = 0.05
    @State private var textBlur: CGFloat = 0.6
    @State private var subtitleOpacity: Double = 0.0
    @State private var didPlayChime: Bool = false
    @State private var didStartReveal: Bool = false
    @State private var noiseImage: Image?
    @AppStorage("scopeTheme") private var themeRaw: String = Theme.light.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String = "SCOPE"
    private var theme: Theme { Theme(rawValue: themeRaw) ?? .light }
    private var revealDuration: TimeInterval { allowSound ? 1.15 : 0.78 }
    private var finishDelay: TimeInterval { allowSound ? 0.3 : 0.18 }
    private var settleDuration: TimeInterval { allowSound ? 0.22 : 0.14 }
    private var postSettleHold: TimeInterval { allowSound ? 0.55 : 0.2 }

    var body: some View {
        ZStack {
            ZStack {
                LinearGradient(
                    colors: [theme.backgroundTop, theme.backgroundBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(theme.isDark ? 0.45 : 0.10)
                    ]),
                    center: .center,
                    startRadius: 90,
                    endRadius: 520
                )
                .ignoresSafeArea()

                if let noiseImage {
                    noiseImage
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .opacity(theme.isDark ? 0.05 : 0.02)
                        .blendMode(.softLight)
                        .ignoresSafeArea()
                }
            }
            .compositingGroup()

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 68, weight: .semibold))
                        .tracking(trackingValue)
                        .foregroundColor(theme.textPrimary)
                        .opacity(textOpacity)
                        .blur(radius: textBlur)
                        .mask(
                            Rectangle()
                                .frame(width: width * revealProgress, height: height)
                                .offset(x: -(width * (1.0 - revealProgress)) / 2.0)
                        )

                    Text("Deterministic Website Audit")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(theme.textPrimary.opacity(0.6))
                        .opacity(subtitleOpacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .animation(.easeInOut(duration: 0.2), value: themeRaw)
        .onChange(of: triggerID) { _, _ in
            resetAndStart()
        }
    }

    private func resetAndStart() {
        ensureNoiseImage()
        withAnimation(nil) {
            didFinish = false
            revealProgress = 0.0
            trackingValue = 6.0
            textOpacity = 0.05
            textBlur = 0.6
            subtitleOpacity = 0.0
            didPlayChime = false
            didStartReveal = false
        }
        startReveal()
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

    private func startReveal() {
        guard !didFinish else { return }
        didFinish = true
        if !didStartReveal {
            didStartReveal = true
            DispatchQueue.main.async {
                playLaunchChimeIfNeeded()
            }
        }
        withAnimation(.easeInOut(duration: revealDuration)) {
            revealProgress = 1.0
            trackingValue = 1.0
        }
        withAnimation(.easeInOut(duration: revealDuration * 0.6)) {
            textOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDuration + finishDelay) {
            withAnimation(.easeInOut(duration: settleDuration)) {
                textOpacity = 1.0
                textBlur = 0.0
                subtitleOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + settleDuration + postSettleHold) {
                onFinished()
            }
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
