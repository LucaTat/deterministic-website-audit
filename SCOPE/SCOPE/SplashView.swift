import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

struct SplashView: View {
    let onFinished: () -> Void

    @State private var didFinish: Bool = false
    @State private var revealProgress: CGFloat = 0.0
    @State private var trackingValue: CGFloat = 6.0
    @State private var textOpacity: Double = 0.05
    @State private var textBlur: CGFloat = 0.6
    @State private var subtitleOpacity: Double = 0.0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var didPlayChime: Bool = false
    @AppStorage("scopeTheme") private var themeRaw: String = Theme.light.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String = "SCOPE"
    private let revealDuration: TimeInterval = 0.9
    private let finishDelay: TimeInterval = 0.25
    private let settleDuration: TimeInterval = 0.18
    private let postSettleHold: TimeInterval = 0.45
    private var theme: Theme { Theme(rawValue: themeRaw) ?? .light }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

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
        .onAppear {
            startReveal()
        }
    }

    private func startReveal() {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: revealDuration)) {
            revealProgress = 1.0
            trackingValue = 1.0
        }
        withAnimation(.easeInOut(duration: revealDuration * 0.6)) {
            textOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + revealDuration) {
            playLaunchChimeIfNeeded()
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
        guard !didPlayChime else { return }
        guard !reduceMotion else { didPlayChime = true; return }

        defer { didPlayChime = true }

        guard let url = Bundle.main.url(forResource: "launch_chime", withExtension: "wav") else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.12
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            // silent fail
        }
    }
}
