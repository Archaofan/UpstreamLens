import XCTest
@testable import UpstreamLens

final class StabilityTests: XCTestCase {
    // MARK: - 备份轮换与损坏恢复

    private func tempFile(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stability-\(UUID().uuidString)-\(name)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func sampleData(name: String) -> LocalData {
        let source = WatchSource(repository: "acme/\(name)")
        var data = LocalData()
        data.sources = [source]
        return data
    }

    func testSaveRotatesBackupAndRecoveryRestoresIt() throws {
        let main = tempFile("data.json")
        let backup = tempFile("data.json.bak")
        try LocalStore.save(sampleData(name: "v1"), to: main)
        // 模拟“上一次成功写入后主文件被写坏”
        try LocalStore.save(sampleData(name: "v1"), to: main)
        let bakURL = main.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakURL.path))
        try Data("corrupt{{".utf8).write(to: main)
        // 主文件损坏、备份完好 → 恢复
        let recovered = try LocalStore.loadWithRecovery(from: main, backup: bakURL)
        XCTAssertEqual(recovered.data.sources.first?.repository, "acme/v1")
        XCTAssertNotNil(recovered.notice)
        // 主备全坏 → 抛错（进入受保护模式）
        try Data("corrupt{{".utf8).write(to: bakURL)
        XCTAssertThrowsError(try LocalStore.loadWithRecovery(from: main, backup: bakURL))
        _ = backup
    }

    func testLoadWithRecoveryHealthyFileHasNoNotice() throws {
        let main = tempFile("data.json")
        let bak = tempFile("data.json.bak")
        try LocalStore.save(sampleData(name: "ok"), to: main)
        let result = try LocalStore.loadWithRecovery(from: main, backup: bak)
        XCTAssertNil(result.notice)
        XCTAssertEqual(result.data.sources.first?.repository, "acme/ok")
    }

    func testMissingFilesLoadAsEmpty() throws {
        let main = tempFile("data.json")
        let bak = tempFile("data.json.bak")
        let result = try LocalStore.loadWithRecovery(from: main, backup: bak)
        XCTAssertNil(result.notice)
        XCTAssertTrue(result.data.sources.isEmpty)
    }

    // MARK: - 记录总量上限

    private func makeFinding(_ status: FindingStatus, daysAgo: Double) -> Finding {
        Finding(sourceID: UUID(), upstreamID: UUID().uuidString, title: status.rawValue, body: "",
                url: "u", foundAt: Date().addingTimeInterval(-daysAgo * 86_400),
                relevance: .routine, reason: "r", status: status)
    }

    func testCapDropsOldestHandledFirst() {
        var data = LocalData()
        data.findings = (0..<600).map { makeFinding(.handled, daysAgo: 1000 - Double($0)) }
        data.findings += (0..<500).map { makeFinding(.viewed, daysAgo: 400 - Double($0)) }
        let capped = data.capped()
        XCTAssertEqual(capped.findings.count, LocalData.maxFindings)
        // 1100 → 1000：最旧的 100 条已处理被丢，已查看全保留。
        XCTAssertEqual(capped.findings.filter { $0.status == .viewed }.count, 500)
        XCTAssertEqual(capped.findings.filter { $0.status == .handled }.count, 500)
    }

    func testCapFallsThroughToUnreadOnlyWhenNecessary() {
        var data = LocalData()
        data.findings = (0..<1200).map { makeFinding(.unread, daysAgo: 2000 - Double($0)) }
        let capped = data.capped()
        XCTAssertEqual(capped.findings.count, LocalData.maxFindings)
        // 全部是未读：丢最旧的 200 条未读。
        XCTAssertEqual(capped.findings.map(\.foundAt).min()!,
                       data.findings.sorted { $0.foundAt < $1.foundAt }[200].foundAt)
    }

    func testUnderCapUnchanged() {
        var data = LocalData()
        data.findings = [makeFinding(.unread, daysAgo: 1)]
        XCTAssertEqual(data.capped().findings.count, 1)
    }

    // MARK: - 预设库

    func testPresetLibraryValidAndComplete() {
        let presets = PresetLibrary.validated()
        XCTAssertEqual(presets.count, PresetLibrary.all.count, "所有预设都必须通过校验，若有仓库改名应及时更新")
        for preset in presets {
            XCTAssertNotNil(try? GitHubClient.normalizedRepository(preset.repository))
            if preset.kind == .path {
                XCTAssertFalse(preset.path.isEmpty)
            } else {
                XCTAssertTrue(preset.path.isEmpty)
            }
            XCTAssertEqual(preset.iconURL?.host, "github.com", "预设图标必须是 GitHub 头像直链")
            let owner = preset.repository.split(separator: "/").first.map(String.init) ?? ""
            XCTAssertEqual(preset.iconURL?.absoluteString, "https://github.com/\(owner).png?size=120")
        }
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count, "预设 id 不得重复")
    }

    func testAvatarCacheNameIsStableAndFilesystemSafe() {
        let url = URL(string: "https://github.com/openclaw.png?size=120")!
        let first = AvatarCache.cachedFileURL(for: url)
        XCTAssertEqual(first, AvatarCache.cachedFileURL(for: URL(string: "https://github.com/openclaw.png?size=120")!),
                       "同名 URL 派生的缓存文件名必须一致")
        // 非字母数字（含点号）都替换为下划线，文件名天然安全。
        XCTAssertTrue(first.lastPathComponent.contains("github_com_openclaw_png_size_120"))
        XCTAssertFalse(first.lastPathComponent.contains("?"), "文件名不得包含 URL 特殊字符")
    }

    // MARK: - Widget 快照

    func testWidgetSnapshotCarriesHeadlineRelevance() throws {
        let snapshot = WidgetSnapshot(pendingCount: 2, headline: "v2 发布",
                                      headlineRelevance: .important,
                                      lastSuccessfulCheck: Date(timeIntervalSince1970: 1_700_000_000),
                                      generatedAt: .now)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: try JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.pendingCount, 2)
        XCTAssertEqual(decoded.headline, "v2 发布")
        XCTAssertEqual(decoded.headlineRelevance, .important)
    }

    func testWidgetSnapshotLegacyWithoutRelevanceDecodes() throws {
        // 旧快照没有 headlineRelevance 字段，必须能解码为 nil（向后兼容）。
        let legacy = #"{"pendingCount":1,"headline":"x","lastSuccessfulCheck":null,"generatedAt":0}"#
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.pendingCount, 1)
        XCTAssertNil(decoded.headlineRelevance)
    }
}

