import XCTest
@testable import UpstreamLens

final class URLParsingTests: XCTestCase {
    func testPlainOwnerRepo() {
        let parsed = ParsedGitHubURL.parse("acme/tool")
        XCTAssertEqual(parsed?.repository, "acme/tool")
        XCTAssertEqual(parsed?.target, .repository)
    }

    func testRepositoryURL() {
        let parsed = ParsedGitHubURL.parse("https://github.com/acme/tool")
        XCTAssertEqual(parsed?.repository, "acme/tool")
        XCTAssertEqual(parsed?.target, .repository)
    }

    func testRepositoryURLWithGitSuffix() {
        XCTAssertEqual(ParsedGitHubURL.parse("https://github.com/acme/tool.git")?.repository, "acme/tool")
        XCTAssertEqual(ParsedGitHubURL.parse("https://github.com/acme/tool.git")?.target, .repository)
    }

    func testSchemelessLink() {
        XCTAssertEqual(ParsedGitHubURL.parse("github.com/acme/tool")?.repository, "acme/tool")
    }

    func testTagLink() {
        let parsed = ParsedGitHubURL.parse("https://github.com/acme/tool/tree/v2.1.0")
        XCTAssertEqual(parsed?.target, .tree(ref: "v2.1.0", path: nil))
        let source = parsed?.watchSource
        XCTAssertEqual(source?.kind, .tag)
        XCTAssertEqual(source?.installedVersion, "v2.1.0")
    }

    func testDirectoryTreeLink() {
        let parsed = ParsedGitHubURL.parse("https://github.com/acme/tool/tree/main/docs/guide")
        XCTAssertEqual(parsed?.target, .tree(ref: "main", path: "docs/guide"))
        let source = parsed?.watchSource
        XCTAssertEqual(source?.kind, .path)
        XCTAssertEqual(source?.path, "docs/guide")
        XCTAssertEqual(source?.branch, "main")
    }

    func testBlobLinkPrefillsPathSource() {
        let parsed = ParsedGitHubURL.parse("https://github.com/acme/tool/blob/main/skills/foo/SKILL.md")
        XCTAssertEqual(parsed?.target, .blob(ref: "main", path: "skills/foo/SKILL.md"))
        let source = parsed?.watchSource
        XCTAssertEqual(source?.kind, .path)
        XCTAssertEqual(source?.path, "skills/foo/SKILL.md")
        XCTAssertEqual(source?.branch, "main")
    }

    func testReleasesLinkMapsToRepository() {
        XCTAssertEqual(ParsedGitHubURL.parse("https://github.com/acme/tool/releases")?.target, .repository)
        XCTAssertEqual(ParsedGitHubURL.parse("https://github.com/acme/tool/tags")?.target, .repository)
    }

    func testPercentEncodedPathIsDecoded() {
        let parsed = ParsedGitHubURL.parse("https://github.com/acme/tool/tree/main/my%20docs")
        XCTAssertEqual(parsed?.target, .tree(ref: "main", path: "my docs"))
    }

    func testInvalidInputs() {
        XCTAssertNil(ParsedGitHubURL.parse(""))
        XCTAssertNil(ParsedGitHubURL.parse("https://example.com/acme/tool"))
        XCTAssertNil(ParsedGitHubURL.parse("acme"))
    }

    func testIssueLinkStillOffersRepository() {
        // 粘贴 issue 链接时退化为监控整个仓库，而不是解析失败。
        let parsed = ParsedGitHubURL.parse("https://github.com/acme/tool/issues/12")
        XCTAssertEqual(parsed?.repository, "acme/tool")
        XCTAssertEqual(parsed?.target, .repository)
    }

    func testRepositoryLinkPrefillsReleaseSource() {
        let source = ParsedGitHubURL.parse("https://github.com/acme/tool")?.watchSource
        XCTAssertEqual(source?.kind, .release)
        XCTAssertEqual(source?.repository, "acme/tool")
    }
}
