import XCTest
@testable import UpstreamLens

final class SourceListImportTests: XCTestCase {
    private let sampleObject = """
    说明文字可以随便写。
    ```json
    {
      "schema": "upstreamlens.source-list",
      "version": 1,
      "sources": [
        {"repository": "openclaw/openclaw", "kind": "release", "installedVersion": "1.4.2",
         "displayName": "OpenClaw", "keywords": "breaking, security", "purpose": "本机部署的 AI 助理"},
        {"repository": "https://github.com/n8n-io/n8n", "kind": "TAG"},
        {"repository": "obra/superpowers", "kind": "path", "path": "skills", "branch": "main"}
      ]
    }
    ```
    """

    func testParseHandlesFencesAndMapsFields() throws {
        let parsed = try SourceListImport.parse(Data(sampleObject.utf8))
        XCTAssertEqual(parsed.warnings, [])
        XCTAssertEqual(parsed.sources.count, 3)

        let first = parsed.sources[0]
        XCTAssertEqual(first.repository, "openclaw/openclaw")
        XCTAssertEqual(first.kind, .release)
        XCTAssertEqual(first.installedVersion, "1.4.2")
        XCTAssertEqual(first.displayName, "OpenClaw")
        XCTAssertEqual(first.keywords, "breaking, security")
        XCTAssertEqual(first.purpose, "本机部署的 AI 助理")

        // URL 形式归一化为 owner/repo；kind 大小写不敏感；缺省字段为空。
        let second = parsed.sources[1]
        XCTAssertEqual(second.repository, "n8n-io/n8n")
        XCTAssertEqual(second.kind, .tag)
        XCTAssertTrue(second.installedVersion.isEmpty)

        let third = parsed.sources[2]
        XCTAssertEqual(third.kind, .path)
        XCTAssertEqual(third.path, "skills")
        XCTAssertEqual(third.branch, "main")
    }

    func testParseAcceptsTopLevelArray() throws {
        let array = #"{"repository": "langgenius/dify", "installedVersion": "0.9.0"}"#
        let parsed = try SourceListImport.parse(Data(("```json\n[\(array)]\n```" as String).utf8))
        XCTAssertEqual(parsed.sources.count, 1)
        XCTAssertEqual(parsed.sources[0].kind, .release, "缺省 kind 按 release 处理")
    }

    func testParseSkipsInvalidEntriesWithWarnings() throws {
        let json = """
        [
          {"repository": "not a repo at all/with/too/many/slashes"},
          {"repository": "open-webui/open-webui", "kind": "path"},
          {"repository": "langgenius/dify", "kind": "yaml"},
          {"repository": "  ", "kind": "release"}
        ]
        """
        let parsed = try SourceListImport.parse(Data(json.utf8))
        // path 模式缺 path 被跳过；kind 无法识别降级为 release；空仓库直接忽略。
        XCTAssertEqual(parsed.sources.map(\.repository), ["langgenius/dify"])
        XCTAssertEqual(parsed.sources[0].kind, .release)
        XCTAssertTrue(parsed.warnings.contains { $0.contains("open-webui/open-webui") && $0.contains("path") })
        XCTAssertTrue(parsed.warnings.contains { $0.contains("yaml") })
    }

    func testParseDeduplicatesWithinList() throws {
        let json = """
        [{"repository": "a/b"}, {"repository": "a/b", "kind": "release"}, {"repository": "a/b", "kind": "tag"}]
        """
        let parsed = try SourceListImport.parse(Data(json.utf8))
        XCTAssertEqual(parsed.sources.count, 2, "同仓库同模式只保留一条，不同模式各自保留")
    }

    func testParseThrowsForNonJSON() {
        XCTAssertThrowsError(try SourceListImport.parse(Data("这不是 JSON".utf8))) { error in
            XCTAssertTrue(error is SourceListError)
        }
        XCTAssertThrowsError(try SourceListImport.parse(Data("[]".utf8)))
    }

    func testExtractFencedJSONWithoutClosingFenceTakesRest() {
        let text = "前缀说明\n```json\n{\"a\":1}\n"
        XCTAssertEqual(SourceListImport.extractFencedJSON(text), "{\"a\":1}\n")
    }

    func testBOMIsIgnored() throws {
        let bom = "\u{FEFF}" + #"{"sources": [{"repository": "a/b"}]}"#
        let parsed = try SourceListImport.parse(Data(bom.utf8))
        XCTAssertEqual(parsed.sources.count, 1)
    }
}
