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

    var body: some View {
        NavigationStack {
            List {
                Section("监控状态") {
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

                Section("待查看变化") {
                    let pending = model.findings.filter { $0.status == .unread }
                    if pending.isEmpty {
                        Text("暂无待查看变化").foregroundStyle(.secondary)
                    }
                    ForEach(pending) { finding in
                        NavigationLink {
                            FindingDetailView(model: model, id: finding.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(finding.title).font(.headline)
                                Text(finding.relevance.rawValue).font(.caption).foregroundStyle(finding.relevance == .important ? .orange : .secondary)
                                Text(finding.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }

                Section("来源") {
                    if model.sources.isEmpty { Text("点击右上角 + 添加 GitHub 来源").foregroundStyle(.secondary) }
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

struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: WatchSource
    let onSave: (WatchSource) -> Void
    @State private var error: String?

    init(source: WatchSource, onSave: @escaping (WatchSource) -> Void) {
        _source = State(initialValue: source)
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
                }
                Section("我的使用情况（仅保存在本机）") {
                    TextField("显示名称", text: $source.displayName)
                    TextField("用途", text: $source.purpose)
                    TextField("正在使用的版本／Tag／提交", text: $source.installedVersion)
                    TextField("关键词，逗号分隔", text: $source.keywords)
                    TextField("采用理由", text: $source.rationale, axis: .vertical)
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
                    Text(finding.reason)
                    LabeledContent("上游标识", value: finding.upstreamID)
                    LabeledContent("发现时间") { Text(finding.foundAt, style: .date) }
                }
                Section("变化内容") { Text(finding.body.isEmpty ? "上游未提供说明。" : finding.body).textSelection(.enabled) }
                Section("操作") {
                    if let url = URL(string: finding.url) { Link("查看 GitHub 原文", destination: url) }
                    Picker("状态", selection: Binding(get: { finding.status }, set: { model.setStatus($0, for: id) })) {
                        ForEach(FindingStatus.allCases, id: \.self) { status in Text(status.rawValue).tag(status) }
                    }
                }
            }
        }
        .navigationTitle("变化详情")
        .onAppear { if model.findings.first(where: { $0.id == id })?.status == .unread { model.setStatus(.viewed, for: id) } }
    }
}
