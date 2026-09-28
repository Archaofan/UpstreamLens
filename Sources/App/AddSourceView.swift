import SwiftUI

/// 添加来源的第一步：搜索仓库名或粘贴 GitHub 链接，二选一进入确认页；手动填写作为兜底。
struct AddSourceView: View {
    @ObservedObject var model: AppModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var results: [RepoSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var showConfirmFor: String?
    @State private var manualSource: WatchSource?
    @State private var manualPrefill: String?

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                directSection
                statusSections
                otherSection
            }
            .navigationTitle("添加来源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .task(id: input) {
                // 输入防抖：停顿 600ms 后自动搜索；链接形状的输入不消耗搜索限额。
                guard !isLinkLike, input.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                await search()
            }
            .sheet(item: Binding(
                get: { showConfirmFor.map { ConfirmTarget(repository: $0) } },
                set: { showConfirmFor = $0?.repository })) { target in
                RepoConfirmView(model: model, input: target.repository) {
                    dismiss()
                    onSaved()
                } onRequestManual: {
                    // 探测失败的兜底：关掉确认页后弹出手动表单（预填已识别的仓库名）。
                    manualPrefill = target.repository
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        manualSource = WatchSource(repository: target.repository)
                    }
                }
            }
            .sheet(item: $manualSource) { source in
                SourceEditorView(source: source, prefillRepository: manualPrefill) { saved in
                    model.upsert(saved)
                    Task { await model.refresh(saved.id) }
                    dismiss()
                    onSaved()
                }
            }
        }
    }

    private struct ConfirmTarget: Identifiable {
        let repository: String
        var id: String { repository }
    }

    // MARK: - 分区视图（拆小以缩短类型检查时间）

    private var inputSection: some View {
        Section {
            TextField("搜索仓库名，或粘贴 GitHub 链接", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
        } footer: {
            Text("支持 github.com 仓库、分支、文件链接，或直接输入 owner/repo。")
        }
    }

    @ViewBuilder private var directSection: some View {
        if let direct = directRepository {
            Section("识别到仓库") {
                Button {
                    showConfirmFor = direct
                } label: {
                    Label("继续添加 \(direct)", systemImage: "arrow.right.circle")
                }
            }
        }
    }

    @ViewBuilder private var statusSections: some View {
        if isSearching {
            Section {
                HStack {
                    ProgressView()
                    Text("正在搜索…").foregroundStyle(.secondary)
                }
            }
        } else if let searchError {
            Section {
                Label(searchError, systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } else if !results.isEmpty {
            resultsSection
        } else if showEmptyHint {
            Section {
                Text("没有匹配结果，或输入完成后回车搜索。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        Section("搜索结果") {
            ForEach(results, id: \.fullName) { result in
                Button {
                    showConfirmFor = result.fullName
                } label: {
                    resultRow(result)
                }
            }
        }
    }

    private func resultRow(_ result: RepoSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(result.fullName).font(.headline).foregroundStyle(.primary)
                Spacer()
                Label("\(result.stargazersCount)", systemImage: "star")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let description = result.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var otherSection: some View {
        Section("其他方式") {
            Button {
                manualPrefill = directRepository
                manualSource = WatchSource()
            } label: {
                Label("手动填写", systemImage: "square.and.pencil")
            }
        }
    }

    // MARK: - 逻辑

    /// 输入已经是 `owner/repo` 或 GitHub 链接时，无需搜索直接进入确认页。
    private var directRepository: String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if ParsedGitHubURL.parse(trimmed) != nil {
            return (try? GitHubClient.normalizedRepository(trimmed)) ?? trimmed
        }
        return nil
    }

    private var isLinkLike: Bool { directRepository != nil }

    private var showEmptyHint: Bool {
        input.trimmingCharacters(in: .whitespaces).count >= 2 && directRepository == nil
    }

    private func search() async {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !isLinkLike else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            results = try await GitHubClient().searchRepositories(query)
        } catch GitHubError.rateLimited(let info) {
            results = []
            searchError = GitHubError.rateLimited(info).localizedDescription + " 也可以直接粘贴仓库链接。"
        } catch {
            results = []
            searchError = "搜索失败：\(error.localizedDescription)"
        }
    }
}
