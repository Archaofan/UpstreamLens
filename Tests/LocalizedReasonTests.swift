import XCTest
@testable import UpstreamLens

/// 判断理由是用户最常看到的文字，且会永久写进 Finding，绝不能是硬编码中文。
/// 这些测试同时守住"命名占位符必须被填满"——模板里残留 {name} 就是漏填。
final class LocalizedReasonTests: XCTestCase {
    private func versionedSource(_ installed: String, keywords: String = "") -> WatchSource {
        var source = WatchSource(repository: "acme/tool")
        source.installedVersion = installed
        source.keywords = keywords
        return source
    }

    /// 模板里不允许残留未替换的占位符。
    private func assertNoLeftoverPlaceholders(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let leftovers = ["{term}", "{terms}", "{upstream}", "{installed}", "{steps}", "{count}", "{detail}"]
            .filter { text.contains($0) }
        XCTAssertTrue(leftovers.isEmpty, "理由里残留占位符 \(leftovers)：\(text)", file: file, line: line)
    }

    func testMajorUpgradeReasonIsFullyFilledIn() {
        let source = versionedSource("0.20.6")
        let (relevance, reason) = RelevanceEngine.assess(source: source, text: "release", versionHint: "v2.0.0")
        XCTAssertEqual(relevance, .important)
        assertNoLeftoverPlaceholders(reason)
        XCTAssertTrue(reason.contains("2.0.0"), reason)
        XCTAssertTrue(reason.contains("0.20.6"), reason)
    }

    func testMinorUpgradeReasonIsFullyFilledIn() {
        let source = versionedSource("0.20.6")
        let (relevance, reason) = RelevanceEngine.assess(source: source, text: "release", versionHint: "v0.21.5")
        XCTAssertEqual(relevance, .routine)
        assertNoLeftoverPlaceholders(reason)
        XCTAssertTrue(reason.contains("0.21.5"), reason)
        XCTAssertTrue(reason.contains("0.20.6"), reason)
    }

    func testPrereleaseReasonIsFullyFilledIn() {
        let source = versionedSource("0.20.6")
        let (relevance, reason) = RelevanceEngine.assess(source: source, text: "release", versionHint: "v0.21.0-rc.1")
        XCTAssertEqual(relevance, .uncertain)
        assertNoLeftoverPlaceholders(reason)
    }

    func testKeywordReasonIsFullyFilledIn() {
        let source = versionedSource("", keywords: "config, security")
        let (relevance, reason) = RelevanceEngine.assess(source: source, text: "Config parameter renamed")
        XCTAssertEqual(relevance, .important)
        assertNoLeftoverPlaceholders(reason)
        XCTAssertTrue(reason.lowercased().contains("config"), reason)
    }

    func testBreakingTermReasonIsFullyFilledIn() {
        let source = versionedSource("")
        let (relevance, reason) = RelevanceEngine.assess(source: source, text: "This is a breaking change")
        XCTAssertEqual(relevance, .important)
        assertNoLeftoverPlaceholders(reason)
        XCTAssertTrue(reason.lowercased().contains("breaking change"), reason)
    }

    func testPurposeReasonIsFullyFilledIn() {
        var source = WatchSource(repository: "acme/tool")
        source.purpose = "remote access for my NAS"
        let (_, reason) = RelevanceEngine.assess(source: source, text: "improved remote access handling")
        assertNoLeftoverPlaceholders(reason)
    }

    func testFallbackReasonsAreFullyFilledIn() {
        let source = versionedSource("0.20.6")
        let (_, withVersion) = RelevanceEngine.assess(source: source, text: "unrelated words")
        assertNoLeftoverPlaceholders(withVersion)
        XCTAssertTrue(withVersion.contains("0.20.6"), withVersion)

        let empty = WatchSource(repository: "acme/tool")
        let (_, noContext) = RelevanceEngine.assess(source: empty, text: "unrelated words")
        assertNoLeftoverPlaceholders(noContext)
        XCTAssertFalse(noContext.isEmpty)

        var contextual = WatchSource(repository: "acme/tool")
        contextual.keywords = ""
        contextual.purpose = ""
        let (_, routine) = RelevanceEngine.assess(source: contextual, text: "unrelated words")
        assertNoLeftoverPlaceholders(routine)
    }

    /// 未替换的占位符在英文下就是 key 本身，必须能被填满。
    func testPlaceholderFillingHelperWorks() {
        XCTAssertEqual(L10n.fill("a {x} b {y}", ["x": "1", "y": "2"]), "a 1 b 2")
        XCTAssertEqual(L10n.fill("a {x}", [:]), "a {x}", "缺参数时保留占位符，便于测试发现漏填")
        XCTAssertEqual(L10n.fill("no placeholders", ["x": "1"]), "no placeholders")
    }

    /// 英文模式下理由必须是英文（这里断言不含中日韩汉字）。
    func testReasonIsNotHardcodedChinese() {
        let source = versionedSource("0.20.6")
        let (_, reason) = RelevanceEngine.assess(source: source, text: "release", versionHint: "v0.21.5")
        let hasCJK = reason.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        XCTAssertFalse(hasCJK, "英文环境下理由不该出现中文：\(reason)")
    }
}
