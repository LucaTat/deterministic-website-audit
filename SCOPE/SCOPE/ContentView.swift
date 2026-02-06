import SwiftUI
import AppKit
import Darwin
import PDFKit

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

struct RunMetrics {
    struct Manifest: Codable {
        let domain: String?
        let lang: String?
        let generated_utc: String?
        let version: String?
    }

    let domain: String?
    let lang: String?
    let generatedUTC: String?
    let version: String?
    let auditReport: Bool
    let actionScope: Bool
    let proofPack: Bool
    let regression: Bool
    let masterPdf: Bool
    let masterBundle: Bool
    let bundleZip: Bool
    let checksums: Bool
    let masterSize: String?
    let masterBundleSize: String?
    let bundleSize: String?
    let masterPages: Int?
    let masterBundlePages: Int?

    init(runDir: URL) {
        let fm = FileManager.default
        let manifestURL = runDir.appendingPathComponent("final/manifest.json")
        var manifest: Manifest? = nil
        if let data = try? Data(contentsOf: manifestURL) {
            manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        }

        let runBase = runDir.lastPathComponent
        let inferredLang: String? = {
            let lower = runBase.lowercased()
            if lower.hasSuffix("_ro") { return "RO" }
            if lower.hasSuffix("_en") { return "EN" }
            return nil
        }()
        let inferredDomain: String? = {
            let parts = runBase.split(separator: "_")
            if parts.isEmpty { return nil }
            if parts.count >= 2 {
                let last = parts.last?.lowercased()
                if last == "ro" || last == "en" {
                    return String(parts[parts.count - 2])
                }
            }
            return String(parts.last!)
        }()

        domain = manifest?.domain ?? inferredDomain
        lang = manifest?.lang ?? inferredLang
        generatedUTC = manifest?.generated_utc
        version = manifest?.version

        func exists(_ rel: String) -> Bool {
            fm.fileExists(atPath: runDir.appendingPathComponent(rel).path)
        }

        auditReport = exists("audit/report.pdf")
        actionScope = exists("action_scope/action_scope.pdf")
        proofPack = exists("proof_pack/proof_pack.pdf")
        regression = exists("regression/regression.pdf")
        masterPdf = exists("final/master.pdf")
        masterBundle = exists("final/MASTER_BUNDLE.pdf")
        bundleZip = exists("final/client_safe_bundle.zip")
        checksums = exists("final/checksums.sha256")

        // Helper to find path in final/
        func finalPath(_ rel: String) -> URL {
            return runDir.appendingPathComponent("final/\(rel)")
        }

        masterSize = Self.formatSize(path: finalPath("master.pdf"))
        masterBundleSize = Self.formatSize(path: finalPath("MASTER_BUNDLE.pdf"))
        bundleSize = Self.formatSize(path: finalPath("client_safe_bundle.zip"))
        if masterPdf, let doc = PDFDocument(url: finalPath("master.pdf")) {
            masterPages = doc.pageCount
        } else {
            masterPages = nil
        }
        if masterBundle, let doc = PDFDocument(url: finalPath("MASTER_BUNDLE.pdf")) {
            masterBundlePages = doc.pageCount
        } else {
            masterBundlePages = nil
        }
    }

