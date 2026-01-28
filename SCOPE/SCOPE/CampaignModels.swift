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
}
