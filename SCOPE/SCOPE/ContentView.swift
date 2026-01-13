import SwiftUI
import AppKit

// MARK: - Models

struct ScopeResult {
    var pdfs: [String] = []
    var evidenceDirs: [String] = []
    var zip: String? = nil
    var repoRoot: String
    var runDir: String
}

// MARK: - Repo Locator (saved path + quick heuristics)

enum ScopeRepoError: Error {
    case notFound
    case invalidRepo
}

final class ScopeRepoLocator {
    static let appSupportDir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SCOPE", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let savedRepoPathFile: URL = {
        appSupportDir.appendingPathComponent("repo_path.txt")
    }()

    static func isRepoRoot(_ path: String) -> Bool {
        let root = URL(fileURLWithPath: path)
        let batch = root.appendingPathComponent("batch.py").path
        let shipRO = root.appendingPathComponent("scripts/ship_ro.sh").path
        let shipEN = root.appendingPathComponent("scripts/ship_en.sh").path
        let runner = root.appendingPathComponent("scripts/scope_run.sh").path

        return FileManager.default.fileExists(atPath: batch)
            && FileManager.default.fileExists(atPath: shipRO)
            && FileManager.default.fileExists(atPath: shipEN)
            && FileManager.default.fileExists(atPath: runner)
    }

    static func readSavedRepoPath() -> String? {
        guard let data = try? Data(contentsOf: savedRepoPathFile),
              let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    static func saveRepoPath(_ path: String) {
        let s = path.trimmingCharacters(in: .whitespacesAndNewlines)
        try? s.data(using: .utf8)?.write(to: savedRepoPathFile, options: .atomic)
    }

    static func defaultCandidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Desktop/deterministic-website-audit",
            "\(home)/Documents/deterministic-website-audit",
            "\(home)/deterministic-website-audit"
        ]
    }

    static func locateRepo() throws -> String {
        if let saved = readSavedRepoPath(), isRepoRoot(saved) {
            return saved
        }
        for c in defaultCandidates() where isRepoRoot(c) {
            return c
        }
        throw ScopeRepoError.notFound
    }
}

// MARK: - ContentView

struct ContentView: View {

    // Inputs
    @State private var urls: String = ""
    @State private var campaign: String = ""
    @State private var lang: String = "ro"      // ro|en|both
    @State private var cleanup: Bool = true

    // Runtime state
    @State private var isRunning: Bool = false
    @State private var logOutput: String = ""
    @State private var lastExitCode: Int32? = nil

    // Results
    @State private var result: ScopeResult? = nil
    @State private var selectedPDF: String? = nil

    // Run dirs
    @State private var currentRunDir: String? = nil

    // MARK: - Helpers (UI)

