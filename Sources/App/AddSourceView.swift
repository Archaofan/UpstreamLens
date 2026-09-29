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
                presetSection
                otherSection
            }
            .transparentListBackground()
            .navigationTitle("Add Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: input) {
                // 输入防抖：停顿 600ms 后自动搜索；链接形状的输入不消耗搜索限额。
                guard !isLinkLike, input.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                await search()
            }
            .sheet(item: Binding(
                get: { showConfirmFor.map { ConfirmTarget(repository: $0, preset: selectedPreset) } },
                set: {
                    showConfirmFor = $0?.repository
                    if $0 == nil { selectedPreset = nil }
                })) { target in
                // 必须包 NavigationStack：RepoConfirmView 的 Cancel 写在 .toolbar 里，
                // 缺少导航栏时该项根本不渲染，用户会被卡在确认页、只能保存后再删除。
                NavigationStack {
                    RepoConfirmView(model: model, input: target.repository,
                                    preset: target.preset) {
                        dismiss()
                        onSaved()
                    } onRequestManual: {
                        // 探测失败的兜底：关掉确认页后弹出手动表单（预填已识别的仓库名）。
                        manualPrefill = target.repository
                        selectedPreset = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            manualSource = target.preset?.watchSource ?? WatchSource(repository: target.repository)
                        }
                    }
                }
            }
            .sheet(item: $manualSource) { source in
                SourceEditorView(source: source, prefillRepository: manualPrefill,
                                 versionOptionsLoader: { try await model.versionOptions(repository: $0, kind: $1) }) { saved in
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
        var preset: SourcePreset?
        var id: String { repository }
    }

    @State private var selectedPreset: SourcePreset?

    // MARK: - 分区视图（拆小以缩短类型检查时间）

    private var inputSection: some View {
        Section {
            TextField("Search a repo name, or paste a GitHub link", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
        } footer: {
            Text("Supports github.com repo, branch, and file links, or type owner/repo directly.")
        }
    }

    @ViewBuilder private var directSection: some View {
        if let direct = directRepository {
            Section("Repo Detected") {
                Button {
                    showConfirmFor = direct
                } label: {
                    Label("Continue adding \(direct)", systemImage: "arrow.right.circle")
                }
            }
        }
    }

    @ViewBuilder private var statusSections: some View {
        if isSearching {
            Section {
                HStack {
                    ProgressView()
                    Text("Searching…").foregroundStyle(.secondary)
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
                Text("No matches, or press Return after typing.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        Section("Search Results") {
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
        HStack(spacing: 12) {
            RepoAvatarImage(repository: result.fullName,
                            symbol: RepoAvatar.fallbackSymbol(for: .release),
                            size: 38,
                            cornerRadius: 10)
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
    }

    private var presetSection: some View {
        Section {
            ForEach(PresetLibrary.validated()) { preset in
                Button {
                    selectedPreset = preset
                    showConfirmFor = preset.repository
                } label: {
                    HStack(spacing: 12) {
                        PresetIconView(preset: preset)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.displayName).font(.headline).foregroundStyle(.primary)
                            Text(preset.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text("Suggested Presets")
        } footer: {
            Text("High-star AI projects and agent toolchains; tap to prefill.")
        }
    }

    private var otherSection: some View {
        Section("Other Ways") {
            Button {
                manualPrefill = directRepository
                manualSource = WatchSource()
            } label: {
                Label("Enter Manually", systemImage: "square.and.pencil")
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
            var client = GitHubClient()
            client.token = KeychainTokenStore.shared.read()
            results = try await client.searchRepositories(query)
        } catch GitHubError.rateLimited(let info) {
            results = []
            searchError = GitHubError.rateLimited(info).localizedDescription + " " + AppLocalization.string("You can also paste a repo link directly.")
        } catch {
            results = []
            searchError = AppLocalization.string("Search failed") + ": \(error.localizedDescription)"
        }
    }
}
