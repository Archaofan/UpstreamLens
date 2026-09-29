import Foundation
import Security

/// GitHub 令牌的安全存储抽象。实现可替换（Keychain / 测试用内存），
/// AppModel 只依赖协议，单测不触碰真实 Keychain。
protocol TokenStore {
    func read() -> String?
    func set(_ token: String?) throws
}

enum TokenStoreError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "无法安全保存 GitHub 令牌（Keychain 错误 \(status)）。请在系统设置里确认本 App 的钥匙串访问后重试。"
        }
    }
}

/// Keychain 实现：通用密码项，`afterFirstUnlockThisDeviceOnly`。
/// - ThisDeviceOnly：不随设备备份/iCloud 钥匙串迁移，令牌只留本机。
/// - afterFirstUnlock：后台刷新在锁屏下也能读到令牌（否则后台轮次会退回未登录额度）。
struct KeychainTokenStore: TokenStore {
    static let shared = KeychainTokenStore()

    private let service = "com.upstreamlens.github-token"
    private let account = "github-pat"

    func read() -> String? {
        var query = baseQuery()
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// delete-then-add，幂等；传 nil 或空串即登出（删除）。
    func set(_ token: String?) throws {
        SecItemDelete(baseQuery() as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var attributes = baseQuery()
        attributes[kSecValueData] = Data(token.utf8)
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.saveFailed(status) }
    }

    private func baseQuery() -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword,
         kSecAttrService: service,
         kSecAttrAccount: account]
    }
}