    func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .warning
        a.runModal()
    }

    func statusLabel(for code: Int32) -> String {
        switch code {
        case 0: return "OK"
        case 1: return "BROKEN"
        case 2: return "FATAL"
        default: return "UNKNOWN"
        }
    }

    // MARK: - Finder actions

    func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Variant B: reveal in Finder + open in default PDF viewer (Preview)
    func revealAndOpenPDF(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSWorkspace.shared.open(url)
        }
    }

    func openLogsFolder() {
        // 1) If we have a run dir, open logs folder
        if let runDir = currentRunDir {
            let logsDir = URL(fileURLWithPath: runDir).appendingPathComponent("logs")
            if FileManager.default.fileExists(atPath: logsDir.path) {
                NSWorkspace.shared.open(logsDir)
                return
            }
        }

        // 2) Fallback: open SCOPE app support folder
        NSWorkspace.shared.open(ScopeRepoLocator.appSupportDir)
    }

    func openEvidenceFolder() {
        // Best: folder of selected PDF
        if let pdf = selectedPDF {
            let folder = URL(fileURLWithPath: pdf).deletingLastPathComponent().path
            openFolder(folder)
            return
        }
        // Next: open repo reports folder
        if let repo = try? ScopeRepoLocator.locateRepo() {
            let reports = URL(fileURLWithPath: repo).appendingPathComponent("reports").path
            openFolder(reports)
            return
        }
        // fallback
        openLogsFolder()
    }

    func openZIPIfAny() {
        guard let z = result?.zip else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: z)])
    }

    // MARK: - Repo chooser

    func setRepoPath() {
        let panel = NSOpenPanel()
        panel.title = "Select deterministic-website-audit repo folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if ScopeRepoLocator.isRepoRoot(path) {
                ScopeRepoLocator.saveRepoPath(path)
                alert("Repo saved", "Repo path saved:\n\(path)")
            } else {
                alert("Invalid repo folder",
                      "Selected folder is not a valid repo root.\n\nMust contain:\n- batch.py\n- scripts/ship_ro.sh\n- scripts/ship_en.sh\n- scripts/scope_run.sh")
            }
        }
    }

    // MARK: - Core: Run audit

    func writeTargetsFile(from raw: String) -> String? {
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("scope_targets.txt")
        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.data(using: .utf8)?.write(to: tmp, options: .atomic)
            return tmp.path
        } catch {
            return nil
        }
    }

    func ensureExecutable(_ path: String) {
        // best-effort chmod +x
        let p = Process()
        p.launchPath = "/bin/chmod"
        p.arguments = ["+x", path]
        try? p.run()
        p.waitUntilExit()
    }

    func discoverPDFs(repoRoot: String, campaignLabel: String, startedAt: Date) -> [String] {
        // Search repoRoot/reports/<campaignLabel>/**/audit.pdf newer than run start
        let base = URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("reports")
            .appendingPathComponent(campaignLabel.isEmpty ? "Default" : campaignLabel)

        guard FileManager.default.fileExists(atPath: base.path) else { return [] }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var pdfs: [(String, Date)] = []

        for case let url as URL in enumerator {
            if url.lastPathComponent.lowercased() == "audit.pdf" {
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let m = attrs?.contentModificationDate ?? Date.distantPast
                if m >= startedAt.addingTimeInterval(-2) { // small slack
                    pdfs.append((url.path, m))
                }
            }
        }

        // Sort newest first, but keep stable order
        pdfs.sort { $0.1 > $1.1 }
        return pdfs.map { $0.0 }
    }

    func runAudit() {
        guard !isRunning else { return }

        guard let targetsPath = writeTargetsFile(from: urls) else {
            alert("Missing URLs", "Paste at least one URL (one per line).")
            return
        }

        let campaignLabel = campaign.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeCampaign = campaignLabel.isEmpty ? "Default" : campaignLabel

        let repoRoot: String
        do {
            repoRoot = try ScopeRepoLocator.locateRepo()
        } catch {
            alert("Repo not found",
                  "Could not locate deterministic-website-audit repo.\n\nFix:\n1) Click “Set Repo…” and select the repo folder.")
            return
        }

        let runner = URL(fileURLWithPath: repoRoot).appendingPathComponent("scripts/scope_run.sh").path
        guard FileManager.default.fileExists(atPath: runner) else {
            alert("Runner missing", "Missing:\n\(runner)")
            return
        }
        ensureExecutable(runner)

        // Create run dir under Application Support/SCOPE/runs/<timestamp>
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "_")

        let runDirURL = ScopeRepoLocator.appSupportDir
            .appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent(ts, isDirectory: true)

        let logsDir = runDirURL.appendingPathComponent("logs", isDirectory: true)
        let outDir = runDirURL.appendingPathComponent("out", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            alert("Cannot create run folders", "\(error)")
            return
        }

        currentRunDir = runDirURL.path
        isRunning = true
        lastExitCode = nil
        logOutput = ""
        result = nil
        selectedPDF = nil

        let startedAt = Date()

        // Launch runner
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        process.launchPath = "/bin/bash"
        process.arguments = [
            runner,
            targetsPath,
            lang,
            safeCampaign,
            cleanup ? "1" : "0"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                logOutput.append(text)
            }
        }

        process.terminationHandler = { p in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                lastExitCode = p.terminationStatus
                isRunning = false

                // Discover outputs
                let pdfs = discoverPDFs(repoRoot: repoRoot, campaignLabel: safeCampaign, startedAt: startedAt)

                var evidenceDirs: [String] = []
                for pdf in pdfs {
                    let folder = URL(fileURLWithPath: pdf).deletingLastPathComponent().path
                    evidenceDirs.append(folder)
                }

                result = ScopeResult(
                    pdfs: pdfs,
                    evidenceDirs: evidenceDirs,
                    zip: nil,
                    repoRoot: repoRoot,
                    runDir: runDirURL.path
                )

                selectedPDF = pdfs.first
            }
        }

        do {
            try process.run()
        } catch {
            isRunning = false
            alert("Failed to start runner", "\(error)")
        }
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("SCOPE")
                .font(.largeTitle)
                .bold()

            Text("Audit decizional – operator mode")
                .foregroundColor(.secondary)

            Divider()

            Text("URL-uri (un URL pe linie)")
                .bold()

            TextEditor(text: $urls)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .border(Color.gray.opacity(0.3))

            HStack {
                Text("Campaign")
                TextField("ex: Client ABC", text: $campaign)
            }

            HStack {
                Text("Language")

                Picker("", selection: $lang) {
                    Text("RO").tag("ro")
                    Text("EN").tag("en")
                    Text("Both").tag("both")
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Toggle("Cleanup temporary files", isOn: $cleanup)

            Divider()

            // Actions row
            HStack(spacing: 12) {

                Button(isRunning ? "Running…" : "Run Audit") { runAudit() }
                    .disabled(isRunning || urls.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Set Repo…") { setRepoPath() }
                    .disabled(isRunning)

                Button("Open Logs") { openLogsFolder() }
                    .disabled(isRunning == false && currentRunDir == nil)

                Button("Open Evidence") { openEvidenceFolder() }
                    .disabled(isRunning)

                Button("Open ZIP") { openZIPIfAny() }
                    .disabled(isRunning || result?.zip == nil)

                // PDF: best UX
                if let pdfs = result?.pdfs, !pdfs.isEmpty {

                    if pdfs.count > 1 {
                        Picker("", selection: $selectedPDF) {
                            ForEach(pdfs, id: \.self) { path in
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .tag(Optional(path))
                            }
                        }
                        .frame(maxWidth: 260)
                    }

                    Button("Open PDF") {
                        if let pdfPath = selectedPDF ?? pdfs.first {
                            revealAndOpenPDF(pdfPath)
                        }
                    }
                    .disabled(isRunning)

                } else {

                    Button("Open PDF") { }
                        .disabled(true)
                }

                Spacer()

                if let code = lastExitCode {
                    Text(statusLabel(for: code))
                        .font(.headline)
                        .foregroundColor(code == 0 ? .green : (code == 1 ? .orange : .red))
                }
            }

            // Log output
            TextEditor(text: $logOutput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .border(Color.gray.opacity(0.2))
                .disabled(true)

        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 720)
    }
}
