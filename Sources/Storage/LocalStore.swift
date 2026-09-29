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
    static var fileURL: URL {
        folder.appendingPathComponent("UpstreamLens/data.json")
    }
    static var backupURL: URL {
        folder.appendingPathComponent("UpstreamLens/data.json.bak")
    }
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// 常规读取：主文件损坏时抛错，由 loadWithRecovery 决定是否回退备份。
    static func load() throws -> LocalData {
        try load(from: fileURL)
    }

    static func load(from url: URL) throws -> LocalData {
        guard FileManager.default.fileExists(atPath: url.path) else { return LocalData() }
        return try JSONDecoder().decode(LocalData.self, from: Data(contentsOf: url))
    }

    /// 稳健读取（量产要求）：主文件损坏时回退上一份备份，避免一次写坏就丢全部数据。
    /// 返回恢复提示；主备都不可用时抛错，调用方进入受保护模式。
    static func loadWithRecovery(from url: URL = LocalStore.fileURL,
                                 backup: URL = LocalStore.backupURL) throws -> (data: LocalData, notice: String?) {
        do {
            return (try load(from: url), nil)
        } catch {
            guard FileManager.default.fileExists(atPath: backup.path),
                  let recovered = try? load(from: backup) else {
                throw error
            }
            return (recovered, "主数据文件损坏，已从上一份备份恢复（\(error.localizedDescription)）。")
        }
    }

    static func save(_ value: LocalData) throws {
        try save(value, to: fileURL)
    }

    static func save(_ value: LocalData, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // 轮换：写入前把当前主文件复制为 <name>.bak；新写入是原子的，失败时 .bak 仍是上一份好数据。
        let backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bak")
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
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
    /// 运行时解析的 App Group：免费 Apple ID 侧载重签会给组名加团队前缀，
    /// 固定字符串在真机上拿不到容器（见 AppGroupResolver）。
    static var groupID: String { AppGroupResolver.activeGroupID }
    static let fileName = "widget-snapshot.json"

    static func write(from data: LocalData) throws {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw StorageError.appGroupUnavailable
        }
        let pending = data.findings.filter(\.isUnreadRelevant)
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
