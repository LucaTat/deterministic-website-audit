import SwiftUI
import AppKit
import Darwin

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

struct CampaignManagerItem: Identifiable {
    let id: String
    let campaign: String
    let lang: String
    let lastModified: Date
    let runDirCount: Int
    let sizeBytes: Int64?
    let path: String
    let manifest: CampaignManifest
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
    @State private var isShowingLogOutput: Bool = false
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
    @State private var lastRunDir: String? = nil
    @State private var lastRunLogPath: String? = nil
    @State private var lastRunDomain: String? = nil
    @State private var showAdvanced: Bool = false
    @State private var recentCampaigns: [RecentCampaign] = []
    @State private var runHistory: [RunEntry] = []
    @State private var repoRoot: String? = nil
    @State private var exportStatus: String? = nil
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
    @State private var campaignsPanel: [CampaignSummary] = []
    @State private var expandedCampaigns: Set<String> = []
    @State private var pendingDeleteCampaign: CampaignSummary? = nil
    @State private var showDeleteCampaignConfirm: Bool = false
    @State private var showAbout: Bool = false
    @State private var demoDeliverablePath: String? = nil
    @State private var showCampaignManager: Bool = false
    @State private var campaignManagerItems: [CampaignManagerItem] = []
    @State private var campaignManagerSelection: Set<String> = []
    @State private var showCampaignManagerDeleteConfirm: Bool = false
    @State private var campaignManagerStatus: String? = nil
    @State private var showAllRunsSheet: Bool = false
    @State private var showDeleteRunConfirm: Bool = false
    @State private var pendingDeleteRun: RunRecord? = nil
    @State private var showDeleteCampaignRunConfirm: Bool = false
    @State private var pendingDeleteCampaignRun: RunRecord? = nil
    @State private var showManageCampaignsSheet: Bool = false
    @State private var showManageCampaignDeleteConfirm: Bool = false
    @State private var pendingManageDeleteCampaign: CampaignSummary? = nil

    @State private var exportIsRunning: Bool = false
    @State private var exportStatusText: String = "Ready"
    @State private var runExportTask: Process? = nil
    @State private var runExportRunID: String? = nil
    @State private var runExportCancelRequested: Bool = false

    @State private var toolRunning: Bool = false
    @State private var toolStatus: String? = nil
    @State private var toolTask: Process? = nil
    @State private var toolRunID: String? = nil
    
    @State private var uiRefreshTick: Int = 0
    @State private var showNewCampaignSheet: Bool = false
    @StateObject private var store = CampaignStore(repoRoot: "")
    @AppStorage("scopeTheme") private var themeRaw: String = Theme.light.rawValue
    @AppStorage("scope_use_ai") private var useAI: Bool = true
    @AppStorage("scope_analysis_mode") private var analysisModeRaw: String = "standard"
    @AppStorage("astraRootPath") private var astraRootPath: String = ""
    private let runHistoryKey = "astraRunHistory"
    private let logQueue = DispatchQueue(label: "scope.log.write.queue")

    private var analysisMode: String {
        analysisModeRaw == "extended" ? "extended" : "standard"
    }

    private var theme: Theme { Theme(rawValue: themeRaw) ?? .light }

