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
        return campaignsRoot(exportRoot: exportRoot).appendingPathComponent(safe).appendingPathComponent(lang)
    }

    func loadOrCreateManifest(
        campaign: String,
        lang: String,
        exportRoot: String,
        isoNow: () -> String
    ) -> (manifest: CampaignManifest, manifestURL: URL) {
        let safe = campaignFolderName(for: campaign)
        let langURL = campaignsRoot(exportRoot: exportRoot).appendingPathComponent(safe).appendingPathComponent(lang)
        ensureDirectory(langURL.path)
        let manifestURL = langURL.appendingPathComponent("manifest.json")

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
        let runName = "\(timestamp)_\(safeDomain)"
        return campaignsRoot(exportRoot: exportRoot)
            .appendingPathComponent(safeCampaign)
            .appendingPathComponent(lang)
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
            let langs = (try? fm.contentsOfDirectory(at: c, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
                .filter { $0.hasDirectoryPath }
                .map { $0.lastPathComponent }
                .sorted() ?? []
            let runs = listRuns(campaignURL: c)
            let lastUpdated = mostRecentRunDate(campaignURL: c) ?? (try? c.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let runCount = runs.count
            out.append(CampaignSummary(name: c.lastPathComponent, langs: langs, campaignURL: c, runCount: runCount, runs: runs, lastUpdated: lastUpdated))
        }
        return out.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    private func listRuns(campaignURL: URL) -> [CampaignRunItem] {
        var out: [CampaignRunItem] = []
        let langs = (try? fm.contentsOfDirectory(at: campaignURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.filter { $0.hasDirectoryPath } ?? []
        for langURL in langs {
            let lang = langURL.lastPathComponent
            guard let runDirs = try? fm.contentsOfDirectory(at: langURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for runURL in runDirs where runURL.hasDirectoryPath {
                let name = runURL.lastPathComponent
                let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
                let timestamp = parts.first ?? ""
                let domain = parts.count > 1 ? parts[1] : ""
                let info = CampaignRunInfo(
                    url: "",
                    domain: domain,
                    timestamp: timestamp,
                    lang: lang,
                    campaign: campaignURL.lastPathComponent
                )
                out.append(CampaignRunItem(id: runURL.path, runURL: runURL, run: info))
            }
        }
        return out.sorted { $0.run.timestamp > $1.run.timestamp }
    }

    func mostRecentRunURL(campaignURL: URL) -> URL? {
        let runs = listRuns(campaignURL: campaignURL)
        return runs.first?.runURL
    }

    private func mostRecentRunDate(campaignURL: URL) -> Date? {
        let langs = (try? fm.contentsOfDirectory(at: campaignURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.filter { $0.hasDirectoryPath } ?? []
        var latest: Date? = nil
        for langURL in langs {
            let runDirs = (try? fm.contentsOfDirectory(at: langURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]))?.filter { $0.hasDirectoryPath } ?? []
            for runURL in runDirs {
                let date = (try? runURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                if let date {
                    if latest == nil || date > latest! {
                        latest = date
                    }
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
}
