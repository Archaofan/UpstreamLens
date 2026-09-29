import SwiftUI

/// 预设图标：显示项目所有者的 GitHub 头像，离线或加载失败时回退 SF Symbol。
/// 头像加载与磁盘缓存统一走 `RepoAvatarImage` / `AvatarCache`（兼容旧 preset-icons 目录）。
struct PresetIconView: View {
    let preset: SourcePreset

    var body: some View {
        RepoAvatarImage(repository: preset.repository,
                        symbol: preset.symbol,
                        size: 30,
                        cornerRadius: 9)
    }
}
