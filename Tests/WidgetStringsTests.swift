import XCTest
@testable import UpstreamLens

final class WidgetStringsTests: XCTestCase {
    func testEnglishTable() {
        let t = WidgetStrings.table("en")
        XCTAssertEqual(t["pending"], "to review")
        XCTAssertEqual(t["checked"], "Checked %@")
        XCTAssertFalse(t.isEmpty)
    }

    func testChineseTable() {
        let t = WidgetStrings.table("zh-Hans")
        XCTAssertEqual(t["pending"], "条待查看")
        XCTAssertEqual(t["checked"], "检查于 %@")
    }

    func testUnknownLanguageFallsBackToEnglish() {
        let t = WidgetStrings.table("fr-FR")
        XCTAssertEqual(t["pending"], "to review", "未知语言回退英文")
    }

    func testCheckedFormatFills() {
        let en = WidgetStrings.table("en")
        let filled = String(format: en["checked"]!, "2h ago")
        XCTAssertEqual(filled, "Checked 2h ago")
        let zh = WidgetStrings.table("zh-Hans")
        XCTAssertEqual(String(format: zh["checked"]!, "2小时前"), "检查于 2小时前")
    }
}
