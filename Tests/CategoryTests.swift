import XCTest
@testable import UpstreamLens

final class CategoryCatalogTests: XCTestCase {
    func testBuiltInIDsAreUnique() {
        let ids = CategoryCatalog.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testUncategorizedIDExistsInCatalog() {
        XCTAssertNotNil(CategoryCatalog.builtIn(CategoryCatalog.uncategorizedID),
                        "兜底类别必须在目录里，否则“其他”分组无法显示名称与图标")
    }

    func testEveryBuiltInHasNameKeyAndSymbol() {
        for builtIn in CategoryCatalog.builtIns {
            XCTAssertFalse(builtIn.nameKey.isEmpty, "\(builtIn.id) 缺少本地化键")
            XCTAssertFalse(builtIn.symbol.isEmpty, "\(builtIn.id) 缺少图标")
        }
    }

    func testDefaultCategoriesMatchBuiltIns() {
        let defaults = CategoryCatalog.defaultCategories
        XCTAssertEqual(defaults.map(\.id), CategoryCatalog.builtIns.map(\.id))
        XCTAssertTrue(defaults.allSatisfy { $0.customName == nil }, "内置类别不该带自定义名")
    }

    func testUnknownIDSymbolFallsBack() {
        XCTAssertEqual(CategoryCatalog.symbol("nope"), "square.grid.2x2")
        XCTAssertEqual(CategoryCatalog.nameKey("nope"), "nope")
    }

    func testDisplayNamePrefersCustomName() {
        let named = SourceCategory(id: "ai", customName: "我的 AI", symbol: "brain")
        XCTAssertEqual(named.displayName, "我的 AI")
        let blank = SourceCategory(id: "ai", customName: "   ", symbol: "brain")
        XCTAssertNotEqual(blank.displayName, "   ", "空白自定义名应回落到本地化内置名")
    }
}

final class CategoryClassifierTests: XCTestCase {
    /// 真机场景：Hermes Agent 这类 AI agent 仓库应归到 AI。
    func testClassifiesAIAgentRepository() {
        XCTAssertEqual(CategoryClassifier.suggest(repository: "NousResearch/hermes-agent"), "ai")
        XCTAssertEqual(CategoryClassifier.suggest(repository: "openclaw/openclaw",
                                                  text: "AI agent, gateway, ollama, qdrant"), "ai")
    }

    func testClassifiesCommonTechDomains() {
        XCTAssertEqual(CategoryClassifier.suggest(repository: "fatedier/frp",
                                                  text: "proxy tunnel nat"), "network")
        XCTAssertEqual(CategoryClassifier.suggest(repository: "meilisearch/meilisearch",
                                                  text: "search engine database"), "data")
        XCTAssertEqual(CategoryClassifier.suggest(repository: "grafana/grafana",
                                                  text: "self-hosted monitoring dashboard"), "selfhosted")
        XCTAssertEqual(CategoryClassifier.suggest(repository: "astral-sh/ruff",
                                                  text: "linter formatter cli"), "devtools")
    }

    /// 词边界匹配：短词不能命中长词里的子串，否则会把大量仓库误判成 AI。
    func testShortTokensDoNotMatchInsideLongerWords() {
        // "ml" 不能命中 "html"
        XCTAssertNil(CategoryClassifier.suggest(repository: "acme/html-renderer"))
        // "ai" 不能命中 "email"
        XCTAssertNil(CategoryClassifier.suggest(repository: "acme/email-tool"))
        // "ai" 不能命中 "domain"
        XCTAssertNil(CategoryClassifier.suggest(repository: "acme/domain-utils"))
    }

    func testTokenMatchingAcceptsRealBoundaries() {
        XCTAssertTrue(CategoryClassifier.containsToken("an ml toolkit", "ml"))
        XCTAssertTrue(CategoryClassifier.containsToken("ml-toolkit", "ml"))
        XCTAssertTrue(CategoryClassifier.containsToken("toolkit/ml", "ml"))
        XCTAssertFalse(CategoryClassifier.containsToken("html", "ml"))
    }