final class NotificationPlannerTests: XCTestCase {
    private func source(notifyEnabled: Bool? = nil) -> WatchSource {
        var source = WatchSource(repository: "acme/tool", displayName: "工具")
        source.notifyEnabled = notifyEnabled
        return source
    }

    private func finding(_ relevance: Relevance, status: FindingStatus = .unread) -> Finding {
        Finding(sourceID: source().id, upstreamID: UUID().uuidString, title: "T \(relevance.rawValue)",
                body: "", url: "u", foundAt: .now, relevance: relevance, reason: "r", status: status)
    }

    func testMasterOffNeverNotifies() {
        XCTAssertTrue(NotificationPlanner.plan(additions: [finding(.important)], source: source(), masterEnabled: false).isEmpty)
    }

    func testSourceToggleRespected() {
        XCTAssertTrue(NotificationPlanner.plan(additions: [finding(.important)], source: source(notifyEnabled: false), masterEnabled: true).isEmpty)
        XCTAssertFalse(NotificationPlanner.plan(additions: [finding(.important)], source: source(notifyEnabled: true), masterEnabled: true).isEmpty)
        XCTAssertFalse(NotificationPlanner.plan(additions: [finding(.important)], source: source(notifyEnabled: nil), masterEnabled: true).isEmpty)
    }

    func testRoutineAndHandledExcluded() {
        let additions = [finding(.routine), finding(.important, status: .handled)]
        XCTAssertTrue(NotificationPlanner.plan(additions: additions, source: source(), masterEnabled: true).isEmpty)
    }

