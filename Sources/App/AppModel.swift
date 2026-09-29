import Foundation
import UIKit

@MainActor final class AppModel: ObservableObject {
    private struct RequestVersion: Equatable {
        let data: Int
        let source: Int
    }

    @Published private(set) var data: LocalData
    @Published var isRefreshing = false
    @Published private(set) var refreshingSourceIDs: Set<UUID> = []
    @Published var storageError: String?
    @Published var widgetError: String?
    @Published private(set) var rateLimit: RateLimitInfo?
    @Published private(set) var isAuthenticated = false
    @Published var authError: String?
    private let fetchChanges: (WatchSource) async throws -> GitHubFetch
    private let saveData: (LocalData) throws -> Void
    private let publishSnapshot: (LocalData) throws -> Void
    private let probeRepository: (String) async throws -> RepoProbe
    private let probePaths: (String, String) async throws -> TreeScan
    private let fetchVersionOptions: (String, SourceKind) async throws -> [VersionOption]
    private let updateBadge: (Int) -> Void
    private let notificationsEnabled: () -> Bool
    private let deliverNotifications: ([PendingNotification]) async -> Void
    private let tokenStore: TokenStore
    private var dataEpoch = 0
    private var sourceEpochs: [UUID: Int] = [:]
    private var inFlightVersions: [UUID: RequestVersion] = [:]
    private var storageReady = true
    private var lastSavedData = LocalData()

