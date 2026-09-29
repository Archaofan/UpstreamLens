import Foundation

struct RateLimitInfo: Equatable {
    let remaining: Int
    let total: Int
    let reset: Date

    var minutesUntilReset: Int {
        max(0, Int(ceil(reset.timeIntervalSinceNow / 60)))
    }

    static func from(_ response: HTTPURLResponse) -> RateLimitInfo? {
        func header(_ name: String) -> String? {
            response.value(forHTTPHeaderField: name)
        }
        guard let remainingText = header("X-RateLimit-Remaining"),
              let remaining = Int(remainingText),
              let resetText = header("X-RateLimit-Reset"),
              let resetEpoch = Double(resetText) else { return nil }
        let total = Int(header("X-RateLimit-Limit") ?? "") ?? 0
        return RateLimitInfo(remaining: remaining, total: total, reset: Date(timeIntervalSince1970: resetEpoch))
    }
}

enum GitHubError: LocalizedError {
    case invalidRepository
    case notFound
    case notAuthorized
    case rateLimited(RateLimitInfo?)
    case server(Int)
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "仓库格式应为 owner/repo。"
        case .notFound: return "仓库、分支或路径不存在，或无法公开访问（私有仓库需要开发者令牌，当前未配置）。"
        case .notAuthorized: return "GitHub 令牌无效或权限不足（401）。请检查令牌是否输入正确、是否已被撤销。"
        case .rateLimited(let info):
            if let info, info.minutesUntilReset > 0 {
                return "GitHub API 已限流，约 \(info.minutesUntilReset) 分钟后恢复。"
            }
            return "GitHub API 已限流，请稍后重试。"
        case .server(let code): return "GitHub 请求失败（HTTP \(code)）。"
        case .invalidResponse: return "GitHub 返回的数据无法解析。"
        case .network(let message): return "网络请求失败：\(message)"
        }
    }
}

struct GitHubFetch {
    var changes: [UpstreamChange]
    var etag: String?
    var unchanged: Bool
    var rateLimit: RateLimitInfo?
}

/// 解析用户粘贴的 GitHub 链接或 `owner/repo` 文本，映射为监控来源预填。
struct ParsedGitHubURL: Equatable {
    enum Target: Equatable {
        case repository
        case tag(ref: String)
        case tree(ref: String, path: String?)
        case blob(ref: String, path: String)
    }

    let owner: String
    let repo: String
    let target: Target

    var repository: String { "\(owner)/\(repo)" }

    static func parse(_ input: String) -> ParsedGitHubURL? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        var cameFromGitHubLink = false
        let lowered = value.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            guard let schemeRange = value.range(of: "://") else { return nil }
            let hostAndPath = value[schemeRange.upperBound...]
            guard hostAndPath.lowercased().hasPrefix("github.com/") else { return nil }
            value = String(hostAndPath.dropFirst("github.com/".count))
            cameFromGitHubLink = true
        } else if lowered.hasPrefix("github.com/") {
            value = String(value.dropFirst("github.com/".count))
            cameFromGitHubLink = true
        }
        let components = value.split(separator: "/").map(String.init)
        guard components.count >= 2, !components[0].isEmpty, !components[1].isEmpty else { return nil }
        guard components.allSatisfy({ !$0.contains(where: { $0 == "?" || $0 == "#" || $0 == "@" }) }) else { return nil }
        // 纯文本形式只接受 owner/repo 两段；GitHub 链接才允许 tree/blob 等更深路径。
        if !cameFromGitHubLink && components.count != 2 { return nil }
        var repoName = components[1]
        if repoName.hasSuffix(".git") { repoName.removeLast(4) }
        guard Self.validSegment(components[0]), Self.validSegment(repoName) else { return nil }
        let owner = components[0]

        func tail(_ index: Int) -> String {
            components[index...].joined(separator: "/")
        }
        func decoded(_ value: String) -> String {
            value.removingPercentEncoding ?? value
        }

        if components.count == 2 {
            return ParsedGitHubURL(owner: owner, repo: repoName, target: .repository)
        }
        switch components[2] {
        case "tree" where components.count >= 4:
            let ref = decoded(components[3])
            let path: String? = components.count > 4 ? decoded(tail(4)) : nil
            return ParsedGitHubURL(owner: owner, repo: repoName, target: .tree(ref: ref, path: path))
        case "blob" where components.count >= 5:
            return ParsedGitHubURL(owner: owner, repo: repoName,
                                   target: .blob(ref: decoded(components[3]), path: decoded(tail(4))))
        case "releases", "tags":
            return ParsedGitHubURL(owner: owner, repo: repoName, target: .repository)
        default:
            return ParsedGitHubURL(owner: owner, repo: repoName, target: .repository)
        }
    }

    /// 映射为新建来源的预填值。
    var watchSource: WatchSource {
        var source = WatchSource(repository: repository)
        switch target {
        case .repository:
            source.kind = .release
        case .tag(let ref):
            source.kind = .tag
            source.installedVersion = ref
        case .tree(let ref, let path):
            if let path {
                source.kind = .path
                source.path = path
                source.branch = ref
            } else {
                source.kind = .tag
                source.installedVersion = ref
            }
        case .blob(let ref, let path):
            source.kind = .path
            source.path = path
            source.branch = ref
        }
        return source
    }

    private static func validSegment(_ segment: String) -> Bool {
        segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }
}

