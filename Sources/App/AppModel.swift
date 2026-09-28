import Foundation
import Combine

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var data: LocalData
    @Published var isRefreshing = false
    @Published var storageError: String?
    @Published var widgetError: String?
    private let fetchChanges: (WatchSource) async throws -> GitHubFetch
    private let saveData: (LocalData) throws -> Void
    private let publishSnapshot: (LocalData) throws -> Void
    private var storageEpoch = 0

    init(initialData: LocalData? = nil,
         fetchChanges: @escaping (WatchSource) async throws -> GitHubFetch = { try await GitHubClient().fetch(source: $0) },
         saveData: @escaping (LocalData) throws -> Void = { try LocalStore.save($0) },
         publishSnapshot: @escaping (LocalData) throws -> Void = { try WidgetSnapshotWriter.write(from: $0) }) {
        self.fetchChanges = fetchChanges
        self.saveData = saveData
        self.publishSnapshot = publishSnapshot
        if let initialData {
            data = initialData
        } else {
            do { data = try LocalStore.load() }
            catch {
                data = LocalData()
                storageError = "无法读取本地数据：\(error.localizedDescription)"
            }
        }
        writeWidget()
    }

    var sources: [WatchSource] { data.sources }
    var findings: [Finding] { data.findings.sorted { $0.foundAt > $1.foundAt } }
    var lastSuccessfulCheck: Date? { data.lastSuccessfulCheck }

    func source(for id: UUID) -> WatchSource? { data.sources.first { $0.id == id } }

    func upsert(_ source: WatchSource) {
        if let index = data.sources.firstIndex(where: { $0.id == source.id }) {
            var updated = source
            let previous = data.sources[index]
            let trackingChanged = previous.repository != source.repository || previous.kind != source.kind ||
                previous.path != source.path || previous.branch != source.branch
            if trackingChanged {
                storageEpoch += 1
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
        storageEpoch += 1
        data.sources.removeAll { $0.id == source.id }
        data.findings.removeAll { $0.sourceID == source.id }
        data.lastSuccessfulCheck = data.sources.compactMap(\.lastCheckedAt).max()
        persist()
    }

    func setStatus(_ status: FindingStatus, for id: UUID) {
        guard let index = data.findings.firstIndex(where: { $0.id == id }) else { return }
        data.findings[index].status = status
        persist()
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for source in data.sources where !source.isPaused {
            await refresh(source.id)
        }
    }

    func refresh(_ id: UUID) async {
        guard let requested = source(for: id), !requested.isPaused else { return }
        let requestEpoch = storageEpoch
        do {
            let fetched = try await fetchChanges(requested)
            guard requestEpoch == storageEpoch,
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
            guard requestEpoch == storageEpoch,
                  let index = data.sources.firstIndex(where: { $0.id == id }),
                  Self.sameTracking(data.sources[index], requested) else { return }
            data.sources[index].lastError = error.localizedDescription
        }
        persist()
    }

    func resetBaseline(for id: UUID) {
        guard let index = data.sources.firstIndex(where: { $0.id == id }) else { return }
        storageEpoch += 1
        data.sources[index].baselineIdentifier = nil
        data.sources[index].baselineContent = nil
        data.sources[index].etag = nil
        data.sources[index].lastError = nil
        persist()
    }

    func exportData() throws -> Data { try LocalStore.export(data) }

    func importData(_ bytes: Data) throws {
        let imported = try LocalStore.importData(bytes)
        storageEpoch += 1
        data = imported
        persist()
    }

    private static func sameTracking(_ left: WatchSource, _ right: WatchSource) -> Bool {
        left.repository == right.repository && left.kind == right.kind &&
        left.path == right.path && left.branch == right.branch
    }

    private func persist() {
        do { try saveData(data); storageError = nil }
        catch { storageError = "保存失败：\(error.localizedDescription)" }
        writeWidget()
    }

    private func writeWidget() {
        do { try publishSnapshot(data); widgetError = nil }
        catch { widgetError = error.localizedDescription }
    }
}
