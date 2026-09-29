import XCTest
@testable import UpstreamLens

final class RepoAvatarTests: XCTestCase {
    func testURLUsesGitHubCDNConvention() {
        XCTAssertEqual(RepoAvatar.url(for: "n8n-io/n8n")?.absoluteString,
                       "https://github.com/n8n-io.png?size=120")
        XCTAssertEqual(RepoAvatar.url(for: "openclaw/openclaw")?.absoluteString,
                       "https://github.com/openclaw.png?size=120")
    }

    func testURLTakesOnlyTheOwnerSegment() {
        // 深路径（tree/blob）也应按所有者取头像，不能把整条路径拼进 URL。
        XCTAssertEqual(RepoAvatar.url(for: "n8n-io/n8n/tree/master/skills/x")?.absoluteString,
                       "https://github.com/n8n-io.png?size=120")
    }

    func testURLRejectsInvalidInput() {
        XCTAssertNil(RepoAvatar.url(for: ""))
        XCTAssertNil(RepoAvatar.url(for: "   "))
        XCTAssertNil(RepoAvatar.url(for: "/n8n"), "前导斜杠会产生空 owner，必须拒绝")
        XCTAssertNil(RepoAvatar.url(for: " /n8n"))
        XCTAssertNil(RepoAvatar.url(for: "my owner/n8n"), "owner 含空白应拒绝")
    }

    func testOwnerExtraction() {
        XCTAssertEqual(RepoAvatar.owner(of: "n8n-io/n8n"), "n8n-io")
        XCTAssertEqual(RepoAvatar.owner(of: " n8n-io/n8n "), "n8n-io")
        XCTAssertEqual(RepoAvatar.owner(of: "a/b/c"), "a")
        XCTAssertEqual(RepoAvatar.owner(of: "a/"), "a")
        // 单独一个 owner 也容忍：与旧实现行为一致，取不到图时由调用方回退符号。
        XCTAssertEqual(RepoAvatar.owner(of: "n8n"), "n8n")
        XCTAssertNil(RepoAvatar.owner(of: ""))
        XCTAssertNil(RepoAvatar.owner(of: "  "))
        XCTAssertNil(RepoAvatar.owner(of: "/n8n"))
        XCTAssertNil(RepoAvatar.owner(of: " /n8n"))
        XCTAssertNil(RepoAvatar.owner(of: "my owner/n8n"))
    }

    func testFallbackSymbolsCoverEveryKind() {
        XCTAssertEqual(RepoAvatar.fallbackSymbol(for: .release), "shippingbox.fill")
        XCTAssertEqual(RepoAvatar.fallbackSymbol(for: .tag), "tag.fill")
        XCTAssertEqual(RepoAvatar.fallbackSymbol(for: .path), "doc.text.fill")
    }

    /// 头像必须走 CDN 约定而非 api.github.com，否则会吃掉用户本就不多的限额。
    func testURLNeverTargetsTheAPI() {
        for repo in ["n8n-io/n8n", "openclaw/openclaw", "deepseek-ai/deepseek-harness"] {
            let url = RepoAvatar.url(for: repo)
            XCTAssertNotNil(url)
            XCTAssertEqual(url?.host, "github.com")
            XCTAssertFalse(url?.absoluteString.contains("api.github.com") ?? true)
        }
    }

    /// 预设入口必须与通用入口一致，避免两套规则漂移。
    func testPresetIconURLMatchesRepoAvatar() {
        for preset in PresetLibrary.validated() {
            XCTAssertEqual(SourcePreset.iconURL(for: preset.repository),
                           RepoAvatar.url(for: preset.repository))
            XCTAssertEqual(preset.iconURL, RepoAvatar.url(for: preset.repository))
        }
    }
}
