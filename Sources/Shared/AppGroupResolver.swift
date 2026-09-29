import Foundation

/// 侧载重签后 App Group 的运行时解析。
///
/// 免费 Apple ID 侧载（SideStore/iloader）签发的 profile 中，App Group 会被加上 10 位团队 ID
/// 前缀（如 `ABCDEF1234.group.com.upstreamlens.ios`），与 entitlements 里请求的无前缀 ID 不完全
/// 相等，导致 `containerURL(for:)` 返回 nil——这是“诊断说权限都在、容器却拿不到”的根因。
/// 策略：先试原始 ID；失败则从 embedded.mobileprovision 原始字节提取实际授权的组，挑选本 App
/// 相关的带前缀变体，逐个验证直到拿到容器。App 与 Widget 进程各自读自己 bundle 的 profile，
/// 签名工具给两者授的是同一个组，两端解析结果一致。
enum AppGroupResolver {
    static let requestedGroupID = "group.com.upstreamlens.ios"

    /// 当前进程应使用的 App Group ID（每个进程只解析一次并缓存）。
    static var activeGroupID: String {
        if let cached { return cached }
        let resolved = resolve(requested: requestedGroupID,
                               profileData: profileData(),
                               fileManager: .default)
        cached = resolved
        return resolved
    }
    nonisolated(unsafe) private static var cached: String?

    /// 读取当前 bundle 的 embedded.mobileprovision（重签工具在设备上写入）。
    static func profileData(bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 纯决策：在授权列表中挑选应使用的组。优先原始请求 ID，其次 `<团队ID>.group.…` 变体。
    static func preferredGroupID(requested: String, granted: [String]) -> String {
        if granted.contains(requested) { return requested }
        if let variant = granted.first(where: { $0 != requested && $0.hasSuffix(".\(requested)") }) {
            return variant
        }
        return requested
    }

    /// 完整解析：候选 ID 逐个问 FileManager，真正拿到容器的那个胜出；都拿不到则返回原始 ID，
    /// 让上层错误提示与诊断照常工作。
    static func resolve(requested: String, profileData: Data?, fileManager: FileManager) -> String {
        if fileManager.containerURL(forSecurityApplicationGroupIdentifier: requested) != nil {
            return requested
        }
        let granted = grantedGroups(in: profileData)
        var candidates = [preferredGroupID(requested: requested, granted: granted)]
        candidates.append(contentsOf: granted.filter { !candidates.contains($0) && $0.contains("upstreamlens") })
        for candidate in candidates {
            if fileManager.containerURL(forSecurityApplicationGroupIdentifier: candidate) != nil {
                return candidate
            }
        }
        return requested
    }

    /// 从 profile 原始字节（DER 包裹的 XML 或二进制 plist）提取所有与本 App 相关的 App Group。
    /// 两种形态里字符串都以 UTF-8 连续存放：以 `group.` 为锚，向左扩展组名合法字符即可同时
    /// 覆盖无前缀与 `<团队ID>.group.…`，无需完整解析 CMS 签名。
    static func grantedGroups(in profileData: Data?) -> [String] {
        guard let data = profileData, !data.isEmpty else { return [] }
        let bytes = [UInt8](data)
        let anchor = Array("group.".utf8)
        var results = Set<String>()
        var index = 0
        while index <= bytes.count - anchor.count {
            if bytes[index] == anchor[0], matches(bytes, at: index, anchor) {
                var start = index
                while start > 0, isGroupNameByte(bytes[start - 1]), index - (start - 1) < 96 {
                    start -= 1
                }
                var end = index + anchor.count
                while end < bytes.count, isGroupNameByte(bytes[end]) { end += 1 }
                let name = String(decoding: bytes[start..<end], as: UTF8.self)
                // plist 里还有 group.com.apple 等系统组，只认与本 App 相关的。
                if name.contains("upstreamlens") { results.insert(name) }
                index = end
            } else {
                index += 1
            }
        }
        return results.sorted()
    }

    /// 组名允许的字符：字母、数字、点、连字符。长度标记、引号、尖括号都会终止扩展。
    private static func isGroupNameByte(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x30 && byte <= 0x39) || byte == 0x2E || byte == 0x2D
    }

    private static func matches(_ bytes: [UInt8], at index: Int, _ anchor: [UInt8]) -> Bool {
        guard index + anchor.count <= bytes.count else { return false }
        for offset in anchor.indices where bytes[index + offset] != anchor[offset] { return false }
        return true
    }
}
