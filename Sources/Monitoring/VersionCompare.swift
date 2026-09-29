import Foundation

/// 语义化版本解析与比较。容忍 `v` 前缀、缺省段（1.2 → 1.2.0）、
/// 预发布段（-alpha.1）与构建元数据（+build）。
struct ParsedVersion: Equatable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    static func parse(_ raw: String) -> ParsedVersion? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        if let plus = value.firstIndex(of: "+") { value = String(value[..<plus]) }
        var core = value
        var prerelease: [String] = []
        if let dash = value.firstIndex(of: "-") {
            core = String(value[..<dash])
            prerelease = value[value.index(after: dash)...]
                .split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            if prerelease.isEmpty || prerelease.contains(where: { $0.isEmpty }) { return nil }
        }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        // 超长数字段超出 Int64 会令 Int 初始化失败，任一段无法转 Int 则视为不可解析。
        guard (1...3).contains(numbers.count),
              numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let ints = numbers.map({ Int($0) }) as? [Int] else { return nil }
        func segment(_ index: Int) -> Int { index < ints.count ? ints[index] : 0 }
        return ParsedVersion(major: segment(0), minor: segment(1), patch: segment(2), prerelease: prerelease)
    }

    static func < (lhs: ParsedVersion, rhs: ParsedVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // 无预发布段 > 有预发布段；预发布段逐个比较，数字段按数值、否则按字典序，前缀相同者更短。
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right { continue }
            if let leftNumber = Int(left), let rightNumber = Int(right) { return leftNumber < rightNumber }
            if Int(left) != nil { return true }
            if Int(right) != nil { return false }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

enum VersionGap: Equatable {
    case upToDate
    case behind(steps: Int, majorBump: Bool)
    case ahead
    case incomparable
}

enum VersionCompare {
    /// 宽松解析：先整体解析，失败则从自由文本里提取首个版本号。
    ///
    /// 真机背景：AI 生成的导入 JSON 常把"使用版本"写成
    /// `0.20.6 (2026.8.27, upstream 4094ab61)`，整体解析会因点号过多（5 段）
    /// 直接失败，于是所有版本比较都退化成"无法判断"，用户看到的就是那条无用的提示。
    static func parse(_ raw: String) -> ParsedVersion? {
        if let direct = ParsedVersion.parse(raw) { return direct }
        guard let extracted = extractVersion(from: raw) else { return nil }
        return ParsedVersion.parse(extracted)
    }

    /// 从自由文本里提取首个看起来像版本号的片段。
    ///
    /// 为避免误判，候选必须**含小数点或以 v 开头**：
    /// 否则 "sha 4094ab61" 里的 "4094" 会被当成版本号。
    static func extractVersion(from raw: String) -> String? {
        let chars = Array(raw)
        var index = 0
        while index < chars.count {
            var start = index
            let hasVPrefix = chars[index] == "v" || chars[index] == "V"
            if hasVPrefix { start = index + 1 }
            guard start < chars.count, chars[start].isNumber else {
                index += 1
                continue
            }
            // 起点前一个字符若是字母或数字，说明我们切在了某个词的中间。
            if index > 0, chars[index - 1].isLetter || chars[index - 1].isNumber {
                index += 1
                continue
            }
            var end = start
            var inPrerelease = false
            while end < chars.count {
                let character = chars[end]
                if character.isNumber { end += 1; continue }
                if character == "." { end += 1; continue }
                if character == "-" && !inPrerelease { inPrerelease = true; end += 1; continue }
                // 字母只允许出现在预发布段（紧跟在 '-' 之后）。
                if character.isLetter && inPrerelease { end += 1; continue }
                break
            }
            while end > start, chars[end - 1] == "." || chars[end - 1] == "-" { end -= 1 }
            if end > start {
                let candidate = String(chars[index..<end])
                let looksVersionShaped = hasVPrefix || candidate.contains(".")
                if looksVersionShaped, ParsedVersion.parse(candidate) != nil {
                    return candidate
                }
            }
            index += 1
        }
        return nil
    }

    /// 年份量级的主版本号。
    /// 上游常用日期做 tag（v2026.9.24），而用户在"使用版本"里填的是产品版本（0.21.5）。
    /// 两者不是同一套编号，硬比会得出"包含主版本升级"这种误导性结论。
    private static func isYearLike(_ version: ParsedVersion) -> Bool {
        (1900...2200).contains(version.major)
    }

    /// 比较用户记录的使用版本与上游标识。无法解析任一端时返回 incomparable。
    static func gap(installed: String, upstream: String) -> VersionGap {
        guard let current = parse(installed), let upstreamVersion = parse(upstream) else {
            return .incomparable
        }
        // 防御：超长数字串（如 release 的数字 id 或纯数字提交）不是语义化版本。
        if current.major > 9_999 || upstreamVersion.major > 9_999 { return .incomparable }
        // 一侧是日期式编号、另一侧不是 → 不是同一套编号，不硬比。
        if isYearLike(current) != isYearLike(upstreamVersion) { return .incomparable }
        if current == upstreamVersion { return .upToDate }
        if current < upstreamVersion {
            let majorBump = upstreamVersion.major > current.major
            let steps: Int
            if majorBump { steps = upstreamVersion.major - current.major }
            else if upstreamVersion.minor != current.minor { steps = upstreamVersion.minor - current.minor }
            else { steps = upstreamVersion.patch - current.patch }
            return .behind(steps: max(steps, 1), majorBump: majorBump)
        }
        return .ahead
    }

    /// 挑选与"使用版本"真正可比的候选版本。
    ///
    /// 优先 tag；只有当 tag 与使用版本不可比时，才退回 release 名称里的版本——
    /// 有些项目 tag 用日期、产品版本只写在名称里，例如
    /// tag `v2026.9.24` 而名称是 `Hermes Agent v0.21.5 (v2026.9.24)`，
    /// 用户记录的恰恰是后者。这样普通项目行为完全不变，只救真正需要救的情况。
    static func comparableHint(installed: String, tag: String?, name: String?) -> String? {
        guard let tag else {
            guard let name else { return nil }
            return extractVersion(from: name)
        }
        guard !installed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return tag }
        if case .incomparable = gap(installed: installed, upstream: tag),
           let name, let fromName = extractVersion(from: name), fromName != tag {
            return fromName
        }
        return tag
    }

    static func describe(_ raw: String) -> String? {
        parse(raw).map { version in
            version.prerelease.isEmpty ? "\(version.major).\(version.minor).\(version.patch)"
                                       : "\(version.major).\(version.minor).\(version.patch)-\(version.prerelease.joined(separator: "."))"
        }
    }
}
