import XCTest
@testable import UpstreamLens

final class RefreshPolicyTests: XCTestCase {
    func testDefaultsWhenUnset() {
        let d = UserDefaults(suiteName: "RefreshPolicyTests.Defaults")!
        d.removePersistentDomain(forName: "RefreshPolicyTests.Defaults")
        XCTAssertTrue(RefreshPolicy.checkOnOpen(d), "未设置默认开")
        XCTAssertTrue(RefreshPolicy.backgroundEnabled(d), "未设置默认开")
        XCTAssertEqual(RefreshPolicy.backgroundMinutes(d), 30, "未设置默认 30")
    }

    func testExplicitOff() {
        let d = UserDefaults(suiteName: "RefreshPolicyTests.Off")!
        d.removePersistentDomain(forName: "RefreshPolicyTests.Off")
        d.set(false, forKey: RefreshPolicy.checkOnOpenKey)
        d.set(false, forKey: RefreshPolicy.backgroundEnabledKey)
        XCTAssertFalse(RefreshPolicy.checkOnOpen(d))
        XCTAssertFalse(RefreshPolicy.backgroundEnabled(d))
    }

    func testValidIntervals() {
        let d = UserDefaults(suiteName: "RefreshPolicyTests.Intervals")!
        d.removePersistentDomain(forName: "RefreshPolicyTests.Intervals")
        for m in RefreshPolicy.intervalOptions {
            d.set(m, forKey: RefreshPolicy.backgroundMinutesKey)
            XCTAssertEqual(RefreshPolicy.backgroundMinutes(d), m)
        }
    }

    func testInvalidIntervalFallsBackToDefault() {
        let d = UserDefaults(suiteName: "RefreshPolicyTests.Invalid")!
        d.removePersistentDomain(forName: "RefreshPolicyTests.Invalid")
        d.set(7, forKey: RefreshPolicy.backgroundMinutesKey)
        XCTAssertEqual(RefreshPolicy.backgroundMinutes(d), 30, "非法值回退 30")
    }
}
