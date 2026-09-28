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

final class GitHubClientTests: XCTestCase {
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
}
