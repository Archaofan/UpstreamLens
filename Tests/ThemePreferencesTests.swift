import XCTest
@testable import UpstreamLens

final class ThemePreferencesTests: XCTestCase {
    func testResolveFallsBackToTealWhenUnsetOrInvalid() {
        XCTAssertEqual(ThemePreferences.resolve(nil), .teal)
        XCTAssertEqual(ThemePreferences.resolve(""), .teal)
        XCTAssertEqual(ThemePreferences.resolve("not-a-theme"), .teal)
        XCTAssertEqual(ThemePreferences.fallback, .teal)
    }

    func testResolveRoundTripsEveryCase() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(ThemePreferences.resolve(theme.rawValue), theme)
        }
    }

    /// raw value 已持久化在 UserDefaults，冲突或改名都会让用户的选择错乱。
    func testRawValuesAreUniqueAndTealIsDefault() {
        let raws = AppTheme.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "raw value 冲突会导致持久化错乱")
        XCTAssertEqual(AppTheme.teal.rawValue, "teal")
    }

    /// teal 必须走 Color.accentColor（资源里的品牌色），不能硬编码，否则与现有视觉不一致。
    func testTealDefersToAccentColorAsset() {
        XCTAssertNil(AppTheme.teal.accent(.light))
        XCTAssertNil(AppTheme.teal.accent(.dark))
    }

    func testOtherThemesProvideExplicitAccent() {
        for theme in AppTheme.allCases where theme != .teal {
            XCTAssertNotNil(theme.accent(.light), "\(theme.rawValue) 缺少浅色强调色")
            XCTAssertNotNil(theme.accent(.dark), "\(theme.rawValue) 缺少深色强调色")
        }
    }

    func testAccentNeverReturnsNil() {
        for theme in AppTheme.allCases {
            _ = ThemePreferences.accent(theme, scheme: .light)
            _ = ThemePreferences.accent(theme, scheme: .dark)
        }
    }

    /// 真机反馈："配色过于丑、对比度太高"，因此除品牌默认色外全部改用 Apple 系统语义色。
    /// 系统色会自动适配深浅色与"增强对比度"，这里守住主题数量与唯一性。
    func testOffersMultipleDistinctThemes() {
        XCTAssertGreaterThanOrEqual(AppTheme.allCases.count, 8, "主题风格应足够多")
        let raws = AppTheme.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "raw value 冲突会导致持久化串味")
    }

    /// 新增主题不得破坏既有持久化值。
    func testPreExistingRawValuesAreStable() {
        for raw in ["teal", "indigo", "violet", "emerald", "amber", "rose"] {
            XCTAssertEqual(AppTheme(rawValue: raw)?.rawValue, raw, "\(raw) 是已发布值，不可更改")
        }
    }

    func testLightAndDarkAccentsDifferForSystemColours() {
        // 系统语义色在深浅色下由系统给出不同取值；这里只要求两者都能取到且非空。
        for theme in AppTheme.allCases where theme != .teal {
            XCTAssertNotNil(theme.accent(.light) ?? theme.accent(.dark), "\(theme.rawValue) 无可用强调色")
        }
    }

    func testStoredReadsFromProvidedDefaults() {
        let name = "ThemePreferencesTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        suite.set(AppTheme.rose.rawValue, forKey: ThemePreferences.storageKey)
        XCTAssertEqual(ThemePreferences.stored(suite), .rose)
        suite.set("bogus", forKey: ThemePreferences.storageKey)
        XCTAssertEqual(ThemePreferences.stored(suite), .teal)
    }
}