struct RepoSearchResult: Codable, Equatable {
    let fullName: String
    let description: String?
    let stargazersCount: Int
    let topics: [String]?
    let defaultBranch: String?
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case stargazersCount = "stargazers_count"
        case topics
        case defaultBranch = "default_branch"
        case htmlURL = "html_url"
    }
}

struct RepoMetadata: Codable, Equatable {
    let fullName: String?
    let description: String?
    let defaultBranch: String?
    let topics: [String]?
    let stargazersCount: Int?
    let pushedAt: String?
    let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case defaultBranch = "default_branch"
        case topics
        case stargazersCount = "stargazers_count"
        case pushedAt = "pushed_at"
        case htmlURL = "html_url"
    }
}

struct LatestRelease: Codable, Equatable {
    let tagName: String
    let name: String?
    let htmlURL: String?
    let publishedAt: String?
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
    }
}

struct TreeScan: Equatable {
    let paths: [String]
    let truncated: Bool
}

/// 上游版本候选（下拉选项）：name 是 tag 名，prerelease 用于界面标注。
struct VersionOption: Equatable, Identifiable {
    let name: String
    let prerelease: Bool
    var id: String { name }
}

struct GitHubClient {
    private let session: URLSession
    /// 可选的 GitHub 令牌（Personal Access Token）；nil 表示未登录，走公开额度。
    var token: String?
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
    init(session: URLSession = GitHubClient.defaultSession) { self.session = session }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return iso8601Fractional.date(from: value) ?? iso8601.date(from: value)
    }

    func fetch(source: WatchSource) async throws -> GitHubFetch {
        let repository = try Self.normalizedRepository(source.repository)
        let endpoint: String
        var query: [URLQueryItem] = [URLQueryItem(name: "per_page", value: "100")]
        switch source.kind {
        case .release: endpoint = "releases"
        case .tag: endpoint = "tags"
        case .path:
            guard !source.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitHubError.notFound }
            endpoint = "commits"
            query.append(URLQueryItem(name: "path", value: source.path))
            if !source.branch.isEmpty { query.append(URLQueryItem(name: "sha", value: source.branch)) }
        }

        var all: [UpstreamChange] = []
        var tagShas: [String] = []
        var firstETag: String?
        var rateLimit: RateLimitInfo?
        for page in 1...3 {
            var pageQuery = query
            pageQuery.append(URLQueryItem(name: "page", value: String(page)))
            let (data, response, unchanged) = try await request(repository: repository, endpoint: endpoint,
                                                                query: pageQuery, etag: page == 1 ? source.etag : nil)
            rateLimit = RateLimitInfo.from(response) ?? rateLimit
            if unchanged { return GitHubFetch(changes: [], etag: source.etag, unchanged: true, rateLimit: rateLimit) }
            if page == 1 { firstETag = response.value(forHTTPHeaderField: "ETag") }
            let batch: [UpstreamChange]
            let tagShasForPage: [String]
            let pageCount: Int
            switch source.kind {
            case .release:
                let releases = try JSONDecoder().decode([ReleaseDTO].self, from: data)
                pageCount = releases.count
                tagShasForPage = []
                batch = releases
                    .filter { !$0.draft }
                    .map { UpstreamChange(identifier: String($0.id), title: ($0.name ?? "").isEmpty ? $0.tag_name : ($0.name ?? $0.tag_name),
                                          body: $0.body ?? "", url: $0.html_url,
                                          publishedAt: Self.date($0.published_at), content: nil,
                                          prerelease: $0.prerelease, versionHint: $0.tag_name) }
            case .tag:
                let tags = try JSONDecoder().decode([TagDTO].self, from: data)
                pageCount = tags.count
                tagShasForPage = tags.map(\.commit.sha)
                batch = tags
                    .map { UpstreamChange(identifier: $0.name, title: $0.name, body: "",
                                          url: "https://github.com/\(repository)/tree/\($0.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0.name)",
                                          publishedAt: nil, content: nil, versionHint: $0.name) }
            case .path:
                let commits = try JSONDecoder().decode([CommitDTO].self, from: data)
                pageCount = commits.count
                tagShasForPage = []
                batch = commits
                    .map { UpstreamChange(identifier: $0.sha, title: $0.commit.message.components(separatedBy: .newlines).first ?? $0.sha,
                                          body: $0.commit.message, url: $0.html_url,
                                          publishedAt: Self.date($0.commit.author?.date), content: nil) }
            }
            all += batch
            tagShas += tagShasForPage
            if source.baselineIdentifier == nil || pageCount < 100 || batch.contains(where: { $0.identifier == source.baselineIdentifier }) { break }
        }

        if source.kind == .path, all.isEmpty {
            _ = try await fileContent(repository: repository, path: source.path,
                                      ref: source.branch.isEmpty ? nil : source.branch)
        }

        if source.kind == .path, let first = all.first {
            let content: String?
            let deleted: Bool
            do {
                content = try await fileContent(repository: repository, path: source.path, ref: first.identifier)
                deleted = false
            } catch GitHubError.notFound {
                content = nil
                deleted = true
            }
            all[0] = UpstreamChange(identifier: first.identifier, title: first.title,
                                    body: first.body + (deleted ? "\n指定路径在该提交中已不存在。" : ""),
                                    url: first.url, publishedAt: first.publishedAt, content: content,
                                    prerelease: first.prerelease, versionHint: first.versionHint)
        }

        if source.kind == .tag, !all.isEmpty {
            // tags 接口不返回说明文字；用默认分支最近 100 条提交按 sha 关联提交标题。
            let messages = (try? await commitMessages(repository: repository)) ?? [:]
            all = all.enumerated().map { index, change in
                guard index < tagShas.count, let message = messages[tagShas[index]] else { return change }
                return UpstreamChange(identifier: change.identifier, title: change.title, body: message,
                                      url: change.url, publishedAt: change.publishedAt, content: change.content,
                                      prerelease: change.prerelease, versionHint: change.versionHint)
            }
        }
        return GitHubFetch(changes: all, etag: firstETag, unchanged: false, rateLimit: rateLimit)
    }

    // MARK: - 添加来源的探测接口

    func searchRepositories(_ query: String, perPage: Int = 10) async throws -> [RepoSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let (data, _) = try await searchRequest(path: "search/repositories",
                                                query: [URLQueryItem(name: "q", value: trimmed),
                                                        URLQueryItem(name: "per_page", value: String(perPage))])
        let payload = try JSONDecoder().decode(SearchResponseDTO.self, from: data)
        return payload.items
    }

    func repoMetadata(_ repository: String) async throws -> RepoMetadata {
        let (data, _) = try await plainRequest(repository: repository, endpoint: "", query: [], etag: nil)
        return try JSONDecoder().decode(RepoMetadata.self, from: data)
    }

    func latestRelease(_ repository: String) async throws -> LatestRelease? {
        do {
            let (data, _) = try await plainRequest(repository: repository, endpoint: "releases/latest", query: [], etag: nil)
            return try JSONDecoder().decode(LatestRelease.self, from: data)
        } catch GitHubError.notFound {
            return nil
        }
    }

    /// 枚举仓库文件树，返回匹配后缀的候选路径（如 SKILL.md）。
    func treePaths(_ repository: String, ref: String, suffixes: [String] = ["SKILL.md"]) async throws -> TreeScan {
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        let (data, _) = try await plainRequest(repository: repository, endpoint: "git/trees/\(encodedRef)",
                                               query: [URLQueryItem(name: "recursive", value: "1")], etag: nil)
        let payload = try JSONDecoder().decode(TreeDTO.self, from: data)
        let paths = payload.tree
            .filter { $0.type == "blob" }
            .map(\.path)
            .filter { path in suffixes.contains(where: path.hasSuffix) }
        return TreeScan(paths: paths, truncated: payload.truncated)
    }

    /// 上游版本候选列表：“正在使用的版本”下拉的数据源，1 次核心接口请求。
    /// path 模式的版本是提交 SHA，不适合下拉选择，直接返回空数组且不发请求。
    func versionOptions(repository: String, kind: SourceKind, perPage: Int = 30) async throws -> [VersionOption] {
        let repository = try Self.normalizedRepository(repository)
        switch kind {
        case .path:
            return []
        case .release:
            let (data, _) = try await plainRequest(repository: repository, endpoint: "releases",
                                                   query: [URLQueryItem(name: "per_page", value: String(perPage))],
                                                   etag: nil)
            let releases = try JSONDecoder().decode([ReleaseDTO].self, from: data)
            return releases.filter { !$0.draft }.map { VersionOption(name: $0.tag_name, prerelease: $0.prerelease) }
        case .tag:
            let (data, _) = try await plainRequest(repository: repository, endpoint: "tags",
                                                   query: [URLQueryItem(name: "per_page", value: String(perPage))],
                                                   etag: nil)
            let tags = try JSONDecoder().decode([TagDTO].self, from: data)
            return tags.map { VersionOption(name: $0.name, prerelease: false) }
        }
    }

    /// 校验令牌并返回 authenticated 核心配额。`GET /rate_limit` 不消耗额度。
    /// 令牌无效（401）抛 `.notAuthorized`；不带令牌也可调用（返回 60 的公开配额）。
    func rateLimitStatus(token: String? = nil) async throws -> RateLimitInfo {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = "/rate_limit"
        guard let url = components.url else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        applyHeaders(&request, token: token ?? self.token)
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            guard let info = RateLimitInfo.from(response) else { throw GitHubError.invalidResponse }
            return info
        case 401:
            throw GitHubError.notAuthorized
        default:
            throw GitHubError.server(response.statusCode)
        }
    }

    private func commitMessages(repository: String) async throws -> [String: String] {
        let (data, _) = try await plainRequest(repository: repository, endpoint: "commits",
                                               query: [URLQueryItem(name: "per_page", value: "100")], etag: nil)
        let commits = try JSONDecoder().decode([CommitDTO].self, from: data)
        var messages: [String: String] = [:]
        for commit in commits {
            messages[commit.sha] = commit.commit.message.components(separatedBy: .newlines).first ?? commit.sha
        }
        return messages
    }

    static func normalizedRepository(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let host = url.host, host.lowercased() == "github.com" {
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if value.hasSuffix(".git") { value.removeLast(4) }
        let parts = value.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." } }) else {
            throw GitHubError.invalidRepository
        }
        return parts.joined(separator: "/")
    }

    // MARK: - 请求实现

    /// 统一设置 GitHub 要求的请求头；token 非空时附带 `Authorization: Bearer`。
    /// token 为 nil 时与未登录行为逐字节一致（不加 Authorization 头）。
    private func applyHeaders(_ request: inout URLRequest, token: String?) {
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UpstreamLens/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private struct SearchResponseDTO: Decodable {
        let items: [RepoSearchResult]
    }

    private struct TreeDTO: Decodable {
        let tree: [Entry]
        let truncated: Bool
        struct Entry: Decodable {
            let path: String
            let type: String
        }
    }

    private func fileContent(repository: String, path: String, ref: String?) async throws -> String? {
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let (data, _, _) = try await request(repository: repository, endpoint: "contents/\(encoded)",
                                             query: ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? [], etag: nil)
        guard let object = try? JSONDecoder().decode(ContentDTO.self, from: data), object.type == "file",
              object.encoding == "base64", let encodedContent = object.content,
              let decoded = Data(base64Encoded: encodedContent.filter { !$0.isWhitespace }) else { return nil }
        return String(data: decoded, encoding: .utf8)
    }

    private func request(repository: String, endpoint: String, query: [URLQueryItem], etag: String?) async throws -> (Data, HTTPURLResponse, Bool) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = "/repos/\(repository)\(endpoint.isEmpty ? "" : "/\(endpoint)")"
        components.queryItems = query
        guard let url = components.url else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        applyHeaders(&request, token: token)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200: return (data, response, false)
        case 304: return (data, response, true)
        case 404: throw GitHubError.notFound
        case 429: throw GitHubError.rateLimited(RateLimitInfo.from(response))
        case 403:
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw GitHubError.rateLimited(RateLimitInfo.from(response))
            }
            throw GitHubError.server(response.statusCode)
        default: throw GitHubError.server(response.statusCode)
        }
    }

    private func plainRequest(repository: String, endpoint: String, query: [URLQueryItem], etag: String?) async throws -> (Data, HTTPURLResponse) {
        let (data, response, unchanged) = try await request(repository: repository, endpoint: endpoint, query: query, etag: etag)
        if unchanged { throw GitHubError.server(304) }
        return (data, response)
    }

    private func searchRequest(path: String, query: [URLQueryItem]) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = "/\(path)"
        components.queryItems = query
        guard let url = components.url else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        applyHeaders(&request, token: token)
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200: return (data, response)
        case 403, 429:
            throw GitHubError.rateLimited(RateLimitInfo.from(response))
        default: throw GitHubError.server(response.statusCode)
        }
    }

    /// 网络错误或 5xx 时重试一次（间隔 1 秒）；403/404/304 等语义响应不重试。
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0...1 {
            do {
                let (data, raw) = try await session.data(for: request)
                guard let response = raw as? HTTPURLResponse else { throw GitHubError.invalidResponse }
                if response.statusCode >= 500, attempt == 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                return (data, response)
            } catch let error as GitHubError {
                throw error
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                throw GitHubError.network(error.localizedDescription)
            }
        }
        throw GitHubError.network("请求未能完成")
    }
}

private struct ReleaseDTO: Decodable {
    let id: Int
    let name: String?
    let tag_name: String
    let body: String?
    let html_url: String
    let published_at: String?
    let draft: Bool
    let prerelease: Bool
}

private struct TagDTO: Decodable {
    let name: String
    let commit: CommitRef
    struct CommitRef: Decodable { let sha: String }
}

struct CommitDTO: Decodable {
    let sha: String
    let html_url: String
    let commit: Detail
    struct Detail: Decodable {
        let message: String
        let author: Author?
    }
    struct Author: Decodable { let date: String? }
}

private struct ContentDTO: Decodable {
    let type: String
    let encoding: String?
    let content: String?
}
