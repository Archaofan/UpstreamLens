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
        await fulfillment(of: [started], timeout: 5)
        let secondFinished = expectation(description: "duplicate call returned without another fetch")
        Task {
            await model.refresh(source.id)
            secondFinished.fulfill()
        }
        await fulfillment(of: [secondFinished], timeout: 5)
        let fetched = GitHubFetch(changes: [change(), UpstreamChange(identifier: "old", title: "Old", body: "", url: "https://github.com/acme/tool", publishedAt: nil, content: nil)], etag: nil, unchanged: false)
        await gate.resume(fetched)
        await first.value
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

    @MainActor func testEditingAnotherSourceDoesNotDiscardInFlightCheck() async {
        let firstSource = WatchSource(repository: "acme/first", baselineIdentifier: "old")
        let secondSource = WatchSource(repository: "acme/second")
        let started = expectation(description: "first source requested")
        let gate = FetchGate(started: started)
        let model = AppModel(initialData: LocalData(sources: [firstSource, secondSource]),
                             fetchChanges: { _ in try await gate.fetch() },
                             saveData: { _ in }, publishSnapshot: { _ in })
        let check = Task { await model.refresh(firstSource.id) }
        await fulfillment(of: [started], timeout: 5)
        var edited = secondSource
        edited.repository = "acme/changed"
        model.upsert(edited)
        await gate.resume(GitHubFetch(changes: [], etag: nil, unchanged: true))
        await check.value
        XCTAssertNotNil(model.source(for: firstSource.id)?.lastCheckedAt)
        XCTAssertEqual(model.source(for: secondSource.id)?.repository, "acme/changed")
    }

    @MainActor func testImportedDataReplacesInFlightRefreshResults() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        let started = expectation(description: "request started")
        let gate = FetchGate(started: started)
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in try await gate.fetch() },
                             saveData: { _ in }, publishSnapshot: { _ in })
        let task = Task { await model.refresh(source.id) }
        await fulfillment(of: [started], timeout: 5)
        let imported = LocalData(sources: [WatchSource(repository: "acme/imported")])
        try? model.importData(LocalStore.export(imported))
        await gate.resume(GitHubFetch(changes: [change()], etag: nil, unchanged: false))
        await task.value
        XCTAssertEqual(model.sources.map(\.repository), ["acme/imported"])
        XCTAssertTrue(model.findings.isEmpty)
    }

    @MainActor func testFailedLoadBlocksSaveUntilValidImport() throws {
        var saves = 0
        let model = AppModel(loadData: { throw CocoaError(.fileReadCorruptFile) },
                             saveData: { _ in saves += 1 }, publishSnapshot: { _ in })
        XCTAssertNotNil(model.storageError)
        XCTAssertFalse(model.canEditData)
        model.upsert(WatchSource(repository: "acme/tool"))
        XCTAssertEqual(saves, 0)
        let backup = try LocalStore.export(LocalData(sources: [WatchSource(repository: "acme/recovered")]))
        try model.importData(backup)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(model.sources.first?.repository, "acme/recovered")
        XCTAssertNil(model.storageError)
        XCTAssertTrue(model.canEditData)
    }

    @MainActor func testFailedSaveRestoresLastSavedDataAndKeepsWidgetInSync() {
        let original = WatchSource(repository: "acme/original")
        var snapshotWrites = 0
        let model = AppModel(initialData: LocalData(sources: [original]),
                             saveData: { _ in throw CocoaError(.fileWriteNoPermission) },
                             publishSnapshot: { _ in snapshotWrites += 1 })
        XCTAssertEqual(snapshotWrites, 1)
        model.upsert(WatchSource(repository: "acme/new"))
        XCTAssertEqual(model.sources.map(\.repository), ["acme/original"])
        XCTAssertNotNil(model.storageError)
        XCTAssertEqual(snapshotWrites, 1)
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

    // MARK: - 批量操作

    @MainActor private func modelWithFindings() -> AppModel {
        let source = WatchSource(repository: "acme/tool")
        var data = LocalData(sources: [source])
        func make(_ status: FindingStatus, _ relevance: Relevance) -> Finding {
            Finding(sourceID: source.id, upstreamID: UUID().uuidString, title: status.rawValue,
                    body: "", url: "https://github.com/acme/tool", foundAt: .now,
                    relevance: relevance, reason: "r", status: status)
        }
        data.findings = [make(.unread, .important), make(.unread, .routine), make(.viewed, .important)]
        return AppModel(initialData: data, saveData: { _ in }, publishSnapshot: { _ in })
    }

    @MainActor func testMarkAllReadKeepsQueueMembership() {
        let model = modelWithFindings()
        model.markAllRead()
        XCTAssertTrue(model.findings.allSatisfy { $0.status != .unread })
        XCTAssertEqual(FindingQueue.pending(model.findings).count, 3)
    }

    @MainActor func testMarkAllHandledMovesEverythingToHistory() {
        let model = modelWithFindings()
        model.markAllHandled()
        XCTAssertTrue(model.findings.allSatisfy { $0.status == .handled })
        XCTAssertTrue(FindingQueue.pending(model.findings).isEmpty)
        XCTAssertEqual(FindingQueue.completed(model.findings).count, 3)
    }

    @MainActor func testClearHandledRecordsRemovesOnlyHistory() {
        let model = modelWithFindings()
        model.markAllHandled()
        model.clearHandledRecords()
        XCTAssertTrue(model.findings.isEmpty)
    }

    // MARK: - 保留策略

    @MainActor func testRefreshAllPrunesExpiredHandledRecords() async {
        let source = WatchSource(repository: "acme/tool")
        var data = LocalData(sources: [source])
        let old = Finding(sourceID: source.id, upstreamID: "old", title: "old", body: "",
                          url: "u", foundAt: Date().addingTimeInterval(-100 * 86_400),
                          relevance: .routine, reason: "r", status: .handled)
        let recent = Finding(sourceID: source.id, upstreamID: "recent", title: "recent", body: "",
                             url: "u", foundAt: Date(), relevance: .routine, reason: "r", status: .handled)
        data.findings = [old, recent]
        let model = AppModel(initialData: data, saveData: { _ in }, publishSnapshot: { _ in })
        await model.refreshAll()
        XCTAssertEqual(model.findings.count, 1)
        XCTAssertEqual(model.findings.first?.upstreamID, "recent")
    }

    @MainActor func testRetentionZeroKeepsOldRecords() async {
        let source = WatchSource(repository: "acme/tool")
        var data = LocalData(sources: [source], retentionDays: 0)
        data.findings = [Finding(sourceID: source.id, upstreamID: "old", title: "old", body: "",
                                 url: "u", foundAt: Date().addingTimeInterval(-1000 * 86_400),
                                 relevance: .routine, reason: "r", status: .handled)]
        let model = AppModel(initialData: data, saveData: { _ in }, publishSnapshot: { _ in })
        await model.refreshAll()
        XCTAssertEqual(model.findings.count, 1)
    }

    @MainActor func testSetRetentionDaysPrunesImmediately() {
        var data = LocalData()
        let source = WatchSource(repository: "acme/tool")
        data.sources = [source]
        data.findings = [Finding(sourceID: source.id, upstreamID: "old", title: "old", body: "",
                                 url: "u", foundAt: Date().addingTimeInterval(-1000 * 86_400),
                                 relevance: .routine, reason: "r", status: .handled)]
        let model = AppModel(initialData: data, saveData: { _ in }, publishSnapshot: { _ in })
        model.setRetentionDays(90)
        XCTAssertTrue(model.findings.isEmpty)
        model.setRetentionDays(0)
        XCTAssertEqual(model.retentionDays, 0)
    }

    // MARK: - 角标与限流状态

    @MainActor func testBadgeTracksUnreadRelevantCount() {
        let source = WatchSource(repository: "acme/tool")
        var data = LocalData(sources: [source])
        func make(_ status: FindingStatus, _ relevance: Relevance, _ id: String) -> Finding {
            Finding(sourceID: source.id, upstreamID: id, title: id, body: "", url: "u",
                    foundAt: .now, relevance: relevance, reason: "r", status: status)
        }
        data.findings = [make(.unread, .important, "a"), make(.unread, .routine, "b"), make(.viewed, .important, "c")]
        var badgeValues: [Int] = []
        let model = AppModel(initialData: data, saveData: { _ in }, publishSnapshot: { _ in },
                             updateBadge: { badgeValues.append($0) })
        XCTAssertEqual(model.unreadRelevantCount, 1)
        model.setStatus(.viewed, for: model.findings.first { $0.upstreamID == "a" }!.id)
        XCTAssertEqual(model.unreadRelevantCount, 0)
        XCTAssertEqual(badgeValues.last, 0)
    }

    @MainActor func testRateLimitInfoStoredAfterSuccessfulRefresh() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        let info = RateLimitInfo(remaining: 41, total: 60, reset: Date().addingTimeInterval(600))
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in GitHubFetch(changes: [], etag: nil, unchanged: true, rateLimit: info) },
                             saveData: { _ in }, publishSnapshot: { _ in })
        await model.refresh(source.id)
        XCTAssertEqual(model.rateLimit, info)
    }

    // MARK: - 探测闭包

    @MainActor func testProbePassesThroughInjectedClosure() async throws {
        let expected = RepoProbe(source: WatchSource(repository: "acme/probed"), metadata: nil,
                                 latest: nil, warnings: ["warning"])
        let model = AppModel(initialData: LocalData(),
                             saveData: { _ in }, publishSnapshot: { _ in },
                             probeRepo: { input in
                                 XCTAssertEqual(input, "acme/probed")
                                 return expected
                             },
                             probePaths: { _, _ in TreeScan(paths: ["skills/a/SKILL.md"], truncated: false) })
        let probe = try await model.probe("acme/probed")
        XCTAssertEqual(probe.source.repository, "acme/probed")
        XCTAssertEqual(probe.warnings, ["warning"])
        let scan = try await model.probePaths(repository: "acme/probed", branch: "main")
        XCTAssertEqual(scan.paths, ["skills/a/SKILL.md"])
    }
}
