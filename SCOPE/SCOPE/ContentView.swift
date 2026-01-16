import SwiftUI
import AppKit

// MARK: - Repo locator

enum ScopeRepoError: Error {
    case notFound
    case invalidRepo
}

struct ScopeRepoLocator {
    static let bookmarkKey = "scopeEngineBookmark"

    static var appSupportDir: String {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?.path
        let dir = (base ?? NSHomeDirectory() + "/Library/Application Support") + "/SCOPE"
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
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

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale {
            if let refreshed = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
        }
        return url
    }

    static func locateRepoURL() throws -> URL {
        guard let url = resolveBookmark(), isRepoRoot(url.path) else {
            throw ScopeRepoError.notFound
        }
        return url
    }

    static func locateRepo() throws -> String {
        try locateRepoURL().path
    }

    static func saveRepoPath(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        try saveRepoURL(url)
    }

    static func saveRepoURL(_ url: URL) throws {
        guard isRepoRoot(url.path) else { throw ScopeRepoError.invalidRepo }
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
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
    enum RunState {
        case idle
        case running
        case done
        case error
    }

    // Inputs
    @State private var urlsText: String = ""
    @State private var campaign: String = ""
    @State private var lang: String = "ro" // ro|en|both
    @State private var cleanup: Bool = true

    // Runtime state
    @State private var isRunning: Bool = false
    @State private var runState: RunState = .idle
    @State private var logOutput: String = ""
    @State private var lastExitCode: Int32? = nil
    @State private var currentTask: Process? = nil
    @State private var cancelRequested: Bool = false

    // Results
    @State private var result: ScopeResult? = nil
    @State private var selectedPDF: String? = nil
    @State private var selectedZIPLang: String = "ro"
    @State private var readyToSend: Bool = false
    @State private var lastRunCampaign: String? = nil
    @State private var lastRunLang: String? = nil
    @State private var lastRunStatus: String? = nil
    @State private var showAdvanced: Bool = false
    @State private var recentCampaigns: [RecentCampaign] = []
    @State private var repoRoot: String? = nil
    @State private var exportStatus: String? = nil
    @State private var historyExportStatus: [String: String] = [:]
    @State private var showHiddenCampaigns: Bool = false
    @State private var campaignSearch: String = ""
    @State private var campaignFilter: CampaignFilter = .all
    @State private var showDeleteHiddenConfirm: Bool = false
    @State private var showDeleteIncompleteConfirm: Bool = false
    @State private var showDeleteOlderConfirm: Bool = false
    @State private var deleteHiddenConfirmText: String = ""
    @State private var deleteIncompleteConfirmText: String = ""
    @State private var deleteOlderConfirmText: String = ""
    @State private var deleteOlderDays: Int = 30
    @State private var deleteHiddenCount: Int = 0
    @State private var deleteIncompleteCount: Int = 0
    @State private var deleteOlderCount: Int = 0
    @State private var historyCleanupStatus: String? = nil
    @State private var showAbout: Bool = false
    @State private var demoDeliverablePath: String? = nil
    @AppStorage("scopeTheme") private var themeRaw: String = Theme.light.rawValue

    private var theme: Theme { Theme(rawValue: themeRaw) ?? .light }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Audit decizional – operator mode")
                            .font(.title3)
                            .foregroundColor(.primary)
                        Spacer()
                        Button("About") {
                            showAbout = true
                        }
                        .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                        .help("Open About and Method details")
                    }
                    Divider()
                }

                GroupBox(label: Text("Inputs").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("URL-uri (un URL pe linie)")
                                .font(.headline)

                            TextEditor(text: $urlsText)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(theme.textPrimary)
                                .padding(8)
                                .frame(minHeight: 200, idealHeight: 240, maxHeight: 320)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(theme.textEditorBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(theme.border, lineWidth: 1)
                                )
                                .help("Paste one URL per line, include https://")
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            let labelWidth: CGFloat = 90
                            HStack(spacing: 12) {
                                Text("Campaign")
                                    .frame(width: labelWidth, alignment: .leading)
                                TextField("e.g. Client A / Outreach Jan", text: $campaign)
                                    .textFieldStyle(.roundedBorder)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(campaignIsValid() ? Color.clear : Color.orange.opacity(0.35), lineWidth: 1)
                                    )
                                    .frame(maxWidth: 320)
                                    .help("Required. Use a clear client name, e.g. Client ABC")

                                Text("Language")
                                    .frame(width: labelWidth, alignment: .leading)

                                Picker("", selection: $lang) {
                                    Text("RO").tag("ro")
                                    Text("EN").tag("en")
                                    Text("RO + EN (2 deliverables)").tag("both")
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 300)
                                .help("Select delivery language")
                            }
                            if !campaignIsValid() {
                                Text("Campaign is required (ex: Client ABC)")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, labelWidth)
                            }

                            HStack(spacing: 12) {
                                Text("Theme")
                                    .frame(width: labelWidth, alignment: .leading)
                                Picker("", selection: $themeRaw) {
                                    Text("Light").tag(Theme.light.rawValue)
                                    Text("Dark").tag(Theme.dark.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 220)

                                Toggle("Cleanup temporary files", isOn: $cleanup)
                                    .toggleStyle(.checkbox)
                                    .help("Remove temporary run files after packaging")
                            }
                            Text("RO + EN generates two ZIPs")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.leading, labelWidth)
                        }

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
                            .background(theme.cardBackground)
                            .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .modifier(CardStyle(theme: theme))
                .disabled(isRunning)

                GroupBox(label: Text("Engine Folder").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            let selectDisabled = isRunning
                            Button { selectEngineFolder() } label: {
                                Label("Select Engine Folder", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(selectDisabled)
                            .opacity(buttonOpacity(disabled: selectDisabled))
                            .help("Select the deterministic-website-audit repo folder")

                            let showDisabled = isRunning || !engineFolderAvailable()
                            Button { showEngineFolder() } label: {
                                Label("Show Engine Folder", systemImage: "folder")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(showDisabled)
                            .opacity(buttonOpacity(disabled: showDisabled))
                            .help("Reveal the selected engine folder in Finder")

                            Spacer()
                        }

                        if repoRoot != nil {
                            Text("Engine folder selected.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Select Engine Folder to continue.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .modifier(CardStyle(theme: theme))

                GroupBox(label: Text("Run").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            let runDisabled = isRunning || !hasAtLeastOneValidURL() || !campaignIsValid() || !engineFolderAvailable()
                            Button { runAudit() } label: {
                                Label("Run", systemImage: "play.fill")
                            }
                            .buttonStyle(NeonPrimaryButtonStyle(theme: theme, isRunning: isRunning))
                            .controlSize(.large)
                            .disabled(runDisabled)
                            .opacity(buttonOpacity(disabled: runDisabled))
                            .help(runHelpText())
                            InfoButton(text: "Runs the audit engine and prepares deliverables. When finished, use Ship Root to send the ZIP.")

                            if isRunning {
                                Button("Cancel") {
                                    cancelRun()
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .help("Cancel the running audit")
                            }

                            let resetDisabled = isRunning
                            Button { resetForNextClient() } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(resetDisabled)
                            .opacity(buttonOpacity(disabled: resetDisabled))
                            .help("Clear inputs and UI state for next client")

                            let demoDisabled = isRunning || !engineFolderAvailable()
                            Button { runDemo() } label: {
                                Label("Run Demo", systemImage: "sparkles")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(demoDisabled)
                            .opacity(buttonOpacity(disabled: demoDisabled))
                            .help("Run a deterministic demo using example.com")

                            Spacer()

                            statusBadge
                                .help("Last run status (OK/BROKEN/FATAL)")
                        }

                        if isRunning {
                            NeonStatusLine(theme: theme)
                                .frame(maxWidth: 180)
                                .padding(.leading, 2)
                        }

                        if let reason = runDisabledReason() {
                            Text(reason)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        if runState != .idle {
                            Text(runStatusLine())
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            let outputDisabled = isRunning || outputFolderPath() == nil
                            Button { openOutputFolder() } label: {
                                Label("Reveal Output", systemImage: "folder")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(outputDisabled)
                            .opacity(buttonOpacity(disabled: outputDisabled))
                            .help("Reveal the output folder for the last run")

                            let logsDisabled = isRunning || ((result?.logFile == nil) && (result?.archivedLogFile == nil))
                            Button { openLogs() } label: {
                                Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(logsDisabled)
                            .opacity(buttonOpacity(disabled: logsDisabled))
                            .help("Open the latest run log")
                        }

                        if demoDeliverablePath != nil {
                            HStack(spacing: 8) {
                                let revealDisabled = isRunning || demoDeliverablePath == nil
                                Button { revealDemoDeliverable() } label: {
                                    Label("Reveal Demo Deliverable", systemImage: "folder.fill")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .disabled(revealDisabled)
                                .opacity(buttonOpacity(disabled: revealDisabled))
                                .help("Reveal deliverables/out/DEMO_EN or DEMO_RO")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .modifier(CardStyle(theme: theme))

                GroupBox(label: Text("Delivery").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            let shipRootDisabled = isRunning || shipRootPath() == nil
                            Button { openShipRoot() } label: {
                                Label("Open Ship Root", systemImage: "shippingbox.fill")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .controlSize(.large)
                            .font(.headline)
                            .disabled(shipRootDisabled)
                            .opacity(buttonOpacity(disabled: shipRootDisabled))
                            .help(shipRootHelpText())
                            InfoButton(text: "Opens the final delivery root folder for this campaign.")
                        }

                        HStack(spacing: 8) {
                            let exportDisabled = isRunning || resolvedRepoRoot() == nil || !campaignIsValidForExport()
                            Button {
                                exportCurrentCampaign()
                            } label: {
                                Label("Export Campaign…", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .disabled(exportDisabled)
                            .opacity(buttonOpacity(disabled: exportDisabled))
                            .help(exportDisabled ? "Available after run" : "Export client-safe ZIPs to a folder")

                            if let status = exportStatus {
                                Text(status)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }

                        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            if lang == "both" {
                                HStack(spacing: 6) {
                                    let shipRoDisabled = isRunning || shipDirPath(forLang: "ro") == nil
                                    Button { openShipFolder(forLang: "ro") } label: {
                                        Label("Open RO", systemImage: "shippingbox.fill")
                                    }
                                    .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                    .disabled(shipRoDisabled)
                                    .opacity(buttonOpacity(disabled: shipRoDisabled))
                                    .help(shipHelpText(forLang: "ro"))
                                    InfoButton(text: "Opens the final delivery folder in archive for this campaign/language.")
                                }

                                HStack(spacing: 6) {
                                    let shipEnDisabled = isRunning || shipDirPath(forLang: "en") == nil
                                    Button { openShipFolder(forLang: "en") } label: {
                                        Label("Open EN", systemImage: "shippingbox.fill")
                                    }
                                    .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                    .disabled(shipEnDisabled)
                                    .opacity(buttonOpacity(disabled: shipEnDisabled))
                                    .help(shipHelpText(forLang: "en"))
                                    InfoButton(text: "Opens the final delivery folder in archive for this campaign/language.")
                                }

                                HStack(spacing: 6) {
                                    let zipRoDisabled = isRunning || shipZipPath(forLang: "ro") == nil
                                    Button { openZIP(forLang: "ro") } label: {
                                        Label("Reveal ZIP RO", systemImage: "archivebox.fill")
                                    }
                                    .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                    .disabled(zipRoDisabled)
                                    .opacity(buttonOpacity(disabled: zipRoDisabled))
                                    .help(zipHelpText(forLang: "ro"))
                                    InfoButton(text: "Reveals the ZIP in Finder so you can attach it to an email.")
                                }

                                HStack(spacing: 6) {
                                    let zipEnDisabled = isRunning || shipZipPath(forLang: "en") == nil
                                    Button { openZIP(forLang: "en") } label: {
                                        Label("Reveal ZIP EN", systemImage: "archivebox.fill")
                                    }
                                    .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                    .disabled(zipEnDisabled)
                                    .opacity(buttonOpacity(disabled: zipEnDisabled))
                                    .help(zipHelpText(forLang: "en"))
                                    InfoButton(text: "Reveals the ZIP in Finder so you can attach it to an email.")
                                }
                            } else {
                                HStack(spacing: 6) {
                                    let shipSingleDisabled = isRunning || shipDirPath(forLang: lang) == nil
                                    Button { openShipFolder(forLang: lang) } label: {
                                        Label(lang == "ro" ? "Open RO" : "Open EN", systemImage: "shippingbox.fill")
                                    }
                                    .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                    .disabled(shipSingleDisabled)
                                    .opacity(buttonOpacity(disabled: shipSingleDisabled))
                                    .help(shipHelpText(forLang: lang))
                                    InfoButton(text: "Opens the final delivery folder in archive for this campaign/language.")
                                }

                                HStack(spacing: 6) {
                                    let zipSingleDisabled = isRunning || shipZipPath(forLang: lang) == nil
                                    Button { openZIPIfAny() } label: {
                                        Label("Reveal ZIP", systemImage: "archivebox.fill")
                                    }
                                    .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                    .disabled(zipSingleDisabled)
                                    .opacity(buttonOpacity(disabled: zipSingleDisabled))
                                    .help(zipHelpText(forLang: lang))
                                    InfoButton(text: "Reveals the ZIP in Finder so you can attach it to an email.")
                                }
                            }

                            HStack(spacing: 6) {
                                let logsDisabled = isRunning || ((result?.logFile == nil) && (result?.archivedLogFile == nil))
                                Button { openLogs() } label: {
                                    Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .tint(.secondary)
                                .disabled(logsDisabled)
                                .opacity(buttonOpacity(disabled: logsDisabled))
                                .help(logsHelpText())
                                InfoButton(text: "Opens the latest run log for troubleshooting.")
                            }
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

                        if readyToSend && (lastExitCode == 0 || lastExitCode == 1) {
                            Text("All deliverables are client-safe.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        if let summary = lastRunSummary() {
                            Text(summary)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .modifier(CardStyle(theme: theme))

                GroupBox(label: Text("History").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            let repoAvailable = (resolvedRepoRoot() != nil)
                            Button { openArchiveRoot() } label: {
                                Label("Open Archive", systemImage: "tray.full.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!repoAvailable)
                            .opacity(buttonOpacity(disabled: !repoAvailable))
                            .help(repoAvailable ? "Open deliverables/archive" : "Select a repo to enable")

                            Button { openTodaysArchive() } label: {
                                Label("Open Today's Archive", systemImage: "calendar")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!repoAvailable)
                            .opacity(buttonOpacity(disabled: !repoAvailable))
                            .help(repoAvailable ? "Open deliverables/archive/<today>" : "Select a repo to enable")
                        }

                        Text("Recent campaigns")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Search campaigns…", text: $campaignSearch)
                                .textFieldStyle(.roundedBorder)

                            Picker("", selection: $campaignFilter) {
                                Text("All").tag(CampaignFilter.all)
                                Text("Ready").tag(CampaignFilter.withZips)
                                Text("Hidden").tag(CampaignFilter.hidden)
                            }
                            .pickerStyle(.segmented)

                            Toggle("Show hidden campaigns", isOn: $showHiddenCampaigns)
                                .toggleStyle(.checkbox)
                        }

                        let repoAvailable = (resolvedRepoRoot() != nil)
                        if !repoAvailable {
                            Text("Select Engine Folder to view history.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else if recentCampaigns.isEmpty {
                            Text("No campaigns yet.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else {
                            let displayedCampaigns = filteredCampaigns()
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(displayedCampaigns) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("\(item.dateString) • \(item.campaign)")
                                                .font(.subheadline)
                                                .foregroundColor(item.isHidden ? .secondary : .primary)
                                                .opacity(item.isHidden ? 0.6 : 1.0)
                                            statusBadge(for: item)
                                            Spacer()
                                            Button { openFolder(item.path) } label: {
                                                Text("Open")
                                            }
                                            .buttonStyle(.bordered)

                                            let exportDisabled = isRunning || resolvedRepoRoot() == nil || !item.hasZips
                                            Button {
                                                exportHistoryCampaign(item)
                                            } label: {
                                                Text("Export…")
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(exportDisabled)
                                            .opacity(buttonOpacity(disabled: exportDisabled))
                                            .help(exportDisabled && !item.hasZips ? "No ZIPs yet" : "Export ZIPs to a folder")

                                            if item.isHidden {
                                                Button { unhideCampaign(item) } label: {
                                                    Label("Unhide", systemImage: "eye")
                                                }
                                                .buttonStyle(.bordered)
                                            } else {
                                                Button { hideCampaign(item) } label: {
                                                    Label("Hide", systemImage: "eye.slash")
                                                }
                                                .buttonStyle(.bordered)
                                            }

                                            let revealDisabled = !item.hasZips
                                            Button { revealCampaignZips(item) } label: {
                                                Text("Reveal ZIPs")
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(revealDisabled)
                                            .opacity(buttonOpacity(disabled: revealDisabled))
                                            .help(revealDisabled ? "No ZIPs yet" : "Reveal ZIPs in Finder")
                                        }

                                        if let status = historyExportStatus[item.id] {
                                            Text(status)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            if displayedCampaigns.isEmpty {
                                Text("No campaigns match.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .modifier(CardStyle(theme: theme))

                GroupBox {
                    DisclosureGroup("Advanced (debug & logs)", isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                let outDisabled = isRunning || outputFolderPath() == nil
                                Button { openOutputFolder() } label: {
                                    Label("Out", systemImage: "folder.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(outDisabled)
                                .opacity(buttonOpacity(disabled: outDisabled))
                                .help(outputHelpText())

                                let evidenceDisabled = isRunning == false && !canOpenEvidence()
                                Button { openEvidence() } label: {
                                    Label("Evidence", systemImage: "tray.full.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(evidenceDisabled)
                                .opacity(buttonOpacity(disabled: evidenceDisabled))
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

                                    let pdfDisabled = isRunning
                                    Button {
                                        if let p = selectedPDF ?? pdfs.first {
                                            revealAndOpenFile(p)
                                        }
                                    } label: {
                                        Label("PDF", systemImage: "doc.richtext")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(pdfDisabled)
                                    .opacity(buttonOpacity(disabled: pdfDisabled))
                                    .help(pdfHelpText())
                                    InfoButton(text: "Opens the generated audit PDF from the last run.")
                                } else {
                                    Button { } label: {
                                        Label("PDF", systemImage: "doc.richtext")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(true)
                                    .opacity(buttonOpacity(disabled: true))
                                    .help(pdfHelpText())
                                    InfoButton(text: "Opens the generated audit PDF from the last run.")
                                }
                            }

                            if let reason = pdfDisabledReason() {
                                Text(reason)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Log")
                                    .font(.headline)

                                Text(clientSafeLogSummary())
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .frame(minHeight: 80, alignment: .topLeading)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(theme.border, lineWidth: 1)
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(theme.textEditorBackground)
                                    )
                                    .help("Summary only. Use Open Logs for details.")
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                Text("History management")
                                    .font(.headline)

                                Button { prepareDeleteHidden() } label: {
                                    Text("Delete hidden campaigns…")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRunning)
                                .opacity(buttonOpacity(disabled: isRunning))

                                if showDeleteHiddenConfirm {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("This will permanently delete \(deleteHiddenCount) campaigns from disk.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                        TextField("Type DELETE to confirm", text: $deleteHiddenConfirmText)
                                            .textFieldStyle(.roundedBorder)
                                        HStack {
                                            Button("Cancel") {
                                                showDeleteHiddenConfirm = false
                                                deleteHiddenConfirmText = ""
                                            }
                                            .buttonStyle(.bordered)

                                            Button("Delete") {
                                                deleteHiddenCampaigns()
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(deleteHiddenConfirmText != "DELETE")
                                        }
                                    }
                                }

                                Button { prepareDeleteIncomplete() } label: {
                                    Text("Delete incomplete campaigns…")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRunning)
                                .opacity(buttonOpacity(disabled: isRunning))

                                if showDeleteIncompleteConfirm {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("This will permanently delete \(deleteIncompleteCount) campaigns from disk.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                        TextField("Type DELETE to confirm", text: $deleteIncompleteConfirmText)
                                            .textFieldStyle(.roundedBorder)
                                        HStack {
                                            Button("Cancel") {
                                                showDeleteIncompleteConfirm = false
                                                deleteIncompleteConfirmText = ""
                                            }
                                            .buttonStyle(.bordered)

                                            Button("Delete") {
                                                deleteIncompleteCampaigns()
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(deleteIncompleteConfirmText != "DELETE")
                                        }
                                    }
                                }

                                HStack(spacing: 8) {
                                    Text("Delete campaigns older than")
                                        .font(.subheadline)
                                    Picker("", selection: $deleteOlderDays) {
                                        Text("7").tag(7)
                                        Text("14").tag(14)
                                        Text("30").tag(30)
                                        Text("90").tag(90)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 220)
                                    Text("days…")
                                        .font(.subheadline)
                                }

                                Button { prepareDeleteOlder() } label: {
                                    Text("Delete campaigns older than \(deleteOlderDays) days…")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRunning)
                                .opacity(buttonOpacity(disabled: isRunning))

                                if showDeleteOlderConfirm {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("This will permanently delete \(deleteOlderCount) campaigns from disk.")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                        TextField("Type DELETE to confirm", text: $deleteOlderConfirmText)
                                            .textFieldStyle(.roundedBorder)
                                        HStack {
                                            Button("Cancel") {
                                                showDeleteOlderConfirm = false
                                                deleteOlderConfirmText = ""
                                            }
                                            .buttonStyle(.bordered)

                                            Button("Delete") {
                                                deleteOlderCampaigns()
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(deleteOlderConfirmText != "DELETE")
                                        }
                                    }
                                }

                                if let status = historyCleanupStatus {
                                    Text(status)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                    .padding(8)
                }
                .modifier(CardStyle(theme: theme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .modifier(NeonPanel(theme: theme))
            .padding(16)
        }
        .background(theme.background)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .animation(.easeInOut(duration: 0.2), value: themeRaw)
        .frame(minWidth: 980, minHeight: 720)
        .sheet(isPresented: $showAbout) {
            AboutView()
                .frame(width: 520, height: 560)
        }
        .onAppear {
            repoRoot = resolvedRepoRoot()
            refreshRecentCampaigns()
        }
        .onChange(of: repoRoot) { _, _ in
            refreshRecentCampaigns()
        }
        .onChange(of: campaignFilter) { _, newValue in
            if newValue == .hidden {
                showHiddenCampaigns = true
            }
        }
        .onChange(of: deleteOlderDays) { _, _ in
            if showDeleteOlderConfirm {
                deleteOlderCount = countOlderCampaigns(days: deleteOlderDays)
            }
        }
    }

    // MARK: - Status UI

    @ViewBuilder
    private var statusBadge: some View {
        if isRunning {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Running audit…")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.gray.opacity(0.15)))
        } else if let code = lastExitCode {
            let (text, color): (String, Color) = {
                switch code {
                case 0: return ("Ready to send", .green)
                case 1: return ("Ready to send (issues found)", .orange)
                case 2: return ("Run failed", .red)
                default: return ("Run failed", .secondary)
                }
            }()

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.headline)
                    .foregroundColor(color)
                Text(statusBadgeSubline(for: code))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(color.opacity(0.12)))
        } else {
            EmptyView()
        }
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
        runState = .idle
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

    private func validateTargetsContent(_ text: String) -> (valid: [String], invalid: [String]) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var valid: [String] = []
        var invalid: [String] = []
        valid.reserveCapacity(lines.count)

        for raw in lines {
            let original = String(raw)
            let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            guard let u = URL(string: trimmed),
                  let scheme = u.scheme,
                  (scheme == "http" || scheme == "https"),
                  u.host != nil
            else {
                invalid.append(original)
                continue
            }
            valid.append(trimmed)
        }

        return (valid, invalid)
    }

    private func validateTargetsInput() -> [String]? {
        let text = urlsText
        guard let data = text.data(using: .utf8) else {
            alert(title: "Invalid targets", message: "Targets must be valid UTF-8 text.")
            return nil
        }
        if data.count > 1_048_576 {
            alert(title: "Targets file too large", message: "The targets list must be 1 MB or less.")
            return nil
        }

        let (validLines, invalidLines) = validateTargetsContent(text)
        if !invalidLines.isEmpty {
            alertInvalidTargets(invalidLines: invalidLines)
            return nil
        }
        if validLines.isEmpty {
            alert(title: "No valid URLs", message: "Adaugă cel puțin un URL valid (http/https).")
            return nil
        }
        return validLines
    }

    private func hasAtLeastOneValidURL() -> Bool {
        !extractURLs(from: urlsText).isEmpty
    }

    private func campaignIsValid() -> Bool {
        !campaign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runDisabledReason() -> String? {
        if isRunning { return "Run disabled: Running…" }
        if !engineFolderAvailable() { return "Select Engine Folder to continue." }
        if !hasAtLeastOneValidURL() { return "Run disabled: Add at least 1 valid URL" }
        if !campaignIsValid() { return "Run disabled: Enter Campaign" }
        return nil
    }

    private func buttonOpacity(disabled: Bool) -> Double {
        disabled ? 0.6 : 1.0
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
            return "Open delivery root. Available after run."
        }
        return "Open the final delivery root folder for this campaign"
    }

    private func zipHelpText(forLang lang: String) -> String {
        if zipDisabledReason() != nil {
            return "Open ZIP for the last run. Available after run."
        }
        if lang == "ro" { return "Open the RO ZIP" }
        if lang == "en" { return "Open the EN ZIP" }
        return "Open the ZIP for the last run"
    }

    private func outputHelpText() -> String {
        if outputFolderPath() == nil {
            return "Open archive root. Available after run."
        }
        return "Open archive root"
    }

    private func logsHelpText() -> String {
        if (result?.archivedLogFile == nil) && (result?.logFile == nil) {
            return "Open logs folder. Available after run."
        }
        return "Open the run log file or logs folder"
    }

    private func evidenceHelpText() -> String {
        if !canOpenEvidence() {
            return "Open evidence/output folder. Available after run."
        }
        return "Open evidence/output folder for the last run"
    }

    private func pdfHelpText() -> String {
        if result?.pdfPaths.isEmpty ?? true {
            return "Open the selected PDF. Available after run."
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

    private func alertInvalidTargets(invalidLines: [String]) {
        let maxList = 10
        let shown = invalidLines.prefix(maxList)
        var message = "Each line must be a valid http/https URL. Please fix the following lines:\n\n"
        message += shown.map { "• \($0)" }.joined(separator: "\n")
        if invalidLines.count > maxList {
            message += "\n\n…and \(invalidLines.count - maxList) more."
        }
        alert(title: "Invalid target URLs", message: message)
    }

    private func writeTargetsTempFile(validLines: [String]) -> String {
        let content = validLines.joined(separator: "\n") + "\n"
        let tmp = FileManager.default.temporaryDirectory.path
        let path = (tmp as NSString).appendingPathComponent("scope_targets.txt")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func makeRunLogFilePath(outputDir: String, prefix: String) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDir) {
            try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        return (outputDir as NSString).appendingPathComponent("\(prefix)_\(stamp).log")
    }

    private struct CardStyle: ViewModifier {
        let theme: Theme

        func body(content: Content) -> some View {
            content
                .background(theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
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

    private func selectEngineFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Selectează folderul repo: deterministic-website-audit"

        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                do {
                    try ScopeRepoLocator.saveRepoURL(url)
                    self.repoRoot = url.path
                    self.refreshRecentCampaigns()
                    self.alert(title: "Engine folder set", message: "Engine folder selected.")
                } catch {
                    self.alert(title: "Invalid repo", message: "Folderul ales nu pare repo-ul corect.")
                }
            }
        }
    }

    private func showEngineFolder() {
        guard let engineURL = beginEngineAccess() else {
            alert(title: "Engine folder missing", message: "Select Engine Folder to continue.")
            return
        }
        openFolder(engineURL.path)
        endEngineAccess(engineURL)
    }

    // MARK: - Run audit (sequential)

    private func runAudit() {
        guard !isRunning else { return }
        guard let validLines = validateTargetsInput() else {
            return
        }
        guard campaignIsValid() else {
            alert(title: "Campaign required", message: "Te rog completează un nume de campanie.")
            return
        }

        isRunning = true
        runState = .running
        logOutput = ""
        lastExitCode = nil
        result = nil
        selectedPDF = nil
        selectedZIPLang = "ro"
        readyToSend = false
        cancelRequested = false

        let baseCampaign = campaign.trimmingCharacters(in: .whitespacesAndNewlines)
        let camp = baseCampaign.isEmpty ? "Default" : baseCampaign

        runRunner(selectedLang: lang, baseCampaign: camp, validLines: validLines)
    }

    private func runDemo() {
        guard !isRunning else { return }
        guard let engineURL = beginEngineAccess() else {
            alert(title: "Engine folder missing", message: "Select Engine Folder to continue.")
            return
        }
        let repoRoot = engineURL.path

        isRunning = true
        runState = .running
        logOutput = ""
        lastExitCode = nil
        result = nil
        readyToSend = false
        selectedPDF = nil
        selectedZIPLang = "en"
        demoDeliverablePath = nil
        cancelRequested = false

        let tmp = FileManager.default.temporaryDirectory.path
        let targetsFile = (tmp as NSString).appendingPathComponent("scope_demo_targets.txt")
        let content = "https://example.com\n"
        try? content.write(toFile: targetsFile, atomically: true, encoding: .utf8)

        let (scriptName, demoCampaign) = demoScriptAndCampaign(for: lang)
        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/\(scriptName)")
        let outputDir = (repoRoot as NSString).appendingPathComponent("deliverables/out/\(demoCampaign)")
        let logFilePath = makeRunLogFilePath(outputDir: outputDir, prefix: "scope_demo")
        FileManager.default.createFile(atPath: logFilePath, contents: nil)
        let task = Process()
        currentTask = task
        task.executableURL = URL(fileURLWithPath: scriptPath)
        task.arguments = [
            targetsFile,
            "--campaign",
            demoCampaign,
            "--cleanup"
        ]
        task.currentDirectoryURL = URL(fileURLWithPath: repoRoot)

        let pipe = Pipe()
        let logHandle = FileHandle(forWritingAtPath: logFilePath)
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self.logOutput += str
                }
            }
            logHandle?.write(data)
        }

        task.terminationHandler = { p in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                logHandle?.closeFile()
                self.endEngineAccess(engineURL)
                self.currentTask = nil
                let code = p.terminationStatus
                self.lastExitCode = code
                self.lastRunCampaign = demoCampaign
                self.lastRunLang = (self.lang == "en") ? "en" : "ro"
                if self.cancelRequested {
                    self.lastRunStatus = "Canceled"
                    self.runState = .error
                    self.cancelRequested = false
                } else {
                    self.lastRunStatus = self.statusLabel(for: code)
                    self.runState = (code == 0 || code == 1) ? .done : .error
                }
                self.readyToSend = (code == 0 || code == 1)

                if code == 0 || code == 1 {
                    let demoPath = (repoRoot as NSString).appendingPathComponent("deliverables/out/\(demoCampaign)")
                    self.demoDeliverablePath = demoPath
                }

                self.isRunning = false
            }
        }

        do {
            try task.run()
        } catch {
            DispatchQueue.main.async {
                self.endEngineAccess(engineURL)
                self.currentTask = nil
                self.isRunning = false
                self.runState = .error
                self.alert(title: "Demo failed", message: "Nu am putut porni demo-ul.")
            }
        }
    }

    private func runRunner(selectedLang: String, baseCampaign: String, validLines: [String]) {
        guard let engineURL = beginEngineAccess() else {
            alert(title: "Engine folder missing", message: "Select Engine Folder to continue.")
            isRunning = false
            return
        }
        let repoRoot = engineURL.path

        let targetsFile = writeTargetsTempFile(validLines: validLines)
        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/scope_run.sh")
        let outputSuffix = (selectedLang == "both") ? "ro" : selectedLang
        let outputDir = (repoRoot as NSString).appendingPathComponent("deliverables/out/\(baseCampaign)_\(outputSuffix)")
        let logFilePath = makeRunLogFilePath(outputDir: outputDir, prefix: "scope_run")
        FileManager.default.createFile(atPath: logFilePath, contents: nil)

        // Build arguments: scope_run.sh <targets> <lang> <campaign> <cleanup>
        let task = Process()
        currentTask = task
        task.executableURL = URL(fileURLWithPath: scriptPath)
        task.arguments = [
            targetsFile,
            selectedLang,
            baseCampaign,
            cleanup ? "1" : "0"
        ]
        task.currentDirectoryURL = URL(fileURLWithPath: repoRoot)

        let pipe = Pipe()
        let logHandle = FileHandle(forWritingAtPath: logFilePath)
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self.logOutput += str
                }
            }
            logHandle?.write(data)
        }

        task.terminationHandler = { p in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                logHandle?.closeFile()
                self.endEngineAccess(engineURL)
                self.currentTask = nil

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

                if self.cancelRequested {
                    self.lastRunStatus = "Canceled"
                    self.runState = .error
                    self.cancelRequested = false
                    self.readyToSend = false
                } else {
                    if code == 0 || code == 1 {
                        self.readyToSend = true
                        self.runState = .done
                    } else {
                        self.readyToSend = false
                        self.runState = .error
                    }
                }
                self.lastRunCampaign = baseCampaign
                self.lastRunLang = selectedLang
                if self.lastRunStatus == nil || self.lastRunStatus == self.statusLabel(for: code) {
                    self.lastRunStatus = self.statusLabel(for: code)
                }

                self.isRunning = false
                self.refreshRecentCampaigns()
            }
        }

        do {
            try task.run()
        } catch {
            DispatchQueue.main.async {
                self.endEngineAccess(engineURL)
                self.currentTask = nil
                self.isRunning = false
                self.runState = .error
                self.alert(title: "Run failed", message: "Nu am putut porni runner-ul.")
            }
        }
    }

    private func cancelRun() {
        guard isRunning else { return }
        cancelRequested = true
        currentTask?.terminate()
    }

    private func runStatusLine() -> String {
        switch runState {
        case .idle:
            return ""
        case .running:
            return "Status: Running…"
        case .done:
            let label = lastRunStatus ?? "OK"
            return "Status: Completed (\(label))"
        case .error:
            let label = lastRunStatus ?? "Run failed"
            return "Status: \(label)"
        }
    }

    private func clientSafeLogSummary() -> String {
        if isRunning {
            return "Running. Logs are saved to file."
        }
        guard let status = lastRunStatus else {
            return "No run yet."
        }
        switch status {
        case "OK":
            return "Success: audit completed."
        case "BROKEN":
            return "Completed with issues found."
        case "FATAL":
            return "Failed: audit did not complete."
        case "Canceled":
            return "Canceled by operator."
        default:
            return "Run finished."
        }
    }

    private func revealDemoDeliverable() {
        guard let repoRoot = try? ScopeRepoLocator.locateRepo() else {
            alert(title: "Repo not found", message: "Apasă Set Repo… și selectează repo-ul corect.")
            return
        }
        let (_, demoCampaign) = demoScriptAndCampaign(for: lang)
        let path = demoDeliverablePath ?? (repoRoot as NSString).appendingPathComponent("deliverables/out/\(demoCampaign)")
        if FileManager.default.fileExists(atPath: path) {
            openFolder(path)
        } else {
            alert(title: "Demo not found", message: "Nu am găsit deliverables/out/DEMO.")
        }
    }

    private func demoScriptAndCampaign(for lang: String) -> (script: String, campaign: String) {
        if lang == "en" {
            return ("ship_en.sh", "DEMO_EN")
        }
        return ("ship_ro.sh", "DEMO_RO")
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

    private func resolvedEngineURL() -> URL? {
        if let root = repoRoot, ScopeRepoLocator.isRepoRoot(root) {
            return URL(fileURLWithPath: root)
        }
        return try? ScopeRepoLocator.locateRepoURL()
    }

    private func engineFolderAvailable() -> Bool {
        resolvedEngineURL() != nil
    }

    private func beginEngineAccess() -> URL? {
        guard let url = resolvedEngineURL() else { return nil }
        return url.startAccessingSecurityScopedResource() ? url : nil
    }

    private func endEngineAccess(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    private func resolvedRepoRoot() -> String? {
        return resolvedEngineURL()?.path
    }

    private func outputFolderPath() -> String? {
        return shipRootPath()
    }

    private func openOutputFolder() {
        guard let path = outputFolderPath() else { return }
        openFolder(path)
    }

    private func exportCurrentCampaign() {
        guard let campaign = lastRunCampaign?.trimmingCharacters(in: .whitespacesAndNewlines),
              !campaign.isEmpty else {
            setExportStatus("No ZIP found to export.")
            return
        }
        let dateString = todayString()
        exportCampaign(campaign: campaign, dateString: dateString, allowOutFallback: true) { status in
            setExportStatus(status)
        }
    }

    private func exportHistoryCampaign(_ item: RecentCampaign) {
        guard let repo = resolvedRepoRoot() else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a destination folder for export"

        panel.begin { resp in
            guard resp == .OK, let destUrl = panel.url else { return }
            let zips = self.findArchiveZips(repoRoot: repo, dateString: item.dateString, campaign: item.campaign)
            guard !zips.isEmpty else {
                DispatchQueue.main.async {
                    self.setHistoryExportStatus("No ZIPs yet.", for: item.id)
                }
                return
            }

            let destFolder = destUrl.path
            let copied = self.copyZipFiles(zips, toFolder: destFolder)
            let folderName = (destFolder as NSString).lastPathComponent
            DispatchQueue.main.async {
                self.setHistoryExportStatus("Exported \(copied) file(s) to \(folderName).", for: item.id)
            }
        }
    }

    private func revealCampaignZips(_ item: RecentCampaign) {
        if !item.zipPaths.isEmpty {
            revealFiles(item.zipPaths)
        } else {
            openFolder(item.path)
        }
    }

    private func hideCampaign(_ item: RecentCampaign) {
        let hiddenPath = (item.path as NSString).appendingPathComponent(".hidden")
        FileManager.default.createFile(atPath: hiddenPath, contents: Data())
        refreshRecentCampaigns()
    }

    private func unhideCampaign(_ item: RecentCampaign) {
        let hiddenPath = (item.path as NSString).appendingPathComponent(".hidden")
        try? FileManager.default.removeItem(atPath: hiddenPath)
        refreshRecentCampaigns()
    }

    private func revealFiles(_ paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func openArchiveRoot() {
        guard let repo = resolvedRepoRoot() else { return }
        let archiveRoot = (repo as NSString).appendingPathComponent("deliverables/archive")
        if FileManager.default.fileExists(atPath: archiveRoot) {
            openFolder(archiveRoot)
        } else {
            openFolder(repo)
        }
    }

    private func openTodaysArchive() {
        guard let repo = resolvedRepoRoot() else { return }
        let archiveRoot = (repo as NSString).appendingPathComponent("deliverables/archive")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let todayPath = (archiveRoot as NSString).appendingPathComponent(today)
        if FileManager.default.fileExists(atPath: todayPath) {
            openFolder(todayPath)
        } else if FileManager.default.fileExists(atPath: archiveRoot) {
            openFolder(archiveRoot)
        } else {
            openFolder(repo)
        }
    }

    private func exportCampaign(campaign: String, dateString: String, allowOutFallback: Bool, statusHandler: @escaping (String) -> Void) {
        guard let repo = resolvedRepoRoot() else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a destination folder for export"

        panel.begin { resp in
            guard resp == .OK, let destUrl = panel.url else { return }
            let folderName = "SCOPE - \(dateString) - \(campaign)"
            let destFolder = (destUrl.path as NSString).appendingPathComponent(folderName)

            let zips = self.findArchiveZips(repoRoot: repo, dateString: dateString, campaign: campaign)
            let fallbackZips = allowOutFallback ? self.findOutZips(repoRoot: repo, campaign: campaign) : []
            let selectedZips = zips.isEmpty ? fallbackZips : zips

            guard !selectedZips.isEmpty else {
                DispatchQueue.main.async {
                    statusHandler("No ZIP found to export.")
                }
                return
            }
 
            let fm = FileManager.default
            try? fm.createDirectory(atPath: destFolder, withIntermediateDirectories: true)
            for zipPath in selectedZips {
                let fileName = (zipPath as NSString).lastPathComponent
                let destPath = (destFolder as NSString).appendingPathComponent(fileName)
                try? fm.removeItem(atPath: destPath)
                do {
                    try fm.copyItem(atPath: zipPath, toPath: destPath)
                } catch {
                    continue
                }
            }

            DispatchQueue.main.async {
                statusHandler("Exported.")
            }
        }
    }

    private func findArchiveZips(repoRoot: String, dateString: String, campaign: String) -> [String] {
        let fm = FileManager.default
        let archiveRoot = (repoRoot as NSString).appendingPathComponent("deliverables/archive")
        let campaignRoot = (archiveRoot as NSString).appendingPathComponent(dateString)
        let campaignRootFull = (campaignRoot as NSString).appendingPathComponent(campaign)
        let langs = ["RO", "EN"]
        var zips: [String] = []
        for lang in langs {
            let langPath = (campaignRootFull as NSString).appendingPathComponent(lang)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: langPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let files: [String] = (try? fm.contentsOfDirectory(atPath: langPath)) ?? []
            for f in files where f.lowercased().hasSuffix(".zip") {
                zips.append((langPath as NSString).appendingPathComponent(f))
            }

        }
        return zips.sorted()
    }

    private func findOutZips(repoRoot: String, campaign: String) -> [String] {
        let fm = FileManager.default
        let outRoot = (repoRoot as NSString).appendingPathComponent("deliverables/out")
        guard let files = try? fm.contentsOfDirectory(atPath: outRoot) else { return [] }
        let lowerCampaign = campaign.lowercased()
        let matches = files.filter { file in
            let lower = file.lowercased()
            return lower.hasPrefix(lowerCampaign.lowercased()) && lower.hasSuffix(".zip")
        }
        return matches.sorted().map { (outRoot as NSString).appendingPathComponent($0) }
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func campaignIsValidForExport() -> Bool {
        guard let c = lastRunCampaign?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !c.isEmpty
    }

    private func setExportStatus(_ text: String) {
        exportStatus = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if exportStatus == text {
                exportStatus = nil
            }
        }
    }

    private func setHistoryExportStatus(_ text: String, for id: String) {
        historyExportStatus[id] = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if historyExportStatus[id] == text {
                historyExportStatus[id] = nil
            }
        }
    }

    private struct RecentCampaign: Identifiable {
        let id: String
        let dateString: String
        let dateValue: Date
        let campaign: String
        let path: String
        let zipPaths: [String]
        let isHidden: Bool
        let hasZips: Bool
    }

    private struct CampaignEntry {
        let dateString: String
        let dateValue: Date
        let campaign: String
        let path: String
        let isHidden: Bool
        let hasZips: Bool
    }

    private func refreshRecentCampaigns() {
        guard let repo = resolvedRepoRoot() else {
            recentCampaigns = []
            return
        }
        recentCampaigns = loadRecentCampaigns(repoRoot: repo)
    }

    private func loadRecentCampaigns(repoRoot: String) -> [RecentCampaign] {
        let fm = FileManager.default
        let archiveRoot = (repoRoot as NSString).appendingPathComponent("deliverables/archive")
        guard fm.fileExists(atPath: archiveRoot) else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        guard let dateDirs = try? fm.contentsOfDirectory(atPath: archiveRoot) else { return [] }
        var items: [RecentCampaign] = []

        for dateName in dateDirs {
            let datePath = (archiveRoot as NSString).appendingPathComponent(dateName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: datePath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let dateValue = dateFormatter.date(from: dateName) else { continue }

            guard let campaignDirs = try? fm.contentsOfDirectory(atPath: datePath) else { continue }
            for campaignName in campaignDirs {
                let campaignPath = (datePath as NSString).appendingPathComponent(campaignName)
                var isCampaignDir: ObjCBool = false
                guard fm.fileExists(atPath: campaignPath, isDirectory: &isCampaignDir), isCampaignDir.boolValue else { continue }

                let hiddenPath = (campaignPath as NSString).appendingPathComponent(".hidden")
                let isHidden = fm.fileExists(atPath: hiddenPath)
                let zipPaths = findZipPaths(in: campaignPath)
                let hasZips = hasAnyZip(in: campaignPath)
                let id = "\(dateName)|\(campaignName)"
                items.append(RecentCampaign(
                    id: id,
                    dateString: dateName,
                    dateValue: dateValue,
                    campaign: campaignName,
                    path: campaignPath,
                    zipPaths: zipPaths,
                    isHidden: isHidden,
                    hasZips: hasZips
                ))
            }
        }

        let sorted = items.sorted {
            if $0.dateValue != $1.dateValue {
                return $0.dateValue > $1.dateValue
            }
            return $0.campaign.localizedCompare($1.campaign) == .orderedAscending
        }
        return Array(sorted.prefix(10))
    }

    private func findZipPaths(in campaignPath: String) -> [String] {
        let fm = FileManager.default
        let langs = ["RO", "EN"]
        var zips: [String] = []
        for lang in langs {
            let langPath = (campaignPath as NSString).appendingPathComponent(lang)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: langPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: langPath)) ?? []
            for f in files where f.lowercased().hasSuffix(".zip") {
                zips.append((langPath as NSString).appendingPathComponent(f))
            }
        }
        return zips.sorted()
    }

    private func hasAnyZip(in campaignPath: String) -> Bool {
        let fm = FileManager.default
        let langs = ["RO", "EN"]
        for lang in langs {
            let langPath = (campaignPath as NSString).appendingPathComponent(lang)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: langPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let files: [String] = (try? fm.contentsOfDirectory(atPath: langPath)) ?? []
            if files.contains(where: { $0.lowercased().hasSuffix(".zip") }) {
                return true
            }
        }
        return false
    }

    private func prepareDeleteHidden() {
        deleteHiddenCount = countHiddenCampaigns()
        showDeleteHiddenConfirm = true
        deleteHiddenConfirmText = ""
    }

    private func prepareDeleteIncomplete() {
        deleteIncompleteCount = countIncompleteCampaigns()
        showDeleteIncompleteConfirm = true
        deleteIncompleteConfirmText = ""
    }

    private func prepareDeleteOlder() {
        deleteOlderCount = countOlderCampaigns(days: deleteOlderDays)
        showDeleteOlderConfirm = true
        deleteOlderConfirmText = ""
    }

    private func deleteHiddenCampaigns() {
        let items = listAllCampaigns().filter { $0.isHidden }
        let deleted = deleteCampaignEntries(items)
        historyCleanupStatus = "Deleted \(deleted) campaigns."
        showDeleteHiddenConfirm = false
        deleteHiddenConfirmText = ""
        refreshRecentCampaigns()
    }

    private func deleteIncompleteCampaigns() {
        let items = listAllCampaigns().filter { !$0.hasZips }
        let deleted = deleteCampaignEntries(items)
        historyCleanupStatus = "Deleted \(deleted) campaigns."
        showDeleteIncompleteConfirm = false
        deleteIncompleteConfirmText = ""
        refreshRecentCampaigns()
    }

    private func deleteOlderCampaigns() {
        let items = listOlderCampaigns(days: deleteOlderDays)
        let deleted = deleteCampaignEntries(items)
        historyCleanupStatus = "Deleted \(deleted) campaigns."
        showDeleteOlderConfirm = false
        deleteOlderConfirmText = ""
        refreshRecentCampaigns()
    }

    private func countHiddenCampaigns() -> Int {
        listAllCampaigns().filter { $0.isHidden }.count
    }

    private func countIncompleteCampaigns() -> Int {
        listAllCampaigns().filter { !$0.hasZips }.count
    }

    private func countOlderCampaigns(days: Int) -> Int {
        listOlderCampaigns(days: days).count
    }

    private func listOlderCampaigns(days: Int) -> [CampaignEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return listAllCampaigns().filter { $0.dateValue < cutoff }
    }

    private func listAllCampaigns() -> [CampaignEntry] {
        guard let archiveRoot = archiveRootPath() else { return [] }
        let fm = FileManager.default
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        guard let dateDirs = try? fm.contentsOfDirectory(atPath: archiveRoot) else { return [] }
        var items: [CampaignEntry] = []

        for dateName in dateDirs {
            let datePath = (archiveRoot as NSString).appendingPathComponent(dateName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: datePath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let dateValue = dateFormatter.date(from: dateName) else { continue }

            guard let campaignDirs = try? fm.contentsOfDirectory(atPath: datePath) else { continue }
            for campaignName in campaignDirs {
                let campaignPath = (datePath as NSString).appendingPathComponent(campaignName)
                var isCampaignDir: ObjCBool = false
                guard fm.fileExists(atPath: campaignPath, isDirectory: &isCampaignDir), isCampaignDir.boolValue else { continue }

                let hiddenPath = (campaignPath as NSString).appendingPathComponent(".hidden")
                let isHidden = fm.fileExists(atPath: hiddenPath)
                let hasZips = hasAnyZip(in: campaignPath)
                items.append(CampaignEntry(
                    dateString: dateName,
                    dateValue: dateValue,
                    campaign: campaignName,
                    path: campaignPath,
                    isHidden: isHidden,
                    hasZips: hasZips
                ))
            }
        }

        return items
    }

    private func deleteCampaignEntries(_ items: [CampaignEntry]) -> Int {
        guard let archiveRoot = archiveRootPath() else { return 0 }
        let fm = FileManager.default
        let root = (archiveRoot as NSString).standardizingPath
        var deleted = 0
        for item in items {
            let path = (item.path as NSString).standardizingPath
            if path.hasPrefix(root + "/") {
                do {
                    try fm.removeItem(atPath: path)
                    deleted += 1
                } catch {
                    continue
                }
            }
        }
        return deleted
    }

    private func copyZipFiles(_ zipPaths: [String], toFolder destFolder: String) -> Int {
        let fm = FileManager.default
        var copied = 0
        for zipPath in zipPaths {
            let fileName = (zipPath as NSString).lastPathComponent
            let destPath = uniqueDestinationPath(folder: destFolder, fileName: fileName)
            do {
                try fm.copyItem(atPath: zipPath, toPath: destPath)
                copied += 1
            } catch {
                continue
            }
        }
        return copied
    }

    private func uniqueDestinationPath(folder: String, fileName: String) -> String {
        let fm = FileManager.default
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = (folder as NSString).appendingPathComponent(fileName)
        if !fm.fileExists(atPath: candidate) { return candidate }

        var counter = 1
        while true {
            let suffix = " (\(counter))"
            let newName = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            candidate = (folder as NSString).appendingPathComponent(newName)
            if !fm.fileExists(atPath: candidate) { return candidate }
            counter += 1
        }
    }

    private func archiveRootPath() -> String? {
        guard let repo = resolvedRepoRoot() else { return nil }
        return (repo as NSString).appendingPathComponent("deliverables/archive")
    }

    private func filteredCampaigns() -> [RecentCampaign] {
        let query = campaignSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = recentCampaigns

        switch campaignFilter {
        case .all:
            if !showHiddenCampaigns {
                items = items.filter { !$0.isHidden }
            }
        case .withZips:
            items = items.filter { $0.hasZips }
            if !showHiddenCampaigns {
                items = items.filter { !$0.isHidden }
            }
        case .hidden:
            items = items.filter { $0.isHidden }
        }

        if !query.isEmpty {
            items = items.filter { $0.campaign.lowercased().contains(query) }
        }

        return items
    }

    private enum CampaignFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case withZips = "With ZIPs"
        case hidden = "Hidden"

        var id: String { rawValue }
    }

    private func statusBadge(for item: RecentCampaign) -> some View {
        let text = item.hasZips ? "Ready" : "Incomplete"
        let color: Color = item.hasZips ? .green : .secondary
        return Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(item.hasZips ? 0.15 : 0.08))
            )
    }

    private func readyToSendHint() -> String? {
        guard !isRunning, let code = lastExitCode else { return nil }
        if code == 0 {
            return "Send the ZIP files to the client. Start with Open Ship Root."
        }
        if code == 1 {
            return "Issues found. Send the ZIP files after reviewing. Start with Open Ship Root."
        }
        if code == 2 {
            return "Run failed. Check Advanced logs."
        }
        return nil
    }

    private func statusBadgeSubline(for code: Int32) -> String {
        if code == 0 { return "Last run OK" }
        if code == 1 { return "Last run: issues found" }
        if code == 2 { return "Last run failed" }
        return "Last run unknown"
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
