import XCTest
@testable import UpstreamLens

/// 真机背景：AI 生成的导入 JSON 把"使用版本"写成
/// `0.20.6 (2026.8.27, upstream 4094ab61)`，整体解析因点号过多（5 段）直接失败，
/// 于是所有版本比较都退化成"无法判断"，用户看到的就是那条没用的提示。
final class FreeTextVersionTests: XCTestCase {
    // MARK: 提取

    func testExtractsVersionFromFreeText() {
        XCTAssertEqual(VersionCompare.extractVersion(from: "0.20.6 (2026.8.27, upstream 4094ab61)"), "0.20.6")
        XCTAssertEqual(VersionCompare.extractVersion(from: "0.20.6 (2026.8.27)"), "0.20.6")
        XCTAssertEqual(VersionCompare.extractVersion(from: "v1.2.3"), "v1.2.3")
        XCTAssertEqual(VersionCompare.extractVersion(from: "installed 2.0.0-rc.1 here"), "2.0.0-rc.1")
    }

    func testExtractsProductVersionFromReleaseName() {
        // 该仓库 tag 是日期，产品版本只写在名称里
        XCTAssertEqual(VersionCompare.extractVersion(from: "Hermes Agent v0.21.5 (v2026.9.24)"), "v0.21.5")
    }

    /// 避免把提交 SHA 里的数字片段当成版本号。
    func testDoesNotExtractBareNumberFragments() {
        XCTAssertNil(VersionCompare.extractVersion(from: "sha 4094ab61"))
        XCTAssertNil(VersionCompare.extractVersion(from: "inputs-a"))
        XCTAssertNil(VersionCompare.extractVersion(from: "no version here"))
        XCTAssertNil(VersionCompare.extractVersion(from: ""))
    }

    /// 纯数字大 id 不含小数点也没有 v 前缀，不该被当成版本号。
    func testDoesNotExtractBareReleaseID() {
        XCTAssertNil(VersionCompare.extractVersion(from: "399277019"))
    }

    // MARK: 宽松解析

    func testLenientParseHandlesFreeText() {
        let parsed = VersionCompare.parse("0.20.6 (2026.8.27, upstream 4094ab61)")
        XCTAssertEqual(parsed?.major, 0)
        XCTAssertEqual(parsed?.minor, 20)
        XCTAssertEqual(parsed?.patch, 6)
    }

    func testLenientParseStillHandlesCleanInput() {
        XCTAssertEqual(VersionCompare.parse("v1.2.3")?.minor, 2)
        XCTAssertNil(VersionCompare.parse("nothing to see"))
    }

    func testDescribeUsesExtractedVersion() {
        XCTAssertEqual(VersionCompare.describe("0.20.6 (2026.8.27, upstream 4094ab61)"), "0.20.6")
    }

    // MARK: 编号体系差异

    /// 日期式 tag 与语义版本不是同一套编号，硬比会得出"包含主版本升级"这种误导结论。
    func testDateTagAndSemanticVersionAreIncomparable() {
        XCTAssertEqual(VersionCompare.gap(installed: "0.20.6", upstream: "v2026.9.24"), .incomparable)
    }

    func testBothDateLikeStayComparable() {
        // 同为日期式编号 → 可比。major 相同，因此比的是 minor：8 → 9，差 1。
        XCTAssertEqual(VersionCompare.gap(installed: "2026.8.27", upstream: "v2026.9.24"),
                       .behind(steps: 1, majorBump: false))
    }

    func testBothSemanticStayComparable() {
        // major 相同，比 minor：20 → 21，差 1。
        XCTAssertEqual(VersionCompare.gap(installed: "0.20.6", upstream: "v0.21.5"),
                       .behind(steps: 1, majorBump: false))
    }

    // MARK: 候选挑选

    func testComparableHintPrefersTagWhenTagIsComparable() {
        XCTAssertEqual(VersionCompare.comparableHint(installed: "1.2.0", tag: "v1.3.0", name: "Release 9.9.9"),
                       "v1.3.0", "tag 本身可比时行为必须与改动前完全一致")
    }

    /// 真机场景：tag 不可比时退回名称里的产品版本，得到真正有用的判断。
    func testComparableHintFallsBackToReleaseName() {
        let hint = VersionCompare.comparableHint(installed: "0.20.6 (2026.8.27, upstream 4094ab61)",
                                                 tag: "v2026.9.24",
                                                 name: "Hermes Agent v0.21.5 (v2026.9.24)")
        XCTAssertEqual(hint, "v0.21.5")
        XCTAssertEqual(VersionCompare.gap(installed: "0.20.6 (2026.8.27, upstream 4094ab61)",
                                          upstream: hint!), .behind(steps: 1, majorBump: false))
    }

    func testComparableHintWithoutTagUsesName() {
        XCTAssertEqual(VersionCompare.comparableHint(installed: "1.0", tag: nil, name: "v2.0"), "v2.0")
        XCTAssertNil(VersionCompare.comparableHint(installed: "1.0", tag: nil, name: nil))
    }

    func testComparableHintWithoutInstalledVersionKeepsTag() {
        XCTAssertEqual(VersionCompare.comparableHint(installed: "", tag: "v2026.9.24", name: "v0.21.5"),
                       "v2026.9.24")
    }

    // MARK: 端到端

    /// 走到真正的判定逻辑上：必须给出可核查的具体版本，而不是"无法判断"。
    func testAssessmentGivesActionableReasonForDateTaggedRepo() {
        var source = WatchSource(repository: "NousResearch/hermes-agent")
        source.installedVersion = "0.20.6 (2026.8.27, upstream 4094ab61)"
        // 基线必须出现在本次拉取窗口里，否则会走"基线重建"分支（那是另一条已测路径）。
        let baseline = UpstreamChange(identifier: "377790585",
                                      title: "Hermes Agent v0.20.6 (v2026.8.27)",
                                      body: "", url: "u", publishedAt: nil, content: nil,
                                      versionHint: "v2026.8.27")
        source.baselineIdentifier = baseline.identifier
        let release = UpstreamChange(identifier: "395553114",
                                     title: "Hermes Agent v0.21.5 (v2026.9.24)",
                                     body: "", url: "u", publishedAt: nil, content: nil,
                                     versionHint: "v2026.9.24")

        let findings = ChangeDetector.apply([release, baseline], to: &source, existing: [], now: .now)

        XCTAssertEqual(findings.count, 1)
        guard let finding = findings.first else { return XCTFail("应产出一条记录") }
        let reason = finding.reason
        XCTAssertFalse(reason.contains("尚不能仅凭上游标识判断"),
                       "版本可比之后不该再退化成无效提示，实际：\(reason)")
        XCTAssertTrue(reason.contains("0.21.5"), "应给出上游产品版本，实际：\(reason)")
        XCTAssertTrue(reason.contains("0.20.6"), "应给出干净的使用版本，实际：\(reason)")
    }
}
