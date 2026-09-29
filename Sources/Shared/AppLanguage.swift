import Foundation

/// 应用内显示语言。默认英文（符合“安装后默认英语”，即使设备是中文）。
/// `system` = 跟随系统。三者都可用 @AppStorage 持久化（RawValue 为 String）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"
    case system = "system"

    var id: String { rawValue }
}

/// 纯函数：把语言选择解析成 (注入 SwiftUI 的 Locale?, 供小组件字符串表/快照使用的语言码)。
/// 与 SwiftUI / UserDefaults 解耦，集中在便于单测。
enum LanguagePreferences {
    /// 受支持、用于小组件字符串表与快照的语言码。
    static let supportedCodes = ["en", "zh-Hans"]

    static func resolve(_ selection: AppLanguage,
                        systemPreferred: [String] = Locale.preferredLanguages)
        -> (locale: Locale?, code: String) {
        switch selection {
        case .english:
            return (Locale(identifier: "en"), "en")
        case .chinese:
            return (Locale(identifier: "zh-Hans"), "zh-Hans")
        case .system:
            // locale=nil 让 SwiftUI 沿用系统当前语言；code 取系统偏好里首个受支持语言。
            return (nil, firstSupported(in: systemPreferred) ?? "en")
        }
    }

    /// 从系统偏好语言里挑第一个受支持的码（en-US→en，zh-Hans-CN/zh_CN→zh-Hans）。
    static func firstSupported(in preferred: [String]) -> String? {
        for raw in preferred {
            let code = normalize(raw)
            if supportedCodes.contains(code) { return code }
        }
        return nil
    }

    /// 归一化：zh_* / zh-Hant → zh-Hans（产品面向简体中文用户，中文优先简中）；en-* → en。
    static func normalize(_ raw: String) -> String {
        let lower = raw.replacingOccurrences(of: "_", with: "-").lowercased()
        if lower.hasPrefix("zh") { return "zh-Hans" }
        if lower.hasPrefix("en") { return "en" }
        return lower
    }
}
