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
    var shipZipByLang: [String: String] = [:]
    var shipRoot: String? = nil
    var archivedLogFile: String? = nil
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
    @State private var readyToSend: Bool = false
    @State private var lastRunCampaign: String? = nil
    @State private var lastRunLang: String? = nil
    @State private var lastRunStatus: String? = nil

    var body: some View {
        ScrollView(.vertical) {
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
                        .frame(minHeight: 220, idealHeight: 260, maxHeight: 360)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                        )
                        .help("Paste one URL per line, include https://")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Campaign")
                            .frame(width: 80, alignment: .leading)
                        TextField("ex: Client ABC", text: $campaign)
                            .textFieldStyle(.roundedBorder)
                            .help("Required. Use a clear client name, e.g. Client ABC")
                    }
                    if !campaignIsValid() {
                        Text("Campaign is required (ex: Client ABC)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 80)
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
                        .help("Select delivery language")

                        Toggle("Cleanup temporary files", isOn: $cleanup)
                            .toggleStyle(.checkbox)
                            .help("Remove temporary run files after packaging")
                    }
                }

                Divider()

                if !hasAtLeastOneValidURL() {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add URLs")
                            .font(.headline)
                        Text("• One URL per line")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("• Include https://")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("• Campaign is required")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                }

                Text("Actions")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button { runAudit() } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                        .disabled(isRunning || !hasAtLeastOneValidURL() || !campaignIsValid())
                        .help(runHelpText())
                        InfoButton(text: "Runs the audit engine and prepares deliverables. When finished, use Ship Root to send the ZIP.")

                        Button { setRepoPath() } label: {
                            Label("Set Repo", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                        .help("Select the deterministic-website-audit folder")

                        Spacer()

                        Button { resetForNextClient() } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning)
                        .help("Clear inputs and UI state for next client")

                        statusPill
                            .help("Last run status (OK/BROKEN/FATAL)")
                        postRunStatusBadge
                    }

                    if let reason = runDisabledReason() {
                        Text(reason)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button { openShipRoot() } label: {
                            Label("Open Ship Root", systemImage: "shippingbox.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                        .disabled(isRunning || shipRootPath() == nil)
                        .help(shipRootHelpText())
                        InfoButton(text: "Opens the final delivery root folder for this campaign.")

                        if lang == "both" {
                            Button { openShipFolder(forLang: "ro") } label: {
                                Label("Open RO", systemImage: "shippingbox.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                            .disabled(isRunning || shipDirPath(forLang: "ro") == nil)
                            .help(shipHelpText(forLang: "ro"))
                            InfoButton(text: "Opens the final delivery folder in archive for this campaign/language.")

                            Button { openShipFolder(forLang: "en") } label: {
                                Label("Open EN", systemImage: "shippingbox.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                            .disabled(isRunning || shipDirPath(forLang: "en") == nil)
                            .help(shipHelpText(forLang: "en"))
                            InfoButton(text: "Opens the final delivery folder in archive for this campaign/language.")
                        } else {
                            Button { openShipFolder(forLang: lang) } label: {
                                Label(lang == "ro" ? "Open RO" : "Open EN", systemImage: "shippingbox.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                            .disabled(isRunning || shipDirPath(forLang: lang) == nil)
                            .help(shipHelpText(forLang: lang))
                            InfoButton(text: "Opens the final delivery folder in archive for this campaign/language.")
                        }

                        if lang == "both" {
                            Button { openZIP(forLang: "ro") } label: {
                                Label("Reveal ZIP RO", systemImage: "archivebox.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning || shipZipPath(forLang: "ro") == nil)
                            .help(zipHelpText(forLang: "ro"))
                            InfoButton(text: "Reveals the ZIP in Finder so you can attach it to an email.")

                            Button { openZIP(forLang: "en") } label: {
                                Label("Reveal ZIP EN", systemImage: "archivebox.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning || shipZipPath(forLang: "en") == nil)
                            .help(zipHelpText(forLang: "en"))
                            InfoButton(text: "Reveals the ZIP in Finder so you can attach it to an email.")
                        } else {
                            Button { openZIPIfAny() } label: {
                                Label("Reveal ZIP", systemImage: "archivebox.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning || shipZipPath(forLang: lang) == nil)
                            .help(zipHelpText(forLang: lang))
                            InfoButton(text: "Reveals the ZIP in Finder so you can attach it to an email.")
                        }

                        Button { openOutputFolder() } label: {
                            Label("Out", systemImage: "folder.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning || outputFolderPath() == nil)
                        .help(outputHelpText())
                    }

                    if let reason = shipDisabledReason() {
                        Text(reason)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let reason = zipDisabledReason() {
                        Text(reason)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let readyLine = readyToSendHint() {
                        Text(readyLine)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if let summary = lastRunSummary() {
                        Text(summary)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button { openLogs() } label: {
                            Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .disabled(isRunning || ((result?.logFile == nil) && (result?.archivedLogFile == nil)))
                        .help(logsHelpText())
                        InfoButton(text: "Opens the latest run log for troubleshooting.")

                        Button { openEvidence() } label: {
                            Label("Evidence", systemImage: "tray.full.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunning == false && !canOpenEvidence())
                        .help(evidenceHelpText())
                        InfoButton(text: "Opens the raw audit output (PDF/JSON/evidence) under reports.")

                        if let pdfs = result?.pdfPaths, !pdfs.isEmpty {
                            if pdfs.count > 1 {
                                Picker("", selection: $selectedPDF) {
                                    ForEach(pdfs, id: \.self) { path in
                                        Text(displayName(forPath: path))
                                            .tag(Optional(path))
                                    }
                                }
                                .frame(maxWidth: 360)
                                .help("Select a PDF to open")
                            } else {
                                Color.clear.onAppear {
                                    selectedPDF = pdfs.first
                                }
                            }

                            Button {
                                if let p = selectedPDF ?? pdfs.first {
                                    revealAndOpenFile(p)
                                }
                            } label: {
                                Label("PDF", systemImage: "doc.richtext")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                            .help(pdfHelpText())
                            InfoButton(text: "Opens the generated audit PDF from the last run.")
                        } else {
                            Button { } label: {
                                Label("PDF", systemImage: "doc.richtext")
                            }
                            .buttonStyle(.bordered)
                            .disabled(true)
                            .help(pdfHelpText())
                            InfoButton(text: "Opens the generated audit PDF from the last run.")
                        }
                    }

                    if let reason = pdfDisabledReason() {
                        Text(reason)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
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
                        .help("Live runner output (read-only)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
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

    @ViewBuilder
    private var postRunStatusBadge: some View {
        if isRunning {
            EmptyView()
        } else if let code = lastExitCode {
            let (text, color): (String, Color) = {
                switch code {
                case 0: return ("Ready to send", .green)
                case 1: return ("Ready to send (issues found)", .orange)
                case 2: return ("Run failed", .red)
                default: return ("Run failed", .secondary)
                }
            }()

            Text(text)
                .font(.subheadline)
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.12))
                .cornerRadius(10)
        } else {
            EmptyView()
        }
    }

    private func statusTextAndColor() -> (String, Color) {
        guard let code = lastExitCode else { return ("—", .secondary) }
        if code == 0 { return ("OK", .green) }
        if code == 1 { return ("BROKEN", .orange) }
        if code == 2 { return ("FATAL", .red) }
        return ("CODE \(code)", .secondary)
    }

    private func statusLabel(for code: Int32) -> String {
        if code == 0 { return "OK" }
        if code == 1 { return "BROKEN" }
        if code == 2 { return "FATAL" }
        return "CODE \(code)"
    }

    private func resetForNextClient() {
        urlsText = ""
        campaign = ""
        lang = "ro"
        logOutput = ""
        lastExitCode = nil
        result = nil
        selectedPDF = nil
        selectedZIPLang = "ro"
        readyToSend = false
        lastRunCampaign = nil
        lastRunLang = nil
        lastRunStatus = nil
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

    private func campaignIsValid() -> Bool {
        !campaign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runDisabledReason() -> String? {
        if isRunning { return "Run disabled: Running…" }
        if !hasAtLeastOneValidURL() { return "Run disabled: Add at least 1 valid URL" }
        if !campaignIsValid() { return "Run disabled: Enter Campaign" }
        return nil
    }

    private func shipDisabledReason() -> String? {
        if isRunning { return "Ship disabled: Running…" }
        if !hasShipForCurrentLang() { return "Ship disabled: No ship folder yet" }
        return nil
    }

    private func zipDisabledReason() -> String? {
        if isRunning { return "ZIP disabled: Running…" }
        if !hasZipForCurrentLang() { return "ZIP disabled: No ZIP yet" }
        return nil
    }

    private func pdfDisabledReason() -> String? {
        if isRunning { return "PDF disabled: Running…" }
        if result?.pdfPaths.isEmpty ?? true { return "PDF disabled: No PDFs yet" }
        return nil
    }

    private func hasShipForCurrentLang() -> Bool {
        if lang == "both" {
            return shipDirPath(forLang: "ro") != nil || shipDirPath(forLang: "en") != nil
        }
        return shipDirPath(forLang: lang) != nil
    }

    private func hasZipForCurrentLang() -> Bool {
        if lang == "both" {
            return shipZipPath(forLang: "ro") != nil || shipZipPath(forLang: "en") != nil
        }
        return shipZipPath(forLang: lang) != nil
    }

    private func runHelpText() -> String {
        if let reason = runDisabledReason() {
            return "Run the audit pipeline. \(reason)"
        }
        return "Run the audit pipeline"
    }

    private func shipHelpText(forLang lang: String) -> String {
        if let reason = shipDisabledReason() {
            return "Open ship/archive folder. \(reason)"
        }
        if lang == "ro" { return "Open the RO ship/archive folder" }
        if lang == "en" { return "Open the EN ship/archive folder" }
        return "Open the ship/archive folder"
    }

    private func shipRootHelpText() -> String {
        if shipRootPath() == nil {
            return "Open delivery root. Run first."
        }
        return "Open the final delivery root folder for this campaign"
    }

    private func zipHelpText(forLang lang: String) -> String {
        if let reason = zipDisabledReason() {
            return "Open ZIP for the last run. \(reason)"
        }
        if lang == "ro" { return "Open the RO ZIP" }
        if lang == "en" { return "Open the EN ZIP" }
        return "Open the ZIP for the last run"
    }

    private func outputHelpText() -> String {
        if outputFolderPath() == nil {
            return "Open archive root. Run first."
        }
        return "Open archive root"
    }

    private func logsHelpText() -> String {
        if (result?.archivedLogFile == nil) && (result?.logFile == nil) {
            return "Open logs folder. Run first."
        }
        return "Open the run log file or logs folder"
    }

    private func evidenceHelpText() -> String {
        if !canOpenEvidence() {
            return "Open evidence/output folder. Run first."
        }
        return "Open evidence/output folder for the last run"
    }

    private func pdfHelpText() -> String {
        if result?.pdfPaths.isEmpty ?? true {
            return "Open the selected PDF. No PDFs yet."
        }
        return "Open the selected PDF"
    }

    private struct InfoButton: View {
        let text: String
        @State private var isPresented: Bool = false

        var body: some View {
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isPresented) {
                Text(text)
                    .font(.footnote)
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(12)
            }
        }
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
        if let archived = result?.archivedLogFile, FileManager.default.fileExists(atPath: archived) {
            revealAndOpenFile(archived)
            return
        }
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
        guard let zipPath = shipZipPath(forLang: lang) else { return }
        revealAndOpenFile(zipPath)
    }

    private func openZIP(forLang lang: String) {
        guard let zipPath = shipZipPath(forLang: lang) else { return }
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
        guard campaignIsValid() else {
            alert(title: "Campaign required", message: "Te rog completează un nume de campanie.")
            return
        }

        isRunning = true
        logOutput = ""
        lastExitCode = nil
        result = nil
        selectedPDF = nil
        selectedZIPLang = "ro"
        readyToSend = false

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
                r.shipZipByLang = hints.shipZipByLang
                r.shipRoot = hints.shipRoot
                r.archivedLogFile = hints.archivedLogFile

                // PDFs: find under reports + deliverables/out
                let pdfs = self.discoverPDFs(repoRoot: repoRoot)
                let filtered = self.filterPDFsByLanguage(pdfs, lang: selectedLang)
                r.pdfPaths = (filtered.isEmpty ? pdfs : filtered).sorted()

                self.result = r

                // auto-select first pdf/zip
                if self.selectedPDF == nil { self.selectedPDF = r.pdfPaths.first }
                self.syncSelectedZIPLang(with: r, selectedLang: selectedLang)

                if code == 0 || code == 1 {
                    self.readyToSend = true
                } else {
                    self.readyToSend = false
                }
                self.lastRunCampaign = baseCampaign
                self.lastRunLang = selectedLang
                self.lastRunStatus = self.statusLabel(for: code)

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

    private func parseScopeHints(from output: String) -> (logFile: String?, zipByLang: [String: String], outDirByLang: [String: String], shipDirByLang: [String: String], shipZipByLang: [String: String], shipRoot: String?, archivedLogFile: String?) {
        var logFile: String? = nil
        var zipByLang: [String: String] = [:]
        var outDirByLang: [String: String] = [:]
        var shipDirByLang: [String: String] = [:]
        var shipZipByLang: [String: String] = [:]
        var shipRoot: String? = nil
        var archivedLogFile: String? = nil

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
                continue
            }
            if line.hasPrefix("SCOPE_SHIP_ZIP_") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = String(parts[0].dropFirst("SCOPE_SHIP_ZIP_".count)).lowercased()
                    shipZipByLang[key] = parts[1]
                }
                continue
            }
            if line.hasPrefix("SCOPE_SHIP_ROOT=") {
                shipRoot = String(line.dropFirst("SCOPE_SHIP_ROOT=".count))
                continue
            }
            if line.hasPrefix("SCOPE_LOG_ARCHIVED=") {
                archivedLogFile = String(line.dropFirst("SCOPE_LOG_ARCHIVED=".count))
            }
        }

        return (logFile, zipByLang, outDirByLang, shipDirByLang, shipZipByLang, shipRoot, archivedLogFile)
    }

    private func availableZipLangs() -> [String]? {
        guard let zips = result?.zipByLang, !zips.isEmpty else { return nil }
        let ordered = ["ro", "en"]
        let known = ordered.filter { zips[$0] != nil }
        if !known.isEmpty { return known }
        return zips.keys.sorted()
    }

    private func shipZipPath(forLang lang: String) -> String? {
        guard let zips = result?.shipZipByLang, !zips.isEmpty else { return nil }
        guard let path = zips[lang], FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func shipRootPath() -> String? {
        guard let root = result?.shipRoot, !root.isEmpty else { return nil }
        return FileManager.default.fileExists(atPath: root) ? root : nil
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

    private func openShipRoot() {
        guard let path = shipRootPath() else { return }
        openFolder(path)
    }

    private func outputFolderPath() -> String? {
        return shipRootPath()
    }

    private func openOutputFolder() {
        guard let path = outputFolderPath() else { return }
        openFolder(path)
    }

    private func readyToSendHint() -> String? {
        guard readyToSend else { return nil }
        return "Ready to send — open Ship Root"
    }

    private func lastRunSummary() -> String? {
        guard let camp = lastRunCampaign,
              let l = lastRunLang,
              let status = lastRunStatus else { return nil }
        let count = zipCountAvailable()
        return "Last run: \(camp) | \(langLabel(for: l)) | \(status) | ZIP: \(count)"
    }

    private func zipCountAvailable() -> Int {
        guard let zips = result?.shipZipByLang else { return 0 }
        return zips.values.filter { FileManager.default.fileExists(atPath: $0) }.count
    }

    private func langLabel(for lang: String) -> String {
        if lang == "ro" { return "RO" }
        if lang == "en" { return "EN" }
        if lang == "both" { return "RO+EN" }
        return lang
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
