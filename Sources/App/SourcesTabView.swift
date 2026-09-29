import SwiftUI

/// 标签胶囊行。刻意用粗略分行而非 Layout，避免额外 API 面与复杂度。
struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private var rows: [[String]] {
        stride(from: 0, to: tags.count, by: 3).map {
            Array(tags[$0..<min($0 + 3, tags.count)])
        }
    }
}

/// 来源标签页：搜索 + 标签筛选 + 按类别分组（可切换为按作者）。
/// 头像行复用 `SourceRowView`，保证与雷达页观感一致。
struct SourcesTabView: View {
    @ObservedObject var model: AppModel
    @AppStorage(ThemePreferences.storageKey) private var rawTheme: AppTheme = .teal
    @AppStorage(SourceGroupPreferences.storageKey) private var storedGroupKind = SourceGroupPreferences.fallback.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var selectedTag: String?
    @State private var editorSource: WatchSource?
    @State private var showAddFlow = false

    private var accent: Color {
        // @AppStorage 已按 RawRepresentable 直接给出 AppTheme，无需再 resolve。
        ThemePreferences.accent(rawTheme, scheme: colorScheme)
    }

    private var groupKind: SourceGroupKind {
        SourceGroupPreferences.resolve(storedGroupKind)
    }

    private var visible: [WatchSource] {
        SourceOrganizer.filter(SourceOrganizer.filter(model.sources, tag: selectedTag), query: query)
    }

    private var groups: [SourceGroup] {
        SourceOrganizer.group(visible, by: groupKind, categories: model.categories)
    }

    private var tags: [String] { SourceOrganizer.allTags(model.sources) }

    var body: some View {
        NavigationStack {
            List {
                groupingRow
                if !tags.isEmpty {
                    tagFilterRow
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.sources) { source in
                            NavigationLink {
                                SourceDetailView(model: model, id: source.id, edit: { editorSource = $0 })
                            } label: {
                                SourceRowView(source: source,
                                              isRefreshing: model.refreshingSourceIDs.contains(source.id))
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            if let symbol = group.symbol {
                                Image(systemName: symbol).font(.caption)
                            }
                            Text(group.title)
                            Spacer()
                            Text("\(group.sources.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .transparentListBackground()
            .navigationTitle("Sources")
            .overlay {
                if visible.isEmpty { emptyState }
            }
            .searchable(text: $query, prompt: AppLocalization.string("Search sources"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddFlow = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Source")
                        .disabled(!model.canEditData)
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
        }
    }

    // MARK: 分组依据

    private var groupingRow: some View {
        // 直接绑定原始字符串存储，Picker 的 tag 也用 rawValue，
        // 避免为枚举写可写计算属性（AppStorage 的 setter 语义容易踩坑）。
        Picker("Group By", selection: $storedGroupKind) {
            ForEach(SourceGroupKind.allCases) { kind in
                Text(kind.displayName).tag(kind.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: 标签筛选

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: AppLocalization.string("All"), isActive: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(tags, id: \.self) { tag in
                    filterChip(title: tag, isActive: selectedTag == tag) {
                        selectedTag = (selectedTag == tag) ? nil : tag
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func filterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isActive ? accent : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: 空状态

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.sources.isEmpty ? "plus.rectangle.on.folder" : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(model.sources.isEmpty ? "No sources yet" : "No matching sources")
                .font(.headline)
            Text(model.sources.isEmpty
                 ? "Add a repo to start tracking its releases."
                 : "Try another keyword, or clear the tag filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}
