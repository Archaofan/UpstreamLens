import Foundation
import SwiftUI

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case release = "Release"
    case tag = "Tag"
    case path = "路径"
    var id: String { rawValue }
    /// 本地化显示名。raw value 已持久化在 data.json，不能改；UI 一律用 displayName。
    var displayName: LocalizedStringKey {
        switch self {
        case .release: return "Release"
        case .tag: return "Tag"
        case .path: return "Path"
        }
    }
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
    /// 用户手动打的标签，用于来源分组与筛选。
    /// 解码宽松处理见下方 extension：旧 data.json 缺该键时解出空数组。
    var tags: [String] = []
    /// 只关注"看起来像版本号"的发布/标签（默认开）。
    /// 上游常把内容寻址快照也做成 release/tag（如 inputs-a…inputs-f），
    /// 这类条目没有版本含义，逐条提醒会刷满列表。
    /// ChangeDetector 有自适应兜底：若过滤后一条不剩就不过滤，来源不会因此沉默。
    var versionLikeOnly: Bool = true
    /// 所属类别 id（见 CategoryCatalog）；nil 视为未归类。
    /// 必须是可选：合成 Codable 对非可选字段不接受缺失 key。
    var category: String?
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

// 注意：必须写在 extension 里。写在 struct 主体内会抑制 Swift 合成的成员初始化器，
// 导致 WatchSource() / WatchSource(repository:) 等既有调用点全部编译失败。
extension WatchSource {
    /// 宽松解码：Swift 合成的 Codable 对「带默认值的非可选属性」仍然要求键存在，
    /// 只有 Optional 才会用 decodeIfPresent。这里全部键改为宽松解码，
    /// 使旧 data.json 与旧备份缺 tags（或任何新增字段）时依然可读。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(SourceKind.self, forKey: .kind) ?? .release
        repository = try c.decodeIfPresent(String.self, forKey: .repository) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        branch = try c.decodeIfPresent(String.self, forKey: .branch) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        installedVersion = try c.decodeIfPresent(String.self, forKey: .installedVersion) ?? ""
        keywords = try c.decodeIfPresent(String.self, forKey: .keywords) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        // 旧数据没有这个键：沿用开启的默认值（并有自适应兜底，不会让来源沉默）。
        versionLikeOnly = try c.decodeIfPresent(Bool.self, forKey: .versionLikeOnly) ?? true
        category = try c.decodeIfPresent(String.self, forKey: .category)
        rationale = try c.decodeIfPresent(String.self, forKey: .rationale) ?? ""
        isPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        notifyEnabled = try c.decodeIfPresent(Bool.self, forKey: .notifyEnabled)
        baselineIdentifier = try c.decodeIfPresent(String.self, forKey: .baselineIdentifier)
        baselineContent = try c.decodeIfPresent(String.self, forKey: .baselineContent)
        etag = try c.decodeIfPresent(String.self, forKey: .etag)
        lastCheckedAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        repoDescription = try c.decodeIfPresent(String.self, forKey: .repoDescription)
        defaultBranch = try c.decodeIfPresent(String.self, forKey: .defaultBranch)
        topics = try c.decodeIfPresent([String].self, forKey: .topics)
    }
}

enum Relevance: String, Codable {
    case important = "值得关注"
    case routine = "一般更新"
    case uncertain = "影响不确定"

    var displayName: LocalizedStringKey {
        switch self {
        case .important: return "Worth Attention"
        case .routine: return "Routine Update"
        case .uncertain: return "Uncertain Impact"
        }
    }
}

enum FindingStatus: String, Codable, CaseIterable {
    case unread = "未读"
    case viewed = "已查看"
    case handled = "已处理"

    var displayName: LocalizedStringKey {
        switch self {
        case .unread: return "Unread"
        case .viewed: return "Viewed"
        case .handled: return "Handled"
        }
    }
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
    /// 来源类别目录（用户可增删改）。
    /// 必须是可选：合成 Codable 对非可选字段不接受缺失 key，旧备份会直接解码失败。
    /// nil 表示从未自定义过，此时用 CategoryCatalog.defaultCategories。
    var categories: [SourceCategory]?
    /// 一次性历史噪音清理标记（见 AppModel.cleanUpLegacyNoiseFindings）。
    /// 可选：旧备份缺该键时视为"尚未清理"，正好触发一次清理。
    var didCleanLegacyNoise: Bool?

    /// 生效的类别列表：用户没配过就用内置默认。
    var effectiveCategories: [SourceCategory] {
        if let categories, !categories.isEmpty { return categories }
        return CategoryCatalog.defaultCategories
    }

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

    /// 删除某个类别后，把仍指向它的来源收归到"其他"，避免出现悬空引用。
    mutating func reassignCategory(_ removedID: String, to fallbackID: String = CategoryCatalog.uncategorizedID) {
        for index in sources.indices where sources[index].category == removedID {
            sources[index].category = fallbackID
        }
    }
}

struct WidgetSnapshot: Codable {
    var pendingCount: Int
    var headline: String?
    /// 顶部待查看项的相关性，供小组件着色；nil 表示无头条或旧快照。
    var headlineRelevance: Relevance?
    var lastSuccessfulCheck: Date?
    var generatedAt: Date
    /// App 当前语言码（en/zh-Hans），供小组件按 App 选择显示；旧快照缺省视为 en。
    var language: String?
    static let empty = WidgetSnapshot(pendingCount: 0, headline: nil, headlineRelevance: nil, lastSuccessfulCheck: nil, generatedAt: .now, language: "en")
}
