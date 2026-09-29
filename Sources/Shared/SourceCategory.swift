import Foundation

/// 来源类别。用于"来源"页分组与筛选。
///
/// `id` 一旦确定不再变化；内置类别的显示名走本地化，
/// 用户改过名（customName 非 nil）则优先用用户的名字。
struct SourceCategory: Codable, Identifiable, Equatable, Hashable {
    var id: String
    /// 自定义显示名；nil 表示使用内置 slug 的本地化名。
    var customName: String?
    var symbol: String

    init(id: String, customName: String? = nil, symbol: String) {
        self.id = id
        self.customName = customName
        self.symbol = symbol
    }
}

// 宽松解码：备份 JSON 有可能是用户让 AI 生成的，字段缺失时不该让整份备份读不出来。
// 放在 extension 里，避免抑制成员初始化器。
extension SourceCategory {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "tag"
    }
}

/// 内置类别目录。`nameKey` 同时就是 String Catalog 的本地化键（英文原文）。
enum CategoryCatalog {    struct BuiltIn: Equatable {
        let id: String
        let nameKey: String
        let symbol: String
    }

    /// 默认类别。用户可在设置里增删改，这里是首次使用的种子。
    static let builtIns: [BuiltIn] = [
        BuiltIn(id: "ai", nameKey: "AI & LLM", symbol: "brain"),
        BuiltIn(id: "selfhosted", nameKey: "Self-Hosted", symbol: "server.rack"),
        BuiltIn(id: "devtools", nameKey: "Dev Tools", symbol: "hammer"),
        BuiltIn(id: "network", nameKey: "Network & Proxy", symbol: "network"),
        BuiltIn(id: "data", nameKey: "Data & Storage", symbol: "externaldrive"),
        BuiltIn(id: "other", nameKey: "Other", symbol: "square.grid.2x2"),
    ]

    /// 未归类来源的兜底类别，也是类别被删除后指向它的来源的落点。
    static let uncategorizedID = "other"

    static var defaultCategories: [SourceCategory] {
        builtIns.map { SourceCategory(id: $0.id, symbol: $0.symbol) }
    }

    static func builtIn(_ id: String) -> BuiltIn? {
        builtIns.first { $0.id == id }
    }

    static func nameKey(_ id: String) -> String {
        builtIn(id)?.nameKey ?? id
    }

    static func symbol(_ id: String) -> String {
        builtIn(id)?.symbol ?? "square.grid.2x2"
    }
}

/// 按仓库名 / topics / 正文（用途、描述、关键词）猜类别。纯函数，便于单测。
///
/// 采用"词边界 + 计分"而不是简单子串匹配：否则 `ml` 会命中 `html`、
/// `ai` 会命中 `email`，把大量仓库误判成 AI。
enum CategoryClassifier {
    /// 顺序无关：按命中数取最高分；同分时靠前规则优先。
    static let rules: [(id: String, terms: [String])] = [
        ("ai", ["ai", "llm", "gpt", "agent", "agents", "rag", "embedding", "embeddings",
                "ollama", "langchain", "transformer", "transformers", "diffusion",
                "machine-learning", "ml", "neural", "openai", "anthropic", "claude",
                "llama", "qdrant", "vector", "prompt", "prompts", "mcp", "copilot",
                "whisper", "speech", "vision", "inference", "model", "models",
                "hermes", "cursor", "aider", "continue"]),
        ("network", ["proxy", "vpn", "tunnel", "dns", "gateway", "wireguard", "frp",
                     "nginx", "traefik", "caddy", "mesh", "sing-box", "clash", "v2ray",
                     "tor", "socks", "router", "firewall", "cdn"]),
        ("data", ["database", "db", "postgres", "postgresql", "mysql", "sqlite", "redis",
                  "mongo", "mongodb", "storage", "backup", "sync", "nas", "s3", "minio",
                  "kafka", "etl", "analytics", "search", "elasticsearch", "meilisearch",
                  "memos", "notes", "wiki", "obsidian"]),
        ("selfhosted", ["self-hosted", "selfhosted", "self-host", "homelab",
                        "docker-compose", "compose", "helm", "dashboard", "monitoring",
                        "grafana", "prometheus", "home-assistant", "immich", "jellyfin",
                        "nextcloud", "portainer", "uptime", "panel"]),
        ("devtools", ["cli", "sdk", "compiler", "linter", "formatter", "build", "builder",
                      "test", "testing", "debug", "debugger", "editor", "ide", "git",
                      "package", "framework", "library", "toolkit", "runtime", "devops",
                      "ci", "docker", "kubernetes", "k8s", "terminal", "shell", "api"]),
    ]

    /// 返回命中最多的类别 id；都不命中返回 nil（由调用方决定是否落到"其他"）。
    static func suggest(repository: String, topics: [String] = [], text: String = "") -> String? {
        let haystack = ([repository] + topics + [text]).joined(separator: " ").lowercased()
        var best: (id: String, score: Int)?
        for rule in rules {
            var score = 0
            for term in rule.terms where containsToken(haystack, term) { score += 1 }
            if score > 0, score > (best?.score ?? 0) {
                best = (rule.id, score)
            }
        }
        return best?.id
    }

    /// 词边界匹配，避免短词误命中长词（ml/html、ai/email）。
    static func containsToken(_ haystack: String, _ token: String) -> Bool {
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: token, range: searchStart..<haystack.endIndex) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !isWordCharacter(haystack[haystack.index(before: range.lowerBound)])
            let afterOK = range.upperBound == haystack.endIndex
                || !isWordCharacter(haystack[range.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
