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
    @State private var navigationPath = NavigationPath()
    @State private var showClipboardBanner = false
    @State private var showMarkAllHandled = false
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
                PendingSectionView(model: model, importantOnly: $importantOnly,
                                   addTapped: { showAddFlow = true })
                WidgetStatusSectionView(error: model.widgetError)
            }
            .listStyle(.insetGrouped)
            .transparentListBackground()
            // 底色由根视图的 appBackground() 提供（关闭时为 systemGroupedBackground，
            // 与改动前一致；开启时为用户图片），这里不再重复绘制不透明底色。
            .refreshable { await model.refreshAll() }
            .navigationTitle("UpstreamLens")
            .navigationDestination(for: FindingRoute.self) { route in
                FindingDetailView(model: model, id: route.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddFlow = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Source")
                        .disabled(!model.canEditData)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            model.markAllRead()
                        } label: {
                            Label("Mark All as Read", systemImage: "envelope.open")
                        }
                        .disabled(!model.findings.contains { $0.status == .unread })
                        Button {
                            showMarkAllHandled = true
                        } label: {
                            Label("Mark All as Handled", systemImage: "checkmark.circle")
                        }
                        .disabled(FindingQueue.pending(model.findings).isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("More Actions")
                }
            }
            .sheet(item: $editorSource) { source in
                SourceEditorView(source: source,
                                 categories: model.categories,
                                 versionOptionsLoader: { try await model.versionOptions(repository: $0, kind: $1) }) { saved in
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
            .alert("Action Failed", isPresented: Binding(get: { dialogError != nil }, set: { if !$0 { dialogError = nil } })) {
                Button("OK", role: .cancel) { dialogError = nil }
            } message: { Text(dialogError ?? "") }
            .confirmationDialog("Mark all pending changes as handled?", isPresented: $showMarkAllHandled) {
                Button("Mark All as Handled", role: .destructive) { model.markAllHandled() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(FindingQueue.pending(model.findings).count) items will move to handled records; this means you have finished reviewing them locally.")
            }
            .onOpenURL { url in handleDeepLink(url) }
            .onReceive(NotificationCenter.default.publisher(for: .openFindingFromNotification)) { note in
                guard let id = note.object as? UUID,
                      model.findings.contains(where: { $0.id == id }) else { return }
                navigationPath.append(FindingRoute(id: id))
            }
            .task { if RefreshPolicy.checkOnOpen() { await model.refreshAll() } }
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
                Text("Possible GitHub link in clipboard")
                    .font(.subheadline)
                Spacer()
                Button("Add") {
                    let changeCount = UIPasteboard.general.changeCount
                    clipboardChangeCountSeen = changeCount
                    showClipboardBanner = false
                    guard let text = UIPasteboard.general.string,
                          ParsedGitHubURL.parse(text) != nil else {
                        dialogError = "Clipboard content is not a recognized GitHub repository link."
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
                .accessibilityLabel("Dismiss")
            }
            .font(.subheadline)
        }
    }


    /// iOS 会把“读剪贴板”变成系统弹窗；这里先用 detectPatterns 只判断模式，不触发弹窗。
    private func detectClipboardGitHubLink() {
        let changeCount = UIPasteboard.general.changeCount
        guard changeCount != clipboardChangeCountSeen else { return }
        UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
            guard UIPasteboard.general.changeCount == changeCount else { return }
            Task { @MainActor in
                if case .success(let patterns) = result, patterns.contains(.probableWebURL) {
                    showClipboardBanner = true
                }
            }
        }
    }

    // MARK: - 深链接

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "upstreamlens" else { return }
        switch url.host {
        case "findings":
            navigationPath = NavigationPath()
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
                Label("Widget Temporarily Unavailable", systemImage: "square.on.square.dashed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Widget")
            } footer: {
                Text("Generate detailed info in Settings → Diagnostics and send it to the developer.")
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
            .glassCard(.regular, cornerRadius: 18, padding: 16)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

private struct PendingSectionView: View {
    @ObservedObject var model: AppModel
    @Binding var importantOnly: Bool
    let addTapped: () -> Void

    var body: some View {
        Section("Pending Changes") {
            let pending = FindingQueue.pending(model.findings, importantOnly: importantOnly)
            if !FindingQueue.pending(model.findings).isEmpty {
                Picker("Filter Changes", selection: $importantOnly) {
                    Text("All").tag(false)
                    Text("Worth Attention").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if pending.isEmpty {
                if importantOnly && !FindingQueue.pending(model.findings).isEmpty {
                    Label("No key changes right now; switch to “All” to view", systemImage: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                } else if model.sources.isEmpty {
                    // 来源管理已独立成"来源"标签页，这里只留一句引导 + 快捷入口，不再重复整份列表。
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No sources yet", systemImage: "plus.circle.fill")
                            .font(.headline)
                        Text("Add a repo in the Sources tab; the first successful check sets the baseline.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Add Source", action: addTapped)
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canEditData)
                    }
                    .padding(.vertical, 8)
                } else {
                    Label("No pending changes right now", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(pending) { finding in
                PendingFindingRowView(model: model, finding: finding)
            }
            let completedCount = FindingQueue.completed(model.findings).count
            if completedCount > 0 {
                NavigationLink("View Handled Records (\(completedCount))") {
                    CompletedFindingsView(model: model)
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
                FindingRowView(finding: finding, sourceTitle: model.source(for: finding.sourceID)?.title ?? "Source")
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
            .accessibilityLabel("Mark as Handled")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.snappy) { model.setStatus(.handled, for: finding.id) }
            } label: {
                Label("Handled", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .leading) {
            if finding.status == .unread {
                Button {
                    withAnimation(.snappy) { model.setStatus(.viewed, for: finding.id) }
                } label: {
                    Label("Read", systemImage: "envelope.open")
                }
                .tint(.blue)
            } else {
                Button {
                    withAnimation(.snappy) { model.setStatus(.unread, for: finding.id) }
                } label: {
                    Label("Unread", systemImage: "envelope.badge")
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
                    Text("Pending Changes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(pendingCount)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text(unreadCount == 0 ? "No unread changes" : "\(unreadCount) unread")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: pendingCount == 0 ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: isRefreshing)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
            }
            Divider()
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(sourceCount) sources")
                        .font(.subheadline.weight(.medium))
                    if let lastCheck {
                        Text("Last check: \(lastCheck, style: .relative)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Waiting for first successful check")
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
                .accessibilityLabel(isRefreshing ? "Checking" : "Refresh Now")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .contain)
    }
}

struct SourceRowView: View {
    let source: WatchSource
    let isRefreshing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RepoAvatarImage(repository: source.repository,
                            symbol: RepoAvatar.fallbackSymbol(for: source.kind),
                            size: 32,
                            cornerRadius: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(source.title).font(.headline)
                    if source.isPaused { Text("Paused").font(.caption).foregroundStyle(.secondary) }
                }
                (Text("\(source.repository) · ") + Text(source.kind.displayName))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
                if isRefreshing {
                    Label("Checking", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let error = source.lastError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if let date = source.lastCheckedAt {
                    Text("Last successful check: \(date, style: .relative)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Waiting for first successful check")
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
                            .accessibilityLabel("Unread")
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
                        Text(finding.relevance.displayName)
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
                FindingRowView(finding: finding, sourceTitle: model.source(for: finding.sourceID)?.title ?? "Source")
            }
        }
        .searchable(text: $searchText, prompt: "Search title, content, or source")
        .transparentListBackground()
        .navigationTitle("Handled Records")
    }
}

struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: WatchSource
    let onSave: (WatchSource) -> Void
    /// 可选类别（来源页传入）；为空时不显示类别选择器，测试/预览仍可用。
    var categories: [SourceCategory] = []
    /// 版本下拉的数据源；为 nil（测试/预览）时退回手填文本框。
    var versionOptionsLoader: ((String, SourceKind) async throws -> [VersionOption])?
    @State private var error: String?
    @State private var showMoreContext: Bool
    /// 标签编辑文本；保存时经 SourceOrganizer.parseTags 清洗后写回 source.tags。
    @State private var tagsText: String

    init(source: WatchSource, prefillRepository: String? = nil,
         categories: [SourceCategory] = [],
         versionOptionsLoader: ((String, SourceKind) async throws -> [VersionOption])? = nil,
         onSave: @escaping (WatchSource) -> Void) {
        var initial = source
        if initial.repository.isEmpty, let prefillRepository {
            initial.repository = prefillRepository
        }
        _source = State(initialValue: initial)
        _showMoreContext = State(initialValue: !source.installedVersion.isEmpty || !source.keywords.isEmpty || !source.rationale.isEmpty)
        _tagsText = State(initialValue: source.tags.joined(separator: ", "))
        self.categories = categories
        self.versionOptionsLoader = versionOptionsLoader
        self.onSave = onSave
    }

    /// 类别选择。类别目录来自设置，可增删改。
    @ViewBuilder private var categorySection: some View {
        if !categories.isEmpty {
            Section {
                Picker("Category", selection: Binding(
                    get: { source.category ?? CategoryCatalog.uncategorizedID },
                    set: { source.category = $0 })) {
                    ForEach(categories) { category in
                        Label(category.displayName, systemImage: category.symbol).tag(category.id)
                    }
                }
            } header: {
                Text("Category")
            } footer: {
                Text("Used to group and filter the Sources tab. Categories can be edited in Settings → Categories.")
            }
        }
    }

    /// 标签区：逗号/空格分隔输入，实时预览解析结果，来源多时便于筛选。
    private var tagSection: some View {        Section {
            TextField("Tags, e.g. self-hosted, NAS, AI", text: $tagsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            let parsed = SourceOrganizer.parseTags(tagsText)
            if !parsed.isEmpty {
                FlowTagRow(tags: parsed)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Separate with commas or spaces. Tags are stored on this device and used to filter the Sources tab.")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub Source") {
                    Picker("Mode", selection: $source.kind) {
                        ForEach(SourceKind.allCases) { kind in Text(kind.displayName).tag(kind) }
                    }
                    TextField("owner/repo or repo link", text: $source.repository)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if source.kind == .path {
                        TextField("Path, e.g. skills/example/SKILL.md", text: $source.path)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Branch (empty = default branch)", text: $source.branch)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Text("The first successful check only sets a baseline; old versions are not treated as new changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                // 只对 release/tag 有意义；path 模式的提交没有版本标识，检测器会自动跳过过滤。
                if source.kind != .path {
                    Section {
                        Toggle("Only Version-Like Releases", isOn: $source.versionLikeOnly)
                    } footer: {
                        Text("Upstreams sometimes publish content-addressed snapshots as releases or tags, which carry no version meaning. Turning this on keeps only entries that look like version numbers. If nothing qualifies, everything is kept so the source never goes silent.")
                    }
                }
                Section("My Usage (stored on this device only)") {
                    TextField("Display Name", text: $source.displayName)
                    TextField("Purpose, e.g. NAS remote access", text: $source.purpose)
                    DisclosureGroup("More Personal Info (optional)", isExpanded: $showMoreContext) {
                        if let versionOptionsLoader {
                            VersionPickerField(repository: source.repository, kind: source.kind,
                                               loadOptions: VersionPickerField.makeLoader(
                                                   versionOptionsLoader,
                                                   repository: source.repository, kind: source.kind),
                                               selection: $source.installedVersion)
                        } else {
                            TextField("Version / Tag / commit in use", text: $source.installedVersion)
                                .textInputAutocapitalization(.never)
                        }
                        TextField("Keywords to watch, comma-separated", text: $source.keywords)
                        TextField("Why you adopted it", text: $source.rationale, axis: .vertical)
                    }
                }
                Toggle("Pause Monitoring", isOn: $source.isPaused)
                categorySection
                tagSection
                if let error { Text(error).foregroundStyle(.red) }
            }
            .transparentListBackground()
            .navigationTitle("Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            source.repository = try GitHubClient.normalizedRepository(source.repository)
                            source.path = source.path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                            if source.kind == .path && source.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                error = "Enter the file or directory path to monitor."; return
                            }
                            source.tags = SourceOrganizer.parseTags(tagsText)
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
                Section("Usage (stored on this device only)") {
                    TextField("Display Name", text: $source.displayName)
                    TextField("Purpose, e.g. NAS remote access", text: $source.purpose)
                    VersionPickerField(repository: source.repository, kind: source.kind,
                                       loadOptions: VersionPickerField.makeLoader(
                                           { try await model.versionOptions(repository: $0, kind: $1) },
                                           repository: source.repository, kind: source.kind),
                                       selection: $source.installedVersion)
                    TextField("Keywords to watch, comma-separated", text: $source.keywords)
                        .textInputAutocapitalization(.never)
                    TextField("Why you adopted it", text: $source.rationale, axis: .vertical)
                    Toggle("Notify on New Changes", isOn: Binding(
                        get: { source.notifyEnabled ?? true },
                        set: { source.notifyEnabled = $0 }))
                }
                Toggle("Pause Monitoring", isOn: $source.isPaused)
            }
            .transparentListBackground()
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
                Section("Source") {
                    LabeledContent("Repository", value: source.repository)
                    LabeledContent("Mode") { Text(source.kind.displayName) }
                    if source.kind == .path { LabeledContent("Path", value: source.path) }
                    if source.kind == .path && !source.branch.isEmpty { LabeledContent("Branch", value: source.branch) }
                    if let description = source.repoDescription, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let date = source.lastCheckedAt { LabeledContent("Last Check") { Text(date, style: .relative) } }
                    if let error = source.lastError { Text(error).foregroundStyle(.red) }
                }
                Section("My Usage") {
                    if source.purpose.isEmpty && source.installedVersion.isEmpty && source.keywords.isEmpty && source.rationale.isEmpty {
                        Text("Adding purpose, keywords, and the version in use improves accuracy.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        if !source.purpose.isEmpty { LabeledContent("Purpose", value: source.purpose) }
                        if !source.installedVersion.isEmpty { LabeledContent("Version in Use", value: source.installedVersion) }
                        if !source.keywords.isEmpty { LabeledContent("Keywords", value: source.keywords) }
                        if !source.rationale.isEmpty { Text(source.rationale).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Button("Edit Usage") { showPersonalEditor = true }
                    if source.isPaused {
                        Label("Monitoring Paused", systemImage: "pause.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if source.notifyEnabled == false {
                        Label("Notifications Off for This Source", systemImage: "bell.slash")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("Changes") {
                    let findings = model.findings.filter { $0.sourceID == id }
                    if findings.isEmpty { Text("No new changes yet; the first check only sets a baseline.").foregroundStyle(.secondary) }
                    ForEach(findings) { finding in
                        NavigationLink(finding.title) { FindingDetailView(model: model, id: finding.id) }
                    }
                }
                Section {
                    Button {
                        Task { await model.refresh(id) }
                    } label: {
                        HStack {
                            Text("Check This Source")
                            if model.refreshingSourceIDs.contains(id) {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    if source.lastError == ChangeDetector.missingBaselineMessage {
                        Button("Rebuild Baseline") {
                            model.resetBaseline(for: id)
                            Task { await model.refresh(id) }
                        }
                    }
                    Button("Edit Watch Target") { edit(source) }
                    Button("Delete Source", role: .destructive) { model.delete(source); dismiss() }
                }
            }
        }
        .transparentListBackground()
        .navigationTitle(model.source(for: id)?.title ?? "Source")
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
                Section("Assessment") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: finding.relevance == .important ? "sparkles" : "info.circle.fill")
                            .font(.title2)
                            .foregroundStyle(finding.relevance == .important ? Color.orange : Color.accentColor)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(finding.relevance.displayName)
                                    .font(.title3.weight(.semibold))
                                if finding.showsPrereleaseBadge {
                                    Text("Prerelease")
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
                    LabeledContent("Status") { Text(finding.status.displayName) }
                    if let source = model.source(for: finding.sourceID) {
                        LabeledContent("Source", value: source.title)
                    }
                    LabeledContent("Upstream ID", value: finding.upstreamID)
                    LabeledContent("Found At") { Text(finding.foundAt, style: .date) }
                }
                if finding.oldContent != nil || finding.newContent != nil {
                    Section("File Comparison") {
                        DiffView(old: finding.oldContent, new: finding.newContent)
                    }
                }
                Section("Change Content") {
                    if let markdownBody {
                        Text(markdownBody).textSelection(.enabled)
                    } else {
                        Text(finding.body.isEmpty ? "No description provided upstream." : finding.body).textSelection(.enabled)
                    }
                }
                Section("Actions") {
                    if let url = URL(string: finding.url) { Link("View on GitHub", destination: url) }
                    if finding.status == .handled {
                        Button("Return to Pending") { model.setStatus(.viewed, for: id) }
                    } else {
                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.snappy) { model.setStatus(.handled, for: id) }
                        } label: {
                            Label("Mark as Handled", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        if finding.status == .viewed {
                            Button("Mark as Unread") { model.setStatus(.unread, for: id) }
                        }
                    }
                }
            }
        }
        .transparentListBackground()
        .navigationTitle("Change Details")
        .onAppear { if finding?.status == .unread { model.setStatus(.viewed, for: id) } }
    }
}
