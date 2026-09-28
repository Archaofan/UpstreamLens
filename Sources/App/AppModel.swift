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
    private let fetchChanges: (WatchSource) async throws -> GitHubFetch
    private let saveData: (LocalData) throws -> Void
    private let publishSnapshot: (LocalData) throws -> Void
    private let probeRepository: (String) async throws -> RepoProbe
    private let probePaths: (String, String) async throws -> TreeScan
    private let updateBadge: (Int) -> Void
    private var dataEpoch = 0
    private var sourceEpochs: [UUID: Int] = [:]
    private var inFlightVersions: [UUID: RequestVersion] = [:]
    private var storageReady = true
    private var lastSavedData = LocalData()

    init(initialData: LocalData? = nil,
         loadData: @escaping () throws -> LocalData = { try LocalStore.load() },
         fetchChanges: @escaping (WatchSource) async throws -> GitHubFetch = { try await GitHubClient().fetch(source: $0) },
         saveData: @escaping (LocalData) throws -> Void = { try LocalStore.save($0) },
         publishSnapshot: @escaping (LocalData) throws -> Void = { try WidgetSnapshotWriter.write(from: $0) },
         probeRepo: @escaping (String) async throws -> RepoProbe = { try await RepoProbing.probe($0) },
         probePaths: @escaping (String, String) async throws -> TreeScan = { try await RepoProbing.probePaths($0, branch: $1) },
         updateBadge: @escaping (Int) -> Void = { count in UIApplication.shared.applicationIconBadgeNumber = count }) {
        self.fetchChanges = fetchChanges
        self.saveData = saveData
        self.publishSnapshot = publishSnapshot
        self.probeRepository = probeRepo
        self.probePaths = probePaths
        self.updateBadge = updateBadge
        if let initialData {
            data = initialData
        } else {
            do { data = try loadData() }
            catch {
                data = LocalData()
                storageReady = false
                storageError = "无法读取本地数据，已暂停保存以保护原文件。请导入有效备份：\(error.localizedDescription)"
            }
        }
        lastSavedData = data
        if storageReady { writeWidget() }
        updateBadge(unreadRelevantCount)
    }

    var sources: [WatchSource] { data.sources }
    var findings: [Finding] { data.findings.sorted { $0.foundAt > $1.foundAt } }
    var lastSuccessfulCheck: Date? { data.lastSuccessfulCheck }
    var canEditData: Bool { storageReady }
    var unreadRelevantCount: Int { data.findings.filter(\.isUnreadRelevant).count }

    func source(for id: UUID) -> WatchSource? { data.sources.first { $0.id == id } }

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

    // MARK: - 添加来源的探测

    func probe(_ input: String) async throws -> RepoProbe {
        try await probeRepository(input)
    }

    func probePaths(repository: String, branch: String) async throws -> TreeScan {
        try await probePaths(repository, branch)
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
        lines.append("")
        lines.append("[存储] 可写：\(storageReady ? "是" : "否")；来源 \(data.sources.count) 个，记录 \(data.findings.count) 条")
        if let storageError { lines.append("存储错误：\(storageError)") }
        lines.append("")
        lines.append("[App Group] ID：\(WidgetSnapshotWriter.groupID)")
        let containerExists = Diagnostics.appGroupContainerExists(groupID: WidgetSnapshotWriter.groupID)
        lines.append("共享容器可获得：\(containerExists ? "是" : "否 ← entitlement 未生效")")
        let roundTrip = Diagnostics.appGroupRoundTrip(groupID: WidgetSnapshotWriter.groupID)
        lines.append("读写往返测试：\(roundTrip == nil ? "通过" : "失败（\(roundTrip!)")）")
        if let widgetError { lines.append("小组件错误：\(widgetError)") }
        lines.append("")
        lines.append("[签名证据]")
        if let profileData = Diagnostics.provisionProfileData() {
            let inProfile = Diagnostics.contains(profileData, needle: WidgetSnapshotWriter.groupID)
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
            storageError = "保存失败，已恢复上次保存的数据：\(error.localizedDescription)"
            return error
        }
    }

    private func writeWidget() {
        do { try publishSnapshot(data); widgetError = nil }
        catch { widgetError = error.localizedDescription }
    }
}
