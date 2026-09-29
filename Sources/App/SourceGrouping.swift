import Foundation

/// 一个分组。id 在"按类别"时是类别 id，在"按 owner"时是 owner 名。
struct SourceGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String?
    let sources: [WatchSource]
}

/// 来源筛选与分组的纯逻辑，集中一处便于单测覆盖。
enum SourceOrganizer {
    /// 按关键词实时过滤：命中标题 / 仓库 / 用途 / 关键词 / 标签。
    static func filter(_ sources: [WatchSource], query: String) -> [WatchSource] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sources }
        return sources.filter { source in
            source.title.lowercased().contains(q)
                || source.repository.lowercased().contains(q)
                || source.purpose.lowercased().contains(q)
                || source.keywords.lowercased().contains(q)
                || source.tags.contains { $0.lowercased().contains(q) }
        }
    }

    /// 按标签筛选；tag 为 nil 或空时不过滤。
    static func filter(_ sources: [WatchSource], tag: String?) -> [WatchSource] {
        guard let tag, !tag.isEmpty else { return sources }
        return sources.filter { $0.tags.contains(tag) }
    }

    /// 汇总所有来源用过的标签：去重、排序。
    static func allTags(_ sources: [WatchSource]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for source in sources {
            for tag in source.tags where !tag.isEmpty && !seen.contains(tag) {
                seen.insert(tag)
                out.append(tag)
            }
        }
        return out.sorted()
    }

    /// 按类别分组：顺序跟随类别目录，未归类或类别已被删除的来源落到"其他"。
    static func groupByCategory(_ sources: [WatchSource],
                               categories: [SourceCategory]) -> [SourceGroup] {
        var order = categories.map(\.id)
        var buckets: [String: [WatchSource]] = [:]
        for source in sources {
            var id = source.category ?? CategoryCatalog.uncategorizedID
            if !order.contains(id) { id = CategoryCatalog.uncategorizedID }
            if !order.contains(id) { order.append(id) }
            buckets[id, default: []].append(source)
        }
        return order.compactMap { id in
            guard let list = buckets[id], !list.isEmpty else { return nil }
            let category = categories.first { $0.id == id }
            let title = category?.displayName ?? id
            let symbol = category?.symbol ?? CategoryCatalog.symbol(id)
            return SourceGroup(id: id, title: title, symbol: symbol, sources: list)
        }
    }

    /// 按仓库 owner 自动分组，保持给定顺序。
    static func groupByOwner(_ sources: [WatchSource]) -> [SourceGroup] {
        var order: [String] = []
        var buckets: [String: [WatchSource]] = [:]
        for source in sources {
            let owner = RepoAvatar.owner(of: source.repository) ?? AppLocalization.string("Other")
            if buckets[owner] == nil {
                order.append(owner)
                buckets[owner] = []
            }
            buckets[owner]?.append(source)
        }
        return order.map {
            SourceGroup(id: $0, title: $0, symbol: "person.crop.square", sources: buckets[$0] ?? [])
        }
    }

    /// 按指定依据分组。
    static func group(_ sources: [WatchSource], by kind: SourceGroupKind,
                      categories: [SourceCategory]) -> [SourceGroup] {
        switch kind {
        case .category: return groupByCategory(sources, categories: categories)
        case .owner: return groupByOwner(sources)
        }
    }

    /// 解析用户输入的标签文本（中英文逗号、空格、换行分隔）。
    /// 去空白、去重，单个标签限 24 字符、总数限 12 个，避免脏数据把界面撑坏。
    static func parseTags(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let separators = CharacterSet(charactersIn: ",， \t\n")
        for raw in text.components(separatedBy: separators) {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, tag.count <= 24, !seen.contains(tag) else { continue }
            seen.insert(tag)
            out.append(tag)
        }
        return Array(out.prefix(12))
    }
}
