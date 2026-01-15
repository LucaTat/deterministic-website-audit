import SwiftUI

struct SplashView: View {
    let onFinished: () -> Void

    @State private var revealedCount: Int = 0
    @State private var didFinish: Bool = false
    @AppStorage("scopeTheme") private var themeRaw: String = Theme.light.rawValue

    private let title: String = "SCOPE"
    private let revealInterval: TimeInterval = 0.12
    private let finishDelay: TimeInterval = 0.45
    private var theme: Theme { Theme(rawValue: themeRaw) ?? .light }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            HStack(spacing: 0) {
                ForEach(Array(title.enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .opacity(index < revealedCount ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: revealedCount)
                }
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

        let total = title.count
        for index in 1...total {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * revealInterval) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    revealedCount = index
                }
                if index == total {
                    DispatchQueue.main.asyncAfter(deadline: .now() + finishDelay) {
                        onFinished()
                    }
                }
            }
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
