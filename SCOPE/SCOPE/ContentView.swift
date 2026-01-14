import SwiftUI
import AppKit

// MARK: - Repo locator

enum ScopeRepoError: Error {
    case notFound
    case invalidRepo
}

struct ScopeRepoLocator {
    static var appSupportDir: String {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?.path
        let dir = (base ?? NSHomeDirectory() + "/Library/Application Support") + "/SCOPE"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    static var savedRepoPathFile: String {
        appSupportDir + "/repo_path.txt"
    }

    static func isRepoRoot(_ path: String) -> Bool {
        let fm = FileManager.default
        let required = [
            "batch.py",
            "scripts/scope_run.sh",
            "scripts/ship_ro.sh",
            "scripts/ship_en.sh"
        ]
        for r in required {
            if !fm.fileExists(atPath: (path as NSString).appendingPathComponent(r)) { return false }
        }
        return true
    }

    static func locateRepo() throws -> String {
        // 1) saved
        if let saved = try? String(contentsOfFile: savedRepoPathFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty,
           isRepoRoot(saved) {
            return saved
        }

        // 2) heuristics
        let candidates = [
            NSHomeDirectory() + "/Desktop/deterministic-website-audit",
            NSHomeDirectory() + "/Documents/deterministic-website-audit"
        ]
        for c in candidates where isRepoRoot(c) { return c }

        throw ScopeRepoError.notFound
    }

    static func saveRepoPath(_ path: String) throws {
        guard isRepoRoot(path) else { throw ScopeRepoError.invalidRepo }
        try path.write(toFile: savedRepoPathFile, atomically: true, encoding: .utf8)
    }
}

// MARK: - Result model

struct ScopeResult {
    var pdfPaths: [String] = []
    var logFile: String? = nil
    var zipByLang: [String: String] = [:]
    var outDirByLang: [String: String] = [:]
    var shipDirByLang: [String: String] = [:]
}

// MARK: - ContentView

struct ContentView: View {
    // Inputs
    @State private var urlsText: String = ""
    @State private var campaign: String = ""
    @State private var lang: String = "ro" // ro|en|both
    @State private var cleanup: Bool = true

    // Runtime state
    @State private var isRunning: Bool = false
    @State private var logOutput: String = ""
    @State private var lastExitCode: Int32? = nil

    // Results
    @State private var result: ScopeResult? = nil
    @State private var selectedPDF: String? = nil
    @State private var selectedZIPLang: String = "ro"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Audit decizional – operator mode")
                    .font(.title3)
                    .foregroundColor(.primary)

                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL-uri (un URL pe linie)")
                    .font(.headline)

                TextEditor(text: $urlsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Campaign")
                        .frame(width: 80, alignment: .leading)
                    TextField("ex: Client ABC", text: $campaign)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    Text("Language")
                        .frame(width: 80, alignment: .leading)

                    Picker("", selection: $lang) {
                        Text("RO").tag("ro")
                        Text("EN").tag("en")
                        Text("RO + EN (2 deliverables)").tag("both")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Toggle("Cleanup temporary files", isOn: $cleanup)
                        .toggleStyle(.checkbox)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("Run Audit") { runAudit() }
                    .disabled(isRunning || !hasAtLeastOneValidURL())

                Button("Set Repo…") { setRepoPath() }
                    .disabled(isRunning)

                Button("Open Logs") { openLogs() }
                    .disabled(isRunning == false && (result?.logFile == nil))

                Button("Open Evidence") { openEvidence() }
                    .disabled(isRunning == false && !canOpenEvidence())

                if lang == "both" {
                    Button("Open ZIP (RO)") { openZIP(forLang: "ro") }
                        .disabled(isRunning || zipPath(forLang: "ro") == nil)
                    Button("Open ZIP (EN)") { openZIP(forLang: "en") }
                        .disabled(isRunning || zipPath(forLang: "en") == nil)
                } else {
                    Button("Open ZIP") { openZIPIfAny() }
                        .disabled(isRunning || currentZipPath() == nil)
                }

                Text("Opens Finder and selects the ZIP file")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Button("Open Output Folder") { openOutputFolder() }
                    .disabled(isRunning || outputFolderPath() == nil)

                if lang == "both" {
                    Button("Open Ship Folder (RO)") { openShipFolder(forLang: "ro") }
                        .disabled(isRunning || shipDirPath(forLang: "ro") == nil)
                    Button("Open Ship Folder (EN)") { openShipFolder(forLang: "en") }
                        .disabled(isRunning || shipDirPath(forLang: "en") == nil)
                } else {
                    Button("Open Ship Folder") { openShipFolder(forLang: lang) }
                        .disabled(isRunning || shipDirPath(forLang: lang) == nil)
                }

                // PDF picker + open
                if let pdfs = result?.pdfPaths, !pdfs.isEmpty {
                    if pdfs.count > 1 {
                        Picker("", selection: $selectedPDF) {
                            ForEach(pdfs, id: \.self) { path in
                                Text(displayName(forPath: path))
                                    .tag(Optional(path))
                            }
                        }
                        .frame(maxWidth: 360)
                    } else {
                        // ensure selection
                        Color.clear.onAppear {
                            selectedPDF = pdfs.first
                        }
                    }

                    Button("Open PDF") {
                        if let p = selectedPDF ?? pdfs.first {
                            revealAndOpenFile(p)
                        }
                    }
                    .disabled(isRunning)
                } else {
                    Button("Open PDF") { }
                        .disabled(true)
                }

                Spacer()

                statusPill
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Log")
                    .font(.headline)

                TextEditor(text: .constant(logOutput))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .disabled(true)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 720)
    }

    // MARK: - Status UI

    private var statusPill: some View {
        let (text, color) = statusTextAndColor()
        return Text(text)
            .font(.headline)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.10))
            .cornerRadius(10)
    }

