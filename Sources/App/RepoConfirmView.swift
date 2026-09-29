import SwiftUI

/// 添加来源的确认页：探测仓库元数据并预填，用户只需核对后点一次保存。
struct RepoConfirmView: View {
    @ObservedObject var model: AppModel
    let input: String
    /// 从预设进入时预填的字段（监控方式、路径、用途、关键词），探测结果只补充元数据。
    var preset: SourcePreset? = nil
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
                        Text("Reading repo info…").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Probing uses up to 2 requests plus 1 for the version list; subsequent checks with no changes don't count against the limit.")
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    if onRequestManual != nil {
                        Button("Switch to Manual Entry") {
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
        .transparentListBackground()
        .navigationTitle("Confirm Source")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .task { await probeRepository() }
        .task(id: source.kind == .path ? "path:\(source.path.isEmpty)" : "other") {
            await scanPathCandidatesIfNeeded()
        }
    }

    @ViewBuilder private var readySections: some View {
        Section("Repository") {
            HStack(spacing: 12) {
                RepoAvatarImage(repository: source.repository,
                                symbol: RepoAvatar.fallbackSymbol(for: source.kind),
                                size: 44,
                                cornerRadius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.repository).font(.headline)
                    if let metadata = probe?.metadata, let description = metadata.description, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            if let metadata = probe?.metadata, let stars = metadata.stargazersCount {
                Label("\(stars)", systemImage: "star").font(.caption).foregroundStyle(.secondary)
            }
            if let latest = probe?.latest {
                LabeledContent("Latest Upstream Version") {
                    Text(latest.tagName + (latest.prerelease ? " " + AppLocalization.string("(prerelease)") : ""))
                }
            }
        }

        Section("Monitoring Method") {
            Picker("Mode", selection: $source.kind) {
                ForEach(SourceKind.allCases) { kind in Text(kind.displayName).tag(kind) }
            }
            if source.kind == .path {
                TextField("Path, e.g. skills/example/SKILL.md", text: $source.path)
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
                    LabeledContent("Branch", value: source.branch)
                }
            }
            if source.kind != .path {
                VersionPickerField(repository: source.repository, kind: source.kind,
                                   loadOptions: VersionPickerField.makeLoader(
                                       { try await model.versionOptions(repository: $0, kind: $1) },
                                       repository: source.repository, kind: source.kind),
                                   selection: $source.installedVersion)
            }
        }

        Section {
            TextField("Display Name", text: $source.displayName)
            TextField("Purpose, e.g. NAS remote access", text: $source.purpose, axis: .vertical)
            if useDescriptionAsPurpose == false, let description = probe?.metadata?.description, !description.isEmpty {
                Button("Use Repo Description as Purpose") {
                    source.purpose = description
                    useDescriptionAsPurpose = true
                }
                .font(.subheadline)
            }
            TextField("Keywords to watch, comma-separated (optional)", text: $keywordsText)
                .textInputAutocapitalization(.never)
        } header: {
            Text("My Usage (stored on this device only, can add later)")
        } footer: {
            Text("This info is only used locally to judge relevance; it is never sent to GitHub.")
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
                Text("Save and Set Baseline").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            Text("The first successful check records the current baseline only; historical versions are not treated as new changes.")
        }
    }

    private func probeRepository() async {
        do {
            let result = try await model.probe(input)
            probe = result
            source = result.source
            if let preset {
                source.kind = preset.kind
                source.path = preset.path
                if !preset.branch.isEmpty { source.branch = preset.branch }
                source.displayName = preset.displayName
                source.purpose = preset.purpose
                source.keywords = preset.keywords
            }
            if source.displayName.isEmpty {
                source.displayName = source.repository.split(separator: "/").last.map(String.init) ?? source.repository
            }
            if let topics = result.metadata?.topics, !topics.isEmpty, source.keywords.isEmpty {
                keywordsText = topics.prefix(5).joined(separator: ", ")
            } else if !source.keywords.isEmpty {
                keywordsText = source.keywords
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
                pathScanNote = AppLocalization.string("Too many files in the repo; the list is incomplete. Enter the path manually.")
            } else if scan.paths.isEmpty {
                pathScanNote = AppLocalization.string("No matching SKILL.md files found in the repo; enter the path manually.")
            }
        } catch {
            pathScanNote = AppLocalization.string("Failed to list paths") + ": \(error.localizedDescription)"
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
            validationError = AppLocalization.string("Enter or select a path to monitor.")
            return
        }
        validationError = nil
        // 未指定类别时按仓库名/topics/描述猜一个，省去用户手动归类。
        if source.category == nil {
            source.category = CategoryClassifier.suggest(
                repository: source.repository,
                topics: source.topics ?? [],
                text: [source.displayName, source.purpose, source.keywords, source.repoDescription ?? ""]
                    .joined(separator: " "))
        }
        model.upsert(source)
        Task { await model.refresh(source.id) }
        dismiss()
        onSaved()
    }
}
