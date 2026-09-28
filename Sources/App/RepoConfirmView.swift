import SwiftUI

/// 添加来源的确认页：探测仓库元数据并预填，用户只需核对后点一次保存。
struct RepoConfirmView: View {
    @ObservedObject var model: AppModel
    let input: String
    let onSaved: () -> Void
    /// 探测失败时的手动表单兜底入口；由调用方提供（如 AddSourceView）。
    var onRequestManual: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .probing
    @State private var probe: RepoProbe?
    @State private var source = WatchSource()
    @State private var useDescriptionAsPurpose = false
    @State private var keywordsText = ""
    @State private var pathCandidates: [String] = []
    @State private var pathScanNote: String?
    @State private var isScanningPaths = false
    @State private var validationError: String?

    enum Phase: Equatable {
        case probing
        case ready
        case failed(String)
    }

    var body: some View {
        Form {
            switch phase {
            case .probing:
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取仓库信息…").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("最多使用 2 次 GitHub API 请求。")
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    if onRequestManual != nil {
                        Button("改为手动填写") {
                            let request = onRequestManual
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                request?()
                            }
                        }
                    }
                }
            case .ready:
                readySections
            }
        }
        .navigationTitle("确认来源")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        }
        .task { await probeRepository() }
        .task(id: source.kind == .path ? "path:\(source.path.isEmpty)" : "other") {
            await scanPathCandidatesIfNeeded()
        }
    }

    @ViewBuilder private var readySections: some View {
        Section("仓库") {
            LabeledContent("仓库", value: source.repository)
            if let metadata = probe?.metadata, let description = metadata.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            if let metadata = probe?.metadata, let stars = metadata.stargazersCount {
                Label("\(stars)", systemImage: "star").font(.caption).foregroundStyle(.secondary)
            }
            if let latest = probe?.latest {
                LabeledContent("上游最新版本") {
                    Text(latest.tagName + (latest.prerelease ? "（预发布）" : ""))
                }
            }
        }

        Section("监控方式") {
            Picker("模式", selection: $source.kind) {
                ForEach(SourceKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            if source.kind == .path {
                TextField("路径，如 skills/example/SKILL.md", text: $source.path)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if !pathCandidates.isEmpty {
                    ForEach(pathCandidates, id: \.self) { candidate in
                        Button {
                            source.path = candidate
                        } label: {
                            HStack {
                                Text(candidate).font(.subheadline)
                                Spacer()
                                if source.path == candidate {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                if let pathScanNote {
                    Text(pathScanNote).font(.footnote).foregroundStyle(.secondary)
                }
                if source.kind == .path && !source.branch.isEmpty {
                    LabeledContent("分支", value: source.branch)
                }
            }
            if source.kind != .path {
                TextField("正在使用的版本／Tag（可留空）", text: $source.installedVersion)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }

        Section {
            TextField("显示名称", text: $source.displayName)
            TextField("用途，例如 NAS 远程连接", text: $source.purpose, axis: .vertical)
            if useDescriptionAsPurpose == false, let description = probe?.metadata?.description, !description.isEmpty {
                Button("使用仓库描述作为用途") {
                    source.purpose = description
                    useDescriptionAsPurpose = true
                }
                .font(.subheadline)
            }
            TextField("关注关键词，逗号分隔（可选）", text: $keywordsText)
                .textInputAutocapitalization(.never)
        } header: {
            Text("我的使用情况（仅保存在本机，可稍后补充）")
        } footer: {
            Text("这些信息只用于本地判断相关性，不会发给 GitHub。")
        }

        if let probe, !probe.warnings.isEmpty {
            Section {
                ForEach(probe.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }

        if let validationError {
            Section { Text(validationError).foregroundStyle(.red).font(.subheadline) }
        }

        Section {
            Button {
                save()
            } label: {
                Text("保存并建立基线").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            Text("首次成功检查只记录当前基线，不会把历史版本当成新变化。")
        }
    }

    private func probeRepository() async {
        do {
            let result = try await model.probe(input)
            probe = result
            source = result.source
            if source.displayName.isEmpty {
                source.displayName = source.repository.split(separator: "/").last.map(String.init) ?? source.repository
            }
            if let topics = result.metadata?.topics, !topics.isEmpty, source.keywords.isEmpty {
                keywordsText = topics.prefix(5).joined(separator: ", ")
            }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func scanPathCandidatesIfNeeded() async {
        guard phase == .ready, source.kind == .path, source.path.isEmpty, pathCandidates.isEmpty, !isScanningPaths else { return }
        isScanningPaths = true
        defer { isScanningPaths = false }
        do {
            let scan = try await model.probePaths(repository: source.repository, branch: source.branch)
            pathCandidates = Array(scan.paths.prefix(30))
            if scan.truncated {
                pathScanNote = "仓库文件过多，列表不完整；请手动输入路径。"
            } else if scan.paths.isEmpty {
                pathScanNote = "仓库中没有找到匹配 SKILL.md 的文件，请手动输入路径。"
            }
        } catch {
            pathScanNote = "路径枚举失败：\(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            source.repository = try GitHubClient.normalizedRepository(source.repository)
        } catch {
            validationError = error.localizedDescription
            return
        }
        source.keywords = keywordsText
        if source.kind == .path && source.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationError = "请填写或选择要监控的路径。"
            return
        }
        validationError = nil
        model.upsert(source)
        Task { await model.refresh(source.id) }
        dismiss()
        onSaved()
    }
}
