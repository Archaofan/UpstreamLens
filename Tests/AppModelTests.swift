import XCTest
@testable import UpstreamLens

private actor FetchGate {
    let started: XCTestExpectation
    private var continuations: [CheckedContinuation<GitHubFetch, Error>] = []

    init(started: XCTestExpectation) { self.started = started }

    func fetch() async throws -> GitHubFetch {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            started.fulfill()
        }
    }

    func resume(_ result: GitHubFetch) {
        continuations.removeFirst().resume(returning: result)
    }
}

final class AppModelTests: XCTestCase {
    private func change() -> UpstreamChange {
        UpstreamChange(identifier: "new", title: "New", body: "security", url: "https://github.com/acme/tool", publishedAt: nil, content: nil)
    }

    @MainActor func testDeleteDuringNetworkRequestDoesNotRestoreSource() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        let started = expectation(description: "request started")
        let gate = FetchGate(started: started)
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in try await gate.fetch() },
                             saveData: { _ in }, publishSnapshot: { _ in })
        let task = Task { await model.refresh(source.id) }
        await fulfillment(of: [started], timeout: 5)
        model.delete(source)
        await gate.resume(GitHubFetch(changes: [change()], etag: nil, unchanged: false))
        await task.value
        XCTAssertTrue(model.sources.isEmpty)
        XCTAssertTrue(model.findings.isEmpty)
    }

    @MainActor func testConcurrentRefreshesCreateOneFinding() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        let started = expectation(description: "two requests started")
        started.expectedFulfillmentCount = 2
        let gate = FetchGate(started: started)
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in try await gate.fetch() },
                             saveData: { _ in }, publishSnapshot: { _ in })
        let first = Task { await model.refresh(source.id) }
        let second = Task { await model.refresh(source.id) }
        await fulfillment(of: [started], timeout: 5)
        let fetched = GitHubFetch(changes: [change(), UpstreamChange(identifier: "old", title: "Old", body: "", url: "https://github.com/acme/tool", publishedAt: nil, content: nil)], etag: nil, unchanged: false)
        await gate.resume(fetched)
        await gate.resume(fetched)
        await first.value
        await second.value
        XCTAssertEqual(model.findings.count, 1)
        XCTAssertEqual(model.source(for: source.id)?.baselineIdentifier, "new")
    }

    @MainActor func testMissingBaselineKeepsLastSuccessfulTime() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "removed")
        let upstream = change()
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in GitHubFetch(changes: [upstream], etag: "new-etag", unchanged: false) },
                             saveData: { _ in }, publishSnapshot: { _ in })
        await model.refresh(source.id)
        XCTAssertEqual(model.source(for: source.id)?.baselineIdentifier, "removed")
        XCTAssertEqual(model.source(for: source.id)?.lastError, ChangeDetector.missingBaselineMessage)
        XCTAssertNil(model.lastSuccessfulCheck)
        XCTAssertNil(model.source(for: source.id)?.etag)
    }

    @MainActor func testChangingTrackedPathClearsOldTargetCheckStatus() async {
        let oldCheck = Date(timeIntervalSince1970: 1_700_000_000)
        let otherCheck = Date(timeIntervalSince1970: 1_600_000_000)
        let source = WatchSource(kind: .path, repository: "acme/tool", path: "skills/old/SKILL.md",
                                 baselineIdentifier: "old-sha", lastCheckedAt: oldCheck,
                                 lastError: "旧路径请求失败")
        let other = WatchSource(repository: "acme/other", lastCheckedAt: otherCheck)
        let model = AppModel(initialData: LocalData(sources: [source, other], lastSuccessfulCheck: oldCheck),
                             fetchChanges: { _ in throw GitHubError.notFound },
                             saveData: { _ in }, publishSnapshot: { _ in })
        var edited = source
        edited.path = "skills/new/SKILL.md"

        model.upsert(edited)
        XCTAssertNil(model.source(for: source.id)?.lastCheckedAt)
        XCTAssertNil(model.source(for: source.id)?.lastError)
        XCTAssertEqual(model.lastSuccessfulCheck, otherCheck)
        await model.refresh(source.id)
        XCTAssertNil(model.source(for: source.id)?.lastCheckedAt)
        XCTAssertEqual(model.source(for: source.id)?.lastError, GitHubError.notFound.localizedDescription)
        XCTAssertEqual(model.lastSuccessfulCheck, otherCheck)
    }

    @MainActor func testDeletingCheckedSourceUsesRemainingCheckTime() {
        let earlier = Date(timeIntervalSince1970: 1_600_000_000)
        let later = Date(timeIntervalSince1970: 1_700_000_000)
        let first = WatchSource(repository: "acme/first", lastCheckedAt: earlier)
        let second = WatchSource(repository: "acme/second", lastCheckedAt: later)
        let model = AppModel(initialData: LocalData(sources: [first, second], lastSuccessfulCheck: later),
                             saveData: { _ in }, publishSnapshot: { _ in })

        model.delete(second)
        XCTAssertEqual(model.lastSuccessfulCheck, earlier)
        model.delete(first)
        XCTAssertNil(model.lastSuccessfulCheck)
    }
}
