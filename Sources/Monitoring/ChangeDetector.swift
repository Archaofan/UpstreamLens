import Foundation

struct UpstreamChange: Equatable {
    let identifier: String
    let title: String
    let body: String
    let url: String
    let publishedAt: Date?
    let content: String?
    var prerelease: Bool = false
    /// 可与用户"使用版本"比较的版本号（release 的 tag 名、tag 名）；提交 sha 等为 nil。
    var versionHint: String? = nil
}

enum RelevanceEngine {
    /// 出现这些词通常意味着兼容性或安全问题，优先级高于普通关键词。
    static let breakingTerms = [
        "breaking change", "breaking", "removed", "deprecated", "incompatible", "requires",
        "migration", "migrate", "dropped support", "no longer", "security", "vulnerability", "cve",
        "exploit", "破坏性", "不兼容", "弃用", "移除", "安全漏洞", "漏洞", "迁移",
    ]

    /// 判定一条上游变化对用户的相关性。理由必须引用命中的具体词句，便于回原文核查。
    /// 优先级：破坏性/安全词 > 关键词 > 版本比较 > 用途语境 > 兜底。
    ///
    /// 文案一律走 L10n 命名占位符：这些理由会写进 Finding 永久保存，
    /// 且是用户最常看到的文字，不能是硬编码中文。
    static func assess(source: WatchSource, text: String, versionHint: String? = nil) -> (Relevance, String) {
        let lower = text.lowercased()
        if let breaking = firstTermHit(terms: breakingTerms, in: lower) {
            return (.important, L10n.format(
                "The change mentions “{term}”, which usually signals a compatibility or security impact. Check the original wording against how you use it.",
                ["term": breaking]))
        }
        let keywordHits = hits(terms: terms(from: source.keywords), in: lower)
        if !keywordHits.isEmpty {
            return (.important, L10n.format(
                "The change mentions your watched keyword(s) “{terms}”. Check the original wording against how you use it.",
                ["terms": keywordHits.prefix(3).joined(separator: ", ")]))
        }
        if let versionHint, !source.installedVersion.isEmpty {
            switch VersionCompare.gap(installed: source.installedVersion, upstream: versionHint) {
            case .behind(let steps, let majorBump):
                let upstreamText = VersionCompare.describe(versionHint) ?? versionHint
                let installedText = VersionCompare.describe(source.installedVersion) ?? source.installedVersion
                let pair = ["upstream": upstreamText, "installed": installedText]
                if VersionCompare.parse(versionHint)?.prerelease.isEmpty == false {
                    return (.uncertain, L10n.format(
                        "Upstream latest is the pre-release {upstream}; you recorded {installed}. Whether to adopt a pre-release is your call.",
                        pair))
                }
                if majorBump {
                    return (.important, L10n.format(
                        "Upstream latest is {upstream}; you recorded {installed}. This spans about {steps} major version step(s); check compatibility.",
                        pair.merging(["steps": String(steps)]) { _, new in new }))
                }
                return (.routine, L10n.format(
                    "Upstream latest is {upstream}; you recorded {installed}. Only minor version steps (about {steps}).",
                    pair.merging(["steps": String(steps)]) { _, new in new }))
            case .upToDate:
                return (.routine, AppLocalization.string("The upstream version matches the version you recorded."))
            case .ahead:
                return (.uncertain, AppLocalization.string(
                    "The version you recorded is ahead of the upstream identifier (a development build, or a different numbering scheme). Check the original."))
            case .incomparable:
                break
            }
        }
        let contextHits = hits(terms: terms(from: source.contextText, minASCIILength: 3), in: lower)
        if !contextHits.isEmpty {
            return (.important, L10n.format(
                "The change mentions your recorded purpose or rationale “{terms}”.",
                ["terms": contextHits.prefix(3).joined(separator: ", ")]))
        }
        if !source.installedVersion.isEmpty {
            return (.uncertain, L10n.format(
                "You recorded version {installed}. The upstream identifier alone is not enough to tell whether an upgrade is needed.",
                ["installed": source.installedVersion]))
        }
        if source.contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (.uncertain, AppLocalization.string(
                "No usage recorded, so the personal impact cannot be judged. Check the upstream original."))
        }
        return (.routine, AppLocalization.string(
            "Nothing matched your recorded keywords or purpose; you can still read the upstream original."))
    }

    /// ASCII 词按词边界匹配（避免 "api" 误命中 "rapid"），CJK 词按子串匹配。
    static func hits(terms: [String], in lowerText: String) -> [String] {
        var matched: [String] = []
        for term in terms where !term.isEmpty {
            if isCJKTerm(term) {
                if lowerText.contains(term) { matched.append(term) }
            } else if containsWord(lowerText, term) {
                matched.append(term)
            }
        }
        return matched
    }

    static func firstTermHit(terms: [String], in lowerText: String) -> String? {
        hits(terms: terms, in: lowerText).first
    }

    /// 拆词：按中英文逗号、顿号、分号、换行和空格拆分；ASCII 词要求不短于
    /// minASCIILength（默认 2），CJK 词不设长度下限。
    static func terms(from raw: String, minASCIILength: Int = 2) -> [String] {
        raw.lowercased()
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" || $0 == "、" || $0 == ";" || $0 == "；" || $0 == " " || $0 == "　" || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { term in
                guard !term.isEmpty else { return false }
                if isCJKTerm(term) { return true }
                return term.count >= minASCIILength
            }
    }

    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    static func isCJKTerm(_ term: String) -> Bool {
        term.contains(where: isCJK)
    }

    static func containsWord(_ lowerText: String, _ lowerTerm: String) -> Bool {
        // 首个出现可能是别的词的子串（"rapid" 里的 "api"），必须遍历所有命中位置。
        var searchStart = lowerText.startIndex
        while let range = lowerText.range(of: lowerTerm, range: searchStart..<lowerText.endIndex) {
            let beforeOK = range.lowerBound == lowerText.startIndex
                || !isWordCharacter(lowerText[lowerText.index(before: range.lowerBound)])
            let afterOK = range.upperBound == lowerText.endIndex
                || !isWordCharacter(lowerText[range.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

enum ChangeDetector {
    static let emptyBaseline = "<no-upstream-items>"
    /// 上游历史变动（条目被撤回/删除）导致基线不可用时的说明文案。
    /// 注意：现在这种情况是**静默重建基线**（见 apply），不再写进 lastError；
    /// 此常量保留给诊断与测试引用，因此也走本地化。
    static var missingBaselineMessage: String {
        AppLocalization.string("The previously known upstream item no longer exists upstream, so new changes cannot be judged safely.")
    }

    /// 单次检查最多产出多少条独立记录；超出则合并成一条摘要。
    /// 真机反馈：上游一次批量发布 16 个条目，来源刷出 16 条无效提醒。
    static let maxFindingsPerCheck = 5
    /// 摘要里最多列出多少个标题。
    static let maxTitlesInSummary = 10

    /// 该标识是否"看起来像版本号"。
    /// `inputs-a` / `inputs-7` 这类内容寻址标签没有版本含义，不应逐条提醒。
    /// 注意超长数字（release 数字 id、纯数字提交）能 parse 但不是版本号。
    static func looksLikeVersion(_ raw: String) -> Bool {
        guard let parsed = ParsedVersion.parse(raw) else { return false }
        return parsed.major <= 9_999 && parsed.minor <= 9_999 && parsed.patch <= 9_999
    }

    /// 该标识是否是"纯数字 id"（release 的数字 id）。
    ///
    /// 这是判断"历史噪音记录"最可靠的信号：纯数字不可能是版本号（版本号含小数点），
    /// 也不可能是 tag 名或提交 SHA。用于存量清理时，比"不像版本号"精确得多——
    /// 后者会把 UUID 等防御性标识也一并误判成噪音。
    static func isNumericIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isNumber)
    }

    /// 按"只看版本号形式"过滤。
    /// 两个安全阀：
    /// 1. 只要有任何条目没有版本标识（例如 path 模式的提交），就完全不过滤；
    /// 2. 若过滤后一条不剩，说明这个来源本来就不用版本号命名，宁可保留也不要让它彻底沉默。
    static func filtered(_ changes: [UpstreamChange], versionLikeOnly: Bool) -> [UpstreamChange] {
        guard versionLikeOnly, !changes.isEmpty else { return changes }
        guard changes.allSatisfy({ $0.versionHint != nil }) else { return changes }
        let kept = changes.filter { looksLikeVersion($0.versionHint ?? "") }
        return kept.isEmpty ? changes : kept
    }

    static func apply(_ changes: [UpstreamChange], to source: inout WatchSource, existing: [Finding], now: Date) -> [Finding] {
        let considered = filtered(changes, versionLikeOnly: source.versionLikeOnly)

        // 上游当前确实没有条目。旧实现在这里把"空结果"当成"基线丢失"报错，
        // 于是没有 release 的仓库会一直显示错误。这里对齐为正常的空基线。
        guard let newest = considered.first else {
            source.baselineIdentifier = emptyBaseline
            source.baselineContent = nil
            source.lastCheckedAt = now
            source.lastError = nil
            return []
        }

        let previous = source.baselineIdentifier
        // 基线不在本次窗口内：上游删除了该条、或它被挤出了分页范围。
        // 旧实现在这里置错并 return，而且**永远不更新基线**，来源会永久卡在报错状态、
        // 再也无法恢复（真机反馈正是如此）。现在改为静默重建基线：
        // 已无法判断窗口内哪些是"新"的，就不猜、不刷屏，下一轮恢复正常比对。
        let baselineMissing = previous.map {
            $0 != emptyBaseline && $0 != newest.identifier && !considered.contains { $0.identifier == previous }
        } ?? false

        source.baselineIdentifier = newest.identifier
        source.lastCheckedAt = now
        source.lastError = nil
        if let content = newest.content { source.baselineContent = content }

        if baselineMissing { return [] }

        guard let previous, previous != newest.identifier else { return [] }

        let unseen = considered.prefix { $0.identifier != previous }
        let fresh = unseen.reversed().filter { change in
            !existing.contains { $0.sourceID == source.id && $0.upstreamID == change.identifier }
        }
        guard !fresh.isEmpty else { return [] }

        let summary = contentSummary(old: source.baselineContent, new: newest.content)
        if fresh.count > maxFindingsPerCheck {
            return [aggregate(fresh, newest: newest, source: source, summary: summary, now: now)]
        }
        return fresh.map { change in
            let text = [change.title, change.body, summary].joined(separator: "\n")
            let hint = VersionCompare.comparableHint(installed: source.installedVersion,
                                                     tag: change.versionHint,
                                                     name: change.title)
            let (relevance, reason) = RelevanceEngine.assess(source: source, text: text, versionHint: hint)
            return Finding(sourceID: source.id, upstreamID: change.identifier, title: change.title,
                           body: change.body.isEmpty ? summary : change.body + (summary.isEmpty ? "" : "\n\n" + summary),
                           url: change.url, foundAt: now, relevance: relevance, reason: reason,
                           oldContent: source.baselineContent, newContent: change.content,
                           isPrerelease: change.prerelease)
        }
    }

    /// 批量发布合并成一条：既不丢信息，也不把列表和通知刷爆。
    /// 单条记录用 newest 的 identifier，保证下一轮的去重仍然正确。
    private static func aggregate(_ fresh: [UpstreamChange], newest: UpstreamChange,
                                  source: WatchSource, summary: String, now: Date) -> Finding {
        let titles = fresh.map(\.title)
        let listed = titles.prefix(maxTitlesInSummary).map { "• " + $0 }.joined(separator: "\n")
        let header = String(format: AppLocalization.string("%lld upstream items were published at once; listed as one summary item to avoid flooding the list."),
                            Int64(fresh.count))
        let body = header + "\n\n" + listed + (titles.count > maxTitlesInSummary ? "\n…" : "")
        let text = [titles.joined(separator: "\n"), summary].joined(separator: "\n")
        let hint = VersionCompare.comparableHint(installed: source.installedVersion,
                                                 tag: newest.versionHint,
                                                 name: newest.title)
        let (relevance, reason) = RelevanceEngine.assess(source: source, text: text, versionHint: hint)
        return Finding(sourceID: source.id, upstreamID: newest.identifier,
                       title: String(format: AppLocalization.string("%lld upstream updates at once"), Int64(fresh.count)),
                       body: body, url: newest.url, foundAt: now, relevance: relevance, reason: reason,
                       oldContent: source.baselineContent, newContent: newest.content,
                       isPrerelease: newest.prerelease)
    }

    static func contentSummary(old: String?, new: String?) -> String {
        guard let old, let new, old != new else { return "" }
        let counts = DiffEngine.counts(old: old, new: new)
        let oldLines = Set(old.components(separatedBy: .newlines))
        let newLines = Set(new.components(separatedBy: .newlines))
        let added = newLines.subtracting(oldLines)
        let removed = oldLines.subtracting(newLines)
        let excerpt = (added.prefix(3).map { "+ " + $0 } + removed.prefix(3).map { "− " + $0 }).joined(separator: "\n")
        let head = String(format: AppLocalization.string("File change: about %lld lines added, %lld lines removed."),
                          Int64(counts.added), Int64(counts.removed))
        return head + (excerpt.isEmpty ? "" : "\n" + excerpt)
    }
}
