import XCTest
@testable import UpstreamLens

private actor FetchGate {
    let started: XCTestExpectation
    let nextStarted: XCTestExpectation?
    private var continuations: [CheckedContinuation<GitHubFetch, Error>] = []

    init(started: XCTestExpectation, nextStarted: XCTestExpectation? = nil) {
        self.started = started
        self.nextStarted = nextStarted
    }

    func fetch() async throws -> GitHubFetch {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            if continuations.count == 1 { started.fulfill() }
            else { nextStarted?.fulfill() }
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

    @MainActor func testConcurrentRefreshesUseOneRequest() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        let started = expectation(description: "one request started")
        let gate = FetchGate(started: started)
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in try await gate.fetch() },
                             saveData: { _ in }, publishSnapshot: { _ in })
        let first = Task { await model.refresh(source.id) }
        let second = Task { await model.refresh(source.id) }
        await fulfillment(of: [started], timeout: 5)
        let fetched = GitHubFetch(changes: [change(), UpstreamChange(identifier: "old", title: "Old", body: "", url: "https://github.com/acme/tool", publishedAt: nil, content: nil)], etag: nil, unchanged: false)
        await gate.resume(fetched)
        await first.value
        await second.value
        XCTAssertEqual(model.findings.count, 1)
        XCTAssertEqual(model.source(for: source.id)?.baselineIdentifier, "new")
    }

    @MainActor func testEditedSourceCanRefreshWhileOldRequestIsInFlight() async {
        let source = WatchSource(repository: "acme/old", baselineIdentifier: "old")
        let firstStarted = expectation(description: "old revision requested")
        let secondStarted = expectation(description: "new revision requested")
        let gate = FetchGate(started: firstStarted, nextStarted: secondStarted)
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in try await gate.fetch() },
                             saveData: { _ in }, publishSnapshot: { _ in })
        let first = Task { await model.refresh(source.id) }
        await fulfillment(of: [firstStarted], timeout: 5)
        var edited = source
        edited.repository = "acme/new"
        model.upsert(edited)
        let second = Task { await model.refresh(source.id) }
        await fulfillment(of: [secondStarted], timeout: 5)
        await gate.resume(GitHubFetch(changes: [], etag: nil, unchanged: true))
        await gate.resume(GitHubFetch(changes: [], etag: nil, unchanged: true))
        await first.value
        await second.value
        XCTAssertEqual(model.source(for: source.id)?.repository, "acme/new")
    }

    @MainActor func testFailedLoadBlocksSaveUntilValidImport() throws {
        var saves = 0
        let model = AppModel(loadData: { throw CocoaError(.fileReadCorruptFile) },
                             saveData: { _ in saves += 1 }, publishSnapshot: { _ in })
        XCTAssertNotNil(model.storageError)
        model.upsert(WatchSource(repository: "acme/tool"))
        XCTAssertEqual(saves, 0)
        let backup = try LocalStore.export(LocalData(sources: [WatchSource(repository: "acme/recovered")]))
        try model.importData(backup)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(model.sources.first?.repository, "acme/recovered")
        XCTAssertNil(model.storageError)
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
