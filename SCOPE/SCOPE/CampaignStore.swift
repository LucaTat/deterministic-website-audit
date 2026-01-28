import Foundation
import Combine

struct Campaign: Identifiable, Hashable {
    let id: String
    let name: String
    let campaignURL: URL
}

final class CampaignStore: ObservableObject {
    var repoRoot: String
    private let fm = FileManager.default
    private let selectedCampaignKey = "scope.selectedCampaignID"
    private let runHistoryKey = "astraRunHistory"

    @Published var selectedCampaignID: String? {
        didSet {
            UserDefaults.standard.set(selectedCampaignID, forKey: selectedCampaignKey)
        }
    }

    init(repoRoot: String) {
        self.repoRoot = repoRoot
        self.selectedCampaignID = UserDefaults.standard.string(forKey: selectedCampaignKey)
    }

    func ensureDirectory(_ path: String) {
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    func campaignFolderName(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Campaign" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let cleaned = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let collapsed = cleaned.replacingOccurrences(of: "--", with: "-")
        return collapsed.prefix(80).description
    }

    func campaignsRoot(exportRoot: String) -> URL {
        URL(fileURLWithPath: exportRoot).appendingPathComponent("campaigns")
    }

    private func exportRootPath() -> String? {
        let trimmed = repoRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).appendingPathComponent("deliverables")
    }

    func listCampaignsForPicker(exportRoot: String) -> [Campaign] {
        let root = campaignsRoot(exportRoot: exportRoot)
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return items
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            .map { url in
                Campaign(id: url.path, name: url.lastPathComponent, campaignURL: url)
            }
    }

    func ensureDefaultCampaign() -> Campaign {
        let name = "Default"
        let safe = campaignFolderName(for: name)
        if let exportRoot = exportRootPath() {
            let url = campaignsRoot(exportRoot: exportRoot).appendingPathComponent(safe)
            ensureDirectory(url.path)
            let campaign = Campaign(id: url.path, name: name, campaignURL: url)
            if selectedCampaignID == nil {
                selectedCampaignID = campaign.id
            }
            return campaign
        }
        let fallbackURL = URL(fileURLWithPath: repoRoot).appendingPathComponent("deliverables").appendingPathComponent("campaigns").appendingPathComponent(safe)
        let campaign = Campaign(id: fallbackURL.path, name: name, campaignURL: fallbackURL)
        if selectedCampaignID == nil {
            selectedCampaignID = campaign.id
        }
        return campaign
    }

    var selectedCampaign: Campaign? {
        guard let exportRoot = exportRootPath() else { return nil }
        let campaigns = listCampaignsForPicker(exportRoot: exportRoot)
        if let id = selectedCampaignID, let match = campaigns.first(where: { $0.id == id }) {
            return match
        }
        return nil
    }

    func createCampaign(name: String) -> Campaign? {
        guard let exportRoot = exportRootPath() else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let safe = campaignFolderName(for: trimmed)
        let url = campaignsRoot(exportRoot: exportRoot).appendingPathComponent(safe)
        ensureDirectory(url.path)
        let campaign = Campaign(id: url.path, name: trimmed, campaignURL: url)
        selectedCampaignID = campaign.id
        return campaign
    }

    func campaignLangURL(campaign: String, lang: String, exportRoot: String) -> URL {
        let safe = campaignFolderName(for: campaign)
        return campaignsRoot(exportRoot: exportRoot).appendingPathComponent(safe)
    }

    func loadOrCreateManifest(
        campaign: String,
        lang: String,
        exportRoot: String,
        isoNow: () -> String
    ) -> (manifest: CampaignManifest, manifestURL: URL) {
        let safe = campaignFolderName(for: campaign)
        let campaignURL = campaignsRoot(exportRoot: exportRoot).appendingPathComponent(safe)
        ensureDirectory(campaignURL.path)
        let manifestURL = campaignURL.appendingPathComponent("manifest.json")

        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode(CampaignManifest.self, from: data) {
            return (decoded, manifestURL)
        }

        let now = isoNow()
        let m = CampaignManifest.new(campaign: campaign, campaign_fs: safe, lang: lang, now: now)
        writeManifestAtomic(m, to: manifestURL)
        return (m, manifestURL)
    }

