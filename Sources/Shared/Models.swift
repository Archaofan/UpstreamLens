import Foundation

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case release = "Release"
    case tag = "Tag"
    case path = "路径"
    var id: String { rawValue }
}

struct WatchSource: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: SourceKind = .release
    var repository = ""
    var path = ""
    var branch = ""
    var displayName = ""
    var purpose = ""
    var installedVersion = ""
    var keywords = ""
    var rationale = ""
    var isPaused = false
    /// 通知开关；nil 视为开启（总开关独立于来源级开关）。
    var notifyEnabled: Bool?
    var baselineIdentifier: String?
    var baselineContent: String?
    var etag: String?
    var lastCheckedAt: Date?
    var lastError: String?
    // 缓存自 GitHub 仓库元数据，只用于展示与预填，可随时为 nil。
    var repoDescription: String?
    var defaultBranch: String?
    var topics: [String]?

    var title: String { displayName.isEmpty ? repository : displayName }

    /// 供 RelevanceEngine 使用的合并文本（用途 + 理由 + topics）。
    var contextText: String { [purpose, rationale, (topics ?? []).joined(separator: " ")].joined(separator: " ") }
}

enum Relevance: String, Codable {
    case important = "值得关注"
    case routine = "一般更新"
    case uncertain = "影响不确定"
}

enum FindingStatus: String, Codable, CaseIterable {
    case unread = "未读"
    case viewed = "已查看"
    case handled = "已处理"
}

struct Finding: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceID: UUID
    var upstreamID: String
    var title: String
    var body: String
    var url: String
    var foundAt: Date
    var relevance: Relevance
    var reason: String
    var status: FindingStatus = .unread
    var oldContent: String?
    var newContent: String?
    // 必须保持可选：合成 Codable 对非可选字段不接受缺失 key，否则旧备份解码直接失败。
    var isPrerelease: Bool? = false

    var showsPrereleaseBadge: Bool { isPrerelease == true }

    var isUnreadRelevant: Bool { status == .unread && relevance != .routine }
}

struct LocalData: Codable {
    // schemaVersion 缺省视为 1（旧备份）；新字段全部可选，旧数据无需迁移即可读。
    var schemaVersion: Int? = 2
    var sources: [WatchSource] = []
    var findings: [Finding] = []
    var lastSuccessfulCheck: Date?
    /// 已处理记录保留天数；nil 或 0 表示永久保留。
    var retentionDays: Int?

    /// 已处理记录保留天数；nil 表示用户从未选择（视为永久保留，避免升级后静默删数据），0 也是永久保留。
    var effectiveRetentionDays: Int {
        retentionDays ?? 0
    }

    func pruned(now: Date) -> LocalData {
        let days = effectiveRetentionDays
        guard days > 0 else { return self }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var copy = self
        copy.findings = findings.filter { !($0.status == .handled && $0.foundAt < cutoff) }
        return copy
    }

    /// 记录总量上限：超过时优先丢弃最旧的已处理，其次已查看，最后未读，防止 JSON 无限膨胀。
    static let maxFindings = 1000

    func capped() -> LocalData {
        guard findings.count > Self.maxFindings else { return self }
        var remaining = findings
        for status in [FindingStatus.handled, .viewed, .unread] {
            guard remaining.count > Self.maxFindings else { break }
            let excess = remaining.count - Self.maxFindings
            let drop = Set(remaining
                .filter { $0.status == status }
                .sorted { $0.foundAt < $1.foundAt }
                .prefix(excess)
                .map(\.id))
            remaining.removeAll { drop.contains($0.id) }
        }
        var copy = self
        copy.findings = remaining
        return copy
    }
}

struct WidgetSnapshot: Codable {
    var pendingCount: Int
    var headline: String?
    var lastSuccessfulCheck: Date?
    var generatedAt: Date
    static let empty = WidgetSnapshot(pendingCount: 0, headline: nil, lastSuccessfulCheck: nil, generatedAt: .now)
}
