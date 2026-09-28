import Foundation

struct UpstreamChange: Equatable {
    let identifier: String
    let title: String
    let body: String
    let url: String
    let publishedAt: Date?
    let content: String?
}

enum RelevanceEngine {
    static func assess(source: WatchSource, text: String) -> (Relevance, String) {
        let lower = text.lowercased()
        let terms = source.keywords
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if let hit = terms.first(where: { lower.contains($0) }) {
            return (.important, "变更提及你关注的关键词「\(hit)」。请核对原文与当前用途。")
        }
        let context = (source.purpose + " " + source.rationale).lowercased()
        let words = context.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 }
        if let hit = words.first(where: { lower.contains($0) }) {
            return (.important, "变更提及你记录的用途或理由「\(hit)」。")
        }
        if !source.installedVersion.isEmpty {
            return (.uncertain, "你记录的使用版本是 \(source.installedVersion)；尚不能仅凭上游版本号判断是否需要升级。")
        }
        if source.purpose.isEmpty && source.rationale.isEmpty && terms.isEmpty {
            return (.uncertain, "未填写使用情况，无法判断个人影响；请查看上游原文。")
        }
        return (.routine, "未匹配你记录的关键词或用途；仍可查看上游原文。")
    }
}

enum ChangeDetector {
    static let emptyBaseline = "<no-upstream-items>"

    static func apply(_ changes: [UpstreamChange], to source: inout WatchSource, existing: [Finding], now: Date) -> [Finding] {
        guard let newest = changes.first else {
            if source.baselineIdentifier == nil { source.baselineIdentifier = emptyBaseline }
            source.lastCheckedAt = now
            source.lastError = nil
            return []
        }
        let previous = source.baselineIdentifier
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
            let (relevance, reason) = RelevanceEngine.assess(source: source, text: text)
            return Finding(sourceID: source.id, upstreamID: change.identifier, title: change.title,
                           body: change.body.isEmpty ? summary : change.body + (summary.isEmpty ? "" : "\n\n" + summary),
                           url: change.url, foundAt: now, relevance: relevance, reason: reason,
                           oldContent: source.baselineContent, newContent: change.content)
        }
    }

    static func contentSummary(old: String?, new: String?) -> String {
        guard let old, let new, old != new else { return "" }
        let oldLines = Set(old.components(separatedBy: .newlines))
        let newLines = Set(new.components(separatedBy: .newlines))
        let added = newLines.subtracting(oldLines)
        let removed = oldLines.subtracting(newLines)
        let excerpt = (added.prefix(3).map { "+ " + $0 } + removed.prefix(3).map { "− " + $0 }).joined(separator: "\n")
        return "文件变化：新增约 \(added.count) 行，删除约 \(removed.count) 行。" + (excerpt.isEmpty ? "" : "\n" + excerpt)
    }
}
