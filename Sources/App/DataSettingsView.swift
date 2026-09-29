import SwiftUI

/// 数据与备份子页：导出/导入/清理、保留期，以及 AI 来源清单批量导入。
struct DataSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var backup: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: PendingImport?
    @State private var dialogError: String?
    @State private var confirmClearHandled = false
    @State private var showAiPrompt = false
    @State private var showSourceListImporter = false
    @State private var pendingSourceList: PendingSourceListImport?
    @State private var importResultMessage: String?
    @State private var cacheBytes = 0
    @State private var showClearCacheDialog = false
    @State private var cacheResultMessage: String?

    private struct PendingImport: Identifiable {
        let data: Data
        let sourceCount: Int
        let findingCount: Int
        var id: String { "\(sourceCount)-\(findingCount)" }
    }

    private struct PendingSourceListImport: Identifiable {
        let sources: [WatchSource]
        let warnings: [String]
        var id: Int { sources.count }
    }

    var body: some View {
        Form {
            dataSection
            cacheSection
            helpSection
        }
        .transparentListBackground()
        .navigationTitle("Data & Backup")
        .onAppear { cacheBytes = AvatarCache.totalBytes() }
        .fileExporter(isPresented: $showExporter, document: backup, contentType: .json,
                      defaultFilename: "UpstreamLens-backup") { result in
            if case .failure(let error) = result { dialogError = error.localizedDescription }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fileImporter(isPresented: $showSourceListImporter, allowedContentTypes: [.json]) { result in
            handleSourceListImport(result)
        }
        .sheet(isPresented: $showAiPrompt) {
            CopyableTextSheet(
                title: "AI Search Prompt",
                text: SourceListImport.prompt,
                footnote: "Copy this to an AI that can access your machine (e.g. an Agent CLI or IDE assistant); save the JSON it returns as a .json file, then use “Import AI Source List” to add it to monitoring.")
        }
        .confirmationDialog("Replace existing data?", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } })) {
            Button("Replace Existing Data", role: .destructive) {
                guard let pendingImport else { return }
                do { try model.importData(pendingImport.data) }
                catch { dialogError = AppLocalization.string("Import failed") + ": \(error.localizedDescription)" }
                self.pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            if let pending = pendingImport {
                Text("The backup contains \(pending.sourceCount) sources and \(pending.findingCount) records; importing will replace your current \(model.sources.count) sources.")
            }
        }
        .confirmationDialog("Merge import source list?", isPresented: Binding(
            get: { pendingSourceList != nil },
            set: { if !$0 { pendingSourceList = nil } })) {
            Button("Merge Import") {
                guard let pending = pendingSourceList else { return }
                let result = model.mergeSourceList(pending.sources)
                var lines = [String(format: AppLocalization.string("Added %lld sources, skipped %lld duplicates."), result.added, result.skipped)]
                lines.append(contentsOf: pending.warnings)
                importResultMessage = lines.joined(separator: "\n")
                self.pendingSourceList = nil
                Task { await model.refreshAll() }
            }
            Button("Cancel", role: .cancel) { pendingSourceList = nil }
        } message: {
            if let pending = pendingSourceList {
                Text("The list contains \(pending.sources.count) sources and will be merged into your current \(model.sources.count): existing sources are not modified or deleted, and duplicate repos are skipped automatically. A check runs right after import.")
            }
        }
        .alert("Import Complete", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } })) {
            Button("OK", role: .cancel) { importResultMessage = nil }
        } message: { Text(importResultMessage ?? "") }
        .alert("Clear handled records?", isPresented: $confirmClearHandled) {
            Button("Clear", role: .destructive) { model.clearHandledRecords() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Handled records will be permanently deleted. To keep them, export a JSON backup first.")
        }
        .confirmationDialog("Clear icon cache?", isPresented: $showClearCacheDialog) {
            Button("Clear All (including existing sources' avatars)") {
                clearCache(keepExistingSources: false)
            }
            Button("Keep existing sources' avatars, clear the rest") {
                clearCache(keepExistingSources: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only locally cached repository avatar images are deleted. Sources, settings, change records, and backups are never touched. Avatars you keep re-download the next time you view them.")
        }
        .alert("Icon Cache", isPresented: Binding(
            get: { cacheResultMessage != nil },
            set: { if !$0 { cacheResultMessage = nil } })) {
            Button("OK", role: .cancel) { cacheResultMessage = nil }
        } message: { Text(cacheResultMessage ?? "") }
        .alert("Action Failed", isPresented: Binding(get: { dialogError != nil }, set: { if !$0 { dialogError = nil } })) {
            Button("OK", role: .cancel) { dialogError = nil }
        } message: { Text(dialogError ?? "") }
    }

    private var dataSection: some View {
        Section {
            Button {
                do { backup = BackupDocument(data: try model.exportData()); showExporter = true }
                catch { dialogError = error.localizedDescription }
            } label: {
                Label("Export JSON Backup", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("Import JSON Backup (replace existing data)", systemImage: "square.and.arrow.down")
            }
            Toggle(isOn: Binding(
                get: { (model.retentionDays ?? 0) > 0 },
                set: { model.setRetentionDays($0 ? 90 : 0) })) {
                Label("Auto-clear handled records older than 90 days", systemImage: "clock.arrow.circlepath")
            }
            let handledCount = model.findings.filter { $0.status == .handled }.count
            Button(role: .destructive) {
                confirmClearHandled = true
            } label: {
                Label(handledCount == 0 ? "No handled records" : "Clear handled records now (\(handledCount))",
                      systemImage: "trash")
            }
            .disabled(handledCount == 0 || !model.canEditData)
        } header: {
            Text("Data")
        } footer: {
            Text("Exported backups include personal usage info; importing replaces all existing data.")
        }
    }

    private var cacheSection: some View {
        Section {
            LabeledContent("Icon Cache Size",
                           value: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
            Button(role: .destructive) {
                showClearCacheDialog = true
            } label: {
                Label("Clear Icon Cache", systemImage: "photo.stack")
            }
        } header: {
            Text("Icon Cache")
        } footer: {
            Text("Repository avatars are cached on disk so lists stay fast. Clearing only deletes these cached images: sources, settings, change records, and backups are never touched.")
        }
    }

    /// 清除图标缓存。只删头像图片，绝不触碰来源、配置、变化记录与备份。
    private func clearCache(keepExistingSources: Bool) {
        let owners = Set(model.sources.compactMap { RepoAvatar.owner(of: $0.repository) })
        let freed = AvatarCache.clear(keepExistingSources: keepExistingSources, currentOwners: owners)
        cacheBytes = AvatarCache.totalBytes()
        let size = ByteCountFormatter.string(fromByteCount: Int64(freed), countStyle: .file)
        cacheResultMessage = AppLocalization.string("Icon cache cleared") + " " + size
    }

    private var helpSection: some View {
        Section {
            Button {
                showAiPrompt = true
            } label: {
                Label("AI Search Prompt (one-tap copy)", systemImage: "doc.text.viewfinder")
            }
            Button {
                showSourceListImporter = true
            } label: {
                Label("Import AI Source List (merge into existing sources)", systemImage: "sparkles.rectangle.stack")
            }
        } header: {
            Text("Help · Batch-add sources with AI")
        } footer: {
            Text("Copy the prompt to an AI that can access your machine; it searches the open-source projects you use and outputs a JSON list. Save the list as a .json file and import it here; the app merges new sources and checks immediately. Existing sources are never overwritten or modified.")
        }
    }

    private func handleSourceListImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bytes = try Data(contentsOf: url)
            let parsed = try SourceListImport.parse(bytes)
            pendingSourceList = PendingSourceListImport(sources: parsed.sources, warnings: parsed.warnings)
        } catch {
            dialogError = AppLocalization.string("Source list import failed") + ": \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bytes = try Data(contentsOf: url)
            let imported = try LocalStore.importData(bytes)
            pendingImport = PendingImport(data: bytes, sourceCount: imported.sources.count,
                                          findingCount: imported.findings.count)
        } catch {
            dialogError = AppLocalization.string("Import failed") + ": \(error.localizedDescription)"
        }
    }
}
