import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var editorSource: WatchSource?
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var backup: BackupDocument?
    @State private var dialogError: String?
    @State private var importantOnly = false

    var body: some View {
        NavigationStack {
            List {
                Section("监控状态") {
                    let pendingCount = FindingQueue.pending(model.findings).count
                    let unreadCount = model.findings.filter { $0.status == .unread }.count
                    if !model.sources.isEmpty {
                        LabeledContent("待处理变化", value: "\(pendingCount) 条（\(unreadCount) 条未读）")
                    }
                    if let date = model.lastSuccessfulCheck {
                        LabeledContent("上次成功检查") { Text(date, style: .relative) }
                    } else {
                        Text("尚未完成检查。首次添加来源时会建立当前基线。")
                            .foregroundStyle(.secondary)
                    }
                    if let error = model.storageError { Label(error, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.red) }
                    if let error = model.widgetError { Label(error, systemImage: "square.on.square.dashed").foregroundStyle(.orange) }
                    Button {
                        Task { await model.refreshAll() }
                    } label: {
                        Label(model.isRefreshing ? "正在检查…" : "手动刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing || model.sources.isEmpty)
                }

                Section("待处理变化") {
                    let pending = FindingQueue.pending(model.findings, importantOnly: importantOnly)
                    if !FindingQueue.pending(model.findings).isEmpty {
                        Picker("筛选变化", selection: $importantOnly) {
                            Text("全部").tag(false)
                            Text("值得关注").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    if pending.isEmpty {
                        if importantOnly && !FindingQueue.pending(model.findings).isEmpty {
                            Text("暂无值得关注的待处理变化。可切回“全部”查看其他更新。")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("暂无待处理变化。查看过的变化会留在这里，直到你标为已处理。")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(pending) { finding in
                        NavigationLink {
                            FindingDetailView(model: model, id: finding.id)
                        } label: {
                            FindingRowView(finding: finding, sourceTitle: model.source(for: finding.sourceID)?.title ?? "来源")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                model.setStatus(.handled, for: finding.id)
                            } label: {
                                Label("已处理", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                    let completedCount = FindingQueue.completed(model.findings).count
                    if completedCount > 0 {
                        NavigationLink("查看已处理记录（\(completedCount)）") {
                            CompletedFindingsView(model: model)
                        }
                    }
                }

                Section("来源") {
                    if model.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("从一个公开 GitHub 仓库或 Skill 路径开始。首次成功检查只建立当前基线。")
                                .foregroundStyle(.secondary)
                            Button("添加来源") { editorSource = WatchSource() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                    ForEach(model.sources) { source in
                        NavigationLink {
                            SourceDetailView(model: model, id: source.id, edit: { editorSource = $0 })
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(source.title).font(.headline)
                                    if source.isPaused { Text("已暂停").font(.caption).foregroundStyle(.secondary) }
                                }
                                Text("\(source.repository) · \(source.kind.rawValue)").font(.caption).foregroundStyle(.secondary)
                                if let date = source.lastCheckedAt {
                                    HStack(spacing: 4) {
                                        Text("上次成功检查")
                                        Text(date, style: .relative)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                } else {
                                    Text("等待首次成功检查").font(.caption).foregroundStyle(.secondary)
                                }
                                if let error = source.lastError { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("UpstreamLens")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editorSource = WatchSource() } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("导出 JSON") {
                            do { backup = BackupDocument(data: try model.exportData()); showExporter = true }
                            catch { dialogError = error.localizedDescription }
                        }
                        Button("导入 JSON") { showImporter = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $editorSource) { source in
                SourceEditorView(source: source) { saved in
                    model.upsert(saved)
                    Task { await model.refresh(saved.id) }
                }
            }
            .fileExporter(isPresented: $showExporter, document: backup, contentType: .json, defaultFilename: "UpstreamLens-backup") { result in
                if case .failure(let error) = result { dialogError = error.localizedDescription }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try model.importData(Data(contentsOf: url))
                } catch { dialogError = "导入失败：\(error.localizedDescription)" }
            }
            .alert("操作失败", isPresented: Binding(get: { dialogError != nil }, set: { if !$0 { dialogError = nil } })) {
                Button("确定", role: .cancel) { dialogError = nil }
            } message: { Text(dialogError ?? "") }
            .task { await model.refreshAll() }
        }
    }
}

private struct FindingRowView: View {
    let finding: Finding
    let sourceTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(finding.title).font(.headline).lineLimit(2)
                Spacer(minLength: 4)
                if finding.status == .unread {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .accessibilityLabel("未读")
                }
            }
            Text(sourceTitle).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(finding.relevance.rawValue)
                    .foregroundStyle(finding.relevance == .important ? Color.orange : Color.secondary)
                Text(finding.status.rawValue).foregroundStyle(.secondary)
            }
            .font(.caption.bold())
            Text(finding.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

private struct CompletedFindingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List(FindingQueue.completed(model.findings)) { finding in
            NavigationLink {
                FindingDetailView(model: model, id: finding.id)
            } label: {
                FindingRowView(finding: finding, sourceTitle: model.source(for: finding.sourceID)?.title ?? "来源")
            }
        }
        .navigationTitle("已处理记录")
    }
}

struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: WatchSource
    let onSave: (WatchSource) -> Void
    @State private var error: String?
    @State private var showMoreContext: Bool

    init(source: WatchSource, onSave: @escaping (WatchSource) -> Void) {
        _source = State(initialValue: source)
        _showMoreContext = State(initialValue: !source.installedVersion.isEmpty || !source.keywords.isEmpty || !source.rationale.isEmpty)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub 来源") {
                    Picker("模式", selection: $source.kind) {
                        ForEach(SourceKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                    }
                    TextField("owner/repo 或仓库链接", text: $source.repository)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if source.kind == .path {
                        TextField("路径，如 skills/example/SKILL.md", text: $source.path)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("分支（留空使用默认分支）", text: $source.branch)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Text("首次成功检查只建立基线，不会把旧版本当成新变化。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("我的使用情况（仅保存在本机）") {
                    TextField("显示名称", text: $source.displayName)
                    TextField("用途，例如 NAS 远程连接", text: $source.purpose)
                    DisclosureGroup("更多个人信息（可选）", isExpanded: $showMoreContext) {
                        TextField("正在使用的版本／Tag／提交", text: $source.installedVersion)
                        TextField("关注关键词，逗号分隔", text: $source.keywords)
                        TextField("采用理由", text: $source.rationale, axis: .vertical)
                    }
                }
                Toggle("暂停监控", isOn: $source.isPaused)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("来源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            source.repository = try GitHubClient.normalizedRepository(source.repository)
                            source.path = source.path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                            if source.kind == .path && source.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                error = "请填写要监控的文件或目录路径。"; return
                            }
                            onSave(source)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}

struct SourceDetailView: View {
    @ObservedObject var model: AppModel
    let id: UUID
    let edit: (WatchSource) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let source = model.source(for: id) {
                Section("来源") {
                    LabeledContent("仓库", value: source.repository)
                    LabeledContent("模式", value: source.kind.rawValue)
                    if source.kind == .path { LabeledContent("路径", value: source.path) }
                    if !source.purpose.isEmpty { LabeledContent("用途", value: source.purpose) }
                    if !source.installedVersion.isEmpty { LabeledContent("使用版本", value: source.installedVersion) }
                    if let date = source.lastCheckedAt { LabeledContent("上次检查") { Text(date, style: .relative) } }
                    if let error = source.lastError { Text(error).foregroundStyle(.red) }
                }
                Section("变化") {
                    let findings = model.findings.filter { $0.sourceID == id }
                    if findings.isEmpty { Text("暂无新变化；首次检查只建立基线。").foregroundStyle(.secondary) }
                    ForEach(findings) { finding in
                        NavigationLink(finding.title) { FindingDetailView(model: model, id: finding.id) }
                    }
                }
                Section {
                    Button("检查此来源") { Task { await model.refresh(id) } }
                    if source.lastError == ChangeDetector.missingBaselineMessage {
                        Button("重建当前基线") {
                            model.resetBaseline(for: id)
                            Task { await model.refresh(id) }
                        }
                    }
                    Button("编辑") { edit(source) }
                    Button("删除来源", role: .destructive) { model.delete(source); dismiss() }
                }
            }
        }
        .navigationTitle(model.source(for: id)?.title ?? "来源")
    }
}

struct FindingDetailView: View {
    @ObservedObject var model: AppModel
    let id: UUID

    var body: some View {
        List {
            if let finding = model.findings.first(where: { $0.id == id }) {
                Section("判断") {
                    LabeledContent("相关性", value: finding.relevance.rawValue)
                    LabeledContent("状态", value: finding.status.rawValue)
                    if let source = model.source(for: finding.sourceID) {
                        LabeledContent("来源", value: source.title)
                    }
                    Text(finding.reason)
                    LabeledContent("上游标识", value: finding.upstreamID)
                    LabeledContent("发现时间") { Text(finding.foundAt, style: .date) }
                }
                Section("变化内容") { Text(finding.body.isEmpty ? "上游未提供说明。" : finding.body).textSelection(.enabled) }
                Section("操作") {
                    if let url = URL(string: finding.url) { Link("查看 GitHub 原文", destination: url) }
                    if finding.status == .handled {
                        Button("重新加入待处理") { model.setStatus(.viewed, for: id) }
                    } else {
                        Button {
                            model.setStatus(.handled, for: id)
                        } label: {
                            Label("标为已处理", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        if finding.status == .viewed {
                            Button("标为未读") { model.setStatus(.unread, for: id) }
                        }
                    }
                }
            }
        }
        .navigationTitle("变化详情")
        .onAppear { if model.findings.first(where: { $0.id == id })?.status == .unread { model.setStatus(.viewed, for: id) } }
    }
}
