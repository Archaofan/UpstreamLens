import XCTest
@testable import UpstreamLens

final class RelevanceEngineTests: XCTestCase {
    private func sourceWith(
        keywords: String = "", purpose: String = "", rationale: String = "",
        installedVersion: String = "", topics: [String]? = nil
    ) -> WatchSource {
        var source = WatchSource(repository: "owner/repo")
        source.keywords = keywords
        source.purpose = purpose
        source.rationale = rationale
        source.installedVersion = installedVersion
        source.topics = topics
        return source
    }

    func testWordBoundaryAvoidsFalsePositive() {
        let source = sourceWith(keywords: "api")
        let result = RelevanceEngine.assess(source: source, text: "Rapid start guide updated")
        XCTAssertNotEqual(result.0, .important)
        XCTAssertFalse(result.1.contains("api"))
    }

    func testWordBoundaryStillMatchesExactWord() {
        let source = sourceWith(keywords: "api")
        let result = RelevanceEngine.assess(source: source, text: "The API now supports pagination")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("api"))
    }

    func testCJKKeywordMatchesBySubstring() {
        let source = sourceWith(keywords: "同步, 备份")
        let result = RelevanceEngine.assess(source: source, text: "本次更新重写了同步逻辑，并修复若干问题。")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("同步"))
    }

    func testMultipleKeywordHitsListed() {
        let source = sourceWith(keywords: "widget, widgetkit, xcodegen")
        let result = RelevanceEngine.assess(source: source, text: "WidgetKit timeline and XcodeGen project were fixed")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("widget"))
    }

    func testBreakingTermTakesPriority() {
        let source = sourceWith(keywords: "config")
        let result = RelevanceEngine.assess(source: source, text: "Removed legacy config files; see migration guide")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("Removed") || result.1.contains("removed"))
    }

    func testChineseBreakingTerm() {
        let source = sourceWith()
        let result = RelevanceEngine.assess(source: source, text: "此版本弃用了旧的导入格式")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("弃用"))
    }

    func testVersionGapMajorIsImportant() {
        let source = sourceWith(installedVersion: "1.2.0")
        let result = RelevanceEngine.assess(source: source, text: "New release", versionHint: "v2.0.0")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("主版本"))
    }

    func testVersionGapMinorIsRoutine() {
        let source = sourceWith(installedVersion: "1.2.0")
        let result = RelevanceEngine.assess(source: source, text: "New release", versionHint: "v1.3.0")
        XCTAssertEqual(result.0, .routine)
    }

    func testPrereleaseUpstreamIsUncertain() {
        let source = sourceWith(installedVersion: "1.9.0")
        let result = RelevanceEngine.assess(source: source, text: "New release", versionHint: "2.0.0-rc.1")
        XCTAssertEqual(result.0, .uncertain)
        XCTAssertTrue(result.1.contains("预发布"))
    }

    func testUpToDateIsRoutine() {
        let source = sourceWith(installedVersion: "v1.2.0")
        let result = RelevanceEngine.assess(source: source, text: "Tag created", versionHint: "v1.2.0")
        XCTAssertEqual(result.0, .routine)
    }

    func testNumericUpstreamIDNeverComparesAsVersion() {
        let source = sourceWith(installedVersion: "v1.0.0")
        let result = RelevanceEngine.assess(source: source, text: "New release", versionHint: "123456789")
        XCTAssertEqual(result.0, .uncertain)
    }

    func testPurposeContextMatch() {
        let source = sourceWith(purpose: "远程连接 NAS", rationale: "替代 synology 套件")
        let result = RelevanceEngine.assess(source: source, text: "Synology Drive compatibility improved")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("synology"))
    }

    func testEmptyContextIsUncertainWithGuidance() {
        let result = RelevanceEngine.assess(source: sourceWith(), text: "Anything")
        XCTAssertEqual(result.0, .uncertain)
        XCTAssertTrue(result.1.contains("未填写使用情况"))
    }

    func testFallbackRoutine() {
        let source = sourceWith(purpose: "远程连接 NAS")
        let result = RelevanceEngine.assess(source: source, text: "Bump dependencies")
        XCTAssertEqual(result.0, .routine)
    }

    func testTermsParsingSplitsBothCommaStyles() {
        XCTAssertEqual(RelevanceEngine.terms(from: "A，b、c; D\ne"), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(RelevanceEngine.terms(from: "api, a, ok", minASCIILength: 4), ["api", "ok"])
    }
}
