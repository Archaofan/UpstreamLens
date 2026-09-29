import XCTest
@testable import UpstreamLens

final class SourceOrganizerTests: XCTestCase {
    private func make(_ repo: String, _ name: String = "", purpose: String = "",
                      keywords: String = "", tags: [String] = []) -> WatchSource {
        var s = WatchSource(repository: repo)
        s.displayName = name
        s.purpose = purpose
        s.keywords = keywords
        s.tags = tags
        return s
    }

    // MARK: 关键词过滤

    func testFilterMatchesEverySearchableField() {
        let sources = [
            make("openclaw/openclaw", "OpenClaw"),
            make("n8n-io/n8n", purpose: "workflow automation"),
            make("a/b", keywords: "breaking change"),
            make("c/d", tags: ["self-hosted"]),
        ]
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "openclaw").count, 1)
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "n8n-io").count, 1)
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "workflow").count, 1)
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "breaking").count, 1)
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "self-hosted").count, 1)
    }

    func testFilterIsCaseInsensitiveAndTrimsQuery() {
        let sources = [make("n8n-io/n8n", "n8n Workflow")]
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "  N8N  ").count, 1)
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "WORKFLOW").count, 1)
    }

    func testFilterEmptyQueryReturnsEverything() {
        let sources = [make("a/b"), make("c/d")]
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "").count, 2)
        XCTAssertEqual(SourceOrganizer.filter(sources, query: "   ").count, 2)
    }

    func testFilterNoMatchReturnsEmpty() {
        XCTAssertTrue(SourceOrganizer.filter([make("a/b")], query: "zzz").isEmpty)
    }

    // MARK: 标签筛选

    func testFilterByTag() {
        let sources = [make("a/b", tags: ["AI", "NAS"]), make("c/d", tags: ["AI"])]
        XCTAssertEqual(SourceOrganizer.filter(sources, tag: "AI").count, 2)
        XCTAssertEqual(SourceOrganizer.filter(sources, tag: "NAS").count, 1)
        XCTAssertEqual(SourceOrganizer.filter(sources, tag: "missing").count, 0)
        XCTAssertEqual(SourceOrganizer.filter(sources, tag: nil).count, 2)
        XCTAssertEqual(SourceOrganizer.filter(sources, tag: "").count, 2)
    }

    func testAllTagsDedupesSortsAndDropsEmpty() {
        let sources = [make("a/b", tags: ["NAS", "", "AI"]), make("c/d", tags: ["AI", "NAS"])]
        XCTAssertEqual(SourceOrganizer.allTags(sources), ["AI", "NAS"])
    }

    // MARK: 分组

    func testGroupByOwnerGroupsAndKeepsOrder() {
        let sources = [make("n8n-io/n8n"), make("openclaw/openclaw"), make("n8n-io/other")]
        let groups = SourceOrganizer.groupByOwner(sources)
        XCTAssertEqual(groups.map(\.id), ["n8n-io", "openclaw"])
        XCTAssertEqual(groups[0].sources.count, 2)
        XCTAssertEqual(groups[1].sources.count, 1)
    }

    func testGroupByOwnerHandlesInvalidRepository() {
        let groups = SourceOrganizer.groupByOwner([make("/n8n"), make("ok/repo")])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].id, "Other", "无法解析 owner 的归到 Other，并保持输入顺序")
        XCTAssertEqual(groups[1].id, "ok")
    }

    // MARK: 按类别分组

    private func categorySource(_ repo: String, _ category: String?) -> WatchSource {
        var s = WatchSource(repository: repo)
        s.category = category
        return s
    }

    /// 真机诉求：按"AI"这类主题归类，而不是按作者一组一个仓库。
    func testGroupByCategoryUsesCatalogOrderAndSkipsEmptyGroups() {
        let categories = CategoryCatalog.defaultCategories
        let sources = [
            categorySource("a/one", "network"),
            categorySource("b/two", "ai"),
            categorySource("c/three", "ai"),
        ]
        let groups = SourceOrganizer.groupByCategory(sources, categories: categories)
        XCTAssertEqual(groups.map(\.id), ["ai", "network"], "顺序应跟随类别目录，跳过空分组")
        XCTAssertEqual(groups[0].sources.count, 2)
        XCTAssertEqual(groups[1].sources.count, 1)
    }

    func testGroupByCategoryFallsBackToUncategorized() {
        let categories = CategoryCatalog.defaultCategories
        let sources = [categorySource("a/one", nil), categorySource("b/two", "does-not-exist")]
        let groups = SourceOrganizer.groupByCategory(sources, categories: categories)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, CategoryCatalog.uncategorizedID)
        XCTAssertEqual(groups[0].sources.count, 2, "未归类和已删除类别都落到“其他”")
    }

    func testGroupByCategoryIsEmptyForNoSources() {
        XCTAssertTrue(SourceOrganizer.groupByCategory([], categories: CategoryCatalog.defaultCategories).isEmpty)
    }

    func testGroupDispatchesOnKind() {
        let sources = [categorySource("a/one", "ai")]
        XCTAssertEqual(SourceOrganizer.group(sources, by: .category, categories: CategoryCatalog.defaultCategories).first?.id, "ai")
        XCTAssertEqual(SourceOrganizer.group(sources, by: .owner, categories: CategoryCatalog.defaultCategories).first?.id, "a")
    }

    // MARK: 标签解析

    func testParseTagsSplitsOnCommaSpaceAndChineseComma() {
        XCTAssertEqual(SourceOrganizer.parseTags("a, b，c d"), ["a", "b", "c", "d"])
        XCTAssertEqual(SourceOrganizer.parseTags("  self-hosted ,  NAS  "), ["self-hosted", "NAS"])
    }

    func testParseTagsDedupesAndDropsEmpty() {
        XCTAssertEqual(SourceOrganizer.parseTags("AI, AI, , NAS"), ["AI", "NAS"])
    }

    func testParseTagsRejectsOverlongTagAndCapsCount() {
        let long = String(repeating: "x", count: 25)
        XCTAssertEqual(SourceOrganizer.parseTags(long), [])
        // 必须有分隔符，"ok" 才会成为独立标签；否则整串按一个超长标签被拒。
        XCTAssertEqual(SourceOrganizer.parseTags("ok,\(long)"), ["ok"])

        let many = (1...20).map { "t\($0)" }.joined(separator: ",")
        XCTAssertEqual(SourceOrganizer.parseTags(many).count, 12, "标签总数应受限，避免撑坏界面")
    }

    func testParseTagsEmptyInput() {
        XCTAssertEqual(SourceOrganizer.parseTags(""), [])
        XCTAssertEqual(SourceOrganizer.parseTags("   "), [])
    }
}
