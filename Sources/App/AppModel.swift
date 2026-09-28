import Foundation
import Combine

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var data: LocalData
    @Published var isRefreshing = false
    @Published var storageError: String?
    @Published var widgetError: String?
    private let client = GitHubClient()

    init() {
        do { data = try LocalStore.load() }
        catch {
            data = LocalData()
            storageError = "无法读取本地数据：\(error.localizedDescription)"
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
            if previous.repository != source.repository || previous.kind != source.kind || previous.path != source.path || previous.branch != source.branch {
                updated.baselineIdentifier = nil
                updated.baselineContent = nil
                updated.etag = nil
                data.findings.removeAll { $0.sourceID == source.id }
            } else {
                updated.baselineIdentifier = previous.baselineIdentifier
                updated.baselineContent = previous.baselineContent
                updated.etag = previous.etag
                updated.lastCheckedAt = previous.lastCheckedAt
                updated.lastError = previous.lastError
            }
            data.sources[index] = updated
        } else {
            data.sources.append(source)
        }
        persist()
    }

    func delete(_ source: WatchSource) {
        data.sources.removeAll { $0.id == source.id }
        data.findings.removeAll { $0.sourceID == source.id }
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
        guard let index = data.sources.firstIndex(where: { $0.id == id }), !data.sources[index].isPaused else { return }
        var source = data.sources[index]
        do {
            let fetched = try await client.fetch(source: source)
            let now = Date()
            if !fetched.unchanged {
                let additions = ChangeDetector.apply(fetched.changes, to: &source, existing: data.findings, now: now)
                data.findings.append(contentsOf: additions)
                source.etag = fetched.etag
            } else {
                source.lastCheckedAt = now
                source.lastError = nil
            }
            data.lastSuccessfulCheck = now
        } catch {
            source.lastError = error.localizedDescription
        }
        data.sources[index] = source
        persist()
    }

    func exportData() throws -> Data { try LocalStore.export(data) }

    func importData(_ bytes: Data) throws {
        let imported = try LocalStore.importData(bytes)
        data = imported
        persist()
    }

    private func persist() {
        do { try LocalStore.save(data); storageError = nil }
        catch { storageError = "保存失败：\(error.localizedDescription)" }
        writeWidget()
    }

    private func writeWidget() {
        do { try WidgetSnapshotWriter.write(from: data); widgetError = nil }
        catch { widgetError = error.localizedDescription }
    }
}