    private func statusTextAndColor() -> (String, Color) {
        guard let code = lastExitCode else { return ("—", .secondary) }
        if code == 0 { return ("OK", .green) }
        if code == 1 { return ("BROKEN", .orange) }
        if code == 2 { return ("FATAL", .red) }
        return ("CODE \(code)", .secondary)
    }

    // MARK: - URL validation

    private func extractURLs(from text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var urls: [String] = []
        urls.reserveCapacity(lines.count)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            guard let u = URL(string: line) else { continue }
            guard let scheme = u.scheme, (scheme == "http" || scheme == "https") else { continue }
            guard u.host != nil else { continue }

            urls.append(line)
        }

        return urls
    }

    private func hasAtLeastOneValidURL() -> Bool {
        !extractURLs(from: urlsText).isEmpty
    }

    // MARK: - Helpers

    private func displayName(forPath path: String, tailComponents: Int = 3) -> String {
        let parts = (path as NSString).pathComponents
        let tail = parts.suffix(tailComponents)
        return tail.joined(separator: "/")
    }

    private func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func revealAndOpenFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSWorkspace.shared.open(url)
        }
    }

    private func alert(title: String, message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func writeTargetsTempFile() -> String {
        let urls = extractURLs(from: urlsText)
        let content = urls.joined(separator: "\n") + "\n"

        let tmp = FileManager.default.temporaryDirectory
        let path = tmp.appendingPathComponent("scope_targets.txt").path
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: - Finder actions

    private func openLogs() {
        if let log = result?.logFile, FileManager.default.fileExists(atPath: log) {
            revealAndOpenFile(log)
            return
        }

        // fallback: repo deliverables/logs
        if let repo = try? ScopeRepoLocator.locateRepo() {
            let logsDir = (repo as NSString).appendingPathComponent("deliverables/logs")
            if FileManager.default.fileExists(atPath: logsDir) {
                openFolder(logsDir)
                return
            }
        }

        openFolder(ScopeRepoLocator.appSupportDir)
    }

    private func openEvidence() {
        if let e = currentEvidenceDir(), FileManager.default.fileExists(atPath: e) {
            openFolder(e)
            return
        }

        if let repo = try? ScopeRepoLocator.locateRepo() {
            let reports = (repo as NSString).appendingPathComponent("reports")
            if FileManager.default.fileExists(atPath: reports) {
                openFolder(reports)
                return
            }
        }

        openFolder(ScopeRepoLocator.appSupportDir)
    }

    private func openZIPIfAny() {
        guard let zipPath = currentZipPath() else { return }
        revealAndOpenFile(zipPath)
    }

    private func openZIP(forLang lang: String) {
        guard let zipPath = zipPath(forLang: lang) else { return }
        revealAndOpenFile(zipPath)
    }

    // MARK: - Repo chooser

    private func setRepoPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Selectează folderul repo: deterministic-website-audit"

        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                do {
                    try ScopeRepoLocator.saveRepoPath(url.path)
                    self.alert(title: "Repo set", message: url.path)
                } catch {
                    self.alert(title: "Invalid repo", message: "Folderul ales nu pare repo-ul corect.")
                }
            }
        }
    }

    // MARK: - Run audit (sequential)

    private func runAudit() {
        let urls = extractURLs(from: urlsText)
        guard !urls.isEmpty else {
            alert(title: "No valid URLs", message: "Adaugă cel puțin un URL valid (http/https).")
            return
        }

        isRunning = true
        logOutput = ""
        lastExitCode = nil
        result = nil
        selectedPDF = nil
        selectedZIPLang = "ro"

        let baseCampaign = campaign.trimmingCharacters(in: .whitespacesAndNewlines)
        let camp = baseCampaign.isEmpty ? "Default" : baseCampaign

        runRunner(selectedLang: lang, baseCampaign: camp)
    }

    private func runRunner(selectedLang: String, baseCampaign: String) {
        let repoRoot: String
        do {
            repoRoot = try ScopeRepoLocator.locateRepo()
        } catch {
            alert(title: "Repo not found", message: "Apasă Set Repo… și selectează repo-ul corect.")
            isRunning = false
            return
        }

        let targetsFile = writeTargetsTempFile()
        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/scope_run.sh")

        // Build arguments: scope_run.sh <targets> <lang> <campaign> <cleanup>
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [
            scriptPath,
            targetsFile,
            selectedLang,
            baseCampaign,
            cleanup ? "1" : "0"
        ]
        task.currentDirectoryURL = URL(fileURLWithPath: repoRoot)

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self.logOutput += str
                }
            }
        }

        task.terminationHandler = { p in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil

                let code = p.terminationStatus
                self.lastExitCode = code

                let output = self.logOutput
                let hints = self.parseScopeHints(from: output)

                var r = ScopeResult()
                r.logFile = hints.logFile
                r.zipByLang = hints.zipByLang
                r.outDirByLang = hints.outDirByLang
                r.shipDirByLang = hints.shipDirByLang

                // PDFs: find under reports + deliverables/out
                let pdfs = self.discoverPDFs(repoRoot: repoRoot)
                let filtered = self.filterPDFsByLanguage(pdfs, lang: selectedLang)
                r.pdfPaths = (filtered.isEmpty ? pdfs : filtered).sorted()

                self.result = r

                // auto-select first pdf/zip
                if self.selectedPDF == nil { self.selectedPDF = r.pdfPaths.first }
                self.syncSelectedZIPLang(with: r, selectedLang: selectedLang)

                self.isRunning = false
            }
        }

        do {
            try task.run()
        } catch {
            DispatchQueue.main.async {
                self.isRunning = false
                self.alert(title: "Run failed", message: "Nu am putut porni runner-ul.")
            }
        }
    }

    private func parseScopeHints(from output: String) -> (logFile: String?, zipByLang: [String: String], outDirByLang: [String: String], shipDirByLang: [String: String]) {
        var logFile: String? = nil
        var zipByLang: [String: String] = [:]
        var outDirByLang: [String: String] = [:]
        var shipDirByLang: [String: String] = [:]

        for lineSub in output.split(separator: "\n") {
            let line = String(lineSub)
            if line.hasPrefix("SCOPE_LOG_FILE=") {
                logFile = String(line.dropFirst("SCOPE_LOG_FILE=".count))
                continue
            }
            if line.hasPrefix("SCOPE_ZIP_") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = String(parts[0].dropFirst("SCOPE_ZIP_".count)).lowercased()
                    zipByLang[key] = parts[1]
                }
                continue
            }
            if line.hasPrefix("SCOPE_OUT_DIR_") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = String(parts[0].dropFirst("SCOPE_OUT_DIR_".count)).lowercased()
                    outDirByLang[key] = parts[1]
                }
                continue
            }
            if line.hasPrefix("SCOPE_SHIP_DIR_") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = String(parts[0].dropFirst("SCOPE_SHIP_DIR_".count)).lowercased()
                    shipDirByLang[key] = parts[1]
                }
            }
        }

        return (logFile, zipByLang, outDirByLang, shipDirByLang)
    }

    private func availableZipLangs() -> [String]? {
        guard let zips = result?.zipByLang, !zips.isEmpty else { return nil }
        let ordered = ["ro", "en"]
        let known = ordered.filter { zips[$0] != nil }
        if !known.isEmpty { return known }
        return zips.keys.sorted()
    }

    private func zipPath(forLang lang: String) -> String? {
        guard let zips = result?.zipByLang, !zips.isEmpty else { return nil }
        guard let path = zips[lang], FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func currentZipPath() -> String? {
        guard let zips = result?.zipByLang, !zips.isEmpty else { return nil }
        let key = (lang == "both") ? selectedZIPLang : lang
        if let path = zips[key], FileManager.default.fileExists(atPath: path) {
            return path
        }
        for (_, path) in zips where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    private func shipDirPath(forLang lang: String) -> String? {
        guard let dirs = result?.shipDirByLang, !dirs.isEmpty else { return nil }
        guard let path = dirs[lang], FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func openShipFolder(forLang lang: String) {
        guard let path = shipDirPath(forLang: lang) else { return }
        openFolder(path)
    }

    private func outputFolderPath() -> String? {
        guard let repo = try? ScopeRepoLocator.locateRepo() else { return nil }
        let outDir = (repo as NSString).appendingPathComponent("deliverables/out")
        return FileManager.default.fileExists(atPath: outDir) ? outDir : nil
    }

    private func openOutputFolder() {
        guard let path = outputFolderPath() else { return }
        openFolder(path)
    }

    private func currentEvidenceDir() -> String? {
        guard let dirs = result?.outDirByLang, !dirs.isEmpty else { return nil }
        let key = (lang == "both") ? selectedZIPLang : lang
        if let path = dirs[key], FileManager.default.fileExists(atPath: path) {
            return path
        }
        for (_, path) in dirs where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    private func canOpenEvidence() -> Bool {
        if let dir = currentEvidenceDir(), FileManager.default.fileExists(atPath: dir) {
            return true
        }
        if let repo = try? ScopeRepoLocator.locateRepo() {
            let reports = (repo as NSString).appendingPathComponent("reports")
            return FileManager.default.fileExists(atPath: reports)
        }
        return false
    }

    private func syncSelectedZIPLang(with result: ScopeResult, selectedLang: String) {
        if selectedLang == "both" {
            if result.zipByLang["ro"] != nil {
                selectedZIPLang = "ro"
            } else if let first = availableZipLangs()?.first {
                selectedZIPLang = first
            }
        } else if result.zipByLang[selectedLang] != nil {
            selectedZIPLang = selectedLang
        } else if let first = availableZipLangs()?.first {
            selectedZIPLang = first
        }
    }

    // MARK: - Discover artifacts

    private func discoverPDFs(repoRoot: String) -> [String] {
        let fm = FileManager.default
        let roots = [
            (repoRoot as NSString).appendingPathComponent("reports"),
            (repoRoot as NSString).appendingPathComponent("deliverables/out")
        ]

        var found: [String] = []

        for r in roots {
            guard fm.fileExists(atPath: r) else { continue }

            let e = fm.enumerator(at: URL(fileURLWithPath: r), includingPropertiesForKeys: nil)
            while let u = e?.nextObject() as? URL {
                if u.lastPathComponent.lowercased() == "audit.pdf" {
                    found.append(u.path)
                }
            }
        }

        return Array(Set(found)).sorted()
    }

    private func filterPDFsByLanguage(_ pdfs: [String], lang: String) -> [String] {
        func matches(_ path: String, _ l: String) -> Bool {
            let p = path.lowercased()
            if l == "ro" { return p.contains("_ro") || p.contains("/ro/") || p.contains("ro/") }
            if l == "en" { return p.contains("_en") || p.contains("/en/") || p.contains("en/") }
            return true
        }

        if lang == "ro" { return pdfs.filter { matches($0, "ro") } }
        if lang == "en" { return pdfs.filter { matches($0, "en") } }
        return pdfs
    }
}
