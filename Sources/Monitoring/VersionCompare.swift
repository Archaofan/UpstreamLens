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
            prerelease = value[value.index(after: dash)...].split(separator: ".").map(String.init)
            if prerelease.isEmpty || prerelease.contains(where: { $0.isEmpty }) { return nil }
        }
        let numbers = core.split(separator: ".").map(String.init)
        guard (1...3).contains(numbers.count),
              numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let ints = numbers.map { Int($0)! }
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
    /// 比较用户记录的使用版本与上游标识。无法解析任一端时返回 incomparable。
    static func gap(installed: String, upstream: String) -> VersionGap {
        guard let current = ParsedVersion.parse(installed), let upstreamVersion = ParsedVersion.parse(upstream) else {
            return .incomparable
        }
        // 防御：超长数字串（如 release 的数字 id 或纯数字提交）不是语义化版本。
        if current.major > 9_999 || upstreamVersion.major > 9_999 { return .incomparable }
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

    static func describe(_ raw: String) -> String? {
        ParsedVersion.parse(raw).map { version in
            version.prerelease.isEmpty ? "\(version.major).\(version.minor).\(version.patch)"
                                       : "\(version.major).\(version.minor).\(version.patch)-\(version.prerelease.joined(separator: "."))"
        }
    }
}
