import SwiftUI

#if os(macOS)
import AppKit

struct WindowEventObserver: NSViewRepresentable {
    let onDeminiaturize: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.handleDeminiaturize),
                name: NSWindow.didDeminiaturizeNotification,
                object: window
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDeminiaturize: onDeminiaturize)
    }

    final class Coordinator: NSObject {
        let onDeminiaturize: () -> Void

        init(onDeminiaturize: @escaping () -> Void) {
            self.onDeminiaturize = onDeminiaturize
        }

        @objc func handleDeminiaturize() {
            onDeminiaturize()
        }
    }
}
#endif
