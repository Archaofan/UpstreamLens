import XCTest
@testable import UpstreamLens

final class DiffTests: XCTestCase {
    func testIdenticalContentHasNoDiff() {
        XCTAssertTrue(DiffEngine.lines(old: "a\nb", new: "a\nb").isEmpty)
        XCTAssertTrue(DiffEngine.lines(old: nil, new: "a").isEmpty)
        XCTAssertTrue(DiffEngine.lines(old: "a", new: nil).isEmpty)
    }

    func testMiddleLineReplacement() {
        let lines = DiffEngine.lines(old: "a\nb\nc", new: "a\nx\nc")
        XCTAssertEqual(lines.filter { $0.symbol == .added }.map(\.text), ["x"])
        XCTAssertEqual(lines.filter { $0.symbol == .removed }.map(\.text), ["b"])
        XCTAssertEqual(lines.filter { $0.symbol == .same }.map(\.text), ["a", "c"])
    }

    func testAdditionsAndRemovalsAtEnd() {
        let lines = DiffEngine.lines(old: "a\nb", new: "a\nb\nc\nd")
        XCTAssertEqual(lines.filter { $0.symbol == .added }.map(\.text), ["c", "d"])
        XCTAssertTrue(lines.filter { $0.symbol == .removed }.isEmpty)
    }

    func testCountsIgnoreReorderedDuplicateLines() {
        let counts = DiffEngine.counts(old: "a\nb\nc", new: "c\nb\na")
        XCTAssertEqual(counts.added, 0)
        XCTAssertEqual(counts.removed, 0)
        let changed = DiffEngine.counts(old: "a\nb", new: "a\nx\ny")
        XCTAssertEqual(changed.added, 2)
        XCTAssertEqual(changed.removed, 1)
    }

    func testCommonPrefixSuffixTrimmedBeforeLCS() {
        // 公共前后缀被裁剪后剩余部分才参与比较；两端完全不同时全量输出。
        let lines = DiffEngine.lines(old: "head\nold1\nold2\ntail", new: "head\nnew1\ntail")
        let added = lines.filter { $0.symbol == .added }.map(\.text)
        let removed = lines.filter { $0.symbol == .removed }.map(\.text)
        XCTAssertTrue(added.contains("new1"))
        XCTAssertTrue(removed.contains("old1"))
        XCTAssertTrue(removed.contains("old2"))
    }
}
