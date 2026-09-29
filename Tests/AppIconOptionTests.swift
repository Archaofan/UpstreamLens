import XCTest
@testable import UpstreamLens

final class AppIconOptionTests: XCTestCase {
    func testAlternateNamesMatchBundledPNGs() {
        // 这些名字必须与 Assets/AppIcons 下的文件名以及 Info.plist 的
        // CFBundleAlternateIcons 键一致，否则 setAlternateIconName 会失败。
        let expected: [AppIconOption: String?] = [
            .primary: nil,
            .violet: "AppIconViolet",
            .emerald: "AppIconEmerald",
            .amber: "AppIconAmber",
        ]
        for option in AppIconOption.allCases {
            XCTAssertEqual(option.alternateName, expected[option], "\(option.rawValue) 的图标名不匹配")
        }
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(AppIconOption.allCases.map(\.rawValue),
                       ["primary", "violet", "emerald", "amber"])
    }

    func testResolveFallsBackToPrimary() {
        XCTAssertEqual(AppIconPreferences.resolve(nil), .primary)
        XCTAssertEqual(AppIconPreferences.resolve(""), .primary)
        XCTAssertEqual(AppIconPreferences.resolve("not-a-real-icon"), .primary)
    }

    func testResolveAcceptsKnownValues() {
        XCTAssertEqual(AppIconPreferences.resolve("violet"), .violet)
        XCTAssertEqual(AppIconPreferences.resolve("emerald"), .emerald)
        XCTAssertEqual(AppIconPreferences.resolve("amber"), .amber)
        XCTAssertEqual(AppIconPreferences.resolve("primary"), .primary)
    }

    func testStoredReadsUserDefaults() {
        let suite = "AppIconOptionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppIconPreferences.stored(defaults), .primary)
        defaults.set("amber", forKey: AppIconPreferences.storageKey)
        XCTAssertEqual(AppIconPreferences.stored(defaults), .amber)
        defaults.set("garbage", forKey: AppIconPreferences.storageKey)
        XCTAssertEqual(AppIconPreferences.stored(defaults), .primary)
    }

    func testIDsAreUnique() {
        let ids = AppIconOption.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