    init(initialData: LocalData? = nil,
         tokenStore: TokenStore = KeychainTokenStore.shared,
         loadData: @escaping () throws -> (data: LocalData, notice: String?) = { try LocalStore.loadWithRecovery() },
         fetchChanges: ((WatchSource) async throws -> GitHubFetch)? = nil,
         saveData: @escaping (LocalData) throws -> Void = { try LocalStore.save($0) },
         publishSnapshot: @escaping (LocalData) throws -> Void = { try WidgetSnapshotWriter.write(from: $0) },
         probeRepo: ((String) async throws -> RepoProbe)? = nil,
         probePaths: ((String, String) async throws -> TreeScan)? = nil,
         fetchVersionOptions: ((String, SourceKind) async throws -> [VersionOption])? = nil,
         updateBadge: @escaping (Int) -> Void = { count in UIApplication.shared.applicationIconBadgeNumber = count },
         notificationsEnabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "notificationsEnabled") },
         deliverNotifications: @escaping ([PendingNotification]) async -> Void = { await NotificationScheduler().deliver($0) }) {
        self.tokenStore = tokenStore
        // 默认网络闭包在每次调用时读取令牌并注入——登录/登出即时生效，无需重建 AppModel。
        self.fetchChanges = fetchChanges ?? { source in
            var client = GitHubClient()
            client.token = tokenStore.read()
            return try await client.fetch(source: source)
        }
        self.saveData = saveData
        self.publishSnapshot = publishSnapshot
        self.probeRepository = probeRepo ?? { input in
            var client = GitHubClient()
            client.token = tokenStore.read()
            return try await RepoProbing.probe(input, client: client)
        }
        self.probePaths = probePaths ?? { repository, branch in
            var client = GitHubClient()
            client.token = tokenStore.read()
            return try await RepoProbing.probePaths(repository, branch: branch, client: client)
        }
        self.fetchVersionOptions = fetchVersionOptions ?? { repository, kind in
            var client = GitHubClient()
            client.token = tokenStore.read()
            return try await client.versionOptions(repository: repository, kind: kind)
        }
        self.updateBadge = updateBadge
        self.notificationsEnabled = notificationsEnabled
        self.deliverNotifications = deliverNotifications
        self.isAuthenticated = (tokenStore.read() != nil)
        if let initialData {
            data = initialData
        } else {
            do {
                let loaded = try loadData()
                data = loaded.data
                if let notice = loaded.notice { storageError = notice }
            }
            catch {
                data = LocalData()
                storageReady = false
                storageError = L10n.format(
                    "Could not read local data, so saving is paused to protect the original file. Import a valid backup: {detail}",
                    ["detail": error.localizedDescription])
            }
        }
        lastSavedData = data
        if storageReady {
            // 一次性清理历史噪音：老版本把 inputs-a 这类内容寻址快照也逐条记成了待处理提醒。
            // 修好生成逻辑只防新的，存量记录必须一起收拾，否则用户看到的还是刷屏。
            cleanUpLegacyNoiseFindings()
            writeWidget()
        }
        updateBadge(unreadRelevantCount)
    }

    /// 一次性把"内容寻址发布"的存量待处理记录标记为已处理（**不删除**，仍可在已处理里查到）。
    ///
    /// 严格限定，避免误伤：
    /// - 只处理 release / tag 来源（path 模式的 upstreamID 是提交 SHA）；
    /// - 只处理该来源**开启了** versionLikeOnly 的（用户关掉过滤说明他确实要看这些）；
    /// - upstreamID 必须**是纯数字**且不像版本号：纯数字只可能是 release 的数字 id，
    ///   不可能是版本号或 tag 名。用"不像版本号"当条件太宽，会把 UUID 等防御性标识也误判；
    /// - 只处理未读/已查看的，已经处理过的不动；
    /// - 只执行一次，用 LocalData 里的标记记住。
    @discardableResult
    func cleanUpLegacyNoiseFindings() -> Int {
        guard storageReady, data.didCleanLegacyNoise != true else { return 0 }
        let guardedSources = Set(data.sources
            .filter { $0.kind != .path && $0.versionLikeOnly }
            .map(\.id))
        var cleaned = 0
        for index in data.findings.indices {
            let finding = data.findings[index]
            guard finding.status == .unread || finding.status == .viewed else { continue }
            guard guardedSources.contains(finding.sourceID) else { continue }
            guard ChangeDetector.isNumericIdentifier(finding.upstreamID),
                  !ChangeDetector.looksLikeVersion(finding.upstreamID) else { continue }
            data.findings[index].status = .handled
            cleaned += 1
        }
        data.didCleanLegacyNoise = true
        persist()
        if cleaned > 0 { updateBadge(unreadRelevantCount) }
        return cleaned
    }

    var sources: [WatchSource] { data.sources }
    var findings: [Finding] { data.findings.sorted { $0.foundAt > $1.foundAt } }
    var lastSuccessfulCheck: Date? { data.lastSuccessfulCheck }
    var canEditData: Bool { storageReady }
    var unreadRelevantCount: Int { data.findings.filter(\.isUnreadRelevant).count }
    /// 生效的来源类别目录（用户没配过就是内置默认）。
    var categories: [SourceCategory] { data.effectiveCategories }

    func source(for id: UUID) -> WatchSource? { data.sources.first { $0.id == id } }

    // MARK: 类别管理

    func replaceCategories(_ categories: [SourceCategory]) {
        guard storageReady else { return }
        data.categories = categories
        persist()
    }

    /// 删除类别，并把仍指向它的来源收归到"其他"，避免悬空引用。
    func deleteCategory(_ id: String) {
        guard storageReady else { return }
        data.categories = data.effectiveCategories.filter { $0.id != id }
        data.reassignCategory(id)
        persist()
    }

    /// 把某来源归入一个类别。
    func setCategory(_ categoryID: String?, for sourceID: UUID) {
        guard storageReady else { return }
        guard let index = data.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        data.sources[index].category = categoryID
        persist()
    }

    /// 给尚未归类的来源按仓库名/topics/描述猜一个类别。
    /// 只填空白项，绝不覆盖用户已有的选择。返回改动条数。
    @discardableResult
    func autoCategorizeUnassigned() -> Int {
        guard storageReady else { return 0 }
        var changed = 0
        for index in data.sources.indices where data.sources[index].category == nil {
            let source = data.sources[index]
            let guess = CategoryClassifier.suggest(
                repository: source.repository,
                topics: source.topics ?? [],
                text: [source.displayName, source.purpose, source.keywords, source.repoDescription ?? ""]
                    .joined(separator: " "))
            if let guess {
                data.sources[index].category = guess
                changed += 1
            }
        }
        if changed > 0 { persist() }
        return changed
    }

    func upsert(_ source: WatchSource) {
        guard storageReady else { return }
        if let index = data.sources.firstIndex(where: { $0.id == source.id }) {
            var updated = source
            let previous = data.sources[index]
            let trackingChanged = previous.repository != source.repository || previous.kind != source.kind ||
                previous.path != source.path || previous.branch != source.branch
            if trackingChanged {
                sourceEpochs[source.id, default: 0] += 1
                updated.baselineIdentifier = nil
                updated.baselineContent = nil
                updated.etag = nil
                updated.lastCheckedAt = nil
                updated.lastError = nil
                data.findings.removeAll { $0.sourceID == source.id }
            } else {
                updated.baselineIdentifier = previous.baselineIdentifier
                updated.baselineContent = previous.baselineContent
                updated.etag = previous.etag
                updated.lastCheckedAt = previous.lastCheckedAt
                updated.lastError = previous.lastError
            }
            data.sources[index] = updated
            if trackingChanged { data.lastSuccessfulCheck = data.sources.compactMap(\.lastCheckedAt).max() }
        } else {
            data.sources.append(source)
        }
        persist()
    }

    func delete(_ source: WatchSource) {
        guard storageReady else { return }
        sourceEpochs[source.id, default: 0] += 1
        data.sources.removeAll { $0.id == source.id }
        data.findings.removeAll { $0.sourceID == source.id }
        data.lastSuccessfulCheck = data.sources.compactMap(\.lastCheckedAt).max()
        persist()
    }

    /// 只更新个人使用情况字段，不动监控目标与基线状态，避免覆盖并发刷新的结果。
    func upsertPersonalContext(_ updated: WatchSource) {
        guard storageReady,
              let index = data.sources.firstIndex(where: { $0.id == updated.id }) else { return }
        data.sources[index].displayName = updated.displayName
        data.sources[index].purpose = updated.purpose
        data.sources[index].installedVersion = updated.installedVersion
        data.sources[index].keywords = updated.keywords
        data.sources[index].rationale = updated.rationale
        data.sources[index].isPaused = updated.isPaused
        persist()
    }

    func setStatus(_ status: FindingStatus, for id: UUID) {
        guard storageReady else { return }
        guard let index = data.findings.firstIndex(where: { $0.id == id }) else { return }
        data.findings[index].status = status
        persist()
    }

    /// 把所有未读标为已查看（仍在待处理队列中）。
    func markAllRead() {
        guard storageReady else { return }
        for index in data.findings.indices where data.findings[index].status == .unread {
            data.findings[index].status = .viewed
        }
        persist()
    }

    /// 把待处理队列整体标为已处理（需 UI 确认后调用）。
    func markAllHandled() {
        guard storageReady else { return }
        for index in data.findings.indices where data.findings[index].status != .handled {
            data.findings[index].status = .handled
        }
        persist()
    }

    /// 清空已处理记录（导出备份后使用）。
    func clearHandledRecords() {
        guard storageReady else { return }
        data.findings.removeAll { $0.status == .handled }
        persist()
    }

    /// 已处理记录保留天数；0 表示永久保留。开启后立即执行一次清理。
    func setRetentionDays(_ days: Int) {
        guard storageReady else { return }
        data.retentionDays = max(0, days)
        if data.retentionDays ?? 0 > 0 {
            data = data.pruned(now: Date())
        }
        persist()
    }

    var retentionDays: Int? { data.retentionDays }

    func refreshAll() async {
        guard storageReady, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for source in data.sources where !source.isPaused {
            await refresh(source.id)
        }
        pruneHandledRecords()
    }

    /// 后台刷新用：剩余限额不足时直接跳过本轮，把额度留给前台。
    func refreshAllRespectingBudget(minRemaining: Int) async {
        guard storageReady, !isRefreshing else { return }
        if let limit = rateLimit, limit.remaining < minRemaining { return }
        await refreshAll()
    }

    func refresh(_ id: UUID) async {
        guard storageReady, let requested = source(for: id), !requested.isPaused else { return }
        let requestVersion = version(for: id)
        guard inFlightVersions[id] != requestVersion else { return }
        inFlightVersions[id] = requestVersion
        refreshingSourceIDs.insert(id)
        defer {
            if inFlightVersions[id] == requestVersion {
                inFlightVersions[id] = nil
                refreshingSourceIDs.remove(id)
            }
        }
        do {
            let fetched = try await fetchChanges(requested)
            guard requestVersion == version(for: id),
                  let index = data.sources.firstIndex(where: { $0.id == id }),
                  Self.sameTracking(data.sources[index], requested) else { return }
            var source = data.sources[index]
            let now = Date()
            if !fetched.unchanged {
                let additions = ChangeDetector.apply(fetched.changes, to: &source, existing: data.findings, now: now)
                data.findings.append(contentsOf: additions)
                if source.lastError == nil {
                    source.etag = fetched.etag
                    data.lastSuccessfulCheck = now
                    if !additions.isEmpty {
                        let planned = NotificationPlanner.plan(additions: additions, source: source,
                                                               masterEnabled: notificationsEnabled())
                        if !planned.isEmpty {
                            await deliverNotifications(planned)
                        }
                    }
                }
            } else {
                source.lastCheckedAt = now
                source.lastError = nil
                data.lastSuccessfulCheck = now
            }
            data.sources[index] = source
            rateLimit = fetched.rateLimit ?? rateLimit
        } catch {
            guard requestVersion == version(for: id),
                  let index = data.sources.firstIndex(where: { $0.id == id }),
                  Self.sameTracking(data.sources[index], requested) else { return }
            if case GitHubError.rateLimited(let info) = error, let info {
                rateLimit = info
            }
            data.sources[index].lastError = error.localizedDescription
        }
        persist()
    }

    func resetBaseline(for id: UUID) {
        guard storageReady else { return }
        guard let index = data.sources.firstIndex(where: { $0.id == id }) else { return }
        sourceEpochs[id, default: 0] += 1
        data.sources[index].baselineIdentifier = nil
        data.sources[index].baselineContent = nil
        data.sources[index].etag = nil
        data.sources[index].lastError = nil
        persist()
    }

    // MARK: - GitHub 登录

    /// 写入/清除 GitHub 令牌（Keychain）。传 nil 或空串即登出。切换登录态供 UI 观察；
    /// 默认网络闭包在下次请求时自动读到新令牌。
    func setAuthToken(_ token: String?) {
        do {
            try tokenStore.set(token)
            isAuthenticated = !(token?.isEmpty ?? true)
            authError = nil
        } catch {
            authError = error.localizedDescription
        }
    }

    // MARK: - 添加来源的探测

    func probe(_ input: String) async throws -> RepoProbe {
        try await probeRepository(input)
    }

    func probePaths(repository: String, branch: String) async throws -> TreeScan {
        try await probePaths(repository, branch)
    }

    /// 上游版本候选（“正在使用的版本”下拉数据源），1 次核心接口请求。
    func versionOptions(repository: String, kind: SourceKind) async throws -> [VersionOption] {
        try await fetchVersionOptions(repository, kind)
    }

    /// 合并 AI 来源清单：只新增现有列表中不存在的来源（按 仓库+模式+路径 判重），
    /// 不覆盖、不删除已有条目，个人使用信息全部保留。
    @discardableResult func mergeSourceList(_ incoming: [WatchSource]) -> (added: Int, skipped: Int) {
        guard storageReady, !incoming.isEmpty else { return (0, incoming.count) }
        var added = 0
        var skipped = 0
        for source in incoming {
            let duplicate = data.sources.contains {
                $0.repository == source.repository && $0.kind == source.kind && $0.path == source.path
            }
            if duplicate {
                skipped += 1
            } else {
                data.sources.append(source)
                added += 1
            }
        }
        if added > 0 { persist() }
        return (added, skipped)
    }

    // MARK: - 导入导出

    func exportData() throws -> Data {
        guard storageReady else { throw StorageError.localDataUnavailable }
        return try LocalStore.export(data)
    }

    func importData(_ bytes: Data) throws {
        try applyImport(LocalStore.importData(bytes))
    }

    func applyImport(_ imported: LocalData) throws {
        dataEpoch += 1
        data = imported
        let wasReady = storageReady
        storageReady = true
        if let error = persist() {
            storageReady = wasReady
            throw error
        }
    }

    // MARK: - 诊断

    /// 生成可整段复制的诊断文本，包含签名链路排查所需的关键证据。
    func diagnosticsReport() -> String {
        var lines: [String] = []
        lines.append("UpstreamLens 诊断")
        lines.append("版本：\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        lines.append("系统：iOS \(UIDevice.current.systemVersion)")
        let authText = isAuthenticated ? "已登录" : "未登录"
        lines.append("GitHub 登录：\(authText)")
        lines.append("")
        lines.append("[存储] 可写：\(storageReady ? "是" : "否")；来源 \(data.sources.count) 个，记录 \(data.findings.count) 条")
        if let storageError { lines.append("存储错误：\(storageError)") }
        lines.append("")
        let granted = AppGroupResolver.grantedGroups(in: Diagnostics.provisionProfileData())
        lines.append("[App Group] 请求 ID：\(AppGroupResolver.requestedGroupID)")
        lines.append("profile 授权的组：\(granted.isEmpty ? "（未读取到）" : granted.joined(separator: "、"))")
        lines.append("实际使用组：\(WidgetSnapshotWriter.groupID)\(WidgetSnapshotWriter.groupID == AppGroupResolver.requestedGroupID ? "" : "（带团队前缀，已自动适配）")")
        let containerExists = Diagnostics.appGroupContainerExists(groupID: WidgetSnapshotWriter.groupID)
        lines.append("共享容器可获得：\(containerExists ? "是" : "否 ← entitlement 未生效")")
        let roundTrip = Diagnostics.appGroupRoundTrip(groupID: WidgetSnapshotWriter.groupID)
        lines.append("读写往返测试：\(roundTrip == nil ? "通过" : "失败（\(roundTrip!)")）")
        if let widgetError { lines.append("小组件错误：\(widgetError)") }
        lines.append("")
        lines.append("[签名证据]")
        if let profileData = Diagnostics.provisionProfileData() {
            let inProfile = Diagnostics.contains(profileData, needle: AppGroupResolver.requestedGroupID)
            lines.append("embedded.mobileprovision：存在；包含 App Group：\(inProfile ? "是" : "否 ← 签发 profile 时权限被丢弃")")
        } else {
            lines.append("embedded.mobileprovision：不存在（可能是未重签的开发包）")
        }
        if let executable = Diagnostics.executableData() {
            let inBinary = Diagnostics.contains(executable, needle: WidgetSnapshotWriter.groupID)
            lines.append("主程序内嵌 entitlements 含 App Group：\(inBinary ? "是" : "否 ← CI 打包时未内嵌")")
        } else {
            lines.append("主程序二进制：无法读取")
        }
        lines.append("")
        lines.append("[GitHub API 限额]")
        if let rateLimit {
            lines.append("剩余 \(rateLimit.remaining)/\(rateLimit.total == 0 ? 60 : rateLimit.total) 次，约 \(rateLimit.minutesUntilReset) 分钟后重置")
        } else {
            lines.append("本次启动尚未获得限额信息（完成一次检查后显示）")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 私有实现

    private static func sameTracking(_ left: WatchSource, _ right: WatchSource) -> Bool {
        left.repository == right.repository && left.kind == right.kind &&
        left.path == right.path && left.branch == right.branch
    }

    private func version(for id: UUID) -> RequestVersion {
        RequestVersion(data: dataEpoch, source: sourceEpochs[id, default: 0])
    }

    private func pruneHandledRecords() {
        let pruned = data.pruned(now: Date())
        guard pruned.findings.count != data.findings.count else { return }
        data = pruned
        persist()
    }

    @discardableResult private func persist() -> Error? {
        guard storageReady else { return StorageError.localDataUnavailable }
        let capped = data.capped()
        if capped.findings.count != data.findings.count { data = capped }
        do {
            try saveData(data)
            lastSavedData = data
            storageError = nil
            writeWidget()
            updateBadge(unreadRelevantCount)
            return nil
        } catch {
            data = lastSavedData
            updateBadge(lastSavedData.findings.filter(\.isUnreadRelevant).count)
            storageError = L10n.format(
                "Saving failed and the last saved data was restored: {detail}",
                ["detail": error.localizedDescription])
            return error
        }
    }

    private func writeWidget() {
        do { try publishSnapshot(data); widgetError = nil }
        catch { widgetError = error.localizedDescription }
    }
}
