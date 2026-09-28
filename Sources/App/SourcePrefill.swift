import Foundation

/// 添加来源时的探测结果：预填来源 + 仓库元数据 + 最新版本 + 非致命警告。
struct RepoProbe {
    let source: WatchSource
    let metadata: RepoMetadata?
    let latest: LatestRelease?
    let warnings: [String]
}

enum RepoProbing {
    /// 输入可以是 `owner/repo` 或任意 GitHub 链接；任何一步失败都不阻塞保存，
    /// 只把对应字段退回手填并给出警告。
    static func probe(_ input: String, client: GitHubClient = GitHubClient()) async throws -> RepoProbe {
        let repository = try GitHubClient.normalizedRepository(input)
        var source = ParsedGitHubURL.parse(input)?.watchSource ?? WatchSource(repository: repository)
        source.repository = repository
        var warnings: [String] = []
        var metadata: RepoMetadata?
        var latest: LatestRelease?
        do {
            metadata = try await client.repoMetadata(repository)
            source.repoDescription = metadata?.description
            source.defaultBranch = metadata?.defaultBranch
            source.topics = metadata?.topics
            if source.kind == .path, source.branch.isEmpty, let branch = metadata?.defaultBranch {
                source.branch = branch
            }
        } catch GitHubError.notFound {
            warnings.append("无法读取仓库信息：仓库不存在或为私有（未配置令牌时只能监控公开仓库）。")
        } catch {
            warnings.append("仓库信息读取失败：\(error.localizedDescription)")
        }
        do {
            latest = try await client.latestRelease(repository)
            if source.kind == .release, source.installedVersion.isEmpty, let tag = latest?.tagName {
                source.installedVersion = tag
            }
        } catch {
            // latestRelease 缺失很常见（无 Release 的仓库），不打扰用户。
        }
        if latest == nil, source.kind == .release, metadata != nil {
            source.kind = .tag
        }
        return RepoProbe(source: source, metadata: metadata, latest: latest, warnings: warnings)
    }

    /// 枚举仓库文件树中的候选路径（默认 SKILL.md）。branch 为空时扫描默认分支。
    static func probePaths(_ repository: String, branch: String, suffixes: [String] = ["SKILL.md"],
                           client: GitHubClient = GitHubClient()) async throws -> TreeScan {
        try await client.treePaths(repository, ref: branch.isEmpty ? "HEAD" : branch, suffixes: suffixes)
    }
}
