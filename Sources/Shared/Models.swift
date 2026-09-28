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

    var title: String { displayName.isEmpty ? repository : displayName }
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
}

struct LocalData: Codable {
    var sources: [WatchSource] = []
    var findings: [Finding] = []
    var lastSuccessfulCheck: Date?
}

struct WidgetSnapshot: Codable {
    var pendingCount: Int
    var headline: String?
    var lastSuccessfulCheck: Date?
    var generatedAt: Date
    static let empty = WidgetSnapshot(pendingCount: 0, headline: nil, lastSuccessfulCheck: nil, generatedAt: .now)
}
