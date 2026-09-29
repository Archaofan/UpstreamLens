import SwiftUI
import UIKit

/// 预设图标：优先显示项目所有者的 GitHub 头像（磁盘缓存，跨启动复用），
/// 离线或加载失败时回退 SF Symbol，保证列表始终整齐。
struct PresetIconView: View {
    let preset: SourcePreset
    @State private var image: UIImage?

    var body: some View {
        icon
            .frame(width: 30, height: 30)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .task(id: preset.id) { image = await PresetIconCache.image(url: preset.iconURL) }
    }

    @ViewBuilder private var icon: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: preset.symbol)
                .font(.headline)
                .foregroundStyle(.tint)
        }
    }
}

enum PresetIconCache {
    /// 缓存文件名由图标 URL 派生（非字母数字替换为下划线，保证跨启动稳定）。
    static func cachedImageURL(for url: URL) -> URL {
        let allowed = CharacterSet.alphanumerics
        let name = url.absoluteString.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return folder.appendingPathComponent(name + ".png")
    }

    static func image(url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let diskURL = cachedImageURL(for: url)
        if let data = try? Data(contentsOf: diskURL), let cached = UIImage(data: data) {
            return cached
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let downloaded = UIImage(data: data) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: diskURL, options: .atomic)
        return downloaded
    }

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("preset-icons", isDirectory: true)
    }
}
