import Foundation

struct DiffLine: Equatable {
    enum Symbol: String {
        case added = "+"
        case removed = "−"
        case same = " "
    }
    let symbol: Symbol
    let text: String
}

enum DiffEngine {
    /// 每侧参与 LCS 的最大行数，超出时先裁掉公共前后缀再截断，避免 O(n²) 爆内存。
    static let maxLines = 400

    static func lines(old: String?, new: String?) -> [DiffLine] {
        guard let old, let new, old != new else { return [] }
        var oldLines = old.components(separatedBy: .newlines)
        var newLines = new.components(separatedBy: .newlines)
        trimCommonPrefixSuffix(&oldLines, &newLines)
        guard !oldLines.isEmpty || !newLines.isEmpty else { return [] }
        if oldLines.count > maxLines { oldLines = Array(oldLines.suffix(maxLines)) }
        if newLines.count > maxLines { newLines = Array(newLines.suffix(maxLines)) }
        return lcs(oldLines, newLines)
    }

    /// 摘要计数，供判断引擎与正文使用；与逐行 diff 一致的前后缀裁剪。
    static func counts(old: String?, new: String?) -> (added: Int, removed: Int) {
        guard let old, let new, old != new else { return (0, 0) }
        var oldLines = old.components(separatedBy: .newlines)
        var newLines = new.components(separatedBy: .newlines)
        trimCommonPrefixSuffix(&oldLines, &newLines)
        var oldSet = Set(oldLines)
        var newSet = Set(newLines)
        oldSet.subtract(newSet)
        newSet.subtract(oldSet)
        return (newSet.count, oldSet.count)
    }

    private static func trimCommonPrefixSuffix(_ left: inout [String], _ right: inout [String]) {
        while !left.isEmpty, !right.isEmpty, left.first == right.first {
            left.removeFirst(); right.removeFirst()
        }
        while !left.isEmpty, !right.isEmpty, left.last == right.last {
            left.removeLast(); right.removeLast()
        }
    }

    private static func lcs(_ oldLines: [String], _ newLines: [String]) -> [DiffLine] {
        let rows = oldLines.count, columns = newLines.count
        var table = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1) {
                table[row][column] = oldLines[row] == newLines[column]
                    ? table[row + 1][column + 1] + 1
                    : max(table[row + 1][column], table[row][column + 1])
            }
        }
        var result: [DiffLine] = []
        var row = 0, column = 0
        while row < rows, column < columns {
            if oldLines[row] == newLines[column] {
                result.append(DiffLine(symbol: .same, text: oldLines[row]))
                row += 1; column += 1
            } else if table[row + 1][column] >= table[row][column + 1] {
                result.append(DiffLine(symbol: .removed, text: oldLines[row]))
                row += 1
            } else {
                result.append(DiffLine(symbol: .added, text: newLines[column]))
                column += 1
            }
        }
        result.append(contentsOf: oldLines[row...].map { DiffLine(symbol: .removed, text: $0) })
        result.append(contentsOf: newLines[column...].map { DiffLine(symbol: .added, text: $0) })
        return result
    }
}
