import SwiftUI
import UIKit

/// 仓库头像地址。复用 GitHub 的 CDN 约定 URL，**不走 API、不占限流额度**，
/// 离线或失败时由调用方回退 SF Symbol。
enum RepoAvatar {
    /// 由所有者名构造头像 URL。
    static func url(forOwner owner: String) -> URL? {
        guard !owner.isEmpty else { return nil }
        // 含空白的 owner 说明 repository 字段异常，直接放弃而不是构造出怪异 URL。
        if owner.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return nil }
        return URL(string: "https://github.com/\(owner).png?size=120")
    }

    /// 由 `owner/repo` 取所有者头像。
    static func url(for repository: String) -> URL? {
        guard let owner = owner(of: repository) else { return nil }
        return url(forOwner: owner)
    }

    /// 从 `owner/repo` 取出所有者；非法或空返回 nil。
    static func owner(of repository: String) -> String? {
        let trimmed = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 必须用 omittingEmptySubsequences: false，否则 split 会吞掉前导斜杠产生的空片段，
        // 使 "/repo" 被误判为合法 owner（旧实现即此缺陷）。
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let owner = parts.first, !owner.isEmpty else { return nil }
        let text = String(owner)
        // 含空白的 owner 说明 repository 字段异常，直接放弃而不是构造出怪异 URL。
        if text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { return nil }
        return text
    }

    /// 无头像时的 SF Symbol 兜底，与来源类型对应。
    static func fallbackSymbol(for kind: SourceKind) -> String {
        switch kind {
        case .path: return "doc.text.fill"
        case .tag: return "tag.fill"
        case .release: return "shippingbox.fill"
        }
    }
}

/// 头像磁盘缓存。泛化自原 PresetIconCache：新目录 `avatars`，
/// 仍可读旧目录 `preset-icons`，避免用户已有缓存全部失效。
enum AvatarCache {
    /// 缓存文件名由 URL 派生（非字母数字替换为下划线，保证跨启动稳定）。
    static func cachedFileURL(for url: URL, in directory: URL? = nil) -> URL {
        let allowed = CharacterSet.alphanumerics
        let name = url.absoluteString.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return (directory ?? folder).appendingPathComponent(name + ".png")
    }

    /// 某个所有者的头像缓存文件地址。
    static func cachedFileURL(forOwner owner: String, in directory: URL? = nil) -> URL? {
        RepoAvatar.url(forOwner: owner).map { cachedFileURL(for: $0, in: directory) }
    }

    static func image(url: URL?, in directory: URL? = nil) async -> UIImage? {
        guard let url else { return nil }
        let diskURL = cachedFileURL(for: url, in: directory)
        if let data = try? Data(contentsOf: diskURL), let cached = UIImage(data: data) {
            return cached
        }
        // 仅生产路径回读旧目录；测试传入目录时不跨目录查找。
        if directory == nil,
           let legacy = legacyCachedFileURL(for: url),
           let data = try? Data(contentsOf: legacy),
           let cached = UIImage(data: data) {
            return cached
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let downloaded = UIImage(data: data) else { return nil }
        try? FileManager.default.createDirectory(at: diskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: diskURL, options: .atomic)
        return downloaded
    }

    static func totalBytes(in directory: URL? = nil) -> Int {
        totalBytes(of: directory ?? folder)
    }

    /// 清除缓存，返回释放的字节数。
    /// - keepExistingSources: true 时只删除当前没有对应来源的头像，已有来源的头像保留。
    @discardableResult
    static func clear(keepExistingSources: Bool, currentOwners: Set<String>, in directory: URL? = nil) -> Int {
        let target = directory ?? folder
        let keep: Set<URL> = keepExistingSources
            ? Set(currentOwners.compactMap { cachedFileURL(forOwner: $0, in: target) })
            : []
        var freed = 0
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: target, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        for file in files where !keep.contains(file) {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if (try? FileManager.default.removeItem(at: file)) != nil { freed += size }
        }
        return freed
    }

    // MARK: 目录

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatars", isDirectory: true)
    }

    private static var legacyFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("preset-icons", isDirectory: true)
    }

    private static func legacyCachedFileURL(for url: URL) -> URL? {
        let allowed = CharacterSet.alphanumerics
        let name = url.absoluteString.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return legacyFolder.appendingPathComponent(name + ".png")
    }

    private static func totalBytes(of directory: URL) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

/// 仓库头像视图：优先所有者头像，取不到回退 SF Symbol，列表始终整齐。
struct RepoAvatarImage: View {
    let repository: String
    var symbol: String
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 9

    @State private var image: UIImage?

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .task(id: repository) {
                image = await AvatarCache.image(url: RepoAvatar.url(for: repository))
            }
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.45))
                .foregroundStyle(.tint)
        }
    }
}