    func writeManifestAtomic(_ manifest: CampaignManifest, to url: URL) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".manifest.tmp.\(UUID().uuidString)")
        try? data.write(to: tmp, options: [.atomic])
        try? fm.removeItem(at: url)
        try? fm.moveItem(at: tmp, to: url)
    }

    func runFolderURL(
        campaign: String,
        lang: String,
        domain: String,
        timestamp: String,
        exportRoot: String
    ) -> URL {
        let safeCampaign = campaignFolderName(for: campaign)
        let safeDomain = domain.lowercased().replacingOccurrences(of: "/", with: "-")
        let runName = "\(timestamp)_\(safeDomain)_\(lang)"
        return campaignsRoot(exportRoot: exportRoot)
            .appendingPathComponent(safeCampaign)
            .appendingPathComponent("runs")
            .appendingPathComponent(runName)
    }

    func appendRun(
        campaign: String,
        lang: String,
        runFolderName: String,
        exportRoot: String,
        isoNow: () -> String
    ) {
        let (manifest, manifestURL) = loadOrCreateManifest(campaign: campaign, lang: lang, exportRoot: exportRoot, isoNow: isoNow)
        var m = manifest
        if !m.runs.contains(runFolderName) {
            m.runs.append(runFolderName)
        }
        m.updated_at = isoNow()
        writeManifestAtomic(m, to: manifestURL)
    }

    func listCampaigns(exportRoot: String) -> [CampaignSummary] {
        let root = campaignsRoot(exportRoot: exportRoot)
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }

        var out: [CampaignSummary] = []
        for c in items where c.hasDirectoryPath {
            let runs = listRuns(campaignURL: c)
            let langs = Array(Set(runs.map { $0.run.lang })).sorted()
            let lastUpdated = mostRecentRunDate(campaignURL: c) ?? (try? c.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let runCount = runs.count
            out.append(CampaignSummary(name: c.lastPathComponent, langs: langs, campaignURL: c, runCount: runCount, runs: runs, lastUpdated: lastUpdated))
        }
        return out.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    private func listRuns(campaignURL: URL) -> [CampaignRunItem] {
        var out: [CampaignRunItem] = []
        let runsRoot = campaignURL.appendingPathComponent("runs")
        guard let runDirs = try? fm.contentsOfDirectory(at: runsRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return out
        }
        for runURL in runDirs where runURL.hasDirectoryPath {
            let name = runURL.lastPathComponent
            let parts = name.split(separator: "_").map(String.init)
            let timestamp = parts.first ?? ""
            let lang = parts.last ?? ""
            let domain = parts.count >= 2 ? parts[1] : ""
            let info = CampaignRunInfo(
                url: "",
                domain: domain,
                timestamp: timestamp,
                lang: lang,
                campaign: campaignURL.lastPathComponent
            )
            out.append(CampaignRunItem(id: runURL.path, runURL: runURL, run: info))
        }
        return out.sorted { $0.run.timestamp > $1.run.timestamp }
    }

    func mostRecentRunURL(campaignURL: URL) -> URL? {
        let runs = listRuns(campaignURL: campaignURL)
        return runs.first?.runURL
    }

    private func mostRecentRunDate(campaignURL: URL) -> Date? {
        let runsRoot = campaignURL.appendingPathComponent("runs")
        let runDirs = (try? fm.contentsOfDirectory(at: runsRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?.filter { $0.hasDirectoryPath } ?? []
        var latest: Date? = nil
        for runURL in runDirs {
            let date = (try? runURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            if let date {
                if latest == nil || date > latest! {
                    latest = date
                }
            }
        }
        return latest
    }

    func deleteCampaignSafely(campaignURL: URL, exportRoot: String) -> Bool {
        let root = campaignsRoot(exportRoot: exportRoot).standardizedFileURL
        let target = campaignURL.standardizedFileURL
        let rootComponents = root.pathComponents
        let targetComponents = target.pathComponents
        guard targetComponents.starts(with: rootComponents) else { return false }
        do {
            try fm.removeItem(at: target)
            return true
        } catch {
            return false
        }
    }

    func deleteCampaignFolder(_ campaignURL: URL) {
        try? fm.removeItem(at: campaignURL)
    }

    func deleteRunFolder(_ runURL: URL) {
        try? fm.removeItem(at: runURL)
    }

    private func runRootURL(campaignId: String, runId: String, exportRoot: String) -> URL {
        campaignsRoot(exportRoot: exportRoot)
            .appendingPathComponent(campaignId)
            .appendingPathComponent("runs")
            .appendingPathComponent(runId)
    }

    private func legacyCampaignId() -> String {
        campaignFolderName(for: "Legacy")
    }

    func migrateLegacyRunsIfNeeded(astraRootPath: String, exportRoot: String) -> [RunEntry] {
        let campaignsRootURL = campaignsRoot(exportRoot: exportRoot).standardizedFileURL
        let history = loadRunHistory()
        guard !history.isEmpty else { return history }

        var updated: [RunEntry] = []
        updated.reserveCapacity(history.count)

        for entry in history {
            let runDirPath = entry.runDir
            if runDirPath.isEmpty {
                updated.append(entry)
                continue
            }
            let runDirURL = URL(fileURLWithPath: runDirPath).standardizedFileURL
            let runComponents = runDirURL.pathComponents
            if runComponents.starts(with: campaignsRootURL.pathComponents) {
                updated.append(entry)
                continue
            }
            if !runDirPath.hasPrefix(astraRootPath) {
                updated.append(entry)
                continue
            }

            let campaignId = inferCampaignId(from: entry, exportRoot: exportRoot) ?? legacyCampaignId()
            let runId = runIdForEntry(entry)
            let runRoot = runRootURL(campaignId: campaignId, runId: runId, exportRoot: exportRoot)
            let astraDest = runRoot.appendingPathComponent("astra")

            if !fm.fileExists(atPath: runRoot.deletingLastPathComponent().path) {
                ensureDirectory(runRoot.deletingLastPathComponent().path)
            }
            if !fm.fileExists(atPath: runRoot.path) {
                ensureDirectory(runRoot.path)
            }

            if !fm.fileExists(atPath: astraDest.path) {
                do {
                    try fm.moveItem(at: runDirURL, to: astraDest)
                } catch {
                    if !fm.fileExists(atPath: astraDest.path) {
                        try? fm.copyItem(at: runDirURL, to: astraDest)
                    }
                }
            }

            let newRunDir = astraDest.path
            let newDeliverables = runRoot.path
            let newLogPath = (fm.fileExists(atPath: astraDest.appendingPathComponent("scope_run.log").path))
                ? astraDest.appendingPathComponent("scope_run.log").path
                : entry.logPath
            let newReportPath = astraDest.appendingPathComponent("deliverables").appendingPathComponent("report.pdf").path
            let reportPath = fm.fileExists(atPath: newReportPath) ? newReportPath : entry.reportPdfPath

            let migrated = RunEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                url: entry.url,
                lang: entry.lang,
                status: entry.status,
                runDir: newRunDir,
                deliverablesDir: newDeliverables,
                reportPdfPath: reportPath,
                decisionBriefPdfPath: entry.decisionBriefPdfPath,
                logPath: newLogPath
            )
            updated.append(migrated)
        }

        saveRunHistory(updated)
        return updated
    }

    private func runIdForEntry(_ entry: RunEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: entry.timestamp)
        let host = URL(string: entry.url)?.host?.lowercased() ?? "run"
        let safeHost = host.replacingOccurrences(of: "/", with: "-")
        return "\(stamp)_\(safeHost)_\(entry.lang)"
    }

    private func inferCampaignId(from entry: RunEntry, exportRoot: String) -> String? {
        let root = campaignsRoot(exportRoot: exportRoot).standardizedFileURL
        let deliverables = URL(fileURLWithPath: entry.deliverablesDir).standardizedFileURL
        let rootComponents = root.pathComponents
        let deliverablesComponents = deliverables.pathComponents
        guard deliverablesComponents.starts(with: rootComponents) else { return nil }
        let idx = rootComponents.count
        guard deliverablesComponents.count > idx else { return nil }
        return deliverablesComponents[idx]
    }

    func deleteCampaign(_ campaign: Campaign, alsoDeleteAstra: Bool) throws {
        guard let exportRoot = exportRootPath() else {
            throw NSError(domain: "SCOPE.Delete", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export root not available."])
        }
        let deleted = deleteCampaignSafely(campaignURL: campaign.campaignURL, exportRoot: exportRoot)
        if !deleted {
            throw NSError(domain: "SCOPE.Delete", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to delete campaign folder."])
        }
        let history = loadRunHistory()
        let campaignPath = campaign.campaignURL.standardizedFileURL.path
        let campaignsRootURL = campaignsRoot(exportRoot: exportRoot).standardizedFileURL
        let rootComponents = campaignsRootURL.pathComponents
        var filtered: [RunEntry] = []
        for entry in history {
            let deliverables = entry.deliverablesDir
            let runDir = entry.runDir
            let logPath = entry.logPath ?? ""
            let isCampaignRun = deliverables.hasPrefix(campaignPath) || runDir.hasPrefix(campaignPath) || logPath.hasPrefix(campaignPath)
            if isCampaignRun {
                if alsoDeleteAstra, !runDir.isEmpty, fm.fileExists(atPath: runDir) {
                    let runURL = URL(fileURLWithPath: runDir).standardizedFileURL
                    if runURL.pathComponents.starts(with: rootComponents) {
                        try? fm.removeItem(at: runURL)
                    }
                }
                continue
            }
            filtered.append(entry)
        }
        saveRunHistory(filtered)
    }

    func deleteRun(_ run: RunRecord, alsoDeleteAstra: Bool) throws {
        guard let exportRoot = exportRootPath() else {
            throw NSError(domain: "SCOPE.Delete", code: 3, userInfo: [NSLocalizedDescriptionKey: "Export root not available."])
        }
        let campaignsRootURL = campaignsRoot(exportRoot: exportRoot).standardizedFileURL
        if !run.deliverablesDir.isEmpty {
            let deliverablesURL = URL(fileURLWithPath: run.deliverablesDir).standardizedFileURL
            let rootComponents = campaignsRootURL.pathComponents
            let targetComponents = deliverablesURL.pathComponents
            if !targetComponents.starts(with: rootComponents) {
                throw NSError(domain: "SCOPE.Delete", code: 4, userInfo: [NSLocalizedDescriptionKey: "Refusing to delete outside campaigns root."])
            }
            if fm.fileExists(atPath: deliverablesURL.path) {
                try fm.removeItem(at: deliverablesURL)
            }
        }
        if let logPath = run.logPath, !logPath.isEmpty {
            let logURL = URL(fileURLWithPath: logPath)
            if fm.fileExists(atPath: logURL.path) {
                try? fm.removeItem(at: logURL)
            }
        }
        if alsoDeleteAstra, !run.runDir.isEmpty, fm.fileExists(atPath: run.runDir) {
            try? fm.removeItem(atPath: run.runDir)
        }
        let filtered = loadRunHistory().filter { entry in
            if entry.id == run.id { return false }
            if !run.deliverablesDir.isEmpty, entry.deliverablesDir == run.deliverablesDir { return false }
            if !run.runDir.isEmpty, entry.runDir == run.runDir { return false }
            return true
        }
        saveRunHistory(filtered)
    }

    func loadRunHistory() -> [RunEntry] {
        guard let data = UserDefaults.standard.data(forKey: runHistoryKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([RunEntry].self, from: data) {
            return decoded.sorted { $0.timestamp > $1.timestamp }
        }
        return []
    }

    func saveRunHistory(_ entries: [RunEntry]) {
        let trimmed = Array(entries.prefix(200))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(trimmed) {
            UserDefaults.standard.set(data, forKey: runHistoryKey)
        }
    }
}
