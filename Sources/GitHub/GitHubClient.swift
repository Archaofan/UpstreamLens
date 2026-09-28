import Foundation

enum GitHubError: LocalizedError {
    case invalidRepository
    case notFound
    case rateLimited
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "仓库格式应为 owner/repo。"
        case .notFound: return "仓库、分支或路径不存在，或无法公开访问。"
        case .rateLimited: return "GitHub API 已限流，请稍后重试。"
        case .server(let code): return "GitHub 请求失败（HTTP \(code)）。"
        case .invalidResponse: return "GitHub 返回的数据无法解析。"
        }
    }
}

struct GitHubFetch {
    var changes: [UpstreamChange]
    var etag: String?
    var unchanged: Bool
}

struct GitHubClient {
    private let session: URLSession
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()
    init(session: URLSession = GitHubClient.defaultSession) { self.session = session }

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
        var firstETag: String?
        for page in 1...3 {
            var pageQuery = query
            pageQuery.append(URLQueryItem(name: "page", value: String(page)))
            let (data, response, unchanged) = try await request(repository: repository, endpoint: endpoint,
                                                                  query: pageQuery, etag: page == 1 ? source.etag : nil)
            if unchanged { return GitHubFetch(changes: [], etag: source.etag, unchanged: true) }
            if page == 1 { firstETag = response.value(forHTTPHeaderField: "ETag") }
            let batch: [UpstreamChange]
            let pageCount: Int
            switch source.kind {
            case .release:
                let releases = try JSONDecoder().decode([ReleaseDTO].self, from: data)
                pageCount = releases.count
                batch = releases
                    .filter { !$0.draft }
                    .map { UpstreamChange(identifier: String($0.id), title: ($0.name ?? "").isEmpty ? $0.tag_name : ($0.name ?? $0.tag_name),
                                          body: $0.body ?? "", url: $0.html_url,
                                          publishedAt: Self.date($0.published_at), content: nil) }
            case .tag:
                let tags = try JSONDecoder().decode([TagDTO].self, from: data)
                pageCount = tags.count
                batch = tags
                    .map { UpstreamChange(identifier: $0.name, title: $0.name, body: "",
                                          url: "https://github.com/\(repository)/tree/\($0.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0.name)",
                                          publishedAt: nil, content: nil) }
            case .path:
                let commits = try JSONDecoder().decode([CommitDTO].self, from: data)
                pageCount = commits.count
                batch = commits
                    .map { UpstreamChange(identifier: $0.sha, title: $0.commit.message.components(separatedBy: .newlines).first ?? $0.sha,
                                          body: $0.commit.message, url: $0.html_url,
                                          publishedAt: Self.date($0.commit.author?.date), content: nil) }
            }
            all += batch
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
                                    url: first.url, publishedAt: first.publishedAt, content: content)
        }
        return GitHubFetch(changes: all, etag: firstETag, unchanged: false)
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
        components.percentEncodedPath = "/repos/\(repository)/\(endpoint)"
        components.queryItems = query
        guard let url = components.url else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UpstreamLens/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, raw) = try await session.data(for: request)
        guard let response = raw as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        switch response.statusCode {
        case 200: return (data, response, false)
        case 304: return (data, response, true)
        case 404: throw GitHubError.notFound
        case 429: throw GitHubError.rateLimited
        case 403:
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" { throw GitHubError.rateLimited }
            throw GitHubError.server(response.statusCode)
        default: throw GitHubError.server(response.statusCode)
        }
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
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
}

private struct TagDTO: Decodable {
    let name: String
    let commit: CommitRef
    struct CommitRef: Decodable { let sha: String }
}

private struct CommitDTO: Decodable {
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