    private static func formatSize(path: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        let kb = (Double(truncating: size) / 1024.0).rounded()
        return "\(Int(kb)) KB"
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
    @State private var exportStartTime: Date? = nil
    @State private var exportBuildEndTime: Date? = nil
    @State private var exportPackageEndTime: Date? = nil
    @State private var exportVerifyEndTime: Date? = nil
    @State private var exportMetricsText: String? = nil
    @State private var exportSizesText: String? = nil
    @State private var metricsExpanded: Set<String> = []
    @State private var runExportTask: Process? = nil
    @State private var runExportRunID: String? = nil
    @State private var runExportCancelRequested: Bool = false

    @State private var toolRunning: Bool = false
    @State private var toolStatus: String? = nil
    @State private var toolTask: Process? = nil
    @State private var toolRunID: String? = nil
    @State private var showBaselinePicker: Bool = false
    @State private var baselinePickerTarget: RunEntry? = nil
    @State private var baselinePickerCandidates: [RunEntry] = []
    @State private var baselinePickerMessage: String? = nil
    @State private var finalizeRunning: Bool = false
    @State private var finalizeStatus: String? = nil
    @State private var finalizeRunID: String? = nil
    
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
        .sheet(isPresented: $showBaselinePicker) {
            baselinePickerSheet()
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
                        .help("Run a deterministic demo using example.com (requires SCOPE_TEST_MODE=1)")

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

                        let logsDisabled = isRunning
                        Button { openLogs() } label: {
                            Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                        .disabled(logsDisabled)
                        .opacity(buttonOpacity(disabled: logsDisabled))
                        .help(logsHelpText())

                        let runFolderDisabled = isRunning
                        Button { openPinnedRunFolder() } label: {
                            Label("Open Run Folder", systemImage: "folder.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(runFolderDisabled)
                        .opacity(buttonOpacity(disabled: runFolderDisabled))
                        .help("Open the last run folder")
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
                            Label("Open Delivery Root", systemImage: "shippingbox.fill")
                        }
                        .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                        .controlSize(.large)
                        .font(.headline)
                        .disabled(shipRootDisabled)
                        .opacity(buttonOpacity(disabled: shipRootDisabled))
                        .help(shipRootHelpText())
                        InfoButton(text: "Opens the run/final folder for the last run.")
                    }

                    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            let masterDisabled = isRunning || finalMasterPath(forLangSelection: lang) == nil
                            Button { openFinalMaster() } label: {
                                Label("Open master.pdf", systemImage: "doc.richtext")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(masterDisabled)
                            .opacity(buttonOpacity(disabled: masterDisabled))
                            .help("Open final/master.pdf")
                            InfoButton(text: "Opens the concatenated master PDF in run/final.")
                        }

                        HStack(spacing: 6) {
                            let bundleDisabled = isRunning || finalBundlePath(forLangSelection: lang) == nil
                            Button { openFinalBundle() } label: {
                                Label("Open MASTER_BUNDLE.pdf", systemImage: "doc.richtext")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(bundleDisabled)
                            .opacity(buttonOpacity(disabled: bundleDisabled))
                            .help("Open final/MASTER_BUNDLE.pdf")
                            InfoButton(text: "Opens the full client bundle PDF in run/final.")
                        }

                        HStack(spacing: 6) {
                            let zipDisabled = isRunning || finalZipPath(forLangSelection: lang) == nil
                            Button { openFinalZip() } label: {
                                Label("Reveal ZIP", systemImage: "archivebox.fill")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .disabled(zipDisabled)
                            .opacity(buttonOpacity(disabled: zipDisabled))
                            .help(zipHelpText(forLang: lang))
                            InfoButton(text: "Reveals run/final/client_safe_bundle.zip in Finder.")
                        }

                        HStack(spacing: 6) {
                            let logsDisabled = isRunning
                            Button { openLogs() } label: {
                                Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(NeonOutlineButtonStyle(theme: theme))
                            .tint(.secondary)
                            .disabled(logsDisabled)
                            .opacity(buttonOpacity(disabled: logsDisabled))
                            .help(logsHelpText())
                            InfoButton(text: "Opens the last run log for troubleshooting.")
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
                                        let runDirForExport = runRootPath(for: entry) ?? ""
                                        let deliverDisabled = isRunning || finalizeRunning || runDirForExport.isEmpty
                                        Button("Deliver (PDF)") {
                                            runFinalizeIfNeeded(entry: entry, openOnSuccess: true)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(deliverDisabled)
                                        .opacity(buttonOpacity(disabled: deliverDisabled))
                                        .help(deliverDisabled ? "Finalize and open MASTER_BUNDLE.pdf" : "Finalize and open MASTER_BUNDLE.pdf")
                                        .fixedSize(horizontal: true, vertical: false)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .minimumScaleFactor(0.85)
                                        .frame(minWidth: 140, alignment: .center)

                                        let exportDisabled = isRunning || exportIsRunning
                                        let bundlePath = runDirForExport.isEmpty ? "" : (runDirForExport as NSString).appendingPathComponent("final/client_safe_bundle.zip")
                                        let hasBundle = !bundlePath.isEmpty && FileManager.default.fileExists(atPath: bundlePath)
                                        let isExportingThis = exportIsRunning && runExportRunID == entry.id
                                        let isFailedThis = (!exportStatusText.isEmpty && exportStatusText.hasPrefix("ERROR:") && runExportRunID == entry.id)
                                        let exportButtonLabel = isExportingThis ? "Exporting…" : (hasBundle ? "Exported ✓" : (isFailedThis ? "Retry Export" : "Export Client Bundle"))

                                        let outDisabled = isRunning || entry.deliverablesDir.isEmpty || !FileManager.default.fileExists(atPath: entry.deliverablesDir)
                                        Button { openFolder(entry.deliverablesDir) } label: {
                                            Text("Open Output")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(outDisabled)
                                        .opacity(buttonOpacity(disabled: outDisabled))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .minimumScaleFactor(0.85)
                                        .frame(minWidth: 100, alignment: .center)

                                        let reportDisabled = isRunning || (entry.reportPdfPath == nil)
                                        Button {
                                            if let path = entry.reportPdfPath { revealAndOpenFile(path) }
                                        } label: {
                                            Text("Open Report")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(reportDisabled)
                                        .opacity(buttonOpacity(disabled: reportDisabled))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .minimumScaleFactor(0.85)
                                        .frame(minWidth: 100, alignment: .center)

                                        Menu("Advanced") {
                                            let logDisabled = isRunning || (entry.logPath == nil)
                                            Button("Open Log") {
                                                if let path = entry.logPath { revealAndOpenFile(path) }
                                            }
                                            .disabled(logDisabled)

                                            Button(exportButtonLabel) {
                                                runExportClientBundle(for: entry)
                                            }
                                            .disabled(exportDisabled)

                                            let openBundleDisabled = isRunning || exportIsRunning || !hasBundle
                                            Button("Open Bundle") {
                                                if !bundlePath.isEmpty {
                                                    revealAndOpenFile(bundlePath)
                                                }
                                            }
                                            .disabled(openBundleDisabled)

                                            if exportIsRunning && runExportRunID == entry.id {
                                                Button("Cancel Export") {
                                                    cancelRunExport()
                                                }
                                            }

                                        let toolDisabled = isRunning || exportIsRunning || toolRunning
                                        let lifecycle = runDirForExport.isEmpty ? nil : lifecycleStatus(runDir: runDirForExport, lang: entry.lang)
                                        let notAuditable = runDirForExport.isEmpty ? false : isNotAuditable(runDir: runDirForExport)
                                        let tool2Allowed = (lifecycle?.audit ?? false) && !notAuditable
                                        let tool3Allowed = (lifecycle?.plan ?? false) && (lifecycle?.baselineLinked ?? false) && !notAuditable
                                        let tool4Allowed = (lifecycle?.verify ?? false) && (lifecycle?.baselineLinked ?? false) && !notAuditable

                                        Button("Run Tool 2 — Action Scope") {
                                            guard let repoRoot = resolvedRepoRoot() else {
                                                toolStatus = "Export failed: Tool 2"
                                                return
                                                }
                                                let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool2_action_scope.sh")
                                            runTool(stepName: "Tool 2", scriptPath: scriptPath, entry: entry, expectedFolder: "action_scope")
                                        }
                                        .disabled(toolDisabled || !tool2Allowed)
                                        .help(tool2Allowed ? "Run Tool 2 — Action Scope" : (notAuditable ? "Tool 2 disabled for NOT AUDITABLE runs." : "Requires audit output (Tool 1)."))

                                        Button("Run Tool 3 — Implementation Proof") {
                                            guard let repoRoot = resolvedRepoRoot() else {
                                                toolStatus = "Export failed: Tool 3"
                                                return
                                                }
                                                let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool3_proof_pack.sh")
                                            runTool(stepName: "Tool 3", scriptPath: scriptPath, entry: entry, expectedFolder: "proof_pack")
                                        }
                                        .disabled(toolDisabled || !tool3Allowed)
                                        .help(tool3Allowed ? "Run Tool 3 — Implementation Proof" : (notAuditable ? "Tool 3 disabled for NOT AUDITABLE runs." : ((lifecycle?.plan ?? false) ? "Select baseline to run Tool 3." : "Run Tool 2 first.")))

                                        Button("Run Tool 4 — Regression Guard") {
                                            guard let repoRoot = resolvedRepoRoot() else {
                                                toolStatus = "Export failed: Tool 4"
                                                return
                                                }
                                                let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool4_regression.sh")
                                            runTool(stepName: "Tool 4", scriptPath: scriptPath, entry: entry, expectedFolder: "regression")
                                        }
                                        .disabled(toolDisabled || !tool4Allowed)
                                        .help(tool4Allowed ? "Run Tool 4 — Regression Guard" : (notAuditable ? "Tool 4 disabled for NOT AUDITABLE runs." : ((lifecycle?.verify ?? false) ? "Select baseline to run Tool 4." : "Run Tool 3 first.")))

                                            let tool2Path = toolPDFPath(for: entry, tool: "tool2") ?? ""
                                            let tool2Disabled = toolDisabled || tool2Path.isEmpty || !FileManager.default.fileExists(atPath: tool2Path)
                                            Button("Open Tool2 Output") {
                                                openToolOutput(for: entry, tool: "tool2")
                                            }
                                            .disabled(tool2Disabled)

                                            let tool3Path = toolPDFPath(for: entry, tool: "tool3") ?? ""
                                            let tool3Disabled = toolDisabled || tool3Path.isEmpty || !FileManager.default.fileExists(atPath: tool3Path)
                                            Button("Open Tool3 Output") {
                                                openToolOutput(for: entry, tool: "tool3")
                                            }
                                            .disabled(tool3Disabled)

                                            let tool4Path = toolPDFPath(for: entry, tool: "tool4") ?? ""
                                            let tool4Disabled = toolDisabled || tool4Path.isEmpty || !FileManager.default.fileExists(atPath: tool4Path)
                                            Button("Open Tool4 Output") {
                                                openToolOutput(for: entry, tool: "tool4")
                                            }
                                            .disabled(tool4Disabled)

                                            let baselineSelectable = (lifecycle?.audit ?? false) && !notAuditable
                                            Button("Select Baseline…") {
                                                openBaselinePicker(for: entry)
                                            }
                                            .disabled(!baselineSelectable)

                                            if lifecycle?.baselineLinked ?? false {
                                                Button("Clear Baseline") {
                                                    if let err = clearBaselineLink(for: entry) {
                                                        alert(title: "Baseline", message: err)
                                                    }
                                                }
                                            }

                                            Button("Delete Run") {
                                                pendingDeleteRun = RunRecord(entry: entry)
                                                showDeleteRunConfirm = true
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .minimumScaleFactor(0.85)
                                        .frame(minWidth: 100, alignment: .center)
                                    }
                                    .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text(exportStatusLabel(for: entry))
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                        if let runDirPath = runRootPath(for: entry),
                                           let suggestion = nextActionSuggestion(runDir: runDirPath, lang: entry.lang) {
                                            Text(suggestion)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                        let key = entry.id
                                        Button(metricsExpanded.contains(key) ? "Metrics ▾" : "Metrics ▸") {
                                            if metricsExpanded.contains(key) {
                                                metricsExpanded.remove(key)
                                            } else {
                                                metricsExpanded.insert(key)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    }
                                    if runExportRunID == entry.id && !exportIsRunning {
                                        if let metrics = exportMetricsText {
                                            Text(metrics)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .padding(.top, 4)
                                        }
                                        if let sizes = exportSizesText {
                                            Text(sizes)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    if metricsExpanded.contains(entry.id), let metrics = runMetrics(for: entry) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let runDirPath = runRootPath(for: entry) {
                                                let lifecycle = lifecycleStatus(runDir: runDirPath, lang: entry.lang)
                                                Text("Lifecycle")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                                Text("Audit \(lifecycle.audit ? "✅" : "❌") · Plan \(lifecycle.plan ? "✅" : "❌") · Verify \(lifecycle.verify ? "✅" : "❌") · Guard \(lifecycle.guardrail ? "✅" : "❌")")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                                Text("Bundle \(lifecycle.bundle ? "✅" : "❌") · Baseline \(lifecycle.baselineLinked ? "linked" : "missing")")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text("Metrics")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            Text("Domain: \(metrics.domain ?? "—") · Lang: \(metrics.lang ?? "—")")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            if let generated = metrics.generatedUTC, let version = metrics.version {
                                                Text("Generated: \(generated) · v\(version)")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                            } else if let generated = metrics.generatedUTC {
                                                Text("Generated: \(generated)")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.primary)
                                            }
                                            Text("audit/report.pdf \(metrics.auditReport ? "✅" : "❌") · action_scope \(metrics.actionScope ? "✅" : "❌") · proof_pack \(metrics.proofPack ? "✅" : "❌")")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            Text("regression \(metrics.regression ? "✅" : "❌") · master.pdf \(metrics.masterPdf ? "✅" : "❌") · MASTER_BUNDLE \(metrics.masterBundle ? "✅" : "❌") · bundle.zip \(metrics.bundleZip ? "✅" : "❌")")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            let checksumsLine = metrics.checksums ? "checksums ✅" : "checksums ❌"
                                            Text(checksumsLine)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            Text("Sizes: master \(metrics.masterSize ?? "—") · bundle \(metrics.bundleSize ?? "—") · MASTER_BUNDLE \(metrics.masterBundleSize ?? "—")")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            let pages = metrics.masterPages != nil ? "\(metrics.masterPages!)" : "—"
                                            Text("Master pages: \(pages)")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                            let bundlePages = metrics.masterBundlePages != nil ? "\(metrics.masterBundlePages!)" : "—"
                                            Text("MASTER_BUNDLE pages: \(bundlePages)")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(.top, 6)
                                    }
                                    if toolRunID == entry.id, let status = toolStatus {
                                        Text(status)
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                    if finalizeRunID == entry.id, let status = finalizeStatus {
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

                            Button { openLogs() } label: {
                                Label("Show log output", systemImage: "doc.text")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                            .opacity(buttonOpacity(disabled: isRunning))

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
                case "NOT AUDITABLE": return ("Not auditable", .orange)
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

    private func isTestModeEnabled() -> Bool {
        let env = ProcessInfo.processInfo.environment
        return env["SCOPE_TEST_MODE"] == "1"
    }

    private func blockedDummyHosts(in urls: [String]) -> [String] {
        var blocked: Set<String> = []
        for value in urls {
            guard let host = URL(string: value)?.host?.lowercased() else { continue }
            if host == "example.invalid" || host == "example.com" || host.hasSuffix(".example.invalid") {
                blocked.insert(host)
            }
        }
        return blocked.sorted()
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
        if !isTestModeEnabled() {
            let blocked = blockedDummyHosts(in: validLines)
            if !blocked.isEmpty {
                let listed = blocked.joined(separator: ", ")
                alert(
                    title: "Dummy domains blocked",
                    message: "Remove dummy domains (\(listed)) or set SCOPE_TEST_MODE=1 for test runs."
                )
                return nil
            }
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
        if !hasShipForCurrentLang() { return "Delivery disabled: Run Deliver (PDF) first" }
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
        return finalRootPath(forLangSelection: lang) != nil
    }

    private func hasZipForCurrentLang() -> Bool {
        return finalZipPath(forLangSelection: lang) != nil
    }

    private func runHelpText() -> String {
        if let reason = runDisabledReason() {
            return "Run the audit pipeline. \(reason)"
        }
        return "Run the audit pipeline (requires Engine + ASTRA folders)"
    }

    private func shipRootHelpText() -> String {
        if shipRootPath() == nil {
            return "Open run/final folder. Available after Deliver (PDF)."
        }
        return "Open the run/final folder"
    }

    private func zipHelpText(forLang lang: String) -> String {
        if zipDisabledReason() != nil {
            return "Open ZIP for the last run. Available after Deliver (PDF)."
        }
        return "Open the ZIP for the last run"
    }

    private func outputHelpText() -> String {
        if outputFolderPath() == nil {
            return "No run folder available for the last run."
        }
        return "Open run folder"
    }

    private func logsHelpText() -> String {
        if scopeRunLogPath() == nil {
            return "Run log not found yet. Finish a run to enable logs."
        }
        return "Open run.log for the last run"
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

                                    let runDirForExport = runRootPath(for: entry) ?? ""
                                    let deliverDisabled = isRunning || finalizeRunning || runDirForExport.isEmpty
                                    Button("Deliver (PDF)") {
                                        runFinalizeIfNeeded(entry: entry, openOnSuccess: true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(deliverDisabled)
                                    .opacity(buttonOpacity(disabled: deliverDisabled))
                                    .help(deliverDisabled ? "Finalize and open MASTER_BUNDLE.pdf" : "Finalize and open MASTER_BUNDLE.pdf")

                                    let exportDisabled = isRunning || exportIsRunning
                                    let bundlePath = runDirForExport.isEmpty ? "" : (runDirForExport as NSString).appendingPathComponent("final/client_safe_bundle.zip")
                                    let hasBundle = !bundlePath.isEmpty && FileManager.default.fileExists(atPath: bundlePath)
                                    let isExportingThis = exportIsRunning && runExportRunID == entry.id
                                    let isFailedThis = (!exportStatusText.isEmpty && exportStatusText.hasPrefix("ERROR:") && runExportRunID == entry.id)
                                    let exportButtonLabel = isExportingThis ? "Exporting…" : (hasBundle ? "Exported ✓" : (isFailedThis ? "Retry Export" : "Export Client Bundle"))

                                    let toolDisabled = isRunning || exportIsRunning || toolRunning
                                    let lifecycle = runDirForExport.isEmpty ? nil : lifecycleStatus(runDir: runDirForExport, lang: entry.lang)
                                    let notAuditable = runDirForExport.isEmpty ? false : isNotAuditable(runDir: runDirForExport)
                                    let tool2Allowed = (lifecycle?.audit ?? false) && !notAuditable
                                    let tool3Allowed = (lifecycle?.plan ?? false) && (lifecycle?.baselineLinked ?? false) && !notAuditable
                                    let tool4Allowed = (lifecycle?.verify ?? false) && (lifecycle?.baselineLinked ?? false) && !notAuditable

                                    Menu("Advanced") {
                                        Button(exportButtonLabel) {
                                            runExportClientBundle(for: entry)
                                        }
                                        .disabled(exportDisabled)

                                        let openBundleDisabled = isRunning || exportIsRunning || !hasBundle
                                        Button("Open Bundle") {
                                            if !bundlePath.isEmpty {
                                                revealAndOpenFile(bundlePath)
                                            }
                                        }
                                        .disabled(openBundleDisabled)

                                        if exportIsRunning && runExportRunID == entry.id {
                                            Button("Cancel Export") {
                                                cancelRunExport()
                                            }
                                        }

                                        let baselineSelectable = (lifecycle?.audit ?? false) && !notAuditable
                                        Button("Select Baseline…") {
                                            openBaselinePicker(for: entry)
                                        }
                                        .disabled(!baselineSelectable)

                                        if lifecycle?.baselineLinked ?? false {
                                            Button("Clear Baseline") {
                                                if let err = clearBaselineLink(for: entry) {
                                                    alert(title: "Baseline", message: err)
                                                }
                                            }
                                        }
                                    }
                                    Button("Run Tool 2 — Action Scope") {
                                        guard let repoRoot = resolvedRepoRoot() else {
                                            toolStatus = "Export failed: Tool 2"
                                            return
                                        }
                                        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool2_action_scope.sh")
                                        runTool(stepName: "Tool 2", scriptPath: scriptPath, entry: entry, expectedFolder: "action_scope")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(toolDisabled || !tool2Allowed)
                                    .opacity(buttonOpacity(disabled: toolDisabled || !tool2Allowed))
                                    .help(tool2Allowed ? "Run Tool 2 — Action Scope" : (notAuditable ? "Tool 2 disabled for NOT AUDITABLE runs." : "Requires audit output (Tool 1)."))

                                    Button("Run Tool 3 — Implementation Proof") {
                                        guard let repoRoot = resolvedRepoRoot() else {
                                            toolStatus = "Export failed: Tool 3"
                                            return
                                        }
                                        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool3_proof_pack.sh")
                                        runTool(stepName: "Tool 3", scriptPath: scriptPath, entry: entry, expectedFolder: "proof_pack")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(toolDisabled || !tool3Allowed)
                                    .opacity(buttonOpacity(disabled: toolDisabled || !tool3Allowed))
                                    .help(tool3Allowed ? "Run Tool 3 — Implementation Proof" : (notAuditable ? "Tool 3 disabled for NOT AUDITABLE runs." : ((lifecycle?.plan ?? false) ? "Select baseline to run Tool 3." : "Run Tool 2 first.")))

                                    Button("Run Tool 4 — Regression Guard") {
                                        guard let repoRoot = resolvedRepoRoot() else {
                                            toolStatus = "Export failed: Tool 4"
                                            return
                                        }
                                        let scriptPath = (repoRoot as NSString).appendingPathComponent("scripts/run_tool4_regression.sh")
                                        runTool(stepName: "Tool 4", scriptPath: scriptPath, entry: entry, expectedFolder: "regression")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(toolDisabled || !tool4Allowed)
                                    .opacity(buttonOpacity(disabled: toolDisabled || !tool4Allowed))
                                    .help(tool4Allowed ? "Run Tool 4 — Regression Guard" : (notAuditable ? "Tool 4 disabled for NOT AUDITABLE runs." : ((lifecycle?.verify ?? false) ? "Select baseline to run Tool 4." : "Run Tool 3 first.")))

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
                                .foregroundStyle(.primary)
                                Text(exportStatusLabel(for: entry))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                if let runDirPath = runRootPath(for: entry),
                                   let suggestion = nextActionSuggestion(runDir: runDirPath, lang: entry.lang) {
                                    Text(suggestion)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                if toolRunID == entry.id, let status = toolStatus {
                                    Text(status)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                if finalizeRunID == entry.id, let status = finalizeStatus {
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

    @ViewBuilder
    private func baselinePickerSheet() -> some View {
        let target = baselinePickerTarget
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Select Baseline")
                    .font(.title3)
                    .foregroundColor(.primary)
                Spacer()
                Button("Close") {
                    showBaselinePicker = false
                }
                .buttonStyle(NeonOutlineButtonStyle(theme: theme))
            }
            if let target {
                let domain = domainFromURLString(target.url) ?? target.url
                Text("Target: \(domain) • \(target.lang.uppercased())")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("No target run selected.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if let message = baselinePickerMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if baselinePickerCandidates.isEmpty {
                Text("No eligible baseline runs found for this domain and language.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                List(baselinePickerCandidates) { entry in
                    Button {
                        guard let target else { return }
                        baselinePickerMessage = nil
                        if let err = writeBaselineLink(target: target, baseline: entry) {
                            baselinePickerMessage = err
                        } else {
                            baselinePickerMessage = "Baseline linked."
                            showBaselinePicker = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(baselineLabel(for: entry))
                                .font(.footnote)
                                .foregroundColor(.primary)
                            Text(entry.status)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(minHeight: 180)
            }
            HStack {
                if let target, readBaselineLink(runDir: runRootPath(for: target) ?? "") != nil {
                    Button("Clear Baseline") {
                        baselinePickerMessage = nil
                        if let err = clearBaselineLink(for: target) {
                            baselinePickerMessage = err
                        } else {
                            baselinePickerMessage = "Baseline cleared."
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("Close") {
                    showBaselinePicker = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
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

    private func openPinnedRunFolder() {
        guard let path = lastRunDir,
              FileManager.default.fileExists(atPath: path) else {
            alert(title: "No run folder", message: "No run folder available for the last run.")
            return
        }
        openFolder(path)
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
        lang: String,
        pinnedRunDir: String?
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

        let runFolderURL: URL
        if let pinned = pinnedRunDir, !pinned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runFolderURL = URL(fileURLWithPath: pinned)
        } else {
            runFolderURL = store.runFolderURL(
                campaign: campaignName,
                lang: lang,
                domain: domain,
                timestamp: timestampString,
                exportRoot: exportRoot
            )
        }
        if pinnedRunDir == nil, fm.fileExists(atPath: runFolderURL.path) {
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
                astraDest.appendingPathComponent("audit").appendingPathComponent("report.pdf").path,
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
                astraDest.appendingPathComponent("audit").appendingPathComponent("report.json").path,
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

        let verdictSourceInAudit = (runDir as NSString).appendingPathComponent("audit/verdict.json")
        let verdictSourceInDeliverables = (deliverablesSource as NSString).appendingPathComponent("verdict.json")
        let verdictSourceAtRoot = (runDir as NSString).appendingPathComponent("verdict.json")
        let verdictDest = astraDest.appendingPathComponent("verdict.json")
        
        if fm.fileExists(atPath: verdictSourceInAudit), !fm.fileExists(atPath: verdictDest.path) {
            try? fm.copyItem(atPath: verdictSourceInAudit, toPath: verdictDest.path)
        } else if fm.fileExists(atPath: verdictSourceInDeliverables), !fm.fileExists(atPath: verdictDest.path) {
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
        let verdictPath = verdictDest.path
        let reportExists = fm.fileExists(atPath: reportPath)
        let verdictExists = fm.fileExists(atPath: verdictPath)
        let success = verdictExists
        if !success {
            if pinnedRunDir == nil {
                try? fm.removeItem(at: runFolderURL)
            }
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
        if let logPath = lastRunLogPath,
           FileManager.default.fileExists(atPath: logPath) {
            revealAndOpenFile(logPath)
            return
        }
        if let runDir = lastRunDir {
            let fallback = (runDir as NSString).appendingPathComponent("logs/run.log")
            if FileManager.default.fileExists(atPath: fallback) {
                revealAndOpenFile(fallback)
                return
            }
        }
        alert(title: "No log file", message: "No log file found for the last run.")
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
        if !isTestModeEnabled() {
            alert(title: "Demo disabled", message: "Set SCOPE_TEST_MODE=1 to run demo with example.com.")
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

    private func preparePinnedRunDir(spec: RunSpec, campaignName: String) -> (runDir: String, logPath: String)? {
        guard let store = campaignStore(), let exportRoot = exportRootPath() else { return nil }
        let fm = FileManager.default
        let domain = domainFromURLString(spec.url) ?? "unknown"
        let baseTimestamp = iso8601String(Date())
        var attempt = 0
        var runURL: URL
        while true {
            let ts = attempt == 0 ? baseTimestamp : "\(baseTimestamp)-\(attempt)"
            runURL = store.runFolderURL(
                campaign: campaignName,
                lang: spec.lang,
                domain: domain,
                timestamp: ts,
                exportRoot: exportRoot
            )
            if !fm.fileExists(atPath: runURL.path) { break }
            attempt += 1
        }

        store.ensureDirectory(runURL.path)
        let logsDir = runURL.appendingPathComponent("logs")
        store.ensureDirectory(logsDir.path)
        let logURL = logsDir.appendingPathComponent("run.log")
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: Data())
        }

        let safeCampaign = store.campaignFolderName(for: campaignName)
        let manifest = CampaignManifest.new(
            campaign: campaignName,
            campaign_fs: safeCampaign,
            lang: spec.lang,
            now: iso8601String(Date())
        )
        store.writeManifestAtomic(manifest, to: runURL.appendingPathComponent("manifest.json"))

        return (runURL.path, logURL.path)
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

            guard let campaignName = self.lastRunCampaign,
                  let pinned = self.preparePinnedRunDir(spec: spec, campaignName: campaignName) else {
                DispatchQueue.main.async {
                    self.lastRunStatus = "FAILED"
                    self.runState = .error
                    self.isRunning = false
                    endAccessIfNeeded()
                    self.alert(title: "Run failed", message: "Could not prepare run folder.")
                }
                return
            }

            let pinnedRunDir = pinned.runDir
            let logPath = pinned.logPath
            fm.createFile(atPath: logPath, contents: nil)
            DispatchQueue.main.async {
                self.lastRunDir = pinnedRunDir
                self.lastRunLogPath = logPath
            }

            logOutput += "\n== ASTRA run \(index)/\(specs.count) • \(spec.lang.uppercased()) • \(spec.url) ==\n"

            let task = Process()
            currentTask = task
            let venvPython = URL(fileURLWithPath: normalizedAstraRoot)
                .appendingPathComponent(".venv/bin/python").path
            let pythonPath = fm.isExecutableFile(atPath: venvPython) ? venvPython : "/usr/bin/python3"
            let scopeScript = (engineRoot as NSString).appendingPathComponent("scripts/scope_engine_run.sh")
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scopeScript, "--url", spec.url, "--run-dir", pinnedRunDir, "--lang", spec.lang, "--max-pages", "15"]
            task.currentDirectoryURL = URL(fileURLWithPath: normalizedAstraRoot)
            var environment = task.environment ?? ProcessInfo.processInfo.environment
            environment["SCOPE_REPO"] = engineRoot
            environment["ASTRA_LANG"] = (spec.lang == "en" ? "EN" : "RO")
            environment["SCOPE_USE_AI"] = useAI ? "1" : "0"
            environment["SCOPE_ANALYSIS_MODE"] = analysisMode
            environment["SCOPE_DISABLE_VISUAL"] = "1"
            environment["SCOPE_SKIP_SITEMAP"] = "1"
            task.environment = environment
            let runEnv = environment

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
                        let runDir = pinnedRunDir
                        let runDirURL = URL(fileURLWithPath: runDir)
                        let repoRoot = self.resolvedRepoRoot() ?? ""

                        func appendToRunLog(_ text: String) {
                            guard !text.isEmpty,
                                  let data = text.data(using: .utf8),
                                  let handle = FileHandle(forWritingAtPath: logPath) else { return }
                            handle.seekToEndOfFile()
                            handle.write(data)
                            handle.closeFile()
                        }

                        var masterFinalExit: Int32 = 1
                        var masterFinalOutput = ""
                        let shouldRunAstra = code == 0 || code == 22 || code == 23 || code == 24
                        if !wasCanceled, !wasTimedOut, shouldRunAstra {
                            let header = "\n== ASTRA pipeline • \(spec.lang.uppercased()) • \(spec.url) ==\n"
                            DispatchQueue.main.async {
                                self.logOutput += header
                            }
                            appendToRunLog(header)
                            let masterResult = self.runToolProcess(
                                executable: pythonPath,
                                arguments: ["-m", "astra.run_full_pipeline", "--det-run-dir", runDir, "--lang", spec.lang.uppercased()],
                                cwd: normalizedAstraRoot,
                                env: runEnv
                            )
                            masterFinalExit = masterResult.0
                            masterFinalOutput = masterResult.1
                            if !masterFinalOutput.isEmpty {
                                DispatchQueue.main.async {
                                    self.logOutput += masterFinalOutput
                                }
                                appendToRunLog(masterFinalOutput)
                            }
                        }

                        var masterFinalError: String? = nil
                        if !wasCanceled, !wasTimedOut, shouldRunAstra, masterFinalExit != 0 {
                            let snippet = self.tailLines(masterFinalOutput, count: 6)
                            let sanitized = self.sanitizeError(snippet, runDir: runDirURL, repoRoot: repoRoot, astraRoot: normalizedAstraRoot)
                            masterFinalError = sanitized.isEmpty ? "Master final failed." : sanitized
                        }

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
                    if masterFinalExit == 0, let campaignName = self.lastRunCampaign {
                        delivery = self.deliverAstraRun(
                            runDir: runDir,
                            url: spec.url,
                            campaignName: campaignName,
                            lang: spec.lang,
                            pinnedRunDir: pinnedRunDir
                        )
                    }

                    let artifacts = self.resolveRunArtifacts(runDir: runDir, lang: spec.lang)
                    let verdictPath = artifacts.verdictPath ?? ""
                    let decisionBriefPath = artifacts.decisionBriefPath
                    let scopeLogPath = (runDir as NSString).appendingPathComponent("scope_run.log")
                    let scopeLogExists = FileManager.default.fileExists(atPath: scopeLogPath)

                    let bundleOk = self.finalArtifactsExist(runDir: runDir)
                    let verdictValue = self.readVerdictValue(runDir: runDir)
                    let verdictExists = verdictValue != nil
                    let isNotAuditable = verdictValue?.uppercased() == "NOT_AUDITABLE"
                    var status: String
                    if wasCanceled {
                        status = "Canceled"
                    } else if wasTimedOut {
                        status = "FAILED"
                    } else if verdictExists {
                        if bundleOk {
                            status = isNotAuditable ? "NOT AUDITABLE" : "SUCCESS"
                        } else {
                            status = "FAILED"
                        }
                    } else {
                        status = "FAILED"
                    }

                    let deliverablesDir = delivery.runFolderPath ?? delivery.deliveredDir ?? ""
                    let astraRunDir = deliverablesDir.isEmpty
                        ? runDir
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
                    let resolvedLogPath = self.lastRunLogPath ?? (scopeLogExists ? scopeLogPath : delivery.scopeLogPath)

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

                        if finalOk {
                            sawError = false
                            self.runState = .done
                        } else {
                            if status == "FAILED" {
                                sawError = true
                                self.runState = .error
                            } else if status == "SUCCESS" {
                                self.runState = .done
                            }
                        }

                        self.lastRunDomain = delivery.domain ?? self.domainFromURLString(spec.url)
                        if self.lastRunLogPath == nil, let resolvedLogPath {
                            self.lastRunLogPath = resolvedLogPath
                        }
                        if self.lastRunDir == nil || !(FileManager.default.fileExists(atPath: self.lastRunDir ?? "")) {
                            self.lastRunDir = runDir
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
                        if finalOk, isNotAuditable {
                            self.lastRunStatus = "NOT AUDITABLE"
                        } else {
                            self.lastRunStatus = finalOk ? "SUCCESS" : status
                        }
                        if let auditCopyError {
                            self.lastRunStatus = "FAILED"
                            self.runState = .error
                            self.readyToSend = false
                            self.logOutput += "\n\(auditCopyError)"
                        }
                        if let masterFinalError {
                            self.lastRunStatus = "FAILED"
                            self.runState = .error
                            self.readyToSend = false
                            self.logOutput += "\nERROR: master_final failed\n\(masterFinalError)"
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
                        self.readyToSend = finalOk || status == "SUCCESS" || status == "WARNING"

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

    private func runMetrics(for entry: RunEntry) -> RunMetrics? {
        guard let runDirPath = runRootPath(for: entry) else { return nil }
        return RunMetrics(runDir: URL(fileURLWithPath: runDirPath))
    }

    private func formatSeconds(_ seconds: Double?) -> String {
        guard let seconds else { return "0.0s" }
        let rounded = (seconds * 10).rounded() / 10
        return String(format: "%.1fs", rounded)
    }

    private func formatKB(_ bytes: Int?) -> String {
        guard let bytes else { return "0 KB" }
        let kb = Int((Double(bytes) / 1024.0).rounded())
        return "\(kb) KB"
    }

    private func fileSizeBytes(_ path: String) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.intValue
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

        // Combine stdout + stderr so failures are visible.
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

    private func resolveConcreteRunDir(baseRunsDir: URL) -> URL? {
        let fm = FileManager.default
        let required = ["audit", "action_scope", "proof_pack", "regression"]

        // Check if baseRunsDir itself has required dirs (direct run folder)
        let hasAll = required.allSatisfy { fm.fileExists(atPath: baseRunsDir.appendingPathComponent($0, isDirectory: true).path) }
        if hasAll { return baseRunsDir }

        // Check if baseRunsDir/astra has required dirs (campaign folder structure)
        let astraSubdir = baseRunsDir.appendingPathComponent("astra")
        let astraHasAll = required.allSatisfy { fm.fileExists(atPath: astraSubdir.appendingPathComponent($0, isDirectory: true).path) }
        if astraHasAll { return astraSubdir }

        return nil
    }

    private func tailLines(_ text: String, count: Int) -> String {
        let lines = text.split(separator: "\n")
        let slice = lines.suffix(count)
        return slice.joined(separator: "\n")
    }

    private func missingRequiredMessage(from output: String) -> String? {
        for lineSub in output.split(separator: "\n") {
            let line = lineSub.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("MISSING_REQUIRED:") {
                let tail = line.dropFirst("MISSING_REQUIRED:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                return tail.isEmpty ? nil : String(tail)
            }
        }
        return nil
    }

    private func sanitizeError(_ text: String, runDir: URL, repoRoot: String, astraRoot: String) -> String {
        var out = text
        out = out.replacingOccurrences(of: runDir.path, with: "<RUN_DIR>")
        out = out.replacingOccurrences(of: repoRoot, with: "<REPO>")
        out = out.replacingOccurrences(of: astraRoot, with: "<ASTRA>")
        return out
    }

    private struct RunArtifacts {
        let runDir: String
        let deliverablesDir: String?
        let verdictPath: String?
        let auditReportPath: String?
        let decisionBriefPath: String?
        let evidenceAppendixPath: String?
        let finalRoot: String?
    }

    private struct BaselineLink {
        let runId: String?
        let runHash: String?
        let label: String?
    }

    private struct LifecycleStatus {
        let audit: Bool
        let plan: Bool
        let verify: Bool
        let guardrail: Bool
        let bundle: Bool
        let baselineLinked: Bool
    }

    private func runRootCandidates(_ runDir: String) -> [String] {
        let base = runDir
        let astraSubdir = (runDir as NSString).appendingPathComponent("astra")
        if base == astraSubdir {
            return [base]
        }
        return [base, astraSubdir]
    }

    private func firstExistingPath(_ candidates: [String]) -> String? {
        let fm = FileManager.default
        for path in candidates where fm.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    private func artifactExists(runDir: String, rel: String) -> Bool {
        let fm = FileManager.default
        for root in runRootCandidates(runDir) {
            let candidate = (root as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: candidate) {
                return true
            }
        }
        return false
    }

    private func resolveDeliverablesDir(runDir: String) -> String? {
        let fm = FileManager.default
        for root in runRootCandidates(runDir) {
            let candidate = (root as NSString).appendingPathComponent("deliverables")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return nil
    }

    private func resolveVerdictPath(runDir: String) -> String? {
        let roots = runRootCandidates(runDir)
        for root in roots {
            let candidates = [
                (root as NSString).appendingPathComponent("deliverables/verdict.json"),
                (root as NSString).appendingPathComponent("audit/verdict.json"),
                (root as NSString).appendingPathComponent("verdict.json"),
            ]
            if let found = firstExistingPath(candidates) {
                return found
            }
        }
        return nil
    }

    private func resolveAuditReportPath(runDir: String) -> String? {
        let roots = runRootCandidates(runDir)
        for root in roots {
            let candidates = [
                (root as NSString).appendingPathComponent("audit/report.pdf"),
                (root as NSString).appendingPathComponent("deliverables/report.pdf"),
            ]
            if let found = firstExistingPath(candidates) {
                return found
            }
        }
        return nil
    }

    private func resolveDecisionBriefPath(runDir: String, lang: String) -> String? {
        let fm = FileManager.default
        let langUpper = lang.uppercased() == "EN" ? "EN" : "RO"
        guard let deliverablesDir = resolveDeliverablesDir(runDir: runDir) else { return nil }
        let canonical = (deliverablesDir as NSString).appendingPathComponent("Decision_Brief_\(langUpper).pdf")
        if fm.fileExists(atPath: canonical) { return canonical }
        let prefix = "Decision Brief - "
        let suffix = " - \(langUpper).pdf"
        if let entries = try? fm.contentsOfDirectory(atPath: deliverablesDir) {
            let matches = entries.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.sorted()
            if let first = matches.first {
                return (deliverablesDir as NSString).appendingPathComponent(first)
            }
        }
        return nil
    }

    private func resolveEvidenceAppendixPath(runDir: String, lang: String) -> String? {
        let fm = FileManager.default
        let langUpper = lang.uppercased() == "EN" ? "EN" : "RO"
        guard let deliverablesDir = resolveDeliverablesDir(runDir: runDir) else { return nil }
        let canonical = (deliverablesDir as NSString).appendingPathComponent("Evidence_Appendix_\(langUpper).pdf")
        if fm.fileExists(atPath: canonical) { return canonical }
        let prefix = "Evidence Appendix - "
        let suffix = " - \(langUpper).pdf"
        if let entries = try? fm.contentsOfDirectory(atPath: deliverablesDir) {
            let matches = entries.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.sorted()
            if let first = matches.first {
                return (deliverablesDir as NSString).appendingPathComponent(first)
            }
        }
        return nil
    }

    private func resolveFinalRoot(runDir: String) -> String? {
        let fm = FileManager.default
        for root in runRootCandidates(runDir) {
            let allExist = requiredFinalArtifacts().allSatisfy { rel in
                fm.fileExists(atPath: (root as NSString).appendingPathComponent(rel))
            }
            if allExist {
                return root
            }
        }
        return nil
    }

    private func resolveRunArtifacts(runDir: String, lang: String) -> RunArtifacts {
        return RunArtifacts(
            runDir: runDir,
            deliverablesDir: resolveDeliverablesDir(runDir: runDir),
            verdictPath: resolveVerdictPath(runDir: runDir),
            auditReportPath: resolveAuditReportPath(runDir: runDir),
            decisionBriefPath: resolveDecisionBriefPath(runDir: runDir, lang: lang),
            evidenceAppendixPath: resolveEvidenceAppendixPath(runDir: runDir, lang: lang),
            finalRoot: resolveFinalRoot(runDir: runDir)
        )
    }

    private func readBaselineLink(runDir: String) -> BaselineLink? {
        let candidates = runRootCandidates(runDir).flatMap { root in
            [
                (root as NSString).appendingPathComponent("baseline.json"),
                (root as NSString).appendingPathComponent("final/baseline.json"),
            ]
        }
        guard let path = firstExistingPath(candidates) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let runId = json["baseline_run_id"] as? String
        let runHash = (json["baseline_run_ref"] as? String) ?? (json["baseline_run_hash"] as? String)
        let label = json["baseline_label"] as? String
        if (runId ?? "").isEmpty && (runHash ?? "").isEmpty {
            return nil
        }
        return BaselineLink(runId: runId, runHash: runHash, label: label)
    }

    private func baselineLabel(for entry: RunEntry) -> String {
        let domain = domainFromURLString(entry.url) ?? entry.url
        return "\(formatRunTimestamp(entry.timestamp)) • \(entry.lang.uppercased()) • \(domain)"
    }

    private func baselineCandidates(for target: RunEntry) -> [RunEntry] {
        let targetDomain = domainFromURLString(target.url)
        let targetLang = target.lang.lowercased()
        let runs = campaignScopedRunHistory()
        let candidates: [(entry: RunEntry, finalOk: Bool)] = runs.compactMap { entry in
            guard entry.id != target.id else { return nil }
            guard entry.lang.lowercased() == targetLang else { return nil }
            guard targetDomain != nil, domainFromURLString(entry.url) == targetDomain else { return nil }
            guard let runDir = runRootPath(for: entry) else { return nil }
            guard isSuccessStatus(entry.status) else { return nil }
            if isNotAuditable(runDir: runDir) { return nil }
            let lifecycle = lifecycleStatus(runDir: runDir, lang: entry.lang)
            guard lifecycle.audit else { return nil }
            return (entry: entry, finalOk: finalArtifactsExist(runDir: runDir))
        }
        return candidates.sorted {
            if $0.finalOk != $1.finalOk { return $0.finalOk && !$1.finalOk }
            return $0.entry.timestamp > $1.entry.timestamp
        }.map { $0.entry }
    }

    private func openBaselinePicker(for entry: RunEntry) {
        baselinePickerTarget = entry
        baselinePickerCandidates = baselineCandidates(for: entry)
        baselinePickerMessage = nil
        showBaselinePicker = true
    }

    private func writeBaselineLink(target: RunEntry, baseline: RunEntry) -> String? {
        guard let targetDir = runRootPath(for: target) else {
            return "Run directory missing."
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: targetDir) else {
            return "Run directory missing."
        }
        let baselineRunDir = runRootPath(for: baseline)
        let baselineRef = baselineRunDir.map { URL(fileURLWithPath: $0).lastPathComponent } ?? baseline.id
        let payload: [String: Any] = [
            "baseline_run_id": baseline.id,
            "baseline_run_ref": baselineRef,
            "baseline_run_hash": baselineRef,
            "baseline_label": baselineLabel(for: baseline),
            "baseline_url": baseline.url,
            "baseline_lang": baseline.lang.uppercased(),
            "baseline_timestamp": iso8601String(baseline.timestamp)
        ]
        let baselinePath = (targetDir as NSString).appendingPathComponent("baseline.json")
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return "Baseline metadata invalid."
        }
        do {
            try data.write(to: URL(fileURLWithPath: baselinePath), options: [.atomic])
        } catch {
            return "Baseline link failed."
        }
        bumpUIRefresh()
        return nil
    }

    private func clearBaselineLink(for target: RunEntry) -> String? {
        guard let targetDir = runRootPath(for: target) else {
            return "Run directory missing."
        }
        let fm = FileManager.default
        let baselinePath = (targetDir as NSString).appendingPathComponent("baseline.json")
        let finalBaselinePath = (targetDir as NSString).appendingPathComponent("final/baseline.json")
        _ = try? fm.removeItem(atPath: baselinePath)
        _ = try? fm.removeItem(atPath: finalBaselinePath)
        bumpUIRefresh()
        return nil
    }

    private func lifecycleStatus(runDir: String, lang: String) -> LifecycleStatus {
        let artifacts = resolveRunArtifacts(runDir: runDir, lang: lang)
        let auditOk = artifacts.auditReportPath != nil && artifacts.verdictPath != nil
        let planOk = artifactExists(runDir: runDir, rel: "action_scope/action_scope.pdf")
        let verifyOk = artifactExists(runDir: runDir, rel: "proof_pack/proof_pack.pdf")
        let guardOk = artifactExists(runDir: runDir, rel: "regression/regression.pdf")
        let bundleOk = artifacts.finalRoot != nil
        let baselineLinked = readBaselineLink(runDir: runDir) != nil
        return LifecycleStatus(
            audit: auditOk,
            plan: planOk,
            verify: verifyOk,
            guardrail: guardOk,
            bundle: bundleOk,
            baselineLinked: baselineLinked
        )
    }

    private func isNotAuditable(runDir: String) -> Bool {
        guard let verdict = readVerdictValue(runDir: runDir) else { return false }
        return verdict.uppercased() == "NOT_AUDITABLE"
    }

    private func nextActionSuggestion(runDir: String, lang: String) -> String? {
        let lifecycle = lifecycleStatus(runDir: runDir, lang: lang)
        if lifecycle.bundle { return "Complete ✓" }
        if isNotAuditable(runDir: runDir) {
            return "Next: Deliver (PDF)"
        }
        if !lifecycle.audit { return "Next: Run Audit (Tool 1)" }
        if !lifecycle.plan { return "Next: Run Tool 2 — Plan" }
        if !lifecycle.baselineLinked { return "Next: Select baseline to run Tool 3/4" }
        if !lifecycle.verify { return "Next: Run Tool 3 — Verify" }
        if !lifecycle.guardrail { return "Next: Run Tool 4 — Guard" }
        return "Next: Deliver (PDF)"
    }

    private func requiredFinalArtifacts() -> [String] {
        return [
            "final/master.pdf",
            "final/MASTER_BUNDLE.pdf",
            "final/client_safe_bundle.zip",
            "final/checksums.sha256"
        ]
    }

    private func finalArtifactsExist(runDir: String) -> Bool {
        return resolveFinalRoot(runDir: runDir) != nil
    }

    private func readVerdictValue(runDir: String) -> String? {
        guard let verdictPath = resolveVerdictPath(runDir: runDir) else { return nil }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: verdictPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let verdict = json["verdict"] as? String {
            return verdict
        }
        return nil
    }

    private func ensureFinalArtifacts(runDir: URL, lang: String, repoRoot: String, env: [String: String]) -> (Bool, String?) {
        // Support multiple folder structures (matching shell script detection):
        // 1. runDir/astra/verdict.json (campaign folder with astra/ subfolder)
        // 2. runDir/astra/audit/verdict.json (alternative location)
        // 3. runDir/audit/verdict.json (direct Astra run)
        // 4. runDir/verdict.json (legacy/simple format)
        let hasVerdict = resolveVerdictPath(runDir: runDir.path) != nil
        guard hasVerdict else {
            return (false, "No verdict.json found")
        }
        let astraRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Desktop")
            .appendingPathComponent("astra")
            .path
        let decisionBriefRel = "deliverables/Decision_Brief_\(lang.uppercased() == "EN" ? "EN" : "RO").pdf"
        let appendixRel = "deliverables/Evidence_Appendix_\(lang.uppercased() == "EN" ? "EN" : "RO").pdf"
        let resolvedBrief = resolveDecisionBriefPath(runDir: runDir.path, lang: lang)
        let resolvedAppendix = resolveEvidenceAppendixPath(runDir: runDir.path, lang: lang)
        if resolvedBrief == nil || resolvedAppendix == nil {
            let genScript = (repoRoot as NSString).appendingPathComponent("scripts/generate_report_from_verdict.py")
            let genResult = runToolProcess(
                executable: "/usr/bin/env",
                arguments: ["python3", genScript, runDir.path, "--lang", lang],
                cwd: repoRoot,
                env: env
            )
            if genResult.0 != 0 {
                return (false, "Missing required: \(decisionBriefRel),\(appendixRel)")
            }
        }
        let finalizeScript = (repoRoot as NSString).appendingPathComponent("scripts/finalize_run.sh")

        let finalizeResult = runToolProcess(
            executable: "/bin/bash",
            arguments: [finalizeScript, runDir.path, lang],
            cwd: repoRoot,
            env: env
        )
        if finalizeResult.0 != 0 {
            if let missing = missingRequiredMessage(from: finalizeResult.1) {
                return (false, "Missing required: \(missing)")
            }
            let msg = sanitizeError(tailLines(finalizeResult.1, count: 6), runDir: runDir, repoRoot: repoRoot, astraRoot: astraRoot)
            return (false, msg)
        }

        guard resolveFinalRoot(runDir: runDir.path) != nil else {
            return (false, "missing required: final artifacts")
        }

        return (true, nil)
    }

    private func runFinalizeIfNeeded(entry: RunEntry, openOnSuccess: Bool) {
        guard let baseRunDir = runRootPath(for: entry) else {
            finalizeStatus = "ERROR: finalize: missing run dir"
            finalizeRunID = entry.id
            return
        }
        guard let repoRoot = resolvedRepoRoot() else {
            finalizeStatus = "ERROR: finalize: repo missing"
            finalizeRunID = entry.id
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: baseRunDir, isDirectory: &isDir), isDir.boolValue else {
            finalizeStatus = "ERROR: finalize: invalid run directory"
            finalizeRunID = entry.id
            return
        }
        let runURL = URL(fileURLWithPath: baseRunDir)
        let langCode = entry.lang.lowercased() == "en" ? "EN" : "RO"
        let masterBundlePath = runURL.appendingPathComponent("final/MASTER_BUNDLE.pdf").path
        let hasAllFinal = requiredFinalArtifacts().allSatisfy { rel in
            FileManager.default.fileExists(atPath: runURL.appendingPathComponent(rel).path)
        }
        if hasAllFinal {
            if openOnSuccess {
                revealAndOpenFile(masterBundlePath)
            }
            return
        }
        if finalizeRunning { return }

        finalizeRunning = true
        finalizeRunID = entry.id
        finalizeStatus = "Finalizing…"

        DispatchQueue.global(qos: .userInitiated).async {
            let venvBin = (repoRoot as NSString).appendingPathComponent(".venv/bin")
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = venvBin + ":" + (env["PATH"] ?? "")

            let result = self.ensureFinalArtifacts(runDir: runURL, lang: langCode, repoRoot: repoRoot, env: env)

            DispatchQueue.main.async {
                self.finalizeRunning = false
                if result.0 {
                    self.finalizeStatus = "OK: finalize"
                    if openOnSuccess {
                        if FileManager.default.fileExists(atPath: masterBundlePath) {
                            self.revealAndOpenFile(masterBundlePath)
                        }
                    } 
                } else {
                    let msg = result.1 ?? "finalize"
                    self.finalizeStatus = "ERROR: finalize: \(msg)"
                }
            }
        }
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
        print("[DEBUG runTool] Starting stepName=\(stepName) scriptPath=\(scriptPath)")
        guard !toolRunning else {
            print("[DEBUG runTool] ABORT: toolRunning=true")
            return
        }
        guard let runDir = runRootPath(for: entry) else {
            print("[DEBUG runTool] ABORT: runRootPath returned nil for entry id=\(entry.id)")
            toolStatus = "Export failed: \(stepName)"
            return
        }
        print("[DEBUG runTool] runDir=\(runDir)")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: runDir, isDirectory: &isDir), isDir.boolValue else {
            print("[DEBUG runTool] ABORT: runDir does not exist or is not directory")
            toolStatus = "Export failed: \(stepName)"
            return
        }
        guard let repoRoot = resolvedRepoRoot() else {
            print("[DEBUG runTool] ABORT: resolvedRepoRoot returned nil")
            toolStatus = "Export failed: \(stepName)"
            return
        }
        print("[DEBUG runTool] repoRoot=\(repoRoot)")

        toolRunning = true
        toolRunID = entry.id
        toolStatus = "Running \(stepName)…"

        DispatchQueue.global(qos: .userInitiated).async {
            let venvBin = (repoRoot as NSString).appendingPathComponent(".venv/bin")
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = venvBin + ":" + (env["PATH"] ?? "")

            print("[DEBUG runTool] Calling script with args: bash \(scriptPath) \(runDir)")
            let result = self.runToolProcess(
                executable: "/usr/bin/env",
                arguments: ["bash", scriptPath, runDir],
                cwd: repoRoot,
                env: env
            )
            print("[DEBUG runTool] Script exit code: \(result.0)")
            print("[DEBUG runTool] Script output: \(result.1)")

            if result.0 != 0 {
                print("[DEBUG runTool] ABORT: script failed with exit code \(result.0)")
                DispatchQueue.main.async {
                    self.toolRunning = false
                    self.toolTask = nil
                    self.toolRunID = nil
                    self.toolStatus = "Export failed: \(stepName)"
                }
                return
            }

            let folderPath = (runDir as NSString).appendingPathComponent(expectedFolder)
            print("[DEBUG runTool] Checking for PDF in: \(folderPath)")
            let pdfFound = (try? FileManager.default.contentsOfDirectory(atPath: folderPath))?.contains(where: { $0.lowercased().hasSuffix(".pdf") }) ?? false
            print("[DEBUG runTool] pdfFound: \(pdfFound)")
            if !pdfFound {
                print("[DEBUG runTool] ABORT: no PDF found in folder")
                DispatchQueue.main.async {
                    self.toolRunning = false
                    self.toolTask = nil
                    self.toolRunID = nil
                    self.toolStatus = "No output produced"
                }
                return
            }

            DispatchQueue.main.async {
                self.toolStatus = "Rebuilding final outputs…"
            }
            DispatchQueue.main.async {
                self.toolRunning = false
                self.toolTask = nil
                self.toolRunID = nil
                self.toolStatus = "OK \(stepName)"
            }

            if stepName == "Tool 4" {
                let baseURL = URL(fileURLWithPath: runDir)
                let langCode = entry.lang.lowercased() == "en" ? "EN" : "RO"
                let ensureResult = self.ensureFinalArtifacts(runDir: baseURL, lang: langCode, repoRoot: repoRoot, env: env)
                DispatchQueue.main.async {
                    if ensureResult.0 {
                        self.toolStatus = "OK \(stepName)"
                    } else {
                        let msg = ensureResult.1 ?? "finalize"
                        self.toolStatus = "ERROR: finalize: \(msg)"
                    }
                }
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
        guard let baseRunDir = runRootPath(for: entry) else {
            exportStatusText = "ERROR: Build master"
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: baseRunDir, isDirectory: &isDir), isDir.boolValue else {
            exportStatusText = "ERROR: Build master"
            return
        }
        guard let repoRoot = resolvedRepoRoot() else {
            exportStatusText = "ERROR: Build master"
            return
        }
        let resolved = URL(fileURLWithPath: baseRunDir)
        let langCode = entry.lang.lowercased() == "en" ? "EN" : "RO"

        exportIsRunning = true
        runExportRunID = entry.id
        runExportCancelRequested = false
        exportStatusText = "Building master PDF…"
        exportStartTime = Date()
        exportBuildEndTime = nil
        exportPackageEndTime = nil
        exportVerifyEndTime = nil
        exportMetricsText = nil
        exportSizesText = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let venvBin = (repoRoot as NSString).appendingPathComponent(".venv/bin")
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = venvBin + ":/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

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

            let ensure = self.ensureFinalArtifacts(runDir: resolved, lang: langCode, repoRoot: repoRoot, env: env)
            if !ensure.0 {
                DispatchQueue.main.async {
                    self.finalizeRunID = entry.id
                    self.finalizeStatus = "ERROR: finalize: \(ensure.1 ?? "finalize")"
                }
                finish("ERROR: finalize")
                return
            }

            let masterBundlePdf = resolved.appendingPathComponent("final/MASTER_BUNDLE.pdf").path
            let finalZip = resolved.appendingPathComponent("final/client_safe_bundle.zip").path

            DispatchQueue.main.async {
                self.exportVerifyEndTime = Date()
                let masterSize = self.fileSizeBytes(masterBundlePdf)
                let zipSize = self.fileSizeBytes(finalZip)
                self.exportSizesText = "MASTER_BUNDLE.pdf \(self.formatKB(masterSize)) · bundle \(self.formatKB(zipSize))"
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
        case "NOT AUDITABLE":
            return "Not auditable: deliverable is a No package."
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

    private func resolveAstraRunDir(from output: String) -> String? {
        if let marker = parseAstraRunDirMarker(from: output) {
            return marker
        }
        return nil
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

    private func latestRunEntry(forLang lang: String?) -> RunEntry? {
        let runs = campaignScopedRunHistory().sorted { $0.timestamp > $1.timestamp }
        guard let lang, lang.lowercased() != "both" else { return runs.first }
        return runs.first { $0.lang.lowercased() == lang.lowercased() }
    }

    private func canonicalRunDir(forLangSelection selection: String?) -> String? {
        let preferredLang = (selection == "both") ? nil : selection
        guard let entry = latestRunEntry(forLang: preferredLang),
              let runDir = runRootPath(for: entry) else { return nil }
        let trimmed = runDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return trimmed
    }

    private func finalRootPath(forLangSelection selection: String?) -> String? {
        guard let runDir = canonicalRunDir(forLangSelection: selection) else { return nil }
        let finalDir = (runDir as NSString).appendingPathComponent("final")
        return FileManager.default.fileExists(atPath: finalDir) ? finalDir : nil
    }

    private func finalZipPath(forLangSelection selection: String?) -> String? {
        guard let runDir = canonicalRunDir(forLangSelection: selection) else { return nil }
        let zipPath = (runDir as NSString).appendingPathComponent("final/client_safe_bundle.zip")
        return FileManager.default.fileExists(atPath: zipPath) ? zipPath : nil
    }

    private func finalMasterPath(forLangSelection selection: String?) -> String? {
        guard let runDir = canonicalRunDir(forLangSelection: selection) else { return nil }
        let path = (runDir as NSString).appendingPathComponent("final/master.pdf")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func finalBundlePath(forLangSelection selection: String?) -> String? {
        guard let runDir = canonicalRunDir(forLangSelection: selection) else { return nil }
        let path = (runDir as NSString).appendingPathComponent("final/MASTER_BUNDLE.pdf")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func shipRootPath() -> String? {
        return finalRootPath(forLangSelection: lang)
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

    private func openFinalMaster() {
        guard let path = finalMasterPath(forLangSelection: lang) else {
            alert(title: "master.pdf missing", message: "master.pdf missing. Run Deliver (PDF) first.")
            return
        }
        revealAndOpenFile(path)
    }

    private func openFinalBundle() {
        guard let path = finalBundlePath(forLangSelection: lang) else {
            alert(title: "MASTER_BUNDLE missing", message: "MASTER_BUNDLE missing. Run Deliver (PDF) first.")
            return
        }
        revealAndOpenFile(path)
    }

    private func openFinalZip() {
        guard let path = finalZipPath(forLangSelection: lang) else {
            alert(title: "Bundle missing", message: "Bundle missing. Run Deliver (PDF) first.")
            return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openShipRoot() {
        guard let finalPath = shipRootPath() else {
            alert(title: "Delivery root missing", message: "Delivery root missing. Run Deliver (PDF) first.")
            return
        }
        guard FileManager.default.fileExists(atPath: finalPath) else {
            alert(title: "Delivery root missing", message: "Delivery root missing. Run Deliver (PDF) first.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: finalPath))
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
        if let runDir = lastRunDir,
           FileManager.default.fileExists(atPath: runDir) {
            return runDir
        }
        return nil
    }

    private func scopeRunLogPath() -> String? {
        let fm = FileManager.default
        if let logPath = lastRunLogPath, fm.fileExists(atPath: logPath) {
            return logPath
        }
        if let runDir = lastRunDir {
            let fallback = (runDir as NSString).appendingPathComponent("logs/run.log")
            return fm.fileExists(atPath: fallback) ? fallback : nil
        }
        return nil
    }

    private func openOutputFolder() {
        guard let path = outputFolderPath() else {
            alert(title: "No run folder", message: "No run folder available for the last run.")
            return
        }
        openFolder(path)
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
        if status == "NOT AUDITABLE" {
            return "NOT AUDITABLE deliverable: no audit checks were performed."
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
        case "NOT AUDITABLE": return "Last run: not auditable"
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
        return finalZipPath(forLangSelection: lang) != nil ? 1 : 0
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
