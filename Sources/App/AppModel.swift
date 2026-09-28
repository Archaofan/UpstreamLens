import Foundation
import Combine

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
    private let fetchChanges: (WatchSource) async throws -> GitHubFetch
    private let saveData: (LocalData) throws -> Void
    private let publishSnapshot: (LocalData) throws -> Void
    private var dataEpoch = 0
    private var sourceEpochs: [UUID: Int] = [:]
    private var inFlightVersions: [UUID: RequestVersion] = [:]
    private var storageReady = true
    private var lastSavedData = LocalData()

    init(initialData: LocalData? = nil,
         loadData: @escaping () throws -> LocalData = { try LocalStore.load() },
         fetchChanges: @escaping (WatchSource) async throws -> GitHubFetch = { try await GitHubClient().fetch(source: $0) },
         saveData: @escaping (LocalData) throws -> Void = { try LocalStore.save($0) },
         publishSnapshot: @escaping (LocalData) throws -> Void = { try WidgetSnapshotWriter.write(from: $0) }) {
        self.fetchChanges = fetchChanges
        self.saveData = saveData
        self.publishSnapshot = publishSnapshot
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
    }

    var sources: [WatchSource] { data.sources }
    var findings: [Finding] { data.findings.sorted { $0.foundAt > $1.foundAt } }
    var lastSuccessfulCheck: Date? { data.lastSuccessfulCheck }
    var canEditData: Bool { storageReady }

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

    func setStatus(_ status: FindingStatus, for id: UUID) {
        guard storageReady else { return }
        guard let index = data.findings.firstIndex(where: { $0.id == id }) else { return }
        data.findings[index].status = status
        persist()
    }

    func refreshAll() async {
        guard storageReady, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for source in data.sources where !source.isPaused {
            await refresh(source.id)
        }
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
        } catch {
            guard requestVersion == version(for: id),
                  let index = data.sources.firstIndex(where: { $0.id == id }),
                  Self.sameTracking(data.sources[index], requested) else { return }
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

    func exportData() throws -> Data {
        guard storageReady else { throw StorageError.localDataUnavailable }
        return try LocalStore.export(data)
    }

    func importData(_ bytes: Data) throws {
        let imported = try LocalStore.importData(bytes)
        dataEpoch += 1
        data = imported
        let wasReady = storageReady
        storageReady = true
        if let error = persist() {
            storageReady = wasReady
            throw error
        }
    }

    private static func sameTracking(_ left: WatchSource, _ right: WatchSource) -> Bool {
        left.repository == right.repository && left.kind == right.kind &&
        left.path == right.path && left.branch == right.branch
    }

    private func version(for id: UUID) -> RequestVersion {
        RequestVersion(data: dataEpoch, source: sourceEpochs[id, default: 0])
    }

    @discardableResult private func persist() -> Error? {
        guard storageReady else { return StorageError.localDataUnavailable }
        do {
            try saveData(data)
            lastSavedData = data
            storageError = nil
            writeWidget()
            return nil
        } catch {
            data = lastSavedData
            storageError = "保存失败，已恢复上次保存的数据：\(error.localizedDescription)"
            return error
        }
    }

    private func writeWidget() {
        do { try publishSnapshot(data); widgetError = nil }
        catch { widgetError = error.localizedDescription }
    }
}
