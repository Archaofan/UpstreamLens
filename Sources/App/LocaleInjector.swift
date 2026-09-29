import SwiftUI
import Foundation

/// 应用内本地化解析。
///
/// 旧实现把选择写进 `UserDefaults` 的 `AppleLanguages`，这会**永久污染**
/// `Locale.preferredLanguages`：一旦写过一次，之后"跟随系统"读到的永远是被自己
/// 改过的值，用户再也回不到真实系统语言（真机反馈：中文系统下跟随系统仍是英文）。
/// 这里彻底放弃该 hack：语言只由本枚举解析，SwiftUI 走 `.environment(\.locale)`，
/// 非 SwiftUI 的 `String(localized:)` 路径走 `AppLocalization.string(_:)`。
enum AppLocalization {
    static let storageKey = "appLanguage"
    /// 旧版本写入的污染键，启动时清除一次。
    static let legacyOverrideKey = "AppleLanguages"
    /// 一次性迁移标记，保证上面那次清除只做一次。
    ///
    /// 为什么需要标记：`AppleLanguages` 是 UserDefaults 的特殊键，
    /// `object(forKey:)` 在 App 域没有值时仍会落回系统全局域（永远非 nil），
    /// 所以"有没有被写过"根本无法用 object(forKey:) 判断。
    /// 又因为 iOS 允许在系统设置里为单个 App 指定语言（同样写进这个键），
    /// 无脑每次启动都 removeObject 会擅自抹掉用户自己的设置，故只做一次。
    static let migrationFlagKey = "didClearLegacyAppleLanguages"

    private static var bundleCache: [String: Bundle] = [:]

    static func selection(_ defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .english
    }

    /// 生效语言码。`.system` 时用设备偏好里首个受支持语言。
    static func resolvedCode(_ defaults: UserDefaults = .standard) -> String {
        let chosen = selection(defaults)
        if chosen == .system {
            return LanguagePreferences.firstSupported(in: Locale.preferredLanguages) ?? "en"
        }
        return chosen.rawValue
    }

    static func resolvedLocale(_ defaults: UserDefaults = .standard) -> Locale {
        Locale(identifier: resolvedCode(defaults))
    }

    /// 清掉历史版本写入的 `AppleLanguages`，让系统语言重新可见。只执行一次。
    static func clearLegacyOverride(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: migrationFlagKey) else { return }
        defaults.removeObject(forKey: legacyOverrideKey)
        defaults.set(true, forKey: migrationFlagKey)
    }

    /// 取当前语言下的文案。
    /// 英文以 key 本身为文案（String Catalog 的 en 值即 key），因此直接返回 key；
    /// 中文走 `zh-Hans.lproj`，查不到时回落 key。
    static func string(_ key: String, defaults: UserDefaults = .standard) -> String {
        let code = resolvedCode(defaults)
        guard code != "en", let bundle = bundle(for: code) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func bundle(for code: String) -> Bundle? {
        if let cached = bundleCache[code] { return cached }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        bundleCache[code] = bundle
        return bundle
    }
}

extension AppLanguage {
    /// 语言名按 iOS 惯例用**本族名**（English / 简体中文），不随界面语言翻译；
    /// 只有"跟随系统"是描述性文案，需要本地化。
    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        case .system: return AppLocalization.string("Follow System")
        }
    }
}

/// 在根视图注入当前语言。SwiftUI `Text` 走 `.environment(\.locale)` 即时切换、无需重启。
struct LocaleInjector: ViewModifier {
    @AppStorage(AppLocalization.storageKey) private var appLanguage: AppLanguage = .english

    func body(content: Content) -> some View {
        content
            .environment(\.locale, AppLocalization.resolvedLocale())
            .onAppear { AppLocalization.clearLegacyOverride() }
    }
}

extension View {
    func injectLocale() -> some View { modifier(LocaleInjector()) }
}
