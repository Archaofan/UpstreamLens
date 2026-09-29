import XCTest
@testable import UpstreamLens

final class WatchSourceDecodeTests: XCTestCase {
    /// 旧版 data.json / 旧备份没有 tags 键，必须解出空数组而不是解码失败。
    /// 用字典构造 JSON，确保这份数据里确实不含 tags 键。
    func testDecodesLegacyJSONWithoutTagsKey() throws {
        let id = UUID()
        let legacy: [String: Any] = [
            "id": id.uuidString,
            "kind": "Release",
            "repository": "n8n-io/n8n",
            "path": "",
            "branch": "",
            "displayName": "n8n",
            "purpose": "workflow",
            "installedVersion": "",
            "keywords": "",
            "rationale": "",
            "isPaused": false,
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("tags") ?? true,
                       "测试数据本身不应含 tags 键，否则测不出兼容性")

        let source = try JSONDecoder().decode(WatchSource.self, from: data)
        XCTAssertEqual(source.tags, [])
        XCTAssertEqual(source.repository, "n8n-io/n8n")
    }

    func testRoundTripsTags() throws {
        var source = WatchSource(repository: "n8n-io/n8n")
        source.tags = ["self-hosted", "AI"]
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(WatchSource.self, from: data)
        XCTAssertEqual(decoded.tags, ["self-hosted", "AI"])
    }

    func testTagsDefaultToEmptyForFreshSource() {
        XCTAssertEqual(WatchSource(repository: "n8n-io/n8n").tags, [])
    }
}
