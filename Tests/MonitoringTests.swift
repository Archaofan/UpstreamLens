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
        let changes = [UpstreamChange(identifier: "v2", title: "v2", body: "security fix", url: "https://github.com/owner/repo/releases/tag/v2", publishedAt: nil, content: nil)]
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

    func testMissingPreviousIdentifierDoesNotInventHistoricalFindings() {
        var source = WatchSource(repository: "owner/repo", baselineIdentifier: "removed-tag")
        let older = UpstreamChange(identifier: "old-tag", title: "Old tag", body: "", url: "https://github.com/owner/repo/tree/old-tag", publishedAt: nil, content: nil)
        let findings = ChangeDetector.apply([older], to: &source, existing: [], now: .now)
        XCTAssertTrue(findings.isEmpty)
        XCTAssertEqual(source.baselineIdentifier, "removed-tag")
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
