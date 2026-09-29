import XCTest
@testable import UpstreamLens

final class BackgroundPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "BackgroundPreferencesTests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        suite = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsWhenUnset() {
        XCTAssertFalse(BackgroundPreferences.isEnabled(suite))
        XCTAssertEqual(BackgroundPreferences.opacity(suite), BackgroundPreferences.defaultOpacity)
        XCTAssertEqual(BackgroundPreferences.brightness(suite), BackgroundPreferences.defaultBrightness)
        XCTAssertEqual(BackgroundPreferences.dimming(suite), BackgroundPreferences.defaultDimming)
    }

    func testOutOfRangeValuesAreClamped() {
        suite.set(2.5, forKey: BackgroundPreferences.opacityKey)
        suite.set(-9.0, forKey: BackgroundPreferences.brightnessKey)
        XCTAssertEqual(BackgroundPreferences.opacity(suite), BackgroundPreferences.opacityRange.upperBound)
        XCTAssertEqual(BackgroundPreferences.brightness(suite), BackgroundPreferences.brightnessRange.lowerBound)
    }

    func testInRangeValuesRoundTrip() {
        suite.set(true, forKey: BackgroundPreferences.enabledKey)
        suite.set(0.6, forKey: BackgroundPreferences.opacityKey)
        suite.set(0.05, forKey: BackgroundPreferences.brightnessKey)
        XCTAssertTrue(BackgroundPreferences.isEnabled(suite))
        XCTAssertEqual(BackgroundPreferences.opacity(suite), 0.6, accuracy: 0.0001)
        XCTAssertEqual(BackgroundPreferences.brightness(suite), 0.05, accuracy: 0.0001)
    }

    /// 透明度下限保证内容可读性，用户不能把背景调到几乎不可读。
    func testOpacityFloorKeepsContentReadable() {
        let floor = BackgroundPreferences.opacityRange.lowerBound
        XCTAssertGreaterThanOrEqual(floor, 0.1)
        XCTAssertEqual(BackgroundPreferences.clamp(0.02, BackgroundPreferences.opacityRange), floor)
    }

    func testClampFunction() {
        XCTAssertEqual(BackgroundPreferences.clamp(5, BackgroundPreferences.opacityRange),
                       BackgroundPreferences.opacityRange.upperBound)
        XCTAssertEqual(BackgroundPreferences.clamp(0.5, BackgroundPreferences.opacityRange), 0.5)
        XCTAssertEqual(BackgroundPreferences.clamp(-5, BackgroundPreferences.brightnessRange),
                       BackgroundPreferences.brightnessRange.lowerBound)
        XCTAssertEqual(BackgroundPreferences.clamp(5, BackgroundPreferences.brightnessRange),
                       BackgroundPreferences.brightnessRange.upperBound)
    }

    /// 亮度必须能双向调整 —— 旧区间 ±0.2 在真机上几乎看不出变化。
    func testBrightnessRangeIsUsableInBothDirections() {
        XCTAssertLessThanOrEqual(BackgroundPreferences.brightnessRange.lowerBound, -0.3)
        XCTAssertGreaterThanOrEqual(BackgroundPreferences.brightnessRange.upperBound, 0.3)
    }

    func testDimmingIsClampedAndDefaultsAreInRange() {
        suite.set(9.0, forKey: BackgroundPreferences.dimmingKey)
        XCTAssertEqual(BackgroundPreferences.dimming(suite), BackgroundPreferences.dimmingRange.upperBound)
        suite.set(-9.0, forKey: BackgroundPreferences.dimmingKey)
        XCTAssertEqual(BackgroundPreferences.dimming(suite), BackgroundPreferences.dimmingRange.lowerBound)

        XCTAssertTrue(BackgroundPreferences.opacityRange.contains(BackgroundPreferences.defaultOpacity))
        XCTAssertTrue(BackgroundPreferences.brightnessRange.contains(BackgroundPreferences.defaultBrightness))
        XCTAssertTrue(BackgroundPreferences.dimmingRange.contains(BackgroundPreferences.defaultDimming))
    }

    /// 非 Double 类型（历史脏数据）必须回退默认值而不是崩溃。
    func testNonNumericValueFallsBackToDefault() {
        suite.set("abc", forKey: BackgroundPreferences.opacityKey)
        XCTAssertEqual(BackgroundPreferences.opacity(suite), BackgroundPreferences.defaultOpacity)
        suite.set("abc", forKey: BackgroundPreferences.dimmingKey)
        XCTAssertEqual(BackgroundPreferences.dimming(suite), BackgroundPreferences.defaultDimming)
    }
}
