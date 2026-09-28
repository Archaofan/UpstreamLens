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
    static func assess(source: WatchSource, text: String, versionHint: String? = nil) -> (Relevance, String) {
        if let upstreamID = versionHint, !source.installedVersion.isEmpty {
            switch VersionCompare.gap(installed: source.installedVersion, upstream: upstreamID) {
            case .behind(let steps, let majorBump):
                let upstreamText = VersionCompare.describe(upstreamID) ?? upstreamID
                let installedText = VersionCompare.describe(source.installedVersion) ?? source.installedVersion
                if ParsedVersion.parse(upstreamID)?.prerelease.isEmpty == false {
                    return (.uncertain, "上游最新为预发布版本 \(upstreamText)，你记录的使用版本是 \(installedText)；预发布是否采用请自行判断。")
                }
                if majorBump {
                    return (.important, "上游最新为 \(upstreamText)，你记录的使用版本是 \(installedText)，包含主版本升级（约 \(steps) 个版本号段），请核对兼容性。")
                }
                return (.routine, "上游最新为 \(upstreamText)，你记录的使用版本是 \(installedText)，仅小版本更新（约 \(steps) 个版本号段）。")
            case .upToDate:
                return (.routine, "上游版本与你记录的使用版本一致。")
            case .ahead:
                return (.uncertain, "你记录的使用版本高于上游标识（可能是开发版或不同编号方式），请核对原文。")
            case .incomparable:
                break
            }
        }

        let lower = text.lowercased()
        if let breaking = firstTermHit(terms: breakingTerms, in: lower) {
            return (.important, "变更包含「\(breaking)」，通常涉及兼容性或安全，请核对原文与当前用途。")
        }
        let keywordHits = hits(terms: terms(from: source.keywords), in: lower)
        if !keywordHits.isEmpty {
            return (.important, "变更提及你关注的关键词「\(keywordHits.prefix(3).joined(separator: "、"))」。请核对原文与当前用途。")
        }
        let contextHits = hits(terms: terms(from: source.contextText, minASCIILength: 3), in: lower)
        if !contextHits.isEmpty {
            return (.important, "变更提及你记录的用途或理由「\(contextHits.prefix(3).joined(separator: "、"))」。")
        }
        if !source.installedVersion.isEmpty {
            return (.uncertain, "你记录的使用版本是 \(source.installedVersion)；尚不能仅凭上游标识判断是否需要升级。")
        }
        if source.contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (.uncertain, "未填写使用情况，无法判断个人影响；请查看上游原文。")
        }
        return (.routine, "未匹配你记录的关键词或用途；仍可查看上游原文。")
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
        guard let range = lowerText.range(of: lowerTerm) else { return false }
        let beforeOK = range.lowerBound == lowerText.startIndex
            || !isWordCharacter(lowerText[lowerText.index(before: range.lowerBound)])
        let afterOK = range.upperBound == lowerText.endIndex
            || !isWordCharacter(lowerText[range.upperBound])
        return beforeOK && afterOK
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

enum ChangeDetector {
    static let emptyBaseline = "<no-upstream-items>"
    static let missingBaselineMessage = "上次已知标识未出现在上游结果中，无法安全判断新变化。请核对来源后重建当前基线。"

    static func apply(_ changes: [UpstreamChange], to source: inout WatchSource, existing: [Finding], now: Date) -> [Finding] {
        guard let newest = changes.first else {
            if let previous = source.baselineIdentifier, previous != emptyBaseline {
                source.lastError = missingBaselineMessage
                return []
            }
            if source.baselineIdentifier == nil { source.baselineIdentifier = emptyBaseline }
            source.lastCheckedAt = now
            source.lastError = nil
            return []
        }
        let previous = source.baselineIdentifier
        if let previous, previous != emptyBaseline, previous != newest.identifier,
           !changes.contains(where: { $0.identifier == previous }) {
            source.lastError = missingBaselineMessage
            return []
        }
        source.baselineIdentifier = newest.identifier
        source.lastCheckedAt = now
        source.lastError = nil
        defer { if let content = newest.content { source.baselineContent = content } }
        guard let previous, previous != newest.identifier else { return [] }

        let unseen = changes.prefix { $0.identifier != previous }
        return unseen.reversed().compactMap { change in
            guard !existing.contains(where: { $0.sourceID == source.id && $0.upstreamID == change.identifier }) else { return nil }
            let summary = contentSummary(old: source.baselineContent, new: change.content)
            let text = [change.title, change.body, summary].joined(separator: "\n")
            let (relevance, reason) = RelevanceEngine.assess(source: source, text: text, versionHint: change.versionHint)
            return Finding(sourceID: source.id, upstreamID: change.identifier, title: change.title,
                           body: change.body.isEmpty ? summary : change.body + (summary.isEmpty ? "" : "\n\n" + summary),
                           url: change.url, foundAt: now, relevance: relevance, reason: reason,
                           oldContent: source.baselineContent, newContent: change.content,
                           isPrerelease: change.prerelease)
        }
    }

    static func contentSummary(old: String?, new: String?) -> String {
        guard let old, let new, old != new else { return "" }
        let counts = DiffEngine.counts(old: old, new: new)
        let oldLines = Set(old.components(separatedBy: .newlines))
        let newLines = Set(new.components(separatedBy: .newlines))
        let added = newLines.subtracting(oldLines)
        let removed = oldLines.subtracting(newLines)
        let excerpt = (added.prefix(3).map { "+ " + $0 } + removed.prefix(3).map { "− " + $0 }).joined(separator: "\n")
        return "文件变化：新增约 \(counts.added) 行，删除约 \(counts.removed) 行。" + (excerpt.isEmpty ? "" : "\n" + excerpt)
    }
}
