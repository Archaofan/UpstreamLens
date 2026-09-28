import Foundation

enum FindingQueue {
    static func pending(_ findings: [Finding], importantOnly: Bool = false) -> [Finding] {
        findings
            .filter { $0.status != .handled && (!importantOnly || $0.relevance == .important) }
            .sorted {
                let leftPriority = priority($0.relevance)
                let rightPriority = priority($1.relevance)
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                if $0.foundAt != $1.foundAt { return $0.foundAt > $1.foundAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    static func completed(_ findings: [Finding]) -> [Finding] {
        findings.filter { $0.status == .handled }.sorted {
            if $0.foundAt != $1.foundAt { return $0.foundAt > $1.foundAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func priority(_ relevance: Relevance) -> Int {
        switch relevance {
        case .important: return 0
        case .uncertain: return 1
        case .routine: return 2
        }
    }
}
