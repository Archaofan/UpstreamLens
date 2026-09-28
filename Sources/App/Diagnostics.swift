import Foundation

/// 诊断纯函数：所有设备端证据都以可复制文本形式给出，供反馈给开发者。
enum Diagnostics {
    /// 在二进制数据中搜索 UTF-8 字节串（用 Foundation 的 memmem 实现）。
    static func contains(_ data: Data, needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        return data.range(of: Data(needle.utf8)) != nil
    }

    /// App Group 容器是否可获得。
    static func appGroupContainerExists(groupID: String, fileManager: FileManager = .default) -> Bool {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    /// 向共享容器写一次、读一次的往返测试。返回 nil 表示通过，否则是错误说明。
    static func appGroupRoundTrip(groupID: String, fileManager: FileManager = .default) -> String? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return "无法获得共享容器 URL（entitlement 未生效）。"
        }
        let probeURL = container.appendingPathComponent("diagnostics-probe.txt")
        do {
            try Data("upstreamlens-probe".utf8).write(to: probeURL, options: .atomic)
            let readBack = try Data(contentsOf: probeURL)
            try? fileManager.removeItem(at: probeURL)
            return readBack == Data("upstreamlens-probe".utf8) ? nil : "写入后读回内容不一致。"
        } catch {
            return "写入或读取失败：\(error.localizedDescription)"
        }
    }

    /// 读取已安装包里的 embedded.mobileprovision（重签后由签名工具写入）。
    static func provisionProfileData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 主可执行文件的原始字节（用于检查 entitlements 是否内嵌）。
    static func executableData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.executableURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
