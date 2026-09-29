import XCTest
import Foundation
@testable import UpstreamLens

private final class MissingPathProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isContents = request.url?.path.contains("/contents/") == true
        let response = HTTPURLResponse(url: request.url!, statusCode: isContents ? 404 : 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isContents ? Data() : Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 按路径路由的假 API；handler 由各测试用例设置。
final class MockAPIProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data, [String: String]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, data, headers) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GitHubClientTests: XCTestCase {
    private func mockedClient() -> GitHubClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAPIProtocol.self]
        return GitHubClient(session: URLSession(configuration: configuration))
    }

    func testMissingPathIsAnErrorWhenCommitListIsEmpty() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MissingPathProtocol.self]
        let client = GitHubClient(session: URLSession(configuration: configuration))
        let source = WatchSource(kind: .path, repository: "acme/tool", path: "skills/missing/SKILL.md")
        do {
            _ = try await client.fetch(source: source)
            XCTFail("A nonexistent path must not be accepted as an empty baseline")
        } catch GitHubError.notFound {
            // Expected: the Contents API confirms that the path does not exist.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSearchDecodesResults() async throws {
        MockAPIProtocol.handler = { request in
            XCTAssertTrue(request.url?.path.contains("/search/repositories") == true)
            let body = """
            {"total_count": 1, "incomplete_results": false, "items": [
              {"full_name": "acme/tool", "description": "A tool", "stargazers_count": 42,
               "topics": ["swift"], "default_branch": "main", "html_url": "https://github.com/acme/tool"}
            ]}
            """
            return (200, Data(body.utf8), [:])
        }
        let results = try await mockedClient().searchRepositories("tool")
        XCTAssertEqual(results.first?.fullName, "acme/tool")
        XCTAssertEqual(results.first?.stargazersCount, 42)
        XCTAssertEqual(results.first?.defaultBranch, "main")
    }

    func testSearchRateLimitSurfacesResetTime() async {
        MockAPIProtocol.handler = { _ in
            (403, Data("{}".utf8), ["X-RateLimit-Remaining": "0", "X-RateLimit-Limit": "10",
                                    "X-RateLimit-Reset": String(Int(Date().timeIntervalSince1970 + 600))])
        }
        do {
            _ = try await mockedClient().searchRepositories("tool")
            XCTFail("Expected rate limit error")
        } catch GitHubError.rateLimited(let info) {
            XCTAssertEqual(info?.remaining, 0)
            XCTAssertEqual(info?.minutesUntilReset, 10)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRepoMetadataDecodes() async throws {
        MockAPIProtocol.handler = { request in
            XCTAssertTrue(request.url?.path == "/repos/acme/tool")
            let body = """
            {"full_name": "acme/tool", "description": "A tool", "default_branch": "main",
             "topics": ["a", "b"], "stargazers_count": 7, "pushed_at": "2026-09-01T00:00:00Z",
             "html_url": "https://github.com/acme/tool"}
            """
            return (200, Data(body.utf8), [:])
        }
        let metadata = try await mockedClient().repoMetadata("acme/tool")
        XCTAssertEqual(metadata.defaultBranch, "main")
        XCTAssertEqual(metadata.topics, ["a", "b"])
        XCTAssertEqual(metadata.stargazersCount, 7)
    }

    func testLatestRelease404IsNil() async throws {
        MockAPIProtocol.handler = { _ in (404, Data("{}".utf8), [:]) }
        let latest = try await mockedClient().latestRelease("acme/tool")
        XCTAssertNil(latest)
    }

    func testLatestReleaseDecodes() async throws {
        MockAPIProtocol.handler = { _ in
            let body = """
            {"tag_name": "v2.0.0", "name": "Two point oh", "html_url": "https://github.com/acme/tool/releases/tag/v2.0.0",
             "published_at": "2026-09-01T00:00:00Z", "prerelease": false}
            """
            return (200, Data(body.utf8), [:])
        }
        let latest = try await mockedClient().latestRelease("acme/tool")
        XCTAssertEqual(latest?.tagName, "v2.0.0")
        XCTAssertEqual(latest?.prerelease, false)
    }

    func testTreePathsFiltersBlobs() async throws {
        MockAPIProtocol.handler = { request in
            XCTAssertTrue(request.url?.query?.contains("recursive=1") == true)
            let body = """
            {"truncated": false, "tree": [
              {"path": "skills/a/SKILL.md", "type": "blob"},
              {"path": "skills", "type": "tree"},
              {"path": "skills/b/SKILL.md", "type": "blob"},
              {"path": "README.md", "type": "blob"}
            ]}
            """
            return (200, Data(body.utf8), [:])
        }
        let scan = try await mockedClient().treePaths("acme/tool", ref: "HEAD")
        XCTAssertEqual(scan.paths, ["skills/a/SKILL.md", "skills/b/SKILL.md"])
        XCTAssertFalse(scan.truncated)
    }

    func testReleaseFetchFlagsPrereleaseAndVersionHint() async throws {
        MockAPIProtocol.handler = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/releases") == true)
            let body = """
            [{"id": 1, "name": "Beta", "tag_name": "v2.0.0-rc.1", "body": "notes", "html_url": "u",
              "published_at": "2026-09-01T00:00:00Z", "draft": false, "prerelease": true}]
            """
            return (200, Data(body.utf8), [:])
        }
        let fetch = try await mockedClient().fetch(source: WatchSource(repository: "acme/tool"))
        XCTAssertEqual(fetch.changes.first?.prerelease, true)
        XCTAssertEqual(fetch.changes.first?.versionHint, "v2.0.0-rc.1")
    }

    func testTagFetchJoinsCommitMessages() async throws {
        MockAPIProtocol.handler = { request in
            if request.url?.path.hasSuffix("/tags") == true {
                let body = """
                [{"name": "v2.0.0", "commit": {"sha": "abc123"}}]
                """
                return (200, Data(body.utf8), [:])
            }
            if request.url?.path.hasSuffix("/commits") == true {
                let body = """
                [{"sha": "abc123", "html_url": "u", "commit": {"message": "Fix crash on launch\\n\\ndetail", "author": {"date": "2026-01-01T00:00:00Z"}}}]
                """
                return (200, Data(body.utf8), [:])
            }
            return (404, Data(), [:])
        }
        let fetch = try await mockedClient().fetch(source: WatchSource(kind: .tag, repository: "acme/tool"))
        XCTAssertEqual(fetch.changes.first?.body, "Fix crash on launch")
        XCTAssertEqual(fetch.changes.first?.versionHint, "v2.0.0")
    }

    func testFetchSurfacesRateLimitHeaders() async throws {
        MockAPIProtocol.handler = { _ in
            (200, Data("[]".utf8),
             ["X-RateLimit-Remaining": "42", "X-RateLimit-Limit": "60",
              "X-RateLimit-Reset": String(Int(Date().timeIntervalSince1970 + 1200))])
        }
        let fetch = try await mockedClient().fetch(source: WatchSource(repository: "acme/tool"))
        XCTAssertEqual(fetch.rateLimit?.remaining, 42)
        XCTAssertEqual(fetch.rateLimit?.total, 60)
        XCTAssertEqual(fetch.rateLimit?.minutesUntilReset, 20)
    }

    func testFractionalSecondsAndPlainDatesParse() {
        XCTAssertNotNil(GitHubClient.date("2026-01-01T00:00:00Z"))
        XCTAssertNotNil(GitHubClient.date("2026-01-01T00:00:00.123Z"))
        XCTAssertNil(GitHubClient.date("not-a-date"))
        XCTAssertNil(GitHubClient.date(nil))
    }

    func testRepoURLNormalizationStillWorks() throws {
        XCTAssertEqual(try GitHubClient.normalizedRepository("https://github.com/acme/tool.git"), "acme/tool")
        XCTAssertThrowsError(try GitHubClient.normalizedRepository("https://example.com/acme/tool"))
    }

    // MARK: - 版本下拉（versionOptions）

    func testVersionOptionsFromReleasesFilterDraftsAndFlagPrerelease() async throws {
        MockAPIProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/releases"))
            let json = """
            [{"id":1,"tag_name":"v2.0.0","name":"Two","html_url":"u","draft":false,"prerelease":false},
             {"id":2,"tag_name":"v2.1.0-rc1","name":null,"html_url":"u","draft":false,"prerelease":true},
             {"id":3,"tag_name":"v1.9.0","name":null,"html_url":"u","draft":true,"prerelease":false}]
            """
            return (200, Data(json.utf8), [:])
        }
        let options = try await mockedClient().versionOptions(repository: "acme/tool", kind: .release)
        XCTAssertEqual(options.map(\.name), ["v2.0.0", "v2.1.0-rc1"], "草稿不进入下拉")
        XCTAssertEqual(options[1].prerelease, true)
    }

    func testVersionOptionsFromTagsReturnNames() async throws {
        MockAPIProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/tags"))
            let json = #"[]"#
            return (200, Data(json.utf8), [:])
        }
        let options = try await mockedClient().versionOptions(repository: "acme/tool", kind: .tag)
        XCTAssertTrue(options.isEmpty)
    }

    func testVersionOptionsPathModeSkipsNetwork() async throws {
        MockAPIProtocol.handler = { _ in
            XCTFail("path 模式不应发起请求")
            return (500, Data(), [:])
        }
        let options = try await mockedClient().versionOptions(repository: "acme/tool", kind: .path)
        XCTAssertTrue(options.isEmpty)
    }

    func testVersionOptionsRejectsInvalidRepository() async {
        do {
            _ = try await mockedClient().versionOptions(repository: "not valid", kind: .release)
            XCTFail("无效仓库必须抛错")
        } catch { /* 预期 */ }
    }
}
