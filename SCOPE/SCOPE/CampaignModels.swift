import Foundation

struct CampaignManifest: Codable {
    var campaign: String
    var campaign_fs: String
    var lang: String
    var created_at: String
    var updated_at: String
    var runs: [String]

    static func new(campaign: String, campaign_fs: String, lang: String, now: String) -> CampaignManifest {
        return CampaignManifest(
            campaign: campaign,
            campaign_fs: campaign_fs,
            lang: lang,
            created_at: now,
            updated_at: now,
            runs: []
        )
    }
}

struct CampaignRunInfo: Codable, Hashable {
    let url: String
    let domain: String
    let timestamp: String
    let lang: String
    let campaign: String
}

struct RunEntry: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let url: String
    let lang: String
    let status: String
    let runDir: String
    let deliverablesDir: String
    let reportPdfPath: String?
    let decisionBriefPdfPath: String?
    let logPath: String?

    var canonicalURL: String {
        RunEntry.canonicalizeURL(url)
    }

    static func canonicalizeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        var working = trimmed
        if !working.contains("://") {
            working = "https://" + working
        }
        guard var comps = URLComponents(string: working) else { return trimmed }
        comps.fragment = nil
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
}

struct RunRecord: Identifiable, Hashable {
    let id: String
    let runDir: String
    let deliverablesDir: String
    let logPath: String?

    init(entry: RunEntry) {
        self.id = entry.id
        self.runDir = entry.runDir
        self.deliverablesDir = entry.deliverablesDir
        self.logPath = entry.logPath
    }

    init(id: String, runDir: String, deliverablesDir: String, logPath: String?) {
        self.id = id
        self.runDir = runDir
        self.deliverablesDir = deliverablesDir
        self.logPath = logPath
    }
}

struct CampaignRunItem: Identifiable, Hashable {
    let id: String
    let runURL: URL
    let run: CampaignRunInfo

    var timestamp: String { run.timestamp }
    var domain: String { run.domain }
    var lang: String { run.lang }
    var campaign: String { run.campaign }
}

struct CampaignSummary: Identifiable, Hashable {
    var id: String { campaignURL.path }
    let name: String
    let langs: [String]
    let campaignURL: URL
    let runCount: Int
    let runs: [CampaignRunItem]
    let lastUpdated: Date
}
