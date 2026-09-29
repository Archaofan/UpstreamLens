import SwiftUI
import UIKit

/// 备用 App 图标。
///
/// `rawValue` 持久化在 UserDefaults，一旦发布不可更改，只可新增。
/// 图标本体是随 App 打包的 PNG（`Assets/AppIcons`），
/// 并在 Info.plist 的 `CFBundleAlternateIcons` 中声明。
///
/// 注意：本类型位于 App 目标而非 Shared：预览需要读取 App 包内的真实图标文件，
/// 而 Shared 看不到 App 目标。真正调用系统的切换逻辑见 `AppIconSwitcher`。
enum AppIconOption: String, CaseIterable, Identifiable {
    case primary
    case violet
    case emerald
    case amber

    var id: String { rawValue }

    /// `setAlternateIconName` 接受的名称；primary 传 nil 表示恢复主图标。
    var alternateName: String? {
        switch self {
        case .primary: return nil
        case .violet: return "AppIconViolet"
        case .emerald: return "AppIconEmerald"
        case .amber: return "AppIconAmber"
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .primary: return "Default"
        case .violet: return "Violet"
        case .emerald: return "Emerald"
        case .amber: return "Amber"
        }
    }

    /// 包内真实图标的候选基名。
    /// 主图标由资源目录生成，实际落盘为 AppIcon60x60（iPhone）与 AppIcon76x76（iPad）。
    private var artworkBaseNames: [String] {
        switch self {
        case .primary: return ["AppIcon60x60", "AppIcon76x76"]
        default: return [alternateName ?? ""]
        }
    }

    /// 预览图：**直接读取 App 包里真正在用的那个图标文件**。
    ///
    /// 旧实现用主题色块当预览，用户反馈"默认那项显示的颜色跟实际图标不一样"——
    /// 因为它显示的是 AccentColor，而 App 图标是另一张设计稿。
    /// 读真实文件可以从根上消除这种不一致，且零额外体积。
    /// Xcode 会把 PNG 重编码为 Apple 的 CgBI 格式，UIImage 能正常解码。
    var artwork: UIImage? {
        for base in artworkBaseNames where !base.isEmpty {
            for suffix in ["@3x", "@2x"] {
                if let path = Bundle.main.path(forResource: base + suffix, ofType: "png"),
                   let image = UIImage(contentsOfFile: path) {
                    return image
                }
            }
        }
        return nil
    }

    /// 真实图标读不到时的兜底色块（正常构建里不该走到这里）。
    func previewColor(_ scheme: ColorScheme) -> Color {
        switch self {
        case .primary: return Color.accentColor
        case .violet: return AppTheme.violet.accent(scheme) ?? Color.accentColor
        case .emerald: return AppTheme.emerald.accent(scheme) ?? Color.accentColor
        case .amber: return AppTheme.amber.accent(scheme) ?? Color.accentColor
        }
    }
}

enum AppIconPreferences {
    static let storageKey = "appIcon"
    static let fallback = AppIconOption.primary

    static func resolve(_ raw: String?) -> AppIconOption {
        AppIconOption(rawValue: raw ?? "") ?? fallback
    }

    static func stored(_ defaults: UserDefaults = .standard) -> AppIconOption {
        resolve(defaults.string(forKey: storageKey))
    }
}
