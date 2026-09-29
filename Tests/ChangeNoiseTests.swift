import XCTest
@testable import UpstreamLens

/// 上游噪音治理：内容寻址快照过滤 + 批量发布合并。
/// 真机背景：NousResearch/hermes-agent 把内容寻址快照做成 release/tag
/// （`inputs-0`…`inputs-f`），一次刷出 16 条 "Pinned inputs X" 无效提醒。
final class ChangeNoiseTests: XCTestCase {
    private func change(_ id: String, _ title: String, hint: String?) -> UpstreamChange {
        UpstreamChange(identifier: id, title: title, body: "", url: "https://example.com/\(id)",
                       publishedAt: nil, content: nil, versionHint: hint)
    }

    // MARK: 版本号识别

    func testLooksLikeVersionAcceptsRealVersions() {
        for tag in ["v2026.9.24", "1.2.3", "0.20.6", "v1.0", "2.0.0-rc.1", "1.2.3+build"] {
            XCTAssertTrue(ChangeDetector.looksLikeVersion(tag), "\(tag) 应被识别为版本号")
        }
    }

    func testLooksLikeVersionRejectsContentAddressedNames() {
        // 真机上刷屏的那批
        for tag in ["inputs-a", "inputs-f", "inputs-0", "inputs-7"] {
            XCTAssertFalse(ChangeDetector.looksLikeVersion(tag), "\(tag) 不是版本号")
        }
        for tag in ["latest", "stable", "nightly", "main"] {
            XCTAssertFalse(ChangeDetector.looksLikeVersion(tag))
        }
    }

    /// release 的数字 id 能被 ParsedVersion 解析，但绝不是版本号。
    func testLooksLikeVersionRejectsHugeNumericIds() {
        XCTAssertFalse(ChangeDetector.looksLikeVersion("399277019"))
        XCTAssertFalse(ChangeDetector.looksLikeVersion("999999999999"))
    }

    // MARK: 过滤

    func testFilterKeepsOnlyVersionLikeEntries() {
        let changes = [
            change("v3", "v3", hint: "v2026.9.24"),
            change("i1", "Pinned inputs a", hint: "inputs-a"),
            change("v2", "v2", hint: "v2026.9.21"),
            change("i2", "Pinned inputs b", hint: "inputs-b"),
        ]
        let kept = ChangeDetector.filtered(changes, versionLikeOnly: true)
        XCTAssertEqual(kept.map(\.identifier), ["v3", "v2"])
    }

    func testFilterDisabledKeepsEverything() {
        let changes = [change("v3", "v3", hint: "v2026.9.24"), change("i1", "inputs a", hint: "inputs-a")]
        XCTAssertEqual(ChangeDetector.filtered(changes, versionLikeOnly: false).count, 2)
    }

    /// 安全阀一：只要有条目没有版本标识（例如 path 模式的提交），就完全不过滤。
    func testFilterIsSkippedWhenAnyEntryHasNoVersionHint() {
        let changes = [
            change("v3", "v3", hint: "v2026.9.24"),
            change("sha", "fix: something", hint: nil),
            change("i1", "inputs a", hint: "inputs-a"),
        ]
        XCTAssertEqual(ChangeDetector.filtered(changes, versionLikeOnly: true).count, 3)
    }

    /// 安全阀二：全被过滤掉时保留全部，绝不让来源彻底沉默。
    func testFilterFallsBackWhenNothingQualifies() {
        let changes = [change("i1", "inputs a", hint: "inputs-a"), change("i2", "inputs b", hint: "inputs-b")]
        let kept = ChangeDetector.filtered(changes, versionLikeOnly: true)
        XCTAssertEqual(kept.count, 2, "全是非版本号时必须兜底保留，否则来源永远不报任何东西")
    }

    func testFilterHandlesEmptyInput() {
        XCTAssertTrue(ChangeDetector.filtered([], versionLikeOnly: true).isEmpty)
    }

    // MARK: 批量合并

    /// 一次发布远多于上限时，只产出一条摘要记录。
    func testBulkReleaseCollapsesIntoOneSummaryFinding() {
        var source = WatchSource(repository: "owner/repo")
        source.baselineIdentifier = "v1"
        let bulk = (2...20).map { change("v\($0)", "v\($0)", hint: "1.0.\($0)") }
        let baseline = change("v1", "v1", hint: "1.0.1")

        let findings = ChangeDetector.apply(bulk + [baseline], to: &source, existing: [], now: .now)

        XCTAssertEqual(findings.count, 1, "19 条新发布必须合并成 1 条，不能刷屏")
        let finding = findings[0]
        XCTAssertTrue(finding.title.contains("19"), "标题应说明数量，实际：\(finding.title)")
        XCTAssertTrue(finding.body.contains("v20"), "摘要应列出条目名")
    }

    /// 未超上限时保持逐条，不做无谓合并。
    func testSmallNumberOfChangesStaysIndividual() {
        var source = WatchSource(repository: "owner/repo")
        source.baselineIdentifier = "v1"
        let changes = [change("v4", "v4", hint: "1.0.4"), change("v3", "v3", hint: "1.0.3"),
                       change("v2", "v2", hint: "1.0.2"), change("v1", "v1", hint: "1.0.1")]
        let findings = ChangeDetector.apply(changes, to: &source, existing: [], now: .now)
        XCTAssertEqual(findings.count, 3)
    }

    /// 合并后仍然只报一次——下一轮不能重复提醒。
    func testAggregatedFindingIsNotRepeated() {
        var source = WatchSource(repository: "owner/repo")
        source.baselineIdentifier = "v1"
        let bulk = (2...20).map { change("v\($0)", "v\($0)", hint: "1.0.\($0)") }
        let all = bulk + [change("v1", "v1", hint: "1.0.1")]

        let first = ChangeDetector.apply(all, to: &source, existing: [], now: .now)
        let second = ChangeDetector.apply(all, to: &source, existing: first, now: .now)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty, "合并记录也必须只报一次")
    }

    /// 大量非版本号条目被过滤后，不该因为"条数多"就触发合并。
    func testFilteredNoiseDoesNotTriggerAggregation() {
        var source = WatchSource(repository: "owner/repo")
        source.baselineIdentifier = "1.0.1"
        var changes = (2...10).map { change("i\($0)", "inputs \($0)", hint: "inputs-\($0)") }
        changes.append(change("1.0.1", "v1.0.1", hint: "1.0.1"))
        changes.insert(change("1.0.2", "v1.0.2", hint: "1.0.2"), at: 0)

        let findings = ChangeDetector.apply(changes, to: &source, existing: [], now: .now)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.upstreamID, "1.0.2")
        XCTAssertFalse(findings.first!.title.contains("upstream updates at once"),
                       "只有一个真实版本变化，不该走合并路径")
    }

    // MARK: 模型兼容

    func testVersionLikeOnlyDefaultsOnForLegacyData() throws {
        let json: [String: Any] = ["id": UUID().uuidString, "kind": "Release", "repository": "a/b"]
        let source = try JSONDecoder().decode(WatchSource.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(source.versionLikeOnly, "旧数据应沿用开启的默认值")
    }
}
