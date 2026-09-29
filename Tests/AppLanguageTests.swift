import XCTest
@testable import UpstreamLens

final class AppLanguageTests: XCTestCase {
    func testResolveEnglish() {
        let r = LanguagePreferences.resolve(.english)
        XCTAssertEqual(r.code, "en")
        XCTAssertEqual(r.locale?.identifier, "en")
    }

    func testResolveChinese() {
        let r = LanguagePreferences.resolve(.chinese)
        XCTAssertEqual(r.code, "zh-Hans")
        XCTAssertNotNil(r.locale)
        XCTAssertTrue(r.locale!.identifier.hasPrefix("zh"))
    }

    func testResolveSystemEnglishPreferred() {
        let r = LanguagePreferences.resolve(.system, systemPreferred: ["en-US", "zh-Hans-CN"])
        XCTAssertEqual(r.code, "en")
        XCTAssertNil(r.locale, "system 用 nil locale 让 SwiftUI 跟随系统")
    }
    func testResolveSystemChinesePreferred() {
        let r = LanguagePreferences.resolve(.system, systemPreferred: ["zh-Hans-CN", "en"])
        XCTAssertEqual(r.code, "zh-Hans")
        XCTAssertNil(r.locale)
    }

    func testResolveSystemUnsupportedFallsBackToEnglish() {
        let r = LanguagePreferences.resolve(.system, systemPreferred: ["fr-FR", "de-DE"])
        XCTAssertEqual(r.code, "en")
    }

    func testNormalize() {
        XCTAssertEqual(LanguagePreferences.normalize("zh_CN"), "zh-Hans")
        XCTAssertEqual(LanguagePreferences.normalize("zh-Hant-TW"), "zh-Hans")
        XCTAssertEqual(LanguagePreferences.normalize("en-US"), "en")
        XCTAssertEqual(LanguagePreferences.normalize("fr"), "fr")
    }

    func testFirstSupported() {
        XCTAssertEqual(LanguagePreferences.firstSupported(in: ["fr", "en-GB"]), "en")
        XCTAssertEqual(LanguagePreferences.firstSupported(in: ["zh-Hans-CN"]), "zh-Hans")
        XCTAssertNil(LanguagePreferences.firstSupported(in: ["fr", "de"]))
    }

    func testAppLanguageRawValuesStable() {
        // RawValue 用于 @AppStorage 持久化，必须稳定。
        XCTAssertEqual(AppLanguage.english.rawValue, "en")
        XCTAssertEqual(AppLanguage.chinese.rawValue, "zh-Hans")
        XCTAssertEqual(AppLanguage.system.rawValue, "system")
    }

    /// 语言名用本族名，不随界面语言翻译；"跟随系统"才是描述性文案。
    func testLanguageDisplayNamesUseEndonyms() {
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.chinese.displayName, "简体中文",
                       "英文界面下也必须显示简体中文，而不是 Chinese")
    }

    func testEveryLanguageHasANonEmptyDisplayName() {
        for language in AppLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty, "\(language.rawValue) 缺少显示名")
        }
    }
}

final class AppLocalizationTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppLocalizationTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        suiteName = nil
        super.tearDown()
    }

    func testExplicitChoicesResolveToTheirOwnCode() {
        suite.set(AppLanguage.english.rawValue, forKey: AppLocalization.storageKey)
        XCTAssertEqual(AppLocalization.resolvedCode(suite), "en")
        XCTAssertEqual(AppLocalization.resolvedLocale(suite).identifier, "en")

        suite.set(AppLanguage.chinese.rawValue, forKey: AppLocalization.storageKey)
        XCTAssertEqual(AppLocalization.resolvedCode(suite), "zh-Hans")
        XCTAssertTrue(AppLocalization.resolvedLocale(suite).identifier.hasPrefix("zh"))
    }

    func testUnsetOrGarbageSelectionFallsBackToEnglish() {
        XCTAssertEqual(AppLocalization.selection(suite), .english)
        suite.set("klingon", forKey: AppLocalization.storageKey)
        XCTAssertEqual(AppLocalization.selection(suite), .english)
    }

    /// system 必须落到某个受支持语言码，绝不能返回空。
    func testSystemSelectionAlwaysResolvesToASupportedCode() {
        suite.set(AppLanguage.system.rawValue, forKey: AppLocalization.storageKey)
        let code = AppLocalization.resolvedCode(suite)
        XCTAssertTrue(LanguagePreferences.supportedCodes.contains(code), "得到未支持的语言码 \(code)")
    }

    /// 旧版本写入的 AppleLanguages 会永久污染 Locale.preferredLanguages，
    /// 使"跟随系统"再也回不到真实系统语言。清理逻辑是这次修复的核心。
    ///
    /// 注意 `AppleLanguages` 是 UserDefaults 的特殊键：清掉 App 域的值之后
    /// `object(forKey:)` 仍会落回系统全局域（依然非 nil），因此只能查持久域。
    func testClearLegacyOverrideRemovesAppDomainValue() {
        suite.set(["en"], forKey: AppLocalization.legacyOverrideKey)
        AppLocalization.clearLegacyOverride(suite)

        let domain = UserDefaults(suiteName: suiteName)!.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertNil(domain[AppLocalization.legacyOverrideKey], "App 自己的持久域里必须已经清掉")
    }

    /// 只做一次：iOS 允许在系统设置里给单个 App 指定语言（同样写这个键），
    /// 每次启动都清会擅自抹掉用户自己的设置。
    func testClearLegacyOverrideRunsOnlyOnce() {
        XCTAssertFalse(suite.bool(forKey: AppLocalization.migrationFlagKey))
        AppLocalization.clearLegacyOverride(suite)
        XCTAssertTrue(suite.bool(forKey: AppLocalization.migrationFlagKey))

        // 迁移之后再写入的值，第二次调用不许再动它。
        suite.set(["zh-Hans"], forKey: AppLocalization.legacyOverrideKey)
        AppLocalization.clearLegacyOverride(suite)
        let domain = UserDefaults(suiteName: suiteName)!.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertNotNil(domain[AppLocalization.legacyOverrideKey], "迁移已完成，不应再清用户后来设置的值")
    }

    func testClearLegacyOverrideIsIdempotentAndKeepsResolutionWorking() {
        AppLocalization.clearLegacyOverride(suite)
        AppLocalization.clearLegacyOverride(suite)
        suite.set(AppLanguage.system.rawValue, forKey: AppLocalization.storageKey)
        XCTAssertTrue(LanguagePreferences.supportedCodes.contains(AppLocalization.resolvedCode(suite)))
    }

    /// 英文直接返回 key（String Catalog 的 en 值即 key），保证不依赖 en.lproj 是否存在。
    func testEnglishStringLookupReturnsKeyItself() {
        suite.set(AppLanguage.english.rawValue, forKey: AppLocalization.storageKey)
        let key = "Some Untranslated Key"
        XCTAssertEqual(AppLocalization.string(key, defaults: suite), key)
    }

    /// key 不是有效的本地化键时也必须原样返回，绝不返回空串。
    func testUnknownKeyNeverReturnsEmpty() {
        suite.set(AppLanguage.chinese.rawValue, forKey: AppLocalization.storageKey)
        let key = "This Key Surely Does Not Exist Anywhere 12345"
        XCTAssertEqual(AppLocalization.string(key, defaults: suite), key)
    }
}
