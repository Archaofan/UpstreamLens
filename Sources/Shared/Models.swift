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
    var isPrerelease: Bool = false

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

    var effectiveRetentionDays: Int {
        guard let retentionDays, retentionDays > 0 else { return 90 }
        return retentionDays
    }

    func pruned(now: Date) -> LocalData {
        let cutoff = now.addingTimeInterval(-Double(effectiveRetentionDays) * 86_400)
        var copy = self
        copy.findings = findings.filter { !($0.status == .handled && $0.foundAt < cutoff) }
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
