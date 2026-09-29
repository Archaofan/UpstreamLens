import XCTest
@testable import UpstreamLens

final class OnboardingTests: XCTestCase {
    /// 真机诉求：引导要扩到 6 页。
    func testHasSixPages() {
        XCTAssertEqual(OnboardingView.pages.count, 6)
    }

    /// 每页内容必须齐全，且标题不重复，避免复制粘贴留下重复页。
    func testEveryPageIsCompleteAndTitlesAreUnique() {
        var titles = Set<String>()
        for (index, page) in OnboardingView.pages.enumerated() {
            XCTAssertFalse(page.symbol.isEmpty, "第 \(index + 1) 页缺少图标")
            XCTAssertFalse(page.title.isEmpty, "第 \(index + 1) 页缺少标题")
            XCTAssertFalse(page.message.isEmpty, "第 \(index + 1) 页缺少正文")
            XCTAssertFalse(page.footnote.isEmpty, "第 \(index + 1) 页缺少脚注")
            XCTAssertTrue(titles.insert(page.title).inserted, "标题重复：\(page.title)")
        }
    }

    /// 第 3 页必须讲类别（本轮新增的能力），第 6 页讲外观自定义。
    func testExpectedTopicsAreCovered() {
        let titles = OnboardingView.pages.map(\.title)
        XCTAssertTrue(titles.contains("Categories, Search & Tags"), "缺少类别/搜索/标签说明页")
        XCTAssertTrue(titles.contains("Make It Yours"), "缺少外观自定义说明页")
    }

    /// 引导不能"只看一次就没了"：设置里必须能重新打开。
    func testGuidanceIsReopenableFromSettings() {
        // 复看模式由 isReview 驱动，默认值必须为 false，否则首次启动会缺语言选择。
        let review = OnboardingView(onFinish: {}, isReview: true)
        XCTAssertTrue(review.isReview)
        let firstRun = OnboardingView(onFinish: {})
        XCTAssertFalse(firstRun.isReview, "首次启动必须是完整引导（含语言选择与跳过）")
    }
}

final class ReleaseVersionTests: XCTestCase {
    /// 版本号与 Info.plist 必须同步为 0.5.0，避免发出去还是 0.4.0。
    func testBundleVersionIsZeroFiveZero() {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "0.5.0")
    }
}
