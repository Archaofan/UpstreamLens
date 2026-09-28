import XCTest
@testable import UpstreamLens

final class VersionCompareTests: XCTestCase {
    func testParseTolerantForms() {
        XCTAssertEqual(ParsedVersion.parse("v1.2.3"), ParsedVersion(major: 1, minor: 2, patch: 3, prerelease: []))
        XCTAssertEqual(ParsedVersion.parse("1.2"), ParsedVersion(major: 1, minor: 2, patch: 0, prerelease: []))
        XCTAssertEqual(ParsedVersion.parse("V10.0.1"), ParsedVersion(major: 10, minor: 0, patch: 1, prerelease: []))
        XCTAssertEqual(ParsedVersion.parse("2026.9.24"), ParsedVersion(major: 2026, minor: 9, patch: 24, prerelease: []))
        XCTAssertEqual(ParsedVersion.parse("1.2.3-alpha.1"),
                       ParsedVersion(major: 1, minor: 2, patch: 3, prerelease: ["alpha", "1"]))
        XCTAssertEqual(ParsedVersion.parse("2.0.0-rc.2+build.9"),
                       ParsedVersion(major: 2, minor: 0, patch: 0, prerelease: ["rc", "2"]))
        XCTAssertNil(ParsedVersion.parse("abc"))
        XCTAssertNil(ParsedVersion.parse("1.2.3.4"))
        XCTAssertNil(ParsedVersion.parse("1..3"))
        XCTAssertNil(ParsedVersion.parse("1.2.3-"))
    }

    func testNumericCompareNotLexicographic() {
        XCTAssertTrue(ParsedVersion.parse("1.10.0")! > ParsedVersion.parse("1.9.9")!)
        XCTAssertTrue(ParsedVersion.parse("0.1.10")! > ParsedVersion.parse("0.1.9")!)
    }

    func testPrereleaseOrdering() {
        XCTAssertTrue(ParsedVersion.parse("1.0.0-alpha")! < ParsedVersion.parse("1.0.0")!)
        XCTAssertTrue(ParsedVersion.parse("1.0.0-alpha")! < ParsedVersion.parse("1.0.0-alpha.1")!)
        XCTAssertTrue(ParsedVersion.parse("1.0.0-alpha")! < ParsedVersion.parse("1.0.0-beta")!)
        XCTAssertTrue(ParsedVersion.parse("1.0.0-alpha.2")! > ParsedVersion.parse("1.0.0-alpha.1")!)
        XCTAssertTrue(ParsedVersion.parse("1.0.0-rc.1")! > ParsedVersion.parse("1.0.0-beta.9")!)
    }

    func testGapBehindWithMajorBump() {
        XCTAssertEqual(VersionCompare.gap(installed: "1.2.0", upstream: "v2.0.0"),
                       .behind(steps: 1, majorBump: true))
        XCTAssertEqual(VersionCompare.gap(installed: "v0.1.6", upstream: "v0.1.14"),
                       .behind(steps: 8, majorBump: false))
        XCTAssertEqual(VersionCompare.gap(installed: "2026.8.1", upstream: "v2026.9.24"),
                       .behind(steps: 1, majorBump: false))
    }

    func testGapOtherDirections() {
        XCTAssertEqual(VersionCompare.gap(installed: "v1.2.0", upstream: "v1.2.0"), .upToDate)
        XCTAssertEqual(VersionCompare.gap(installed: "2.0.0", upstream: "1.9.0"), .ahead)
        XCTAssertEqual(VersionCompare.gap(installed: "abc", upstream: "v1.0.0"), .incomparable)
        XCTAssertEqual(VersionCompare.gap(installed: "v1.0.0", upstream: ""), .incomparable)
    }

    func testNumericIdentifierIsNotAVersion() {
        // release 的数字 id 或纯数字 sha 不得被当成版本号参与比较。
        XCTAssertEqual(VersionCompare.gap(installed: "v1.0.0", upstream: "123456789"), .incomparable)
    }
}