    func testImportantComesFirstAndCapFolds() {
        let additions = (0..<8).map { _ in finding(.important) }
        let planned = NotificationPlanner.plan(additions: additions, source: source(), masterEnabled: true)
        XCTAssertEqual(planned.count, 6, "5 条直接通知 + 1 条折叠摘要")
        XCTAssertTrue(planned.prefix(5).allSatisfy { $0.isImportant })
        XCTAssertFalse(planned.last!.isImportant)
        XCTAssertTrue(planned.last!.body.contains("3"), "折叠摘要应说明还有 3 条：\(planned.last!.body)")
        XCTAssertTrue(planned.last!.body.contains("more related change"),
                      "文案已本地化，测试环境为英文：\(planned.last!.body)")
        // 同一来源的 threadIdentifier 一致，通知中心自动成组。
        XCTAssertTrue(planned.allSatisfy { $0.threadIdentifier == "工具" })
    }

    func testUncertainStillNotifiesAsPassive() {
        let planned = NotificationPlanner.plan(additions: [finding(.uncertain)], source: source(), masterEnabled: true)
        XCTAssertEqual(planned.count, 1)
        XCTAssertFalse(planned.first!.isImportant)
    }
}

final class BackgroundBudgetTests: XCTestCase {
    @MainActor func testBudgetGuardSkipsWhenRemainingTooLow() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        let info = RateLimitInfo(remaining: 2, total: 60, reset: Date().addingTimeInterval(600))
        var fetchCount = 0
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in fetchCount += 1; return GitHubFetch(changes: [], etag: nil, unchanged: true, rateLimit: info) },
                             saveData: { _ in }, publishSnapshot: { _ in })
        // 先建立一次真实刷新以记录限额水位。
        await model.refreshAll()
        XCTAssertEqual(fetchCount, 1)
        await model.refreshAllRespectingBudget(minRemaining: 5)
        XCTAssertEqual(fetchCount, 1, "剩余额度低于后台预算时必须跳过")
        await model.refreshAllRespectingBudget(minRemaining: 1)
        XCTAssertEqual(fetchCount, 2, "预算内时正常刷新")
    }

    @MainActor func testDeliverReceivesPlannedNotifications() async {
        var source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        source.notifyEnabled = true
        var delivered: [PendingNotification] = []
        let change = UpstreamChange(identifier: "v2", title: "Breaking change", body: "security fix",
                                    url: "u", publishedAt: nil, content: nil)
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in
                                 GitHubFetch(changes: [change, UpstreamChange(identifier: "old", title: "old", body: "", url: "u", publishedAt: nil, content: nil)],
                                             etag: nil, unchanged: false)
                             },
                             saveData: { _ in }, publishSnapshot: { _ in },
                             notificationsEnabled: { true },
                             deliverNotifications: { delivered.append(contentsOf: $0) })
        await model.refresh(source.id)
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.body, "Breaking change")
        XCTAssertEqual(delivered.first?.threadIdentifier, source.title)
        XCTAssertTrue(delivered.first!.isImportant, "命中 breaking 词应为重要级")
    }

    @MainActor func testNoNotificationWhenMasterOff() async {
        let source = WatchSource(repository: "acme/tool", baselineIdentifier: "old")
        let change = UpstreamChange(identifier: "v2", title: "Breaking change", body: "security fix",
                                    url: "u", publishedAt: nil, content: nil)
        var delivered: [PendingNotification] = []
        let model = AppModel(initialData: LocalData(sources: [source]),
                             fetchChanges: { _ in
                                 GitHubFetch(changes: [change, UpstreamChange(identifier: "old", title: "old", body: "", url: "u", publishedAt: nil, content: nil)],
                                             etag: nil, unchanged: false)
                             },
                             saveData: { _ in }, publishSnapshot: { _ in },
                             notificationsEnabled: { false },
                             deliverNotifications: { delivered.append(contentsOf: $0) })
        await model.refresh(source.id)
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertEqual(model.findings.count, 1, "记录照常入库，只是不投递")
    }
}
