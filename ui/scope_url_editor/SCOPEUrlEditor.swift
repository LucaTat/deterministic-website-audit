import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var textView: NSTextView!
    private let filePath: String

    init(filePath: String) {
        self.filePath = filePath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        let w: CGFloat = 900
        let h: CGFloat = 620
        let rect = NSRect(x: screenFrame.midX - w/2, y: screenFrame.midY - h/2, width: w, height: h)

        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SCOPE"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        // Header
        let label = NSTextField(labelWithString: "Lipește URL-urile (un URL pe linie).")
        label.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        label.frame = NSRect(x: 24, y: h - 64, width: w - 48, height: 28)
        label.autoresizingMask = [.width, .minYMargin]
        content.addSubview(label)

        // Text area (scroll)
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 86, width: w - 48, height: h - 170))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]

        textView = NSTextView(frame: scroll.bounds)
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.autoresizingMask = [.width, .height]
        scroll.documentView = textView
        content.addSubview(scroll)

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.frame = NSRect(x: w - 24 - 200, y: 24, width: 90, height: 32)
        cancelBtn.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r" // Enter saves
        saveBtn.frame = NSRect(x: w - 24 - 100, y: 24, width: 90, height: 32)
        saveBtn.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(saveBtn)

        // Load initial content
        if let data = FileManager.default.contents(atPath: filePath),
           let str = String(data: data, encoding: .utf8) {
            textView.string = str
        } else {
            textView.string = ""
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing window counts as Cancel
        exit(1)
    }

    @objc private func save() {
        do {
            try textView.string.write(toFile: filePath, atomically: true, encoding: .utf8)
            exit(0)
        } catch {
            exit(2)
        }
    }

    @objc private func cancel() {
        exit(1)
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { exit(2) }
let filePath = args[1]

let app = NSApplication.shared
let delegate = AppDelegate(filePath: filePath)
app.delegate = delegate
app.run()
