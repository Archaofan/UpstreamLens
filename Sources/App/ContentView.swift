import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct FindingRoute: Hashable {
    let id: UUID
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorSource: WatchSource?
    @State private var showAddFlow = false
    @State private var showSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var showClipboardBanner = false
    @State private var dialogError: String?
    @State private var importantOnly = false
    @State private var pendingClipboardAdd: ClipboardAdd?
    @AppStorage("clipboardChangeCountSeen") private var clipboardChangeCountSeen = 0

    private struct ClipboardAdd: Identifiable {
        let text: String
        var id: String { text }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if showClipboardBanner {
                    clipboardBannerSection
                }
                SummarySectionView(model: model)
                StorageErrorSectionView(error: model.storageError)
                PendingSectionView(model: model, importantOnly: $importantOnly)
                SourcesSectionView(model: model, editorSource: $editorSource,
                                   addTapped: { showAddFlow = true })
                WidgetStatusSectionView(error: model.widgetError)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .refreshable { await model.refreshAll() }
            .navigationTitle("UpstreamLens")
            .navigationDestination(for: FindingRoute.self) { route in
                FindingDetailView(model: model, id: route.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddFlow = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加来源")
                        .disabled(!model.canEditData)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            model.markAllRead()
                        } label: {
                            Label("全部标为已读", systemImage: "envelope.open")
                        }
                        .disabled(!model.findings.contains { $0.status == .unread })
                        Button {
                            showSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("更多操作")
                }
            }
            .sheet(item: $editorSource) { source in
                SourceEditorView(source: source) { saved in
                    model.upsert(saved)
                    Task { await model.refresh(saved.id) }
                }
            }
            .sheet(isPresented: $showAddFlow) {
                AddSourceView(model: model, onSaved: {})
            }
            .sheet(item: $pendingClipboardAdd) { payload in
                NavigationStack {
                    RepoConfirmView(model: model, input: payload.text) {}
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(model: model)
            }
            .alert("操作失败", isPresented: Binding(get: { dialogError != nil }, set: { if !$0 { dialogError = nil } })) {
                Button("确定", role: .cancel) { dialogError = nil }
            } message: { Text(dialogError ?? "") }
            .onOpenURL { url in handleDeepLink(url) }
            .task { await model.refreshAll() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                detectClipboardGitHubLink()
            }
        }
    }

    // MARK: - 剪贴板检测（只检测模式，不自动读取内容）

    private var clipboardBannerSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.tint)
                Text("剪贴板里可能有 GitHub 链接")
                    .font(.subheadline)
                Spacer()
                Button("添加") {
                    let changeCount = UIPasteboard.general.changeCount
                    clipboardChangeCountSeen = changeCount
                    showClipboardBanner = false
                    guard let text = UIPasteboard.general.string,
                          ParsedGitHubURL.parse(text) != nil else {
                        dialogError = "剪贴板内容无法识别为 GitHub 仓库链接。"
                        return
                    }
                    pendingClipboardAdd = ClipboardAdd(text: text)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button {
                    clipboardChangeCountSeen = UIPasteboard.general.changeCount
                    showClipboardBanner = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("忽略")
            }
            .font(.subheadline)
        }
    }

    @State private var pendingClipboardAdd: String?

    /// iOS 会把“读剪贴板”变成系统弹窗；这里先用 detectPatterns 只判断模式，不触发弹窗。
    private func detectClipboardGitHubLink() {
        let changeCount = UIPasteboard.general.changeCount
        guard changeCount != clipboardChangeCountSeen else { return }
        UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
            guard UIPasteboard.general.changeCount == changeCount else { return }
            if case .success(let patterns) = result, patterns.contains(.probableWebURL) {
                showClipboardBanner = true
            }
        }
    }

    // MARK: - 深链接

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "upstreamlens" else { return }
        switch url.host {
        case "findings":
            navigationPath = []
            let pending = FindingQueue.pending(model.findings, importantOnly: true)
            let top = pending.first ?? FindingQueue.pending(model.findings).first
            if let top {
                navigationPath.append(FindingRoute(id: top.id))
            }
        case "add":
            showAddFlow = true
        default:
            break
        }
    }
}

