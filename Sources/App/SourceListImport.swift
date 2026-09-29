import Foundation

/// AI 生成的监控来源清单（schema: `upstreamlens.source-list`）。
/// 用户把“帮助”里的提示词交给任意 AI，AI 检索本机在用的开源项目后输出 JSON；
/// App 合并导入，不覆盖已有数据。
struct SourceListDocument: Codable {
    var schema: String?
    var version: Int?
    var sources: [SourceListEntry]?

    struct SourceListEntry: Codable {
        var repository: String
        var kind: String?
        var path: String?
        var branch: String?
        var displayName: String?
        var installedVersion: String?
        var keywords: String?
        var purpose: String?
    }
}

enum SourceListError: LocalizedError {
    case notJSON
    case noSources

    var errorDescription: String? {
        switch self {
        case .notJSON: return "文件不是有效的来源清单 JSON；请让 AI 直接输出 JSON（可带 ```json 代码围栏）后再保存导入。"
        case .noSources: return "清单里没有可导入的来源。"
        }
    }
}

enum SourceListImport {
    /// 设置页展示并复制的提示词：让 AI 在本机检索在用项目，按 schema 输出 JSON。
    static let prompt = """
        请检查我的电脑/服务器，找出我正在实际使用的开源 GitHub 项目，生成 UpstreamLens 监控来源清单 JSON。

        检查范围（按需）：
        1. 包管理器与工具链：brew list、npm ls -g、pip list、cargo install --list、go version -m 等。
        2. 项目依赖文件：package.json、requirements.txt、pyproject.toml、go.mod、Cargo.toml、Podfile.lock。
        3. 本机部署的服务：Docker 容器镜像、systemd 服务、常用 CLI 工具、编辑器插件。

        对每个项目输出：
        - repository：GitHub 仓库，格式 owner/repo；
        - installedVersion：本机正在使用的版本号（从包管理器或 --version 读取，读不到就留空）；
        - kind：release（跟 Release 版本，默认）、tag（无 Release 的仓库用 Tag）、path（只盯仓库里某个文件）；
        - displayName / keywords / purpose：显示名、我可能关注的关键词、我用它做什么。

        只输出一个 JSON 代码块，不要其他解释，格式如下：
        ```json
        {
          "schema": "upstreamlens.source-list",
          "version": 1,
          "sources": [
            {
              "repository": "owner/repo",
              "kind": "release",
              "installedVersion": "1.2.3",
              "displayName": "显示名",
              "keywords": "关键词1, 关键词2",
              "purpose": "我在什么场景使用它"
            }
          ]
        }
        ```
        """

    /// 解析清单：容忍 UTF-8 BOM、Markdown 代码围栏与说明文字（取首个围栏内容）；
    /// 同时接受对象或顶层数组两种形态。无效条目跳过并给出原因，不阻塞其余导入。
    static func parse(_ data: Data) throws -> (sources: [WatchSource], warnings: [String]) {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingBOM
        let jsonText = extractFencedJSON(text)
        guard let jsonData = jsonText.data(using: .utf8) else { throw SourceListError.notJSON }
        let decoder = JSONDecoder()
        var entries: [SourceListDocument.SourceListEntry]
        if let document = try? decoder.decode(SourceListDocument.self, from: jsonData) {
            entries = document.sources ?? []
        } else if let array = try? decoder.decode([SourceListDocument.SourceListEntry].self, from: jsonData) {
            entries = array
        } else {
            throw SourceListError.notJSON
        }
        guard !entries.isEmpty else { throw SourceListError.noSources }

        var sources: [WatchSource] = []
        var warnings: [String] = []
        var seen = Set<String>()
        for entry in entries {
            let rawRepository = entry.repository.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawRepository.isEmpty else { continue }
            let repository: String
            if let parsed = ParsedGitHubURL.parse(rawRepository) {
                repository = parsed.repository
            } else if let normalized = try? GitHubClient.normalizedRepository(rawRepository) {
                repository = normalized
            } else {
                warnings.append("已跳过「\(rawRepository)」：仓库格式不是 owner/repo 或 GitHub 链接。")
                continue
            }
            let kind = mappedKind(entry.kind, repository: repository, warnings: &warnings)
            let path = (entry.path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == .path && path.isEmpty {
                warnings.append("已跳过「\(repository)」：kind=path 时必须提供 path 字段。")
                continue
            }
            let dedupeKey = "\(repository)|\(kind.rawValue)|\(path)"
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)
            var source = WatchSource(kind: kind, repository: repository)
            source.path = path
            source.branch = (entry.branch ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            source.displayName = (entry.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            source.installedVersion = (entry.installedVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            source.keywords = (entry.keywords ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            source.purpose = (entry.purpose ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            sources.append(source)
        }
        guard !sources.isEmpty else { throw SourceListError.noSources }
        return (sources, warnings)
    }

    /// 清单里的 kind 用英文小写；无法识别时按 release 处理并提示。
    static func mappedKind(_ raw: String?, repository: String, warnings: inout [String]) -> SourceKind {
        switch raw?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "tag": return .tag
        case "path": return .path
        case "release", nil, "": return .release
        default:
            warnings.append("「\(repository)」的 kind「\(raw!)」无法识别，已按 release 处理。")
            return .release
        }
    }

    /// AI 常把 JSON 包在 ```json …``` 里或前后加说明文字：取首个围栏行到其后第一个闭合围栏之间；
    /// 没有围栏则原样返回（由 JSON 解码器决定成败）。
    static func extractFencedJSON(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let isFence = { (line: String) in line.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        guard let opening = lines.firstIndex(where: isFence) else { return text }
        guard let closing = lines[(lines.index(after: opening))...].firstIndex(where: isFence) else {
            return lines[(lines.index(after: opening))...].joined(separator: "\n")
        }
        return lines[(lines.index(after: opening))..<closing].joined(separator: "\n")
    }
}

private extension String {
    /// 去掉 UTF-8 BOM（某些编辑器保存带 BOM 的 JSON）。
    var trimmingBOM: String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }
}