    var body: some View {
        rootView
        .background(theme.background)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .animation(.easeInOut(duration: 0.2), value: themeRaw)
        .frame(minWidth: 980, minHeight: 720)
        .sheet(isPresented: $showAbout) {
            AboutView()
                .frame(width: 520, height: 560)
        }
        .sheet(isPresented: $showCampaignManager) {
            campaignManagerSheet()
        }
        .sheet(isPresented: $showManageCampaignsSheet) {
            manageCampaignsSheet()
        }
        .sheet(isPresented: $showAllRunsSheet) {
            allRunsSheet()
        }
        .sheet(isPresented: $showNewCampaignSheet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("New Campaign")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Spacer()
                }

                TextField("Campaign name", text: $campaign)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showNewCampaignSheet = false
                        campaign = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Create") {
                        if let _ = store.createCampaign(name: campaign) {
                            campaign = ""
                            refreshCampaignsPanel()
                            refreshRecentCampaigns()
                        }
                        showNewCampaignSheet = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(campaign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .frame(minWidth: 420)
            .background(theme.background)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.accent)
        }
        .alert("Delete campaign?", isPresented: $showDeleteCampaignConfirm) {
            Button("Delete", role: .destructive) {
                if let campaign = pendingDeleteCampaign {
                    deleteCampaign(campaign)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let name = pendingDeleteCampaign?.name ?? ""
            Text("Delete campaign '\(name)'? This removes all runs and deliverables.")
        }
        .alert("Delete campaign?", isPresented: $showManageCampaignDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let campaign = pendingManageDeleteCampaign {
                    deleteManagedCampaign(campaign)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let name = pendingManageDeleteCampaign?.name ?? ""
            Text("Delete campaign '\(name)'? This permanently deletes all runs and deliverables.")
        }
        .alert("Delete run?", isPresented: $showDeleteRunConfirm) {
            Button("Delete", role: .destructive) {
                if let run = pendingDeleteRun {
                    deleteRunRecord(run)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the run and its artifacts.")
        }
        .alert("Delete run?", isPresented: $showDeleteCampaignRunConfirm) {
            Button("Delete", role: .destructive) {
                if let run = pendingDeleteCampaignRun {
                    deleteRunRecord(run)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the run and its artifacts.")
        }
        .onAppear {
            repoRoot = resolvedRepoRoot()
            if let repoRoot { store.repoRoot = repoRoot }
            refreshRecentCampaigns()
            runHistory = loadRunHistory()
            migrateLegacyRunsIfNeeded()
            refreshCampaignsPanel()
            runOverwriteURLTests()
        }
        .onChange(of: repoRoot) { _, _ in
            if let repoRoot { store.repoRoot = repoRoot }
            refreshRecentCampaigns()
            migrateLegacyRunsIfNeeded()
            refreshCampaignsPanel()
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

    private var rootView: some View {
        Group {
            // Force a dependency so bumpUIRefresh() triggers recompute
            let _ = uiRefreshTick

            // If you intended some conditional behavior, do it without returning nil
            // For now: render the normal main UI.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    pathsSection
                    runControlsSection
                    campaignsSection
                }
                .padding(20)
            }
        }
    }

    private func bumpUIRefresh() {
        uiRefreshTick &+= 1
    }

    private var headerSection: some View {
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
                            let campaigns: [Campaign] = {
                                guard let exportRoot = exportRootPath() else { return [] }
                                return store.listCampaignsForPicker(exportRoot: exportRoot)
                            }()
                            Picker("", selection: Binding<String?>(
                                get: { store.selectedCampaignID },
                                set: { store.selectedCampaignID = $0 }
                            )) {
                                if campaigns.isEmpty {
                                    Text("No campaign selected").tag(String?.none)
                                }
                                ForEach(campaigns) { item in
                                    Text(item.name).tag(Optional(item.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240)
                            .help("Select campaign")

                            Button("New Campaign…") {
                                showNewCampaignSheet = true
                            }
                            .buttonStyle(.bordered)

                            Button("Manage Campaigns") {
                                showManageCampaignsSheet = true
                            }
                            .buttonStyle(.bordered)

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
                        if store.selectedCampaignID == nil {
                            Text("No campaign selected")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.leading, labelWidth)
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
        }
    }

    private var runControlsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("Run").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        let astraTrimmed = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        let astraReady = !astraTrimmed.isEmpty && FileManager.default.fileExists(atPath: astraTrimmed)
                        let runDisabled = isRunning || !hasAtLeastOneValidURL() || !campaignIsValid() || !engineFolderAvailable() || !astraReady
                        Button { runAudit() } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(NeonPrimaryButtonStyle(theme: theme, isRunning: isRunning))
                        .controlSize(.large)
                        .disabled(runDisabled)
                        .opacity(buttonOpacity(disabled: runDisabled))
                        .help(runHelpText())
                        InfoButton(text: "Runs the audit engine and prepares deliverables. When finished, use Export/Delivery to send ZIPs.")

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

                        let demoDisabled = isRunning || !engineFolderAvailable() || !astraReady
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
                        .help(outputHelpText())

                        let logsDisabled = isRunning || scopeRunLogPath() == nil
                        Button { openLogs() } label: {
                            Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                        .disabled(logsDisabled)
                        .opacity(buttonOpacity(disabled: logsDisabled))
                        .help(logsHelpText())

                        let runFolderDisabled = isRunning || lastRunDir == nil
                        Button {
                            if let path = lastRunDir {
                                openFolder(path)
                            }
                        } label: {
                            Label("Open Run Folder", systemImage: "folder.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(runFolderDisabled)
                        .opacity(buttonOpacity(disabled: runFolderDisabled))
                        .help("Open the latest run folder")
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
                            .help("Reveal demo output folder")
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
                            Label("Open Export/Delivery Root", systemImage: "shippingbox.fill")
                        }
                        .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                        .controlSize(.large)
                        .font(.headline)
                        .disabled(shipRootDisabled)
                        .opacity(buttonOpacity(disabled: shipRootDisabled))
                        .help(shipRootHelpText())
                        InfoButton(text: "Opens the export/delivery root folder for this campaign.")
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
                                    Label("Decision Brief RO", systemImage: "doc.richtext")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .disabled(shipRoDisabled)
                                .opacity(buttonOpacity(disabled: shipRoDisabled))
                                .help("Open Decision Brief (RO)")
                                InfoButton(text: "Opens the Decision Brief PDF for this campaign/language.")
                            }

                            HStack(spacing: 6) {
                                let shipEnDisabled = isRunning || shipDirPath(forLang: "en") == nil
                                Button { openShipFolder(forLang: "en") } label: {
                                    Label("Decision Brief EN", systemImage: "doc.richtext")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .disabled(shipEnDisabled)
                                .opacity(buttonOpacity(disabled: shipEnDisabled))
                                .help("Open Decision Brief (EN)")
                                InfoButton(text: "Opens the Decision Brief PDF for this campaign/language.")
                            }

                            HStack(spacing: 6) {
                                let appendixRoDisabled = isRunning || appendixPath(forLang: "ro") == nil
                                Button { openAppendix(forLang: "ro") } label: {
                                    Label("Evidence Appendix RO", systemImage: "doc.append")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .disabled(appendixRoDisabled)
                                .opacity(buttonOpacity(disabled: appendixRoDisabled))
                                .help("Open Evidence Appendix (RO)")
                                InfoButton(text: "Opens the Evidence Appendix PDF for this campaign/language.")
                            }

                            HStack(spacing: 6) {
                                let appendixEnDisabled = isRunning || appendixPath(forLang: "en") == nil
                                Button { openAppendix(forLang: "en") } label: {
                                    Label("Evidence Appendix EN", systemImage: "doc.append")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .disabled(appendixEnDisabled)
                                .opacity(buttonOpacity(disabled: appendixEnDisabled))
                                .help("Open Evidence Appendix (EN)")
                                InfoButton(text: "Opens the Evidence Appendix PDF for this campaign/language.")
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
                                    Label(lang == "ro" ? "Decision Brief RO" : "Decision Brief EN", systemImage: "doc.richtext")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .disabled(shipSingleDisabled)
                                .opacity(buttonOpacity(disabled: shipSingleDisabled))
                                .help("Open Decision Brief")
                                InfoButton(text: "Opens the Decision Brief PDF for this campaign/language.")
                            }

                            HStack(spacing: 6) {
                                let appendixSingleDisabled = isRunning || appendixPath(forLang: lang) == nil
                                Button { openAppendix(forLang: lang) } label: {
                                    Label(lang == "ro" ? "Evidence Appendix RO" : "Evidence Appendix EN", systemImage: "doc.append")
                                }
                                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                                .disabled(appendixSingleDisabled)
                                .opacity(buttonOpacity(disabled: appendixSingleDisabled))
                                .help("Open Evidence Appendix")
                                InfoButton(text: "Opens the Evidence Appendix PDF for this campaign/language.")
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
                            let logsDisabled = isRunning || scopeRunLogPath() == nil
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

                    if readyToSend && (lastRunStatus == "SUCCESS" || lastRunStatus == "WARNING") {
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
        }
    }

    private var campaignsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(label: Text("History").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    let scopedRuns = campaignScopedRunHistory()
                    HStack {
                        Text("Recent runs (ASTRA)")
                            .font(.headline)
                        Spacer()
                        if scopedRuns.count > 10 {
                            Button("View all…") {
                                showAllRunsSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if scopedRuns.isEmpty {
                        Text("No runs yet.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(scopedRuns.prefix(10)) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("\(formatRunTimestamp(entry.timestamp)) • \(entry.lang.uppercased()) • \(entry.url)")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        let runDir = runRootPath(for: entry) ?? ""
                                        let exportedZip = runDir.isEmpty ? "" : (runDir as NSString).appendingPathComponent("final/client_safe_bundle.zip")
                                        let hasExport = !exportedZip.isEmpty && FileManager.default.fileExists(atPath: exportedZip)
                                        let showExporting = exportIsRunning && runExportRunID == entry.id
                                        let showFailed = (!exportStatusText.isEmpty && exportStatusText.hasPrefix("ERROR:") && runExportRunID == entry.id)
                                        let badgeText = showExporting ? "EXPORTING" : (showFailed ? "FAILED" : (hasExport ? "EXPORTED" : "NOT EXPORTED"))
                                        let badgeColor: Color = showExporting ? .blue : (showFailed ? .red : (hasExport ? .green : .secondary))
                                        Text(badgeText)
                                            .font(.caption)
                                            .foregroundColor(badgeColor)
                                    }
                                    HStack(spacing: 8) {
                                        let outDisabled = isRunning || entry.deliverablesDir.isEmpty || !FileManager.default.fileExists(atPath: entry.deliverablesDir)
                                        Button { openFolder(entry.deliverablesDir) } label: {
                                            Text("Open Output")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(outDisabled)
                                        .opacity(buttonOpacity(disabled: outDisabled))

                                        let reportDisabled = isRunning || (entry.reportPdfPath == nil)
                                        Button {
                                            if let path = entry.reportPdfPath { revealAndOpenFile(path) }
                                        } label: {
                                            Text("Open Report")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(reportDisabled)
                                        .opacity(buttonOpacity(disabled: reportDisabled))

                                        let logDisabled = isRunning || (entry.logPath == nil)
                                        Button {
                                            if let path = entry.logPath { revealAndOpenFile(path) }
                                        } label: {
                                            Text("Open Log")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(logDisabled)
                                        .opacity(buttonOpacity(disabled: logDisabled))

                                        let exportDisabled = isRunning || exportIsRunning
                                        Button("Export Client Bundle") {
                                            runExportClientBundle(for: entry)
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(exportDisabled)
                                        .opacity(buttonOpacity(disabled: exportDisabled))

                                        if exportIsRunning && runExportRunID == entry.id {
                                            Button("Cancel Export") {
                                                cancelRunExport()
                                            }
                                            .buttonStyle(.bordered)
                                        }

                                        let toolDisabled = isRunning || exportIsRunning || toolRunning
                                        Button("Run Tool 2 — Action Scope") {
                                            guard let repoRoot = resolvedRepoRoot() else {
                                                toolStatus = "Export failed: Tool 2"
                                                return
                                            }
                                            let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool2_action_scope.sh")
                                            runTool(stepName: "Tool 2", scriptPath: scriptPath, entry: entry, expectedFolder: "action_scope")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(toolDisabled)
                                        .opacity(buttonOpacity(disabled: toolDisabled))

                                        Button("Run Tool 3 — Implementation Proof") {
                                            guard let repoRoot = resolvedRepoRoot() else {
                                                toolStatus = "Export failed: Tool 3"
                                                return
                                            }
                                            let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool3_proof_pack.sh")
                                            runTool(stepName: "Tool 3", scriptPath: scriptPath, entry: entry, expectedFolder: "proof_pack")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(toolDisabled)
                                        .opacity(buttonOpacity(disabled: toolDisabled))

                                        Button("Run Tool 4 — Regression Guard") {
                                            guard let repoRoot = resolvedRepoRoot() else {
                                                toolStatus = "Export failed: Tool 4"
                                                return
                                            }
                                            let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool4_regression.sh")
                                            runTool(stepName: "Tool 4", scriptPath: scriptPath, entry: entry, expectedFolder: "regression")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(toolDisabled)
                                        .opacity(buttonOpacity(disabled: toolDisabled))

                                        let tool2Path = toolPDFPath(for: entry, tool: "tool2") ?? ""
                                        let tool2Disabled = toolDisabled || tool2Path.isEmpty || !FileManager.default.fileExists(atPath: tool2Path)
                                        Button("Open Tool2 Output") {
                                            openToolOutput(for: entry, tool: "tool2")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(tool2Disabled)
                                        .opacity(buttonOpacity(disabled: tool2Disabled))

                                        let tool3Path = toolPDFPath(for: entry, tool: "tool3") ?? ""
                                        let tool3Disabled = toolDisabled || tool3Path.isEmpty || !FileManager.default.fileExists(atPath: tool3Path)
                                        Button("Open Tool3 Output") {
                                            openToolOutput(for: entry, tool: "tool3")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(tool3Disabled)
                                        .opacity(buttonOpacity(disabled: tool3Disabled))

                                        let tool4Path = toolPDFPath(for: entry, tool: "tool4") ?? ""
                                        let tool4Disabled = toolDisabled || tool4Path.isEmpty || !FileManager.default.fileExists(atPath: tool4Path)
                                        Button("Open Tool4 Output") {
                                            openToolOutput(for: entry, tool: "tool4")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(tool4Disabled)
                                        .opacity(buttonOpacity(disabled: tool4Disabled))

                                        Button("Delete Run") {
                                            pendingDeleteRun = RunRecord(entry: entry)
                                            showDeleteRunConfirm = true
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    Text(exportStatusLabel(for: entry))
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                    if toolRunID == entry.id, let status = toolStatus {
                                        Text(status)
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Divider()
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 10) {
                        let repoAvailable = (resolvedRepoRoot() != nil)
                        Button { openArchiveRoot() } label: {
                            Label("Open Archive", systemImage: "tray.full.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!repoAvailable)
                        .opacity(buttonOpacity(disabled: !repoAvailable))
                        .help(repoAvailable ? "Open deliverables/campaigns" : "Select a repo to enable")

                        Button { openTodaysArchive() } label: {
                            Label("Open Today's Archive", systemImage: "calendar")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!repoAvailable)
                        .opacity(buttonOpacity(disabled: !repoAvailable))
                        .help(repoAvailable ? "Open deliverables/campaigns" : "Select a repo to enable")

                    }

                    Text("Recent campaigns")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Search campaigns…", text: $campaignSearch)
                            .textFieldStyle(.roundedBorder)

                        Picker("", selection: $campaignFilter) {
                            Text("All").tag(CampaignFilter.all)
                            Text("Ready").tag(CampaignFilter.withRuns)
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
                                        Text("\(item.campaign) • \(item.lang) • Updated \(formatRunTimestamp(item.lastModified))")
                                            .font(.subheadline)
                                            .foregroundColor(item.isHidden ? .secondary : .primary)
                                            .opacity(item.isHidden ? 0.6 : 1.0)
                                        statusBadge(for: item)
                                        Spacer()
                                        Button { openFolder(item.path) } label: {
                                            Text("Open")
                                        }
                                        .buttonStyle(.bordered)

                                        Button { openCampaignSites(item) } label: {
                                            Text("Reveal Sites")
                                        }
                                        .buttonStyle(.bordered)

                                        Button { deleteCampaignEverywhere(item) } label: {
                                            Text("Delete")
                                        }
                                        .buttonStyle(.bordered)
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

            GroupBox(label: Text("Campaigns").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Campaign storage")
                            .font(.headline)
                        Spacer()
                    }

                    if campaignsPanel.isEmpty {
                        Text("No campaigns yet.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(campaignsPanel) { campaign in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("\(campaign.name) • \(campaign.langs.joined(separator: ", ")) • Runs \(campaign.runCount)")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Button("Open") {
                                            openFolder(campaign.campaignURL.path)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Export") {
                                            exportCampaignFolder(campaign)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Delete") {
                                            pendingDeleteCampaign = campaign
                                            showDeleteCampaignConfirm = true
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    DisclosureGroup("Manage runs", isExpanded: Binding<Bool>(
                                        get: { expandedCampaigns.contains(campaign.id) },
                                        set: { expanded in
                                            if expanded {
                                                expandedCampaigns.insert(campaign.id)
                                            } else {
                                                expandedCampaigns.remove(campaign.id)
                                            }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            let sortedRuns = campaign.runs.sorted { $0.run.timestamp > $1.run.timestamp }
                                            let shownRuns = Array(sortedRuns.prefix(10))
                                            ForEach(shownRuns) { run in
                                                HStack(alignment: .top, spacing: 12) {
                                                    Text("\(formatCampaignRunTimestamp(run.run.timestamp)) • \(run.run.domain) • \(run.run.url)")
                                                        .font(.footnote)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Button("Open Run") {
                                                        openFolder(run.runURL.path)
                                                    }
                                                    .buttonStyle(.bordered)

                                                    Button("Delete Run") {
                                                        let record = RunRecord(
                                                            id: run.id,
                                                            runDir: "",
                                                            deliverablesDir: run.runURL.path,
                                                            logPath: nil
                                                        )
                                                        pendingDeleteCampaignRun = record
                                                        showDeleteCampaignRunConfirm = true
                                                    }
                                                    .buttonStyle(.bordered)
                                                }
                                            }
                                            if sortedRuns.count > 10 {
                                                Text("Showing last 10 runs")
                                                    .font(.footnote)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(8)
                                .background(theme.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.border, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .modifier(CardStyle(theme: theme))


        }
    }

    private var pathsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                DisclosureGroup("Advanced (debug & logs)", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Engine & ASTRA")
                            .font(.headline)

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
                            .help("Reveal the engine repo folder in Finder")

                            Spacer()
                        }

                        Text(engineFolderSummary())
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ASTRA repo")
                            .font(.headline)

                        HStack(spacing: 12) {
                            let selectDisabled = isRunning
                            Button { selectAstraFolder() } label: {
                                Label("Select ASTRA Folder", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(selectDisabled)
                            .opacity(buttonOpacity(disabled: selectDisabled))
                            .help("Select the ASTRA repo folder")

                            let showDisabled = isRunning || !astraFolderAvailable()
                            Button { showAstraFolder() } label: {
                                Label("Show ASTRA Folder", systemImage: "folder")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(showDisabled)
                            .opacity(buttonOpacity(disabled: showDisabled))
                            .help("Reveal the ASTRA repo folder in Finder")
                            Spacer()
                        }

                        Text(astraFolderSummary())
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debugging")
                            .font(.headline)

                        HStack(spacing: 10) {
                            Button { revealLatestDeliverables() } label: {
                                Label("Reveal latest deliverables", systemImage: "folder.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning || lastRunDir == nil)
                            .opacity(buttonOpacity(disabled: isRunning || lastRunDir == nil))

                            Button { openLogOutputModal() } label: {
                                Label("Show log output", systemImage: "doc.text")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning || logOutput.isEmpty)
                            .opacity(buttonOpacity(disabled: isRunning || logOutput.isEmpty))

                            Button { clearLogOutput() } label: {
                                Label("Clear log output", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning || logOutput.isEmpty)
                            .opacity(buttonOpacity(disabled: isRunning || logOutput.isEmpty))
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("History cleanup")
                            .font(.headline)

                        HStack(spacing: 10) {
                            Button { prepareDeleteHidden() } label: {
                                Text("Delete hidden campaigns…")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                            .opacity(buttonOpacity(disabled: isRunning))

                            Button { prepareDeleteIncomplete() } label: {
                                Text("Delete incomplete campaigns…")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                            .opacity(buttonOpacity(disabled: isRunning))
                        }

                        if showDeleteHiddenConfirm {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("This will permanently delete \(deleteHiddenCount) hidden campaigns from disk.")
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

                        if showDeleteIncompleteConfirm {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("This will permanently delete \(deleteIncompleteCount) incomplete campaigns from disk.")
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
        } else if let status = lastRunStatus {
            let (text, color): (String, Color) = {
                switch status {
                case "SUCCESS": return ("Ready to send", .green)
                case "WARNING": return ("Ready to send (warnings)", .orange)
                case "FAILED": return ("Run failed", .red)
                case "Canceled": return ("Canceled", .secondary)
                default: return ("Run finished", .secondary)
                }
            }()

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.headline)
                    .foregroundColor(color)
                Text(statusBadgeSubline(for: status))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(color.opacity(0.12)))
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
                Text(statusBadgeSubline(for: statusLabel(for: code)))
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

    private func isSuccessStatus(_ status: String) -> Bool {
        status == "OK" || status == "SUCCESS"
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
        lastRunDir = nil
        lastRunLogPath = nil
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
        store.selectedCampaignID != nil
    }

    private func runDisabledReason() -> String? {
        if isRunning { return "Run disabled: Running…" }
        if !engineFolderAvailable() { return "Select Engine Folder to continue." }
        let astraTrimmed = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if astraTrimmed.isEmpty { return "Select ASTRA Folder to continue." }
        if !FileManager.default.fileExists(atPath: astraTrimmed) { return "ASTRA folder not found. Select ASTRA Folder." }
        if !campaignIsValid() { return "Select Campaign" }
        if !hasAtLeastOneValidURL() { return "Run disabled: Add at least 1 valid URL" }
        return nil
    }

    private func buttonOpacity(disabled: Bool) -> Double {
        disabled ? 0.6 : 1.0
    }

    private func shipDisabledReason() -> String? {
        if isRunning { return "Delivery disabled: Running…" }
        if !hasShipForCurrentLang() { return "Delivery disabled: No export folder yet" }
        return nil
    }

    private func zipDisabledReason() -> String? {
        if isRunning { return "ZIP disabled: Running…" }
        if !hasZipForCurrentLang() { return "ZIP disabled: No ZIP yet" }
        return nil
    }

    private func pdfDisabledReason() -> String? {
        if isRunning { return "PDF disabled: Running…" }
        if selectedPDF == nil { return "PDF disabled: No PDFs yet" }
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
        return "Run the audit pipeline (requires Engine + ASTRA folders)"
    }

    private func shipHelpText(forLang lang: String) -> String {
        if let reason = shipDisabledReason() {
            return "Open export/delivery folder. \(reason)"
        }
        if lang == "ro" { return "Open the RO export/delivery folder" }
        if lang == "en" { return "Open the EN export/delivery folder" }
        return "Open the export/delivery folder"
    }

    private func shipRootHelpText() -> String {
        if shipRootPath() == nil {
            return "Open export/delivery root. Available after run."
        }
        return "Open the export/delivery root folder for this campaign"
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
        if store.selectedCampaignID == nil {
            return "Select a campaign to reveal output."
        }
        if outputFolderPath() == nil {
            return "Open campaign folder. Available after run."
        }
        return "Open campaign folder"
    }

    private func logsHelpText() -> String {
        if scopeRunLogPath() == nil {
            return "scope_run.log not found yet. Finish a run to enable logs."
        }
        return "Open scope_run.log for the last run"
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

    private func formatRunTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatCampaignRunTimestamp(_ value: String) -> String {
        if let date = parseISO8601Date(value) {
            return formatRunTimestamp(date)
        }
        return value
    }

    private func exportRootPath() -> String? {
        guard let repo = resolvedRepoRoot() else { return nil }
        return (repo as NSString).appendingPathComponent("deliverables")
    }

    private func campaignStore() -> CampaignStore? {
        guard let repo = resolvedRepoRoot() else { return nil }
        if store.repoRoot != repo {
            store.repoRoot = repo
        }
        return store
    }

    private func campaignsRootPath() -> String? {
        guard let exportRoot = exportRootPath() else { return nil }
        return (exportRoot as NSString).appendingPathComponent("campaigns")
    }

    private func campaignFolderPath(campaignName: String, lang: String) -> String? {
        guard let store = campaignStore(), let exportRoot = exportRootPath() else { return nil }
        return store.campaignLangURL(campaign: campaignName, lang: lang, exportRoot: exportRoot).path
    }

    private func sitesRootPath(campaignLangPath: String) -> String {
        campaignLangPath
    }

    private func domainFromURLString(_ url: String) -> String? {
        guard let parsed = URL(string: url), let host = parsed.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    private func normalizeURLForOverwrite(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        var working = trimmed
        if !working.contains("://") { working = "https://" + working }
        guard var comps = URLComponents(string: working) else { return trimmed }
        comps.fragment = nil
        comps.query = nil
        if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
        if let host = comps.host { comps.host = host.lowercased() }
        let path = comps.path.isEmpty ? "/" : comps.path
        if path.count > 1 && path.hasSuffix("/") {
            comps.path = String(path.dropLast())
        } else {
            comps.path = path
        }
        return comps.string ?? trimmed
    }

    private func runOverwriteURLTests() {
#if DEBUG
        assert(normalizeURLForOverwrite("https://magic-gym.ro") == normalizeURLForOverwrite("https://magic-gym.ro/"))
        assert(normalizeURLForOverwrite("https://example.com/path") == normalizeURLForOverwrite("https://example.com/path/"))
        assert(normalizeURLForOverwrite("https://example.com/path?x=1") == normalizeURLForOverwrite("https://example.com/path?x=2"))
#endif
    }

    private func openCampaignManager() {
        campaignManagerSelection = []
        campaignManagerItems = loadCampaignManagerItems()
        campaignManagerStatus = nil
        showCampaignManager = true
    }

    private func refreshCampaignsPanel() {
        guard let exportRoot = exportRootPath() else {
            campaignsPanel = []
            return
        }
        campaignsPanel = campaignStore()?.listCampaigns(exportRoot: exportRoot) ?? []
    }

    private func exportCampaignFolder(_ campaign: CampaignSummary) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a destination folder for export"

        panel.begin { resp in
            guard resp == .OK, let destUrl = panel.url else { return }
            let store = self.campaignStore()
            let safeName = store?.campaignFolderName(for: campaign.name) ?? campaign.name
            let zipName = "\(safeName)_ASTRA.zip"
            let destPath = (destUrl.path as NSString).appendingPathComponent(zipName)
            let fm = FileManager.default
            try? fm.removeItem(atPath: destPath)
            do {
                try zipFolderWithDitto(sourceFolder: campaign.campaignURL, zipPath: destPath)
            } catch {
                return
            }
        }
    }

    private func deleteCampaign(_ campaign: CampaignSummary) {
        if let exportRoot = exportRootPath() {
            let target = Campaign(id: campaign.campaignURL.path, name: campaign.name, campaignURL: campaign.campaignURL)
            do {
                try store.deleteCampaign(target, alsoDeleteAstra: true)
                runHistory = store.loadRunHistory()
                refreshRecentCampaigns()
                if store.selectedCampaignID == campaign.campaignURL.path {
                    let remaining = store.listCampaigns(exportRoot: exportRoot)
                    if let next = remaining.first {
                        store.selectedCampaignID = next.campaignURL.path
                    } else {
                        store.selectedCampaignID = nil
                    }
                }
            } catch {
                alert(title: "Delete failed", message: error.localizedDescription)
            }
        }
        pendingDeleteCampaign = nil
        refreshCampaignsPanel()
    }

    private func deleteCampaignRun(_ run: CampaignRunItem) {
        let record = RunRecord(id: run.id, runDir: "", deliverablesDir: run.runURL.path, logPath: nil)
        deleteRunRecord(record)
    }

    @ViewBuilder
    private func campaignManagerSheet() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Campaign Manager")
                    .font(.title3)
                    .foregroundColor(.primary)
                Spacer()
                Button("Close") {
                    showCampaignManager = false
                }
                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
            }

            if let status = campaignManagerStatus {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if campaignManagerItems.isEmpty {
                Text("No campaigns found.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(campaignManagerItems) { item in
                            HStack(alignment: .center, spacing: 12) {
                                Toggle(isOn: campaignManagerSelectionBinding(for: item.id)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.campaign)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        let detail = "Lang: \(item.lang.uppercased()) • Updated \(formatRunTimestamp(item.lastModified)) • Runs \(item.runDirCount)"
                                        Text(detail)
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                        if let size = item.sizeBytes {
                                            Text("Size: \(formatByteCount(size))")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)

                                Spacer()

                                Button("Open") {
                                    openFolder(item.path)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(theme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Delete Selected (Everywhere)") {
                    showCampaignManagerDeleteConfirm = true
                }
                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                .disabled(campaignManagerSelection.isEmpty)
                .opacity(buttonOpacity(disabled: campaignManagerSelection.isEmpty))
                .help("Delete campaign folder and associated ASTRA run dirs")

                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 860, minHeight: 520)
        .background(theme.background)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .alert("Delete selected campaigns?", isPresented: $showCampaignManagerDeleteConfirm) {
            Button("Delete", role: .destructive) {
                deleteSelectedCampaignsEverywhere()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the campaign folders and their ASTRA run directories.")
        }
    }

    @ViewBuilder
    private func manageCampaignsSheet() -> some View {
        let items = manageCampaignsList()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage Campaigns")
                    .font(.title3)
                    .foregroundColor(.primary)
                Spacer()
                Button("Close") {
                    showManageCampaignsSheet = false
                }
                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
            }

            if items.isEmpty {
                Text("No campaigns found.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Updated \(formatRunTimestamp(item.lastUpdated)) • Runs \(item.runCount)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Reveal") {
                                    openFolder(item.campaignURL.path)
                                }
                                .buttonStyle(.bordered)

                                Button("Delete") {
                                    pendingManageDeleteCampaign = item
                                    showManageCampaignDeleteConfirm = true
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            .padding(8)
                            .background(theme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
        .background(theme.background)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
    }

    @ViewBuilder
    private func allRunsSheet() -> some View {
        let scopedRuns = campaignScopedRunHistory()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All runs (ASTRA)")
                    .font(.title3)
                    .foregroundColor(.primary)
                Spacer()
                Button("Close") {
                    showAllRunsSheet = false
                }
                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
            }

            if scopedRuns.isEmpty {
                Text("No runs yet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(scopedRuns) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(formatRunTimestamp(entry.timestamp)) • \(entry.lang.uppercased()) • \(entry.url)")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                        Text(entry.status)
                                            .font(.caption)
                                            .foregroundColor(isSuccessStatus(entry.status) ? .green : .orange)
                                }
                                HStack(spacing: 8) {
                                    let outDisabled = isRunning || entry.deliverablesDir.isEmpty || !FileManager.default.fileExists(atPath: entry.deliverablesDir)
                                    Button { openFolder(entry.deliverablesDir) } label: {
                                        Text("Open Output")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(outDisabled)
                                    .opacity(buttonOpacity(disabled: outDisabled))

                                    let reportDisabled = isRunning || (entry.reportPdfPath == nil)
                                    Button {
                                        if let path = entry.reportPdfPath { revealAndOpenFile(path) }
                                    } label: {
                                        Text("Open Report")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(reportDisabled)
                                    .opacity(buttonOpacity(disabled: reportDisabled))

                                    let logDisabled = isRunning || (entry.logPath == nil)
                                    Button {
                                        if let path = entry.logPath { revealAndOpenFile(path) }
                                    } label: {
                                        Text("Open Log")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(logDisabled)
                                    .opacity(buttonOpacity(disabled: logDisabled))

                                    let exportDisabled = isRunning || exportIsRunning
                                    Button("Export Client Bundle") {
                                        runExportClientBundle(for: entry)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(exportDisabled)
                                    .opacity(buttonOpacity(disabled: exportDisabled))

                                    if exportIsRunning && runExportRunID == entry.id {
                                        Button("Cancel Export") {
                                            cancelRunExport()
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    let toolDisabled = isRunning || exportIsRunning || toolRunning
                                    Button("Run Tool 2 — Action Scope") {
                                        guard let repoRoot = resolvedRepoRoot() else {
                                            toolStatus = "Export failed: Tool 2"
                                            return
                                        }
                                        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool2_action_scope.sh")
                                        runTool(stepName: "Tool 2", scriptPath: scriptPath, entry: entry, expectedFolder: "action_scope")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(toolDisabled)
                                    .opacity(buttonOpacity(disabled: toolDisabled))

                                    Button("Run Tool 3 — Implementation Proof") {
                                        guard let repoRoot = resolvedRepoRoot() else {
                                            toolStatus = "Export failed: Tool 3"
                                            return
                                        }
                                        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool3_proof_pack.sh")
                                        runTool(stepName: "Tool 3", scriptPath: scriptPath, entry: entry, expectedFolder: "proof_pack")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(toolDisabled)
                                    .opacity(buttonOpacity(disabled: toolDisabled))

                                    Button("Run Tool 4 — Regression Guard") {
                                        guard let repoRoot = resolvedRepoRoot() else {
                                            toolStatus = "Export failed: Tool 4"
                                            return
                                        }
                                        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool4_regression.sh")
                                        runTool(stepName: "Tool 4", scriptPath: scriptPath, entry: entry, expectedFolder: "regression")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(toolDisabled)
                                    .opacity(buttonOpacity(disabled: toolDisabled))

                                    let tool2Path = toolPDFPath(for: entry, tool: "tool2") ?? ""
                                    let tool2Disabled = toolDisabled || tool2Path.isEmpty || !FileManager.default.fileExists(atPath: tool2Path)
                                    Button("Open Tool2 Output") {
                                        openToolOutput(for: entry, tool: "tool2")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(tool2Disabled)
                                    .opacity(buttonOpacity(disabled: tool2Disabled))

                                    let tool3Path = toolPDFPath(for: entry, tool: "tool3") ?? ""
                                    let tool3Disabled = toolDisabled || tool3Path.isEmpty || !FileManager.default.fileExists(atPath: tool3Path)
                                    Button("Open Tool3 Output") {
                                        openToolOutput(for: entry, tool: "tool3")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(tool3Disabled)
                                    .opacity(buttonOpacity(disabled: tool3Disabled))

                                    let tool4Path = toolPDFPath(for: entry, tool: "tool4") ?? ""
                                    let tool4Disabled = toolDisabled || tool4Path.isEmpty || !FileManager.default.fileExists(atPath: tool4Path)
                                    Button("Open Tool4 Output") {
                                        openToolOutput(for: entry, tool: "tool4")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(tool4Disabled)
                                    .opacity(buttonOpacity(disabled: tool4Disabled))

                                    Button("Delete Run") {
                                        pendingDeleteRun = RunRecord(entry: entry)
                                        showDeleteRunConfirm = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Text(exportStatusLabel(for: entry))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                if toolRunID == entry.id, let status = toolStatus {
                                    Text(status)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 860, minHeight: 520)
        .background(theme.background)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
    }


    private func manageCampaignsList() -> [CampaignSummary] {
        guard let exportRoot = exportRootPath() else { return [] }
        return store.listCampaigns(exportRoot: exportRoot)
    }

    private func deleteManagedCampaign(_ campaign: CampaignSummary) {
        guard let exportRoot = exportRootPath() else { return }
        let target = Campaign(id: campaign.campaignURL.path, name: campaign.name, campaignURL: campaign.campaignURL)
        do {
            try store.deleteCampaign(target, alsoDeleteAstra: true)
            refreshCampaignsPanel()
            refreshRecentCampaigns()
            runHistory = store.loadRunHistory()
            if store.selectedCampaignID == campaign.campaignURL.path {
                let remaining = store.listCampaigns(exportRoot: exportRoot)
                if let next = remaining.first {
                    store.selectedCampaignID = next.campaignURL.path
                } else {
                    store.selectedCampaignID = nil
                }
            }
        } catch {
            alert(title: "Delete failed", message: error.localizedDescription)
        }
        pendingManageDeleteCampaign = nil
    }

    private func deleteRunRecord(_ record: RunRecord) {
        do {
            try store.deleteRun(record, alsoDeleteAstra: true)
            runHistory = store.loadRunHistory()
            refreshCampaignsPanel()
            refreshRecentCampaigns()
        } catch {
            alert(title: "Delete failed", message: error.localizedDescription)
        }
        pendingDeleteRun = nil
        pendingDeleteCampaignRun = nil
    }

    private func campaignManagerSelectionBinding(for id: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { campaignManagerSelection.contains(id) },
            set: { isSelected in
                if isSelected {
                    campaignManagerSelection.insert(id)
                } else {
                    campaignManagerSelection.remove(id)
                }
            }
        )
    }

    private func revealLatestDeliverables() {
        guard let runDir = lastRunDir else { return }
        openFolder(runDir)
    }

    private func openLogOutputModal() {
        isShowingLogOutput = true
    }

    private func clearLogOutput() {
        logOutput = ""
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

    private func alertMissingPath(title: String, reason: String, path: String?) {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "(none)" : trimmed
        alert(title: title, message: "\(reason)\nResolved path: \(resolved)")
    }

    private func withExportRootAccess(_ action: () -> Void) {
        if store.isAppSandboxed, let rootURL = store.resolveExportRootURL() {
            let granted = rootURL.startAccessingSecurityScopedResource()
            defer {
                if granted {
                    rootURL.stopAccessingSecurityScopedResource()
                }
            }
            action()
            return
        }
        action()
    }

    private func openRoDeliverables() {
        let fm = FileManager.default
        guard let path = shipDirPath(forLang: "ro") else {
            alertMissingPath(title: "RO deliverables missing", reason: "No RO deliverables path recorded yet.", path: nil)
            openExportRootFallback()
            return
        }
        let baseURL = URL(fileURLWithPath: path)
        guard fm.fileExists(atPath: baseURL.path) else {
            alertMissingPath(title: "RO deliverables missing", reason: "RO deliverables not found on disk.", path: baseURL.path)
            openExportRootFallback()
            return
        }
        if baseURL.pathExtension.lowercased() == "pdf" {
            withExportRootAccess {
                NSWorkspace.shared.open(baseURL)
            }
            return
        }
        var isDir: ObjCBool = false
        let isDirectory = fm.fileExists(atPath: baseURL.path, isDirectory: &isDir) && isDir.boolValue
        if isDirectory {
            for candidate in roReportCandidates(for: baseURL) {
                if fm.fileExists(atPath: candidate.path) {
                    withExportRootAccess {
                        NSWorkspace.shared.open(candidate)
                    }
                    return
                }
            }
            withExportRootAccess {
                NSWorkspace.shared.open(baseURL)
            }
            return
        }
        withExportRootAccess {
            NSWorkspace.shared.open(baseURL)
        }
    }

    private func roReportCandidates(for baseURL: URL) -> [URL] {
        [
            baseURL.appendingPathComponent("Decision_Brief_RO.pdf"),
            baseURL.appendingPathComponent("deliverables").appendingPathComponent("Decision_Brief_RO.pdf"),
            baseURL.appendingPathComponent("astra").appendingPathComponent("deliverables").appendingPathComponent("Decision_Brief_RO.pdf")
        ]
    }

    private func openExportRootFallback() {
        guard let path = shipRootPath() else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openCampaignSites(_ item: RecentCampaign) {
        if FileManager.default.fileExists(atPath: item.sitesPath) {
            openFolder(item.sitesPath)
        } else {
            openFolder(item.path)
        }
    }

    private func confirmDeleteCampaign(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete campaign?"
        alert.informativeText = "This will permanently delete \(name) and associated ASTRA run folders."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    private func deleteCampaignEverywhere(_ item: RecentCampaign) {
        guard confirmDeleteCampaign(item.campaign) else { return }
        guard let exportRoot = exportRootPath() else { return }
        let campaignURL = URL(fileURLWithPath: item.path)
        let target = Campaign(id: campaignURL.path, name: item.campaign, campaignURL: campaignURL)
        do {
            try store.deleteCampaign(target, alsoDeleteAstra: true)
            runHistory = store.loadRunHistory()
            refreshRecentCampaigns()
            refreshCampaignsPanel()
            if store.selectedCampaignID == campaignURL.path {
                let remaining = store.listCampaigns(exportRoot: exportRoot)
                if let next = remaining.first {
                    store.selectedCampaignID = next.campaignURL.path
                } else {
                    store.selectedCampaignID = nil
                }
            }
        } catch {
            alert(title: "Delete failed", message: error.localizedDescription)
        }
    }

    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)
    }

    private func directorySizeBytes(at path: String) -> Int64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func copyScopeFolderIfNeeded(from sourcePath: String, to destPath: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourcePath, isDirectory: &isDir), isDir.boolValue else { return }

        let maxBytes: Int64 = 200 * 1024 * 1024
        if let size = directorySizeBytes(at: sourcePath), size <= maxBytes {
            try? fm.copyItem(atPath: sourcePath, toPath: destPath)
            return
        }

        if !fm.fileExists(atPath: destPath) {
            try? fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)
        }
        let files = (try? fm.contentsOfDirectory(atPath: sourcePath)) ?? []
        for file in files {
            let lower = file.lowercased()
            guard lower.contains("summary") || lower.contains("evidence") else { continue }
            let src = (sourcePath as NSString).appendingPathComponent(file)
            let dst = (destPath as NSString).appendingPathComponent(file)
            var isFile: ObjCBool = false
            if fm.fileExists(atPath: src, isDirectory: &isFile), !isFile.boolValue {
                try? fm.copyItem(atPath: src, toPath: dst)
            }
        }
    }

    private func loadCampaignManagerItems() -> [CampaignManagerItem] {
        let entries = listAllCampaigns()
        let fm = FileManager.default
        let store = campaignStore()
        let exportRoot = exportRootPath()
        var items: [CampaignManagerItem] = []

        for entry in entries {
            let manifest = (exportRoot != nil)
                ? store?.loadOrCreateManifest(
                    campaign: entry.campaign,
                    lang: entry.lang,
                    exportRoot: exportRoot ?? "",
                    isoNow: { iso8601String(Date()) }
                ).manifest
                : nil
            let attrs = (try? fm.attributesOfItem(atPath: entry.path)) ?? [:]
            let updatedAt = manifest?.updated_at ?? ""
            let lastModified = parseISO8601Date(updatedAt) ?? (attrs[.modificationDate] as? Date) ?? Date()
            let size = directorySizeBytes(at: entry.path)
            let id = entry.path
            let manifestLang = manifest?.lang ?? ""
            let langResolved = manifestLang.isEmpty ? entry.lang : manifestLang
            let runDirCountResolved = manifest?.runs.count ?? 0
            let safeFolderName = entry.campaignFs
            let fallbackManifest = CampaignManifest(
                campaign: entry.campaign,
                campaign_fs: safeFolderName,
                lang: entry.lang,
                created_at: iso8601String(Date()),
                updated_at: iso8601String(Date()),
                runs: []
            )
            let item = CampaignManagerItem(
                id: id,
                campaign: entry.campaign,
                lang: langResolved,
                lastModified: lastModified,
                runDirCount: runDirCountResolved,
                sizeBytes: size,
                path: entry.path,
                manifest: (manifest ?? fallbackManifest)
            )
            items.append(item)
        }

        return items.sorted { $0.lastModified > $1.lastModified }
    }

    private func deleteSelectedCampaignsEverywhere() {
        let selected = campaignManagerItems.filter { campaignManagerSelection.contains($0.id) }
        guard !selected.isEmpty else { return }
        var deleted = 0
        var failed = 0

        for item in selected {
            let campaignURL = URL(fileURLWithPath: item.path)
            let target = Campaign(id: campaignURL.path, name: item.campaign, campaignURL: campaignURL)
            do {
                try store.deleteCampaign(target, alsoDeleteAstra: true)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        runHistory = store.loadRunHistory()

        if failed > 0 {
            campaignManagerStatus = "Deleted \(deleted) campaign(s). \(failed) failed."
            alert(title: "Delete failed", message: "\(failed) campaign(s) could not be deleted.")
        } else {
            campaignManagerStatus = "Deleted \(deleted) campaign(s)."
        }
        campaignManagerSelection = []
        refreshRecentCampaigns()
        refreshCampaignsPanel()
        campaignManagerItems = loadCampaignManagerItems()
    }

    private func deliverAstraRun(
        runDir: String,
        url: String,
        campaignName: String,
        lang: String
    ) -> (campaignLangPath: String?, deliveredDir: String?, runFolderPath: String?, domain: String?, reportPath: String?, scopeLogPath: String?, verdictPath: String?, success: Bool) {
        guard let domain = domainFromURLString(url) else {
            return (nil, nil, nil, nil, nil, nil, nil, false)
        }
        guard let store = campaignStore(), let exportRoot = exportRootPath() else {
            return (nil, nil, nil, domain, nil, nil, nil, false)
        }

        let fm = FileManager.default
        let timestampDate = Date()
        let timestampString = iso8601String(timestampDate)
        let campaignLangURL = store.campaignLangURL(campaign: campaignName, lang: lang, exportRoot: exportRoot)
        store.ensureDirectory(campaignLangURL.path)

        var isDir: ObjCBool = false
        let deliverablesSource = (runDir as NSString).appendingPathComponent("deliverables")
        guard fm.fileExists(atPath: deliverablesSource, isDirectory: &isDir), isDir.boolValue else {
            return (campaignLangURL.path, nil, nil, domain, nil, nil, nil, false)
        }

        let runFolderURL = store.runFolderURL(
            campaign: campaignName,
            lang: lang,
            domain: domain,
            timestamp: timestampString,
            exportRoot: exportRoot
        )
        if fm.fileExists(atPath: runFolderURL.path) {
            try? fm.removeItem(at: runFolderURL)
        }
        store.ensureDirectory(runFolderURL.path)
        store.ensureDirectory(runFolderURL.appendingPathComponent("deliverables").path)
        store.ensureDirectory(runFolderURL.appendingPathComponent("final_decision").path)

        let astraDest = runFolderURL.appendingPathComponent("astra")
        if !fm.fileExists(atPath: astraDest.path) {
            try? fm.copyItem(atPath: runDir, toPath: astraDest.path)
        }
        if !fm.fileExists(atPath: astraDest.path) {
            try? fm.createDirectory(at: astraDest, withIntermediateDirectories: true)
        }

        let scopeSource = (runDir as NSString).appendingPathComponent("scope")
        let scopeDest = runFolderURL.appendingPathComponent("scope")
        copyScopeFolderIfNeeded(from: scopeSource, to: scopeDest.path)
        if !fm.fileExists(atPath: scopeDest.path) {
            try? fm.createDirectory(at: scopeDest, withIntermediateDirectories: true)
        }

        let auditDir = runFolderURL.appendingPathComponent("audit")
        let runDirURL = URL(fileURLWithPath: runDir)
        if !fm.fileExists(atPath: auditDir.path) {
            try? fm.createDirectory(at: auditDir, withIntermediateDirectories: true)
        }
        let auditReportDest = auditDir.appendingPathComponent("report.pdf")
        if !fm.fileExists(atPath: auditReportDest.path) {
            let auditCandidates = [
                astraDest.appendingPathComponent("deliverables").appendingPathComponent("report.pdf").path,
                runDirURL.appendingPathComponent("deliverables", isDirectory: true).appendingPathComponent("report.pdf").path,
                runDirURL.appendingPathComponent("scope", isDirectory: true).appendingPathComponent("report.pdf").path,
                runFolderURL.appendingPathComponent("deliverables").appendingPathComponent("report.pdf").path,
                runDirURL.appendingPathComponent("report.pdf").path,
            ]
            if let src = auditCandidates.first(where: { fm.fileExists(atPath: $0) }) {
                try? fm.copyItem(atPath: src, toPath: auditReportDest.path)
            }
        }
        let auditReportJsonDest = auditDir.appendingPathComponent("report.json")
        if !fm.fileExists(atPath: auditReportJsonDest.path) {
            let jsonCandidates = [
                astraDest.appendingPathComponent("deliverables").appendingPathComponent("report.json").path,
                runDirURL.appendingPathComponent("deliverables", isDirectory: true).appendingPathComponent("report.json").path,
                runDirURL.appendingPathComponent("scope", isDirectory: true).appendingPathComponent("report.json").path,
                runDirURL.appendingPathComponent("report.json").path,
            ]
            if let src = jsonCandidates.first(where: { fm.fileExists(atPath: $0) }) {
                try? fm.copyItem(atPath: src, toPath: auditReportJsonDest.path)
            }
        }

        let scopeLogSource = (runDir as NSString).appendingPathComponent("scope_run.log")
        let scopeLogDest = astraDest.appendingPathComponent("scope_run.log")
        if fm.fileExists(atPath: scopeLogSource), !fm.fileExists(atPath: scopeLogDest.path) {
            try? fm.copyItem(atPath: scopeLogSource, toPath: scopeLogDest.path)
        }

        let verdictSourceInDeliverables = (deliverablesSource as NSString).appendingPathComponent("verdict.json")
        let verdictSourceAtRoot = (runDir as NSString).appendingPathComponent("verdict.json")
        let verdictDest = astraDest.appendingPathComponent("verdict.json")
        if fm.fileExists(atPath: verdictSourceInDeliverables), !fm.fileExists(atPath: verdictDest.path) {
            try? fm.copyItem(atPath: verdictSourceInDeliverables, toPath: verdictDest.path)
        } else if fm.fileExists(atPath: verdictSourceAtRoot), !fm.fileExists(atPath: verdictDest.path) {
            try? fm.copyItem(atPath: verdictSourceAtRoot, toPath: verdictDest.path)
        }

        let deliverablesDest = astraDest.appendingPathComponent("deliverables")
        let decisionBriefName = (lang.lowercased() == "ro") ? "Decision_Brief_RO.pdf" : "Decision_Brief_EN.pdf"
        let auditReportPath = auditReportDest.path
        let reportPath = fm.fileExists(atPath: auditReportPath)
            ? auditReportPath
            : deliverablesDest.appendingPathComponent(decisionBriefName).path
        let verdictPath = deliverablesDest.appendingPathComponent("verdict.json").path
        let reportExists = fm.fileExists(atPath: reportPath)
        let verdictExists = fm.fileExists(atPath: verdictPath)
        let success = verdictExists
        if !success {
            try? fm.removeItem(at: runFolderURL)
            return (campaignLangURL.path, nil, nil, domain, reportExists ? reportPath : nil, nil, verdictExists ? verdictPath : nil, false)
        }

        store.appendRun(
            campaign: campaignName,
            lang: lang,
            runFolderName: runFolderURL.lastPathComponent,
            exportRoot: exportRoot,
            isoNow: { iso8601String(Date()) }
        )

        let scopeLogPath = fm.fileExists(atPath: scopeLogSource)
            ? scopeLogSource
            : (fm.fileExists(atPath: scopeLogDest.path) ? scopeLogDest.path : nil)

        return (
            campaignLangURL.path,
            runFolderURL.path,
            runFolderURL.path,
            domain,
            reportExists ? reportPath : nil,
            scopeLogPath,
            verdictExists ? verdictPath : nil,
            success
        )
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
        guard let log = scopeRunLogPath() else { return }
        revealAndOpenFile(log)
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
        openZIP(forLang: lang)
    }

    private func openZIP(forLang lang: String) {
        guard let zipPath = shipZipPath(forLang: lang) else {
            alertMissingPath(title: "ZIP missing", reason: "No ZIP recorded yet.", path: nil)
            return
        }
        let url = URL(fileURLWithPath: zipPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMissingPath(title: "ZIP missing", reason: "ZIP file not found on disk.", path: url.path)
            return
        }
        withExportRootAccess {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
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

    private func selectAstraFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Selectează folderul repo: astra"

        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                self.astraRootPath = url.path
                self.alert(title: "ASTRA folder set", message: "ASTRA folder selected.")
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

    private func showAstraFolder() {
        let trimmed = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert(title: "Select ASTRA Folder to continue.", message: "Select ASTRA Folder to continue.")
            return
        }
        guard FileManager.default.fileExists(atPath: trimmed) else {
            alert(title: "ASTRA folder missing", message: "Select ASTRA Folder to continue.")
            return
        }
        openFolder(trimmed)
    }

    // MARK: - Run audit (sequential)

    private func runAudit() {
        guard !isRunning else { return }
        guard engineFolderAvailable() else {
            alert(title: "Select Engine Folder to continue.", message: "Select Engine Folder to continue.")
            return
        }
        let astraTrimmed = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !astraTrimmed.isEmpty else {
            alert(title: "Select ASTRA Folder to continue.", message: "Select ASTRA Folder to continue.")
            return
        }
        guard FileManager.default.fileExists(atPath: astraTrimmed) else {
            alert(title: "ASTRA folder missing", message: "Select ASTRA Folder to continue.")
            return
        }
        guard campaignIsValid() else {
            alert(title: "Select Campaign", message: "Select Campaign")
            return
        }
        guard let validLines = validateTargetsInput() else {
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
        lastRunDir = nil
        lastRunLogPath = nil
        lastRunDomain = nil

        guard let store = campaignStore(), let selected = store.selectedCampaign else { return }
        runRunner(selectedLang: lang, baseCampaign: selected.name, validLines: validLines)
    }

    private func runDemo() {
        guard !isRunning else { return }
        guard engineFolderAvailable() else {
            alert(title: "Select Engine Folder to continue.", message: "Select Engine Folder to continue.")
            return
        }
        let astraRoot = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !astraRoot.isEmpty else {
            alert(title: "Select ASTRA Folder to continue.", message: "Select ASTRA Folder to continue.")
            return
        }
        guard FileManager.default.fileExists(atPath: astraRoot) else {
            alert(title: "ASTRA folder missing", message: "Select ASTRA Folder to continue.")
            return
        }
        guard let engineURL = beginEngineAccess() else {
            alert(title: "Engine folder missing", message: "Select Engine Folder to continue.")
            return
        }

        isRunning = true
        runState = .running
        logOutput = ""
        lastExitCode = nil
        result = nil
        readyToSend = false
        selectedPDF = nil
        selectedZIPLang = (lang == "en") ? "en" : "ro"
        demoDeliverablePath = nil
        lastRunDir = nil
        lastRunLogPath = nil
        lastRunDomain = nil
        cancelRequested = false

        let demoURL = "https://example.com"
        let specs = buildRunSpecs(validLines: [demoURL], selectedLang: lang)
        lastRunCampaign = "DEMO"
        runAstraSequence(specs: specs, engineURL: engineURL, astraRoot: astraRoot) { entry in
            self.demoDeliverablePath = entry.deliverablesDir
        }
    }

    private func runRunner(selectedLang: String, baseCampaign: String, validLines: [String]) {
        let astraRoot = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !astraRoot.isEmpty else {
            alert(title: "Select ASTRA Folder to continue.", message: "Select ASTRA Folder to continue.")
            isRunning = false
            runState = .error
            return
        }
        guard FileManager.default.fileExists(atPath: astraRoot) else {
            alert(title: "ASTRA folder missing", message: "Select ASTRA Folder to continue.")
            isRunning = false
            runState = .error
            return
        }
        guard let engineURL = beginEngineAccess() else {
            alert(title: "Engine folder missing", message: "Select Engine Folder to continue.")
            isRunning = false
            return
        }
        let specs = buildRunSpecs(validLines: validLines, selectedLang: selectedLang)
        if specs.isEmpty {
            endEngineAccess(engineURL)
            alert(title: "No valid URLs", message: "Paste at least one valid URL.")
            isRunning = false
            runState = .error
            return
        }
        lastRunCampaign = baseCampaign
        runAstraSequence(specs: specs, engineURL: engineURL, astraRoot: astraRoot, onRunRecorded: nil)
    }

    private func runAstraSequence(
        specs: [RunSpec],
        engineURL: URL,
        astraRoot: String,
        onRunRecorded: ((RunEntry) -> Void)?
    ) {
        let engineRoot = engineURL.path
        let normalizedAstraRoot = astraRoot
        let fm = FileManager.default
        var index = 0
        var sawError = false
        var endAccessCalled = false
        let timeoutQueue = DispatchQueue(label: "scope.timeout")
        var timedOutTokens: Set<UUID> = []

        func shellEscape(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }

        func endAccessIfNeeded() {
            if !endAccessCalled {
                endAccessCalled = true
                endEngineAccess(engineURL)
            }
        }

        func runNext() {
            if cancelRequested {
                lastRunStatus = "Canceled"
                runState = .error
                cancelRequested = false
                currentTask = nil
                isRunning = false
                endAccessIfNeeded()
                return
            }
            if index >= specs.count {
                runState = sawError ? .error : .done
                isRunning = false
                endAccessIfNeeded()
                refreshRecentCampaigns()
                return
            }

            let spec = specs[index]
            index += 1
            let logPath = makeAstraLogFilePath(url: spec.url, lang: spec.lang)
            fm.createFile(atPath: logPath, contents: nil)
            lastRunLogPath = logPath

            logOutput += "\n== ASTRA run \(index)/\(specs.count) • \(spec.lang.uppercased()) • \(spec.url) ==\n"

            let escapedRepo = shellEscape(engineRoot)
            let escapedAstraRoot = shellEscape(normalizedAstraRoot)
            let escapedUrl = shellEscape(spec.url)
            let command = """
set -e
ASTRA_ROOT="\(escapedAstraRoot)"
if [[ -x "$ASTRA_ROOT/.venv/bin/python" ]]; then
  PYTHON="$ASTRA_ROOT/.venv/bin/python"
else
  PYTHON="python3"
fi
export SCOPE_REPO="\(escapedRepo)"
export ASTRA_LANG="\(spec.lang == "en" ? "EN" : "RO")"
cd "$ASTRA_ROOT"
"$PYTHON" -m astra run "\(escapedUrl)" --lang \(spec.lang)
"""
            let task = Process()
            currentTask = task
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["bash", "-lc", command]
            var environment = task.environment ?? ProcessInfo.processInfo.environment
            environment["SCOPE_USE_AI"] = useAI ? "1" : "0"
            environment["SCOPE_ANALYSIS_MODE"] = analysisMode
            task.environment = environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            var logHandle = FileHandle(forWritingAtPath: logPath)
            task.standardOutput = outPipe
            task.standardError = errPipe

            let runToken = UUID()
            timeoutQueue.async {
                timedOutTokens.remove(runToken)
            }

            let readHandler: (FileHandle) -> Void = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        self.logOutput += str
                    }
                }
                if !data.isEmpty {
                    self.logQueue.async {
                        logHandle?.write(data)
                    }
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = readHandler
            errPipe.fileHandleForReading.readabilityHandler = readHandler

            task.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                self.logQueue.async {
                    logHandle?.closeFile()
                    logHandle = nil
                }
                let code = p.terminationStatus
                let wasCanceled = self.cancelRequested
                DispatchQueue.main.async {
                    let logSnapshot = self.logOutput
                    let wasTimedOut = timeoutQueue.sync {
                        let had = timedOutTokens.contains(runToken)
                        if had {
                            timedOutTokens.remove(runToken)
                        }
                        return had
                    }

                    DispatchQueue.global(qos: .userInitiated).async {
                        let runDir = self.resolveAstraRunDir(from: logSnapshot, astraRoot: normalizedAstraRoot)
                    var delivery = (
                        campaignLangPath: String?,
                        deliveredDir: String?,
                        runFolderPath: String?,
                        domain: String?,
                        reportPath: String?,
                        scopeLogPath: String?,
                        verdictPath: String?,
                        success: Bool
                    )(nil, nil, nil, nil, nil, nil, nil, false)
                    if let runDir, let campaignName = self.lastRunCampaign {
                        delivery = self.deliverAstraRun(runDir: runDir, url: spec.url, campaignName: campaignName, lang: spec.lang)
                    }

                    let deliverablesPath = runDir == nil ? "" : (runDir! as NSString).appendingPathComponent("deliverables")
                    let verdictPath = deliverablesPath.isEmpty ? "" : (deliverablesPath as NSString).appendingPathComponent("verdict.json")
                    let verdictExists = !verdictPath.isEmpty && FileManager.default.fileExists(atPath: verdictPath)
                    let briefName = (spec.lang.lowercased() == "en") ? "Decision_Brief_EN.pdf" : "Decision_Brief_RO.pdf"
                    let appendixName = (spec.lang.lowercased() == "en") ? "Evidence_Appendix_EN.pdf" : "Evidence_Appendix_RO.pdf"
                    let decisionBriefPath = deliverablesPath.isEmpty ? nil : (deliverablesPath as NSString).appendingPathComponent(briefName)
                        _ = deliverablesPath.isEmpty ? nil : (deliverablesPath as NSString).appendingPathComponent(appendixName)
                    let scopeLogPath = runDir == nil ? nil : (runDir! as NSString).appendingPathComponent("scope_run.log")
                    let scopeLogExists = scopeLogPath != nil && FileManager.default.fileExists(atPath: scopeLogPath ?? "")

                    let status: String
                    if wasCanceled {
                        status = "Canceled"
                    } else if wasTimedOut {
                        status = "FAILED"
                    } else if verdictExists {
                        status = (code == 0) ? "SUCCESS" : "WARNING"
                    } else {
                        status = "FAILED"
                    }

                    let deliverablesDir = delivery.runFolderPath ?? delivery.deliveredDir ?? ""
                    let astraRunDir = deliverablesDir.isEmpty
                        ? (runDir ?? "")
                        : (deliverablesDir as NSString).appendingPathComponent("astra")
                    var auditReportPath: String? = nil
                    var auditCopyError: String? = nil
                    if code == 0 && !deliverablesDir.isEmpty, let repoRoot = self.resolvedRepoRoot() {
                        let auditDir = URL(fileURLWithPath: deliverablesDir).appendingPathComponent("audit", isDirectory: true)
                        if !FileManager.default.fileExists(atPath: auditDir.path) {
                            try? FileManager.default.createDirectory(at: auditDir, withIntermediateDirectories: true)
                        }
                        let parsedPdf = self.lastMatch(in: logSnapshot, pattern: "Saved PDF:\\s+(.+\\\\.pdf)")
                            ?? self.lastMatch(in: logSnapshot, pattern: "pdf:\\s+(.+\\\\.pdf)")
                        let parsedJson = self.lastMatch(in: logSnapshot, pattern: "Saved JSON:\\s+(.+\\\\.json)")
                            ?? self.lastMatch(in: logSnapshot, pattern: "json:\\s+(.+\\\\.json)")
                        let auditDest = auditDir.appendingPathComponent("report.pdf").path
                        if let parsedPdf, FileManager.default.fileExists(atPath: parsedPdf) {
                            try? FileManager.default.removeItem(atPath: auditDest)
                            if (try? FileManager.default.copyItem(atPath: parsedPdf, toPath: auditDest)) != nil {
                                auditReportPath = auditDest
                            }
                        } else if let fallback = self.findRecentAuditPDF(repoRoot: repoRoot) {
                            try? FileManager.default.removeItem(atPath: auditDest)
                            if (try? FileManager.default.copyItem(atPath: fallback, toPath: auditDest)) != nil {
                                auditReportPath = auditDest
                            }
                        }
                        if auditReportPath == nil {
                            auditCopyError = "ERROR could not locate Tool1 PDF"
                        }

                        if let parsedJson, FileManager.default.fileExists(atPath: parsedJson) {
                            let jsonDest = auditDir.appendingPathComponent("report.json").path
                            try? FileManager.default.removeItem(atPath: jsonDest)
                            _ = try? FileManager.default.copyItem(atPath: parsedJson, toPath: jsonDest)
                        }
                    }

                    let reportPath = auditReportPath
                        ?? ((decisionBriefPath != nil && FileManager.default.fileExists(atPath: decisionBriefPath ?? "")) ? decisionBriefPath : nil)
                    let reportExists = reportPath != nil
                    let resolvedLogPath = scopeLogExists ? scopeLogPath : delivery.scopeLogPath

                    let campaignsSnapshot: [CampaignSummary] = {
                        guard let exportRoot = self.exportRootPath() else { return [] }
                        return self.campaignStore()?.listCampaigns(exportRoot: exportRoot) ?? []
                    }()

                    let entry = RunEntry(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        url: spec.url,
                        lang: spec.lang,
                        status: status,
                        runDir: astraRunDir,
                        deliverablesDir: deliverablesDir,
                        reportPdfPath: reportExists ? reportPath : nil,
                        decisionBriefPdfPath: reportExists ? reportPath : nil,
                        logPath: resolvedLogPath
                    )

                        DispatchQueue.main.async {
                        self.currentTask = nil
                        self.lastExitCode = code

                        if status == "FAILED" {
                            sawError = true
                            self.runState = .error
                        }

                        self.lastRunDomain = delivery.domain ?? self.domainFromURLString(spec.url)
                        self.lastRunLogPath = resolvedLogPath
                        if let runDir {
                            self.lastRunDir = runDir
                        } else if !astraRunDir.isEmpty {
                            self.lastRunDir = astraRunDir
                        } else if let campaignLangPath = delivery.campaignLangPath {
                            self.lastRunDir = campaignLangPath
                        } else if let campaignName = self.lastRunCampaign,
                                  let fallbackCampaignPath = self.campaignFolderPath(campaignName: campaignName, lang: spec.lang) {
                            self.lastRunDir = fallbackCampaignPath
                        }

                        if let campaignName = self.lastRunCampaign,
                           let exportRoot = self.exportRootPath() {
                            let campaignURL = self.store.campaignURL(forName: campaignName, exportRoot: exportRoot)
                            let runsRoot = campaignURL.appendingPathComponent("runs").path
                            let newCanonical = self.normalizeURLForOverwrite(entry.url)
                            if !newCanonical.isEmpty {
                                let matches = self.runHistory.filter { existing in
                                    self.normalizeURLForOverwrite(existing.url) == newCanonical
                                        && (existing.deliverablesDir.hasPrefix(runsRoot) || existing.runDir.hasPrefix(runsRoot))
                                }
                                for match in matches {
                                    let oldPath = !match.deliverablesDir.isEmpty ? match.deliverablesDir : match.runDir
                                    guard oldPath.hasPrefix(runsRoot) else { continue }
                                    if FileManager.default.fileExists(atPath: oldPath) {
                                        do {
                                            try FileManager.default.removeItem(atPath: oldPath)
                                            self.logOutput += "\nOVERWRITE_URL: \(newCanonical) old=\(match.id) new=\(entry.id)"
                                        } catch {
                                            self.logOutput += "\nOverwrite failed for \(newCanonical): \(error.localizedDescription)"
                                            return
                                        }
                                    }
                                    self.runHistory.removeAll { $0.id == match.id }
                                }
                            }
                            self.runHistory.insert(entry, at: 0)
                            self.saveRunHistory(self.runHistory)
                        } else {
                            self.runHistory.insert(entry, at: 0)
                            self.saveRunHistory(self.runHistory)
                        }
                        onRunRecorded?(entry)
                        self.campaignsPanel = campaignsSnapshot

                        self.lastRunLang = spec.lang
                        self.lastRunStatus = status
                        if let auditCopyError {
                            self.lastRunStatus = "FAILED"
                            self.runState = .error
                            self.readyToSend = false
                            self.logOutput += "\n\(auditCopyError)"
                        }
                        if let campaignLangPath = delivery.campaignLangPath {
                            if self.result == nil { self.result = ScopeResult() }
                            self.result?.outDirByLang[spec.lang] = campaignLangPath
                        }
                        if reportExists, let reportPath {
                            self.selectedPDF = reportPath
                            if self.result == nil { self.result = ScopeResult() }
                            self.result?.pdfPaths = [reportPath]
                        }
                        self.readyToSend = (status == "SUCCESS" || status == "WARNING")

                        if wasCanceled {
                            self.cancelRequested = false
                            self.runState = .error
                            self.isRunning = false
                            endAccessIfNeeded()
                            return
                        }

                        runNext()
                        }
                    }
                }
            }

            do {
                try task.run()
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8 * 60) {
                    guard self.currentTask === task, task.isRunning else { return }
                    timeoutQueue.async {
                        timedOutTokens.insert(runToken)
                    }
                    self.terminateProcess(task)
                }
            } catch {
                DispatchQueue.main.async {
                    self.currentTask = nil
                    self.lastRunStatus = "FAILED"
                    self.runState = .error
                    self.isRunning = false
                    endAccessIfNeeded()
                    self.alert(title: "Run failed", message: "Nu am putut porni ASTRA.")
                }
            }
        }

        runNext()
    }

    private func terminateProcess(_ task: Process) {
        guard task.isRunning else { return }
        task.terminate()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            if task.isRunning {
                task.interrupt()
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
            if task.isRunning {
                let pid = task.processIdentifier
                if pid > 0 {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    private func cancelRun() {
        guard isRunning else { return }
        cancelRequested = true
        if let task = currentTask, task.isRunning {
            terminateProcess(task)
        }
    }

    private func cancelRunExport() {
        runExportCancelRequested = true
        if let task = runExportTask, task.isRunning {
            terminateProcess(task)
        }
    }

    private func runRootPath(for entry: RunEntry) -> String? {
        let path = !entry.deliverablesDir.isEmpty ? entry.deliverablesDir : entry.runDir
        return path.isEmpty ? nil : path
    }

    private func isRunExportCanceled() -> Bool {
        DispatchQueue.main.sync { runExportCancelRequested }
    }

    private func exportStatusLabel(for entry: RunEntry) -> String {
        if exportIsRunning, runExportRunID == entry.id {
            return exportStatusText
        }
        if runExportRunID == entry.id {
            return exportStatusText
        }
        return "Ready"
    }

    private func lastOkErrorLine(from output: String) -> String? {
        var result: String? = nil
        for lineSub in output.split(separator: "\n") {
            let line = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("OK ") || line.hasPrefix("ERROR ") {
                result = line
            }
        }
        return result
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        cwd: String,
        env: [String: String]
    ) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        DispatchQueue.main.async {
            self.runExportTask = p
        }

        do {
            try p.run()
        } catch {
            return (1, "")
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, output)
    }

    private func runToolProcess(
        executable: String,
        arguments: [String],
        cwd: String,
        env: [String: String]
    ) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        DispatchQueue.main.async {
            self.toolTask = p
        }

        do {
            try p.run()
        } catch {
            return (1, "")
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, output)
    }

    private func lastMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var result: String? = nil
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            if let r = Range(match.range(at: 1), in: text) {
                result = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    private func findRecentAuditPDF(repoRoot: String) -> String? {
        let reportsRoot = URL(fileURLWithPath: repoRoot).appendingPathComponent("reports", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: reportsRoot.path) else { return nil }
        let cutoff = Date().addingTimeInterval(-30 * 60)
        guard let enumerator = fm.enumerator(at: reportsRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var bestPath: String? = nil
        var bestDate: Date = Date.distantPast
        for case let url as URL in enumerator {
            if !url.path.lowercased().hasSuffix(".pdf") { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? Date.distantPast
            if modified < cutoff { continue }
            if modified > bestDate {
                bestDate = modified
                bestPath = url.path
            } else if modified == bestDate {
                if let currentBest = bestPath, url.path < currentBest {
                    bestPath = url.path
                }
            }
        }
        return bestPath
    }

    private func toolOutputPath(for entry: RunEntry, folder: String, fileName: String) -> String? {
        guard let runDir = runRootPath(for: entry) else { return nil }
        let base = URL(fileURLWithPath: runDir).appendingPathComponent(folder, isDirectory: true)
        return base.appendingPathComponent(fileName).path
    }

    private func runTool(stepName: String, scriptPath: String, entry: RunEntry, expectedFolder: String) {
        guard !toolRunning else { return }
        guard let runDir = runRootPath(for: entry) else {
            toolStatus = "Export failed: \(stepName)"
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: runDir, isDirectory: &isDir), isDir.boolValue else {
            toolStatus = "Export failed: \(stepName)"
            return
        }
        guard let repoRoot = resolvedRepoRoot() else {
            toolStatus = "Export failed: \(stepName)"
            return
        }

        toolRunning = true
        toolRunID = entry.id
        toolStatus = "Running \(stepName)…"

        DispatchQueue.global(qos: .userInitiated).async {
            let venvBin = (repoRoot as NSString).appendingPathComponent(".venv/bin")
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = venvBin + ":" + (env["PATH"] ?? "")

            let result = self.runToolProcess(
                executable: "/usr/bin/env",
                arguments: ["bash", scriptPath, runDir],
                cwd: repoRoot,
                env: env
            )

            DispatchQueue.main.async {
                self.toolRunning = false
                self.toolTask = nil
                self.toolRunID = nil

                if result.0 != 0 {
                    self.toolStatus = "Export failed: \(stepName)"
                    return
                }

                let folderPath = (runDir as NSString).appendingPathComponent(expectedFolder)
                let pdfFound = (try? FileManager.default.contentsOfDirectory(atPath: folderPath))?.contains(where: { $0.lowercased().hasSuffix(".pdf") }) ?? false
                self.toolStatus = pdfFound ? "OK \(stepName)" : "No output produced"
            }
        }
    }

    private func toolPDFPath(for entry: RunEntry, tool: String) -> String? {
        guard let runDir = runRootPath(for: entry) else { return nil }
        switch tool {
        case "tool2":
            return URL(fileURLWithPath: runDir)
                .appendingPathComponent("action_scope", isDirectory: true)
                .appendingPathComponent("action_scope.pdf").path
        case "tool3":
            return URL(fileURLWithPath: runDir)
                .appendingPathComponent("proof_pack", isDirectory: true)
                .appendingPathComponent("proof_pack.pdf").path
        case "tool4":
            return URL(fileURLWithPath: runDir)
                .appendingPathComponent("regression", isDirectory: true)
                .appendingPathComponent("regression.pdf").path
        default:
            return nil
        }
    }

    private func openToolOutput(for entry: RunEntry, tool: String) {
        guard let path = toolPDFPath(for: entry, tool: tool) else {
            toolStatus = "No output produced"
            return
        }
        if FileManager.default.fileExists(atPath: path) {
            revealAndOpenFile(path)
        } else {
            toolStatus = "No output produced"
        }
    }

    private func runExportClientBundle(for entry: RunEntry) {
        guard !exportIsRunning else { return }
        guard let runDir = runRootPath(for: entry) else {
            exportStatusText = "ERROR: Build master"
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: runDir, isDirectory: &isDir), isDir.boolValue else {
            exportStatusText = "ERROR: Build master"
            return
        }
        guard let repoRoot = resolvedRepoRoot() else {
            exportStatusText = "ERROR: Build master"
            return
        }

        exportIsRunning = true
        runExportRunID = entry.id
        runExportCancelRequested = false
        exportStatusText = "Exporting…"

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let venvBin = (repoRoot as NSString).appendingPathComponent(".venv/bin")
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = venvBin + ":/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

            let buildScript = (repoRoot as NSString).appendingPathComponent("scripts/build_master_pdf.sh")
            let packageScript = (repoRoot as NSString).appendingPathComponent("scripts/package_run_client_safe_zip.sh")
            let verifyScript = (repoRoot as NSString).appendingPathComponent("scripts/verify_client_safe_zip.py")

            func finish(_ status: String) {
                DispatchQueue.main.async {
                    self.exportIsRunning = false
                    self.runExportTask = nil
                    self.exportStatusText = status
                }
            }

            if self.isRunExportCanceled() {
                finish("ERROR: Build master")
                return
            }

            let buildResult = self.runProcess(
                executable: "/bin/bash",
                arguments: [buildScript, runDir],
                cwd: repoRoot,
                env: env
            )
            if self.isRunExportCanceled() {
                finish("ERROR: Build master")
                return
            }
            if buildResult.0 != 0 {
                finish("ERROR: Build master")
                return
            }
            let masterPdf = (runDir as NSString).appendingPathComponent("final/master.pdf")
            if !fm.fileExists(atPath: masterPdf) {
                finish("ERROR: Build master")
                return
            }

            DispatchQueue.main.async {
                self.exportStatusText = "Master built"
            }

            let packageResult = self.runProcess(
                executable: "/bin/bash",
                arguments: [packageScript, runDir],
                cwd: repoRoot,
                env: env
            )
            if self.isRunExportCanceled() {
                finish("ERROR: Package zip")
                return
            }
            if packageResult.0 != 0 {
                finish("ERROR: Package zip")
                return
            }

            DispatchQueue.main.async {
                self.exportStatusText = "Zip packaged"
            }

            let finalDir = (runDir as NSString).appendingPathComponent("final")
            let finalZip = (finalDir as NSString).appendingPathComponent("client_safe_bundle.zip")
            if !fm.fileExists(atPath: finalZip) {
                finish("ERROR: Package zip")
                return
            }

            DispatchQueue.main.async {
                self.exportStatusText = "Verifying…"
            }

            let verifyResult = self.runProcess(
                executable: "/usr/bin/python3",
                arguments: [verifyScript, finalZip],
                cwd: repoRoot,
                env: env
            )
            if verifyResult.0 != 0 {
                finish("ERROR: Verify zip")
                return
            }

            DispatchQueue.main.async {
                self.exportStatusText = "Verified"
            }
            finish("OK: client_safe_bundle.zip")
        }
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
        case "SUCCESS":
            return "Success: audit completed."
        case "WARNING":
            return "Completed with warnings."
        case "FAILED":
            return "Failed: audit did not complete."
        case "Canceled":
            return "Canceled by operator."
        default:
            return "Run finished."
        }
    }

    private func revealDemoDeliverable() {
        guard let path = demoDeliverablePath, FileManager.default.fileExists(atPath: path) else {
            alert(title: "Demo not found", message: "Nu am găsit output pentru demo.")
            return
        }
        openFolder(path)
    }

    private func demoScriptAndCampaign(for lang: String) -> (script: String, campaign: String) {
        if lang == "en" {
            return ("", "DEMO_EN")
        }
        return ("", "DEMO_RO")
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

    private struct RunSpec {
        let url: String
        let lang: String
    }

    private func buildRunSpecs(validLines: [String], selectedLang: String) -> [RunSpec] {
        var specs: [RunSpec] = []
        if selectedLang == "both" {
            for url in validLines {
                specs.append(RunSpec(url: url, lang: "ro"))
                specs.append(RunSpec(url: url, lang: "en"))
            }
            return specs
        }
        return validLines.map { RunSpec(url: $0, lang: selectedLang) }
    }

    private func parseAstraRunDirMarker(from output: String) -> String? {
        for lineSub in output.split(separator: "\n").reversed() {
            let line = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("ASTRA_RUN_DIR=") {
                var path = String(line.dropFirst("ASTRA_RUN_DIR=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if (path.hasPrefix("\"") && path.hasSuffix("\"")) || (path.hasPrefix("'") && path.hasSuffix("'")) {
                    path = String(path.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return path.isEmpty ? nil : path
            }
        }
        return nil
    }

    private func resolveAstraRunDir(from output: String, astraRoot: String) -> String? {
        if let marker = parseAstraRunDirMarker(from: output) {
            return marker
        }
        return findLatestAstraRunDir(in: astraRoot)
    }

    private func findLatestAstraRunDir(in astraRoot: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: astraRoot),
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var bestPath: String? = nil
        var bestDate: Date = Date.distantPast

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  values.isDirectory == true else { continue }
            let deliverables = url.appendingPathComponent("deliverables")
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: deliverables.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let reportRo = deliverables.appendingPathComponent("Decision_Brief_RO.pdf")
            let reportEn = deliverables.appendingPathComponent("Decision_Brief_EN.pdf")
            let verdictPath = deliverables.appendingPathComponent("verdict.json")
            guard fm.fileExists(atPath: reportRo.path)
                || fm.fileExists(atPath: reportEn.path)
                || fm.fileExists(atPath: verdictPath.path)
            else { continue }
            let modified = values.contentModificationDate ?? Date.distantPast
            if modified > bestDate {
                bestDate = modified
                bestPath = url.path
            }
        }

        return bestPath
    }

    private func makeAstraLogFilePath(url: String, lang: String) -> String {
        let logsDir = (ScopeRepoLocator.appSupportDir as NSString).appendingPathComponent("logs")
        if !FileManager.default.fileExists(atPath: logsDir) {
            try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        let slug = sanitizeFilename(url)
        let file = "astra_\(lang)_\(slug)_\(stamp).log"
        return (logsDir as NSString).appendingPathComponent(file)
    }

    private func sanitizeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        var cleaned = ""
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                cleaned.append(String(scalar))
            } else {
                cleaned.append("_")
            }
        }
        let result = cleaned.replacingOccurrences(of: "__", with: "_")
        return result.isEmpty ? "run" : result
    }

    private func availableZipLangs() -> [String]? {
        guard let zips = result?.zipByLang, !zips.isEmpty else { return nil }
        let ordered = ["ro", "en"]
        let known = ordered.filter { zips[$0] != nil }
        if !known.isEmpty { return known }
        return zips.keys.sorted()
    }

    private func shipZipPath(forLang lang: String) -> String? {
        if let zips = result?.shipZipByLang, let path = zips[lang], !path.isEmpty {
            return path
        }
        if let last = store.lastExportZipPath, !last.isEmpty {
            return last
        }
        return nil
    }

    private func shipRootPath() -> String? {
        return lastRunDeliverablesPath()
    }

    private func shipDirPath(forLang lang: String) -> String? {
        return decisionBriefPath(forLang: lang)
    }

    private func lastRunAstraDirPath() -> String? {
        if let dir = lastRunDir, !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dir
        }
        if let logPath = lastRunLogPath {
            let parent = URL(fileURLWithPath: logPath).deletingLastPathComponent().path
            return parent.isEmpty ? nil : parent
        }
        return nil
    }

    private func lastRunDeliverablesPath() -> String? {
        guard let astraDir = lastRunAstraDirPath() else { return nil }
        let deliverables = (astraDir as NSString).appendingPathComponent("deliverables")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: deliverables, isDirectory: &isDir), isDir.boolValue {
            return deliverables
        }
        return nil
    }

    private func decisionBriefPath(forLang lang: String) -> String? {
        guard let deliverables = lastRunDeliverablesPath() else { return nil }
        let fileName = (lang.lowercased() == "ro") ? "Decision_Brief_RO.pdf" : "Decision_Brief_EN.pdf"
        let path = (deliverables as NSString).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func appendixPath(forLang lang: String) -> String? {
        guard let deliverables = lastRunDeliverablesPath() else { return nil }
        let fileName = (lang.lowercased() == "ro") ? "Evidence_Appendix_RO.pdf" : "Evidence_Appendix_EN.pdf"
        let path = (deliverables as NSString).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func resolveRoDeliverablesPath(campaignURL: URL) -> String? {
        let fm = FileManager.default
        guard let runURL = store.mostRecentRunURL(campaignURL: campaignURL, lang: "ro") else { return nil }
        let reportURL = runURL
            .appendingPathComponent("astra")
            .appendingPathComponent("deliverables")
            .appendingPathComponent("Decision_Brief_RO.pdf")
        if fm.fileExists(atPath: reportURL.path) {
            return reportURL.path
        }
        if fm.fileExists(atPath: runURL.path) {
            return runURL.path
        }
        return nil
    }

    private func openShipFolder(forLang lang: String) {
        if lang.lowercased() == "ro" {
            openRoDeliverables()
            return
        }
        guard let path = shipDirPath(forLang: lang) else {
            alertMissingPath(title: "Decision Brief missing", reason: "No Decision Brief found yet.", path: nil)
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMissingPath(title: "Decision Brief missing", reason: "Decision Brief not found on disk.", path: url.path)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openAppendix(forLang lang: String) {
        guard let path = appendixPath(forLang: lang) else {
            alertMissingPath(title: "Evidence Appendix missing", reason: "No Evidence Appendix found yet.", path: nil)
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMissingPath(title: "Evidence Appendix missing", reason: "Evidence Appendix not found on disk.", path: url.path)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openShipRoot() {
        guard let path = shipRootPath() else {
            alertMissingPath(title: "Export root missing", reason: "No export root recorded yet.", path: nil)
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            alertMissingPath(title: "Export root missing", reason: "Export root folder not found on disk.", path: url.path)
            return
        }
        NSWorkspace.shared.open(url)
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

    private func engineFolderSummary() -> String {
        guard let path = resolvedRepoRoot(), !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Not set"
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return "\(name) • \(path)"
    }

    private func astraFolderAvailable() -> Bool {
        let trimmed = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) && isDir.boolValue
    }

    private func astraFolderSummary() -> String {
        let trimmed = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Not set" }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) && isDir.boolValue
        if !exists {
            return "Missing • \(trimmed)"
        }
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return "\(name) • \(trimmed)"
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
        guard let selected = store.selectedCampaign else { return nil }
        if let runURL = store.mostRecentRunURL(campaignURL: selected.campaignURL),
           FileManager.default.fileExists(atPath: runURL.path) {
            return runURL.path
        }
        return FileManager.default.fileExists(atPath: selected.campaignURL.path) ? selected.campaignURL.path : nil
    }

    private func scopeRunLogPath() -> String? {
        guard let runDir = lastRunAstraDirPath() else { return nil }
        let path = (runDir as NSString).appendingPathComponent("scope_run.log")
        return FileManager.default.fileExists(atPath: path) ? path : nil
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
        let requestedLangs: [String]
        if lang == "both" {
            requestedLangs = ["ro", "en"]
        } else if let last = lastRunLang, last.lowercased() != "both" {
            requestedLangs = [last.lowercased()]
        } else {
            requestedLangs = [lang.lowercased()]
        }
        exportCampaign(campaign: campaign, langs: requestedLangs) { status in
            setExportStatus(status)
        }
    }

    private func campaignScopedRunHistory() -> [RunEntry] {
        guard let root = campaignsRootPath() else { return runHistory }
        return runHistory.filter { $0.deliverablesDir.hasPrefix(root) }
    }

    private func migrateLegacyRunsIfNeeded() {
        guard let exportRoot = exportRootPath() else { return }
        let astraRoot = astraRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !astraRoot.isEmpty else { return }
        let migrated = store.migrateLegacyRunsIfNeeded(astraRootPath: astraRoot, exportRoot: exportRoot)
        runHistory = migrated
        saveRunHistory(migrated)
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
        guard let campaignsRoot = campaignsRootPath() else { return }
        if FileManager.default.fileExists(atPath: campaignsRoot) {
            openFolder(campaignsRoot)
            return
        }
        if let exportRoot = exportRootPath() {
            openFolder(exportRoot)
        }
    }

    private func openTodaysArchive() {
        openArchiveRoot()
    }

    private func exportCampaign(campaign: String, langs: [String], statusHandler: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a destination folder for export"

        panel.begin { resp in
            guard resp == .OK, let destUrl = panel.url else { return }
            let destFolder = destUrl.path
            let fm = FileManager.default
            let store = self.campaignStore()
            var exported = 0
            var missing = 0
            var exportedZips: [String: String] = [:]
            var lastZipPath: String? = nil
            var lastRoDeliverablesPath: String? = nil

            for lang in langs {
                guard let store else { continue }
                guard let exportRoot = exportRootPath() else { continue }
                let campaignURL = store.campaignLangURL(campaign: campaign, lang: lang, exportRoot: exportRoot)
                if !fm.fileExists(atPath: campaignURL.path) {
                    missing += 1
                    continue
                }
                let safeCampaign = store.campaignFolderName(for: campaign)
                let zipName = "\(safeCampaign)_\(lang.uppercased())_ASTRA.zip"
                let zipPath = (destFolder as NSString).appendingPathComponent(zipName)
                try? fm.removeItem(atPath: zipPath)
                do {
                    try zipFolderWithDitto(sourceFolder: campaignURL, zipPath: zipPath)
                    exported += 1
                    exportedZips[lang.lowercased()] = zipPath
                    lastZipPath = zipPath
                    if lang.lowercased() == "ro", lastRoDeliverablesPath == nil {
                        lastRoDeliverablesPath = resolveRoDeliverablesPath(campaignURL: campaignURL)
                    }
                } catch {
                    continue
                }
            }

            DispatchQueue.main.async {
                if exported > 0 {
                    if self.result == nil { self.result = ScopeResult() }
                    self.result?.shipRoot = destFolder
                    for (lang, path) in exportedZips {
                        self.result?.shipZipByLang[lang] = path
                    }
                    self.store.recordLastExport(exportRootURL: destUrl, zipPath: lastZipPath, roDeliverablesPath: lastRoDeliverablesPath)
                    statusHandler("Exported \(exported) ZIP(s).")
                } else if missing > 0 {
                    statusHandler("Campaign folder not found.")
                } else {
                    statusHandler("No ZIP found to export.")
                }
            }
        }
    }

    private func zipFolderWithDitto(sourceFolder: URL, zipPath: String) throws {
        let zipURL = URL(fileURLWithPath: zipPath)
        let fm = FileManager.default
        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceFolder.path, zipURL.path]

        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe

        try p.run()
        p.waitUntilExit()

        if p.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "ditto failed"
            throw NSError(domain: "SCOPE.Zip", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
        }
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

    private func loadRunHistory() -> [RunEntry] {
        guard let data = UserDefaults.standard.data(forKey: runHistoryKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([RunEntry].self, from: data) {
            return decoded.sorted { $0.timestamp > $1.timestamp }
        }
        return []
    }

    private func saveRunHistory(_ entries: [RunEntry]) {
        let trimmed = Array(entries.prefix(200))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(trimmed) {
            UserDefaults.standard.set(data, forKey: runHistoryKey)
        }
    }

    private struct RecentCampaign: Identifiable {
        let id: String
        let campaign: String
        let campaignFs: String
        let lang: String
        let path: String
        let sitesPath: String
        let lastModified: Date
        let runDirs: [String]
        let isHidden: Bool
        let hasRuns: Bool
    }

    private struct CampaignEntry {
        let campaign: String
        let campaignFs: String
        let lang: String
        let path: String
        let sitesPath: String
        let lastModified: Date
        let runDirs: [String]
        let isHidden: Bool
        let hasRuns: Bool
    }

    private func refreshRecentCampaigns() {
        guard let repo = resolvedRepoRoot() else {
            recentCampaigns = []
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = loadRecentCampaigns(repoRoot: repo)
            DispatchQueue.main.async {
                self.recentCampaigns = items
            }
        }
    }

    private func loadRecentCampaigns(repoRoot: String) -> [RecentCampaign] {
        let items = listAllCampaigns().map { entry in
            RecentCampaign(
                id: "\(entry.campaignFs)|\(entry.lang)|\(entry.path)",
                campaign: entry.campaign,
                campaignFs: entry.campaignFs,
                lang: entry.lang,
                path: entry.path,
                sitesPath: entry.sitesPath,
                lastModified: entry.lastModified,
                runDirs: entry.runDirs,
                isHidden: entry.isHidden,
                hasRuns: entry.hasRuns
            )
        }

        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        let sorted = existing.sorted { $0.lastModified > $1.lastModified }
        return Array(sorted.prefix(10))
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
        let items = listAllCampaigns().filter { !$0.hasRuns }
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
        listAllCampaigns().filter { !$0.hasRuns }.count
    }

    private func countOlderCampaigns(days: Int) -> Int {
        listOlderCampaigns(days: days).count
    }

    private func listOlderCampaigns(days: Int) -> [CampaignEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return listAllCampaigns().filter { $0.lastModified < cutoff }
    }

    private func listAllCampaigns() -> [CampaignEntry] {
        guard let campaignsRoot = campaignsRootPath() else { return [] }
        let fm = FileManager.default
        guard fm.fileExists(atPath: campaignsRoot) else { return [] }
        let store = campaignStore()

        guard let campaignDirs = try? fm.contentsOfDirectory(atPath: campaignsRoot) else { return [] }
        var items: [CampaignEntry] = []

        for campaignName in campaignDirs {
            let campaignRoot = (campaignsRoot as NSString).appendingPathComponent(campaignName)
            var isCampaignDir: ObjCBool = false
            guard fm.fileExists(atPath: campaignRoot, isDirectory: &isCampaignDir), isCampaignDir.boolValue else { continue }

            let manifest = (exportRootPath() != nil)
                ? store?.loadOrCreateManifest(
                    campaign: campaignName,
                    lang: "multi",
                    exportRoot: exportRootPath() ?? "",
                    isoNow: { iso8601String(Date()) }
                ).manifest
                : nil
                ?? CampaignManifest(
                    campaign: campaignName,
                    campaign_fs: campaignName,
                    lang: "multi",
                    created_at: iso8601String(Date()),
                    updated_at: iso8601String(Date()),
                    runs: []
                )
            let manifestCampaign = manifest?.campaign ?? ""
            let name = manifestCampaign.isEmpty ? campaignName : manifestCampaign
            let attrs = (try? fm.attributesOfItem(atPath: campaignRoot)) ?? [:]
            let lastModified = parseISO8601Date(manifest?.updated_at ?? "")
                ?? (attrs[.modificationDate] as? Date)
                ?? Date()
            let runsRoot = (campaignRoot as NSString).appendingPathComponent("runs")
            let runDirs = (try? fm.contentsOfDirectory(atPath: runsRoot)) ?? []
            let langs = Set(runDirs.compactMap { $0.split(separator: "_").last.map(String.init) })
            let langResolved: String = {
                if langs.count == 1 { return langs.first ?? "" }
                if langs.count > 1 { return "RO+EN" }
                return ""
            }()
            let sitesPath = campaignRoot
            let hiddenPath = (campaignRoot as NSString).appendingPathComponent(".hidden")
            let isHidden = fm.fileExists(atPath: hiddenPath)
            let hasRuns = !runDirs.isEmpty

            items.append(CampaignEntry(
                campaign: name,
                campaignFs: campaignName,
                lang: langResolved,
                path: campaignRoot,
                sitesPath: sitesPath,
                lastModified: lastModified,
                runDirs: runDirs,
                isHidden: isHidden,
                hasRuns: hasRuns
            ))
        }

        return items
    }

    private func deleteCampaignEntries(_ items: [CampaignEntry]) -> Int {
        guard campaignsRootPath() != nil else { return 0 }
        var deleted = 0
        var failed = 0
        for item in items {
            let campaignURL = URL(fileURLWithPath: item.path)
            let target = Campaign(id: campaignURL.path, name: item.campaign, campaignURL: campaignURL)
            do {
                try store.deleteCampaign(target, alsoDeleteAstra: true)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        runHistory = store.loadRunHistory()
        if failed > 0 {
            historyCleanupStatus = "Deleted \(deleted) campaigns. \(failed) failed."
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

    private func filteredCampaigns() -> [RecentCampaign] {
        let query = campaignSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = recentCampaigns

        switch campaignFilter {
        case .all:
            if !showHiddenCampaigns {
                items = items.filter { !$0.isHidden }
            }
        case .withRuns:
            items = items.filter { $0.hasRuns }
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
        case withRuns = "With Runs"
        case hidden = "Hidden"

        var id: String { rawValue }
    }

    private func statusBadge(for item: RecentCampaign) -> some View {
        let text = item.hasRuns ? "Ready" : "Incomplete"
        let color: Color = item.hasRuns ? .green : .secondary
        return Text(text)
            .font(.caption)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(item.hasRuns ? 0.15 : 0.08))
            )
    }

    private func readyToSendHint() -> String? {
        guard !isRunning, let status = lastRunStatus else { return nil }
        if status == "SUCCESS" {
            return "Send the ZIP files to the client. Start with Open Export/Delivery Root."
        }
        if status == "WARNING" {
            return "Warnings found. Send the ZIP files after reviewing. Start with Open Export/Delivery Root."
        }
        if status == "FAILED" {
            return "Run failed. Check Advanced logs."
        }
        return nil
    }

    private func statusBadgeSubline(for status: String) -> String {
        switch status {
        case "SUCCESS": return "Last run OK"
        case "WARNING": return "Last run: warnings"
        case "FAILED": return "Last run failed"
        case "Canceled": return "Last run canceled"
        case "OK": return "Last run OK"
        case "BROKEN": return "Last run: issues found"
        case "FATAL": return "Last run failed"
        default: return "Last run unknown"
        }
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
