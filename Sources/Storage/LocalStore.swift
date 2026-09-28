import Foundation
import WidgetKit

enum StorageError: LocalizedError {
    case appGroupUnavailable
    case localDataUnavailable
    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: return "共享容器不可用；请在设备上验证侧载签名后的 App Group 权限。"
        case .localDataUnavailable: return "本地数据无法读取，请先导入有效备份。"
        }
    }
}

enum LocalStore {
    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("UpstreamLens/data.json")
    }

    static func load() throws -> LocalData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LocalData() }
        return try JSONDecoder().decode(LocalData.self, from: Data(contentsOf: fileURL))
    }

    static func save(_ value: LocalData) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }

    static func export(_ value: LocalData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    static func importData(_ bytes: Data) throws -> LocalData {
        try JSONDecoder().decode(LocalData.self, from: bytes)
    }
}

enum WidgetSnapshotWriter {
    static let groupID = "group.com.upstreamlens.ios"
    static let fileName = "widget-snapshot.json"

    static func write(from data: LocalData) throws {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw StorageError.appGroupUnavailable
        }
        let pending = data.findings.filter { $0.status == .unread && $0.relevance != .routine }
        let top = pending.sorted {
            if $0.relevance != $1.relevance { return $0.relevance == .important }
            return $0.foundAt > $1.foundAt
        }.first
        let snapshot = WidgetSnapshot(pendingCount: pending.count, headline: top?.title,
                                      lastSuccessfulCheck: data.lastSuccessfulCheck, generatedAt: .now)
        try JSONEncoder().encode(snapshot).write(to: container.appendingPathComponent(fileName), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WidgetSnapshot? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID),
              let bytes = try? Data(contentsOf: container.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: bytes)
    }
}
