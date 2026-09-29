import SwiftUI

/// “正在使用的版本”输入行：优先从上游 Release/Tag 列表下拉选择（1 次核心请求），
/// 迭代快的项目不用背版本号；加载失败或用户选择手动输入时退回普通文本框。
/// path 模式的版本是提交 SHA，没有可枚举的版本列表，保持手填。
/// 组件被嵌进调用方的 Form Section 里，这里只输出行级视图（不自己套 Section）。
struct VersionPickerField: View {
    let repository: String
    let kind: SourceKind
    let loadOptions: () async -> Result<[VersionOption], any Error>
    @Binding var selection: String

    @State private var options: [VersionOption]?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var manualMode = false

    var body: some View {
        if kind == .path {
            pathRow
        } else if manualMode || loadError != nil {
            manualRows
        } else {
            menuRow
        }
    }

    private var pathRow: some View {
        TextField("正在使用的提交 SHA（可留空）", text: $selection)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    @ViewBuilder private var manualRows: some View {
        TextField("正在使用的版本／Tag（可留空）", text: $selection)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        if let loadError {
            Label("上游版本列表读取失败：\(loadError)", systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("重试从上游版本列表选择") {
                manualMode = false
                loadError = nil
                Task { await load() }
            }
            .font(.subheadline)
        }
    }

    private var menuRow: some View {
        Menu {
            menuContent
        } label: {
            HStack {
                Text("正在使用的版本")
                Spacer()
                if selection.isEmpty {
                    Text("从上游选择…").foregroundStyle(.secondary)
                } else {
                    Text(selection).foregroundStyle(.primary)
                }
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var menuContent: some View {
        if let options {
            if options.isEmpty {
                Text("上游暂无 Release／Tag")
            } else {
                Section("上游版本") {
                    ForEach(options) { option in
                        Button {
                            selection = option.name
                        } label: {
                            if option.prerelease {
                                Label("\(option.name)（预发布）", systemImage: "flask")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                }
            }
            Button("手动输入…") { manualMode = true }
            if !selection.isEmpty {
                Button("清除已选版本", role: .destructive) { selection = "" }
            }
        } else if isLoading {
            Text("正在读取上游版本…")
        } else {
            Button {
                Task { await load() }
            } label: {
                Label("读取上游版本列表", systemImage: "arrow.clockwise")
            }
        }
    }

    private func load() async {
        guard options == nil, loadError == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let result = await loadOptions()
        switch result {
        case .success(let list):
            options = list
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }
}

/// 便捷构造：把 throwing 的加载闭包包成 Result 形式。
extension VersionPickerField {
    static func makeLoader(_ load: @escaping (String, SourceKind) async throws -> [VersionOption],
                           repository: String, kind: SourceKind) -> () async -> Result<[VersionOption], any Error> {
        {
            do {
                return .success(try await load(repository, kind))
            } catch {
                return .failure(error)
            }
        }
    }
}