    func testUnknownRepositoryReturnsNil() {
        XCTAssertNil(CategoryClassifier.suggest(repository: "acme/zzz-nothing-matches"))
    }

    func testEmptyInputIsSafe() {
        XCTAssertNil(CategoryClassifier.suggest(repository: ""))
        XCTAssertNil(CategoryClassifier.suggest(repository: "", topics: [], text: ""))
    }

    /// 多域命中时取分数最高者，而不是第一条规则。
    func testHighestScoringCategoryWins() {
        let id = CategoryClassifier.suggest(repository: "acme/thing",
                                           text: "proxy vpn tunnel dns gateway wireguard")
        XCTAssertEqual(id, "network")
    }
}

final class LocalDataCategoryTests: XCTestCase {
    func testEffectiveCategoriesFallBackToBuiltIns() {
        XCTAssertEqual(LocalData().effectiveCategories.map(\.id), CategoryCatalog.builtIns.map(\.id))
        var custom = LocalData()
        custom.categories = []
        XCTAssertEqual(custom.effectiveCategories.count, CategoryCatalog.builtIns.count,
                       "空数组视为未配置，仍用内置默认")
    }

    /// 旧备份没有 categories 键，必须能解码（非可选字段会导致整个备份读不出来）。
    func testLegacyBackupWithoutCategoriesDecodes() throws {
        let json: [String: Any] = ["schemaVersion": 1, "sources": [], "findings": []]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try LocalStore.importData(data)
        XCTAssertNil(decoded.categories)
        XCTAssertEqual(decoded.effectiveCategories.count, CategoryCatalog.builtIns.count)
    }

    func testCategoriesSurviveBackupRoundTrip() throws {
        var data = LocalData()
        data.categories = [SourceCategory(id: "ai", customName: "AI 工具", symbol: "brain")]
        let restored = try LocalStore.importData(try LocalStore.export(data))
        XCTAssertEqual(restored.categories?.first?.customName, "AI 工具")
    }

    /// 删除类别后不能留下悬空引用。
    func testDeletingCategoryReassignsItsSources() {
        var data = LocalData()
        var a = WatchSource(repository: "a/one"); a.category = "gone"
        var b = WatchSource(repository: "b/two"); b.category = "ai"
        data.sources = [a, b]

        data.reassignCategory("gone")

        XCTAssertEqual(data.sources[0].category, CategoryCatalog.uncategorizedID)
        XCTAssertEqual(data.sources[1].category, "ai", "不该动其他来源")
    }

    func testCategoriesAreIncludedInBackup() {
        var data = LocalData()
        data.categories = CategoryCatalog.defaultCategories
        let restored = try? LocalStore.importData(LocalStore.export(data))
        XCTAssertEqual(restored?.categories?.count, CategoryCatalog.builtIns.count)
    }

    /// 备份 JSON 可能是用户让 AI 生成的，字段缺失时不该让整份备份读不出来。
    func testCategoryDecodesLenientlyFromPartialJSON() throws {
        let json = #"[{"id":"ai"}]"#
        let categories = try JSONDecoder().decode([SourceCategory].self, from: Data(json.utf8))
        XCTAssertEqual(categories.first?.id, "ai")
        XCTAssertNil(categories.first?.customName)
        XCTAssertEqual(categories.first?.symbol, "tag", "缺 symbol 时给个能用的默认图标")
    }

    func testCategoryDecodesWithUnknownExtraKeys() throws {
        let json = #"[{"id":"x","customName":"Mine","symbol":"brain","future":"ignored"}]"#
        let categories = try JSONDecoder().decode([SourceCategory].self, from: Data(json.utf8))
        XCTAssertEqual(categories.first?.displayName, "Mine")
        XCTAssertEqual(categories.first?.symbol, "brain")
    }

    /// 整份备份里类别字段残缺也必须可读。
    func testBackupWithPartialCategoriesStillImports() throws {
        let json = #"{"sources":[],"findings":[],"categories":[{"id":"ai"}]}"#
        let data = try LocalStore.importData(Data(json.utf8))
        XCTAssertEqual(data.effectiveCategories.first?.id, "ai")
    }
}
