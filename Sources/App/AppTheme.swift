import SwiftUI
import UIKit

/// 预设配色主题。raw value 持久化在 UserDefaults，**一旦发布不可更改**（只可新增）。
///
/// 配色改用 Apple 的语义系统色（`UIColor.systemXxx`）而非手调 RGB。
/// 理由：手调 RGB 在真机反馈里"对比度过高、显丑"，而系统色是 Apple 按人眼
/// 与深浅色分别调校过的，并且会自动跟随"增强对比度"等辅助功能设置，
/// 这正是 GitHub iOS 等成熟 App 的做法。`teal` 例外：它是品牌色，
/// 直接沿用资源目录里的 AccentColor，不做硬编码。
///
/// 注意 case 名与显示名不必一一对应：case 名是持久化标识（不可改），
/// 显示名面向用户，按实际观感命名（violet 显示为 Purple 等）。
enum AppTheme: String, CaseIterable, Identifiable {
    case teal
    case blue
    case indigo
    case violet
    case emerald
    case amber
    case rose
    case mint

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .violet: return "Purple"
        case .emerald: return "Green"
        case .amber: return "Orange"
        case .rose: return "Pink"
        case .mint: return "Mint"
        }
    }

    /// 强调色；teal 返回 nil，由调用方回退到 Color.accentColor（资源里的品牌色）。
    func accent(_ scheme: ColorScheme) -> Color? {
        switch self {
        case .teal: return nil
        case .blue: return Color(uiColor: .systemBlue)
        case .indigo: return Color(uiColor: .systemIndigo)
        case .violet: return Color(uiColor: .systemPurple)
        case .emerald: return Color(uiColor: .systemGreen)
        case .amber: return Color(uiColor: .systemOrange)
        case .rose: return Color(uiColor: .systemPink)
        case .mint: return Color(uiColor: .systemMint)
        }
    }
}

/// 主题解析集中一处：未设置 / 非法 raw value 一律回退默认 teal。
enum ThemePreferences {
    static let storageKey = "appTheme"
    static let fallback = AppTheme.teal

    static func resolve(_ raw: String?) -> AppTheme {
        guard let raw, let theme = AppTheme(rawValue: raw) else { return fallback }
        return theme
    }

    static func stored(_ defaults: UserDefaults = .standard) -> AppTheme {
        resolve(defaults.string(forKey: storageKey))
    }

    /// 供 UI 直接取强调色；teal 时回退 Color.accentColor（资源里的品牌色）。
    static func accent(_ theme: AppTheme, scheme: ColorScheme) -> Color {
        theme.accent(scheme) ?? Color.accentColor
    }
}
