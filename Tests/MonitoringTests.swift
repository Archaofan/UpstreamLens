import XCTest
@testable import UpstreamLens

final class MonitoringTests: XCTestCase {
    func testFirstCheckSetsBaselineWithoutFinding() {
        var source = WatchSource(repository: "owner/repo")
        let changes = [UpstreamChange(identifier: "v2", title: "v2", body: "", url: "https://github.com/owner/repo/releases/tag/v2", publishedAt: nil, content: nil)]
        let findings = ChangeDetector.apply(changes, to: &source, existing: [], now: .now)
        XCTAssertTrue(findings.isEmpty)
        XCTAssertEqual(source.baselineIdentifier, "v2")
    }

    func testSecondCheckCreatesFindingOnce() {
        var source = WatchSource(repository: "owner/repo", baselineIdentifier: "v1")
        let changes = [
            UpstreamChange(identifier: "v2", title: "v2", body: "security fix", url: "https://github.com/owner/repo/releases/tag/v2", publishedAt: nil, content: nil),
            UpstreamChange(identifier: "v1", title: "v1", body: "", url: "https://github.com/owner/repo/releases/tag/v1", publishedAt: nil, content: nil)
        ]
        let first = ChangeDetector.apply(changes, to: &source, existing: [], now: .now)
        let second = ChangeDetector.apply(changes, to: &source, existing: first, now: .now)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
    }

    func testFirstReleaseAfterEmptyRepositoryIsNew() {
        var source = WatchSource(repository: "owner/repo")
        XCTAssertTrue(ChangeDetector.apply([], to: &source, existing: [], now: .now).isEmpty)
        XCTAssertEqual(source.baselineIdentifier, ChangeDetector.emptyBaseline)
        let first = UpstreamChange(identifier: "1", title: "First release", body: "", url: "https://github.com/owner/repo", publishedAt: nil, content: nil)
        XCTAssertEqual(ChangeDetector.apply([first], to: &source, existing: [], now: .now).count, 1)
    }

    /// 上游删除了基线指向的那条发布（真机场景：release 被撤回）。
    /// 旧实现只置错并 return，而且**永不更新基线**，来源会永久卡在报错状态。
    /// 现在必须静默重建基线、清掉错误，并且不凭空编造历史记录。
    func testMissingPreviousIdentifierRebuildsBaselineAndRecovers() {
        var source = WatchSource(repository: "owner/repo", baselineIdentifier: "removed-release")
        source.lastError = ChangeDetector.missingBaselineMessage
        let older = UpstreamChange(identifier: "surviving-release", title: "Surviving", body: "", url: "https://github.com/owner/repo", publishedAt: nil, content: nil)

        let findings = ChangeDetector.apply([older], to: &source, existing: [], now: .now)

        XCTAssertTrue(findings.isEmpty, "无法判断窗口内哪些是新的，就不该凭空生成记录")
        XCTAssertEqual(source.baselineIdentifier, "surviving-release", "必须重建基线，否则永远无法恢复")
        XCTAssertNil(source.lastError, "错误必须清掉，来源要能自愈")
    }

    /// 基线重建后的下一轮必须恢复正常比对，证明真的恢复了。
    func testSourceRecoversOnTheCheckAfterBaselineRebuild() {
        var source = WatchSource(repository: "owner/repo", baselineIdentifier: "removed-release")
        let current = UpstreamChange(identifier: "v2", title: "v2", body: "", url: "u", publishedAt: nil, content: nil)
        _ = ChangeDetector.apply([current], to: &source, existing: [], now: .now)

        let newer = UpstreamChange(identifier: "v3", title: "v3", body: "", url: "u", publishedAt: nil, content: nil)
        let findings = ChangeDetector.apply([newer, current], to: &source, existing: [], now: .now)

        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.upstreamID, "v3")
    }

    /// 上游一条条目都没有，是正常状态而不是"基线丢失"。
    func testEmptyUpstreamIsNotTreatedAsError() {
        var source = WatchSource(repository: "owner/repo", baselineIdentifier: "v1")
        let findings = ChangeDetector.apply([], to: &source, existing: [], now: .now)
        XCTAssertTrue(findings.isEmpty)
        XCTAssertNil(source.lastError)
        XCTAssertEqual(source.baselineIdentifier, ChangeDetector.emptyBaseline)
    }

    func testKeywordExplainsImportance() {
        let source = WatchSource(repository: "owner/repo", keywords: "config, security")
        let result = RelevanceEngine.assess(source: source, text: "Config parameter renamed")
        XCTAssertEqual(result.0, .important)
        XCTAssertTrue(result.1.contains("config"))
    }

    func testRepositoryURLNormalizesToOwnerRepo() throws {
        XCTAssertEqual(try GitHubClient.normalizedRepository("https://github.com/acme/tool.git"), "acme/tool")
        XCTAssertThrowsError(try GitHubClient.normalizedRepository("https://example.com/acme/tool"))
    }

    func testPathSummaryIdentifiesChangedLines() {
        let result = ChangeDetector.contentSummary(old: "alpha\nbeta", new: "alpha\ngamma")
        XCTAssertTrue(result.contains("+ gamma"))
        XCTAssertTrue(result.contains("− beta"))
    }

    func testBackupPreservesPersonalNotesAndStatus() throws {
        let source = WatchSource(repository: "acme/tool", purpose: "my NAS", keywords: "config")
        let finding = Finding(sourceID: source.id, upstreamID: "v2", title: "Update", body: "", url: "https://github.com/acme/tool", foundAt: .now, relevance: .important, reason: "config", status: .handled)
        let decoded = try LocalStore.importData(LocalStore.export(LocalData(sources: [source], findings: [finding], lastSuccessfulCheck: .now)))
        XCTAssertEqual(decoded.sources.first?.purpose, "my NAS")
        XCTAssertEqual(decoded.findings.first?.status, .handled)
    }
}
