import Foundation

enum FindingQueue {
    static func pending(_ findings: [Finding], importantOnly: Bool = false) -> [Finding] { [] }
    static func completed(_ findings: [Finding]) -> [Finding] { [] }
}