private struct StorageErrorSectionView: View {
    let error: String?

    var body: some View {
        if let error {
            Section {
                Label(error, systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct WidgetStatusSectionView: View {
    let error: String?

    var body: some View {
        if let error {
            Section {
                Label("小组件暂不可用", systemImage: "square.on.square.dashed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("小组件")
            } footer: {
                Text("可在“设置 → 诊断”生成详细信息并发给开发者。")
            }
        }
    }
}

private struct SummarySectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section {
            StatusSummaryView(pendingCount: FindingQueue.pending(model.findings).count,
                              unreadCount: model.findings.filter { $0.status == .unread }.count,
                              sourceCount: model.sources.count, lastCheck: model.lastSuccessfulCheck,
                              isRefreshing: model.isRefreshing) {
                Task { await model.refreshAll() }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

private struct PendingSectionView: View {
    @ObservedObject var model: AppModel
    @Binding var importantOnly: Bool

    var body: some View {
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
                    Label("暂无重点变化；可切回“全部”查看", systemImage: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label(model.sources.isEmpty ? "添加来源后，新变化会显示在这里" : "目前没有待处理变化",
                          systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(pending) { finding in
                PendingFindingRowView(model: model, finding: finding)
            }
            let completedCount = FindingQueue.completed(model.findings).count
            if completedCount > 0 {
                NavigationLink("查看已处理记录（\(completedCount)）") {
                    CompletedFindingsView(model: model)
                }
            }
        }
    }
}

private struct SourcesSectionView: View {
    @ObservedObject var model: AppModel
    @Binding var editorSource: WatchSource?
    let addTapped: () -> Void

    var body: some View {
        Section("来源") {
            if model.sources.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if model.canEditData {
                        Label("添加第一个监控来源", systemImage: "plus.circle.fill")
                            .font(.headline)
                        Text("搜索仓库名或粘贴 GitHub 链接即可；首次成功检查会建立当前基线。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("添加来源", action: addTapped)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    } else {
                        Label("请先恢复本地数据", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.headline)
                        Text("请在“设置 → 数据”中导入有效的 JSON 备份，再添加来源。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            ForEach(model.sources) { source in
                NavigationLink {
                    SourceDetailView(model: model, id: source.id, edit: { editorSource = $0 })
                } label: {
                    SourceRowView(source: source, isRefreshing: model.refreshingSourceIDs.contains(source.id))
                }
            }
        }
    }
}

private struct PendingFindingRowView: View {
    @ObservedObject var model: AppModel
    let finding: Finding

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink {
                FindingDetailView(model: model, id: finding.id)
            } label: {
                FindingRowView(finding: finding, sourceTitle: model.source(for: finding.sourceID)?.title ?? "来源")
            }
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.snappy) { model.setStatus(.handled, for: finding.id) }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("标为已处理")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.snappy) { model.setStatus(.handled, for: finding.id) }
            } label: {
                Label("已处理", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .leading) {
            if finding.status == .unread {
                Button {
                    withAnimation(.snappy) { model.setStatus(.viewed, for: finding.id) }
                } label: {
                    Label("已读", systemImage: "envelope.open")
                }
                .tint(.blue)
            } else {
                Button {
                    withAnimation(.snappy) { model.setStatus(.unread, for: finding.id) }
                } label: {
                    Label("未读", systemImage: "envelope.badge")
                }
                .tint(.indigo)
            }
        }
    }
}

private struct StatusSummaryView: View {
    let pendingCount: Int
    let unreadCount: Int
    let sourceCount: Int
    let lastCheck: Date?
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("待处理变化")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(pendingCount)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text(unreadCount == 0 ? "没有未读变化" : "其中 \(unreadCount) 条未读")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: pendingCount == 0 ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
            }
            Divider()
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(sourceCount) 个来源")
                        .font(.subheadline.weight(.medium))
                    if let lastCheck {
                        Text("上次检查：\(lastCheck, style: .relative)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("等待首次成功检查")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Button(action: refresh) {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isRefreshing || sourceCount == 0)
                .accessibilityLabel(isRefreshing ? "正在检查" : "手动刷新")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}

private struct SourceRowView: View {
    let source: WatchSource
    let isRefreshing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: source.kind == .path ? "doc.text" : source.kind == .tag ? "tag" : "shippingbox")
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(source.title).font(.headline)
                    if source.isPaused { Text("已暂停").font(.caption).foregroundStyle(.secondary) }
                }
                Text("\(source.repository) · \(source.kind.rawValue)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
                if isRefreshing {
                    Label("正在检查", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let error = source.lastError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if let date = source.lastCheckedAt {
                    Text("上次成功检查：\(date, style: .relative)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("等待首次成功检查")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FindingRowView: View {
    let finding: Finding
    let sourceTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: finding.relevance == .important ? "sparkles" : "circle.grid.2x2")
                .font(.headline)
                .foregroundStyle(finding.relevance == .important ? Color.orange : Color.accentColor)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(finding.title).font(.headline).lineLimit(2)
                    Spacer(minLength: 4)
                    if finding.status == .unread {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .accessibilityLabel("未读")
                    }
                }
                HStack(spacing: 4) {
                    Text(sourceTitle).font(.subheadline).foregroundStyle(.secondary)
                    Text("·").font(.subheadline).foregroundStyle(.tertiary)
                    Text(finding.foundAt, style: .relative)
                        .font(.subheadline).foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if finding.relevance == .important {
                        Spacer(minLength: 4)
                        Text(finding.relevance.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(finding.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct CompletedFindingsView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    private var filtered: [Finding] {
        let completed = FindingQueue.completed(model.findings)
        guard !searchText.isEmpty else { return completed }
        let query = searchText.lowercased()
        return completed.filter { finding in
            finding.title.lowercased().contains(query)
                || finding.body.lowercased().contains(query)
                || (model.source(for: finding.sourceID)?.title.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        List(filtered) { finding in
            NavigationLink {
                FindingDetailView(model: model, id: finding.id)
            } label: {
                FindingRowView(finding: finding, sourceTitle: model.source(for: finding.sourceID)?.title ?? "来源")
            }
        }
        .searchable(text: $searchText, prompt: "搜索标题、内容或来源")
        .navigationTitle("已处理记录")
    }
}

struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: WatchSource
    let onSave: (WatchSource) -> Void
    @State private var error: String?
    @State private var showMoreContext: Bool

    init(source: WatchSource, prefillRepository: String? = nil, onSave: @escaping (WatchSource) -> Void) {
        var initial = source
        if initial.repository.isEmpty, let prefillRepository {
            initial.repository = prefillRepository
        }
        _source = State(initialValue: initial)
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

/// 编辑来源的个人使用情况（不动监控目标，不会重置基线）。
struct PersonalContextEditorView: View {
    @ObservedObject var model: AppModel
    let sourceID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var source: WatchSource
    @State private var loaded = false

    init(model: AppModel, sourceID: UUID) {
        self.model = model
        self.sourceID = sourceID
        _source = State(initialValue: model.source(for: sourceID) ?? WatchSource())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("使用情况（仅保存在本机）") {
                    TextField("显示名称", text: $source.displayName)
                    TextField("用途，例如 NAS 远程连接", text: $source.purpose)
                    TextField("正在使用的版本／Tag／提交", text: $source.installedVersion)
                        .textInputAutocapitalization(.never)
                    TextField("关注关键词，逗号分隔", text: $source.keywords)
                        .textInputAutocapitalization(.never)
                    TextField("采用理由", text: $source.rationale, axis: .vertical)
                }
                Toggle("暂停监控", isOn: $source.isPaused)
            }
            .navigationTitle("使用情况")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        model.upsertPersonalContext(source)
                        dismiss()
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
    @State private var showPersonalEditor = false

    var body: some View {
        List {
            if let source = model.source(for: id) {
                Section("来源") {
                    LabeledContent("仓库", value: source.repository)
                    LabeledContent("模式", value: source.kind.rawValue)
                    if source.kind == .path { LabeledContent("路径", value: source.path) }
                    if source.kind == .path && !source.branch.isEmpty { LabeledContent("分支", value: source.branch) }
                    if let description = source.repoDescription, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let date = source.lastCheckedAt { LabeledContent("上次检查") { Text(date, style: .relative) } }
                    if let error = source.lastError { Text(error).foregroundStyle(.red) }
                }
                Section("我的使用情况") {
                    if source.purpose.isEmpty && source.installedVersion.isEmpty && source.keywords.isEmpty && source.rationale.isEmpty {
                        Text("补充用途、关键词和使用版本后，判断会更准。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        if !source.purpose.isEmpty { LabeledContent("用途", value: source.purpose) }
                        if !source.installedVersion.isEmpty { LabeledContent("使用版本", value: source.installedVersion) }
                        if !source.keywords.isEmpty { LabeledContent("关键词", value: source.keywords) }
                        if !source.rationale.isEmpty { Text(source.rationale).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Button("编辑使用情况") { showPersonalEditor = true }
                    if source.isPaused {
                        Label("监控已暂停", systemImage: "pause.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("变化") {
                    let findings = model.findings.filter { $0.sourceID == id }
                    if findings.isEmpty { Text("暂无新变化；首次检查只建立基线。").foregroundStyle(.secondary) }
                    ForEach(findings) { finding in
                        NavigationLink(finding.title) { FindingDetailView(model: model, id: finding.id) }
                    }
                }
                Section {
                    Button {
                        Task { await model.refresh(id) }
                    } label: {
                        HStack {
                            Text("检查此来源")
                            if model.refreshingSourceIDs.contains(id) {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    if source.lastError == ChangeDetector.missingBaselineMessage {
                        Button("重建当前基线") {
                            model.resetBaseline(for: id)
                            Task { await model.refresh(id) }
                        }
                    }
                    Button("编辑监控目标") { edit(source) }
                    Button("删除来源", role: .destructive) { model.delete(source); dismiss() }
                }
            }
        }
        .navigationTitle(model.source(for: id)?.title ?? "来源")
        .sheet(isPresented: $showPersonalEditor) {
            PersonalContextEditorView(model: model, sourceID: id)
        }
    }
}

struct FindingDetailView: View {
    @ObservedObject var model: AppModel
    let id: UUID

    private var finding: Finding? { model.findings.first { $0.id == id } }

    private var markdownBody: AttributedString? {
        guard let body = finding?.body, !body.isEmpty else { return nil }
        return try? AttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    }

    var body: some View {
        List {
            if let finding {
                Section("判断") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: finding.relevance == .important ? "sparkles" : "info.circle.fill")
                            .font(.title2)
                            .foregroundStyle(finding.relevance == .important ? Color.orange : Color.accentColor)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(finding.relevance.rawValue)
                                    .font(.title3.weight(.semibold))
                                if finding.isPrerelease {
                                    Text("预发布")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }
                            Text(finding.reason)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    LabeledContent("状态", value: finding.status.rawValue)
                    if let source = model.source(for: finding.sourceID) {
                        LabeledContent("来源", value: source.title)
                    }
                    LabeledContent("上游标识", value: finding.upstreamID)
                    LabeledContent("发现时间") { Text(finding.foundAt, style: .date) }
                }
                if finding.oldContent != nil || finding.newContent != nil {
                    Section("文件对照") {
                        DiffView(old: finding.oldContent, new: finding.newContent)
                    }
                }
                Section("变化内容") {
                    if let markdownBody {
                        Text(markdownBody).textSelection(.enabled)
                    } else {
                        Text(finding.body.isEmpty ? "上游未提供说明。" : finding.body).textSelection(.enabled)
                    }
                }
                Section("操作") {
                    if let url = URL(string: finding.url) { Link("查看 GitHub 原文", destination: url) }
                    if finding.status == .handled {
                        Button("重新加入待处理") { model.setStatus(.viewed, for: id) }
                    } else {
                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.snappy) { model.setStatus(.handled, for: id) }
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
        .onAppear { if finding?.status == .unread { model.setStatus(.viewed, for: id) } }
    }
}
