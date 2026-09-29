import XCTest
@testable import UpstreamLens

/// 存量噪音清理：真机数据里已经躺着 16 条 "Pinned inputs X"。
/// 修好生成逻辑只防新的，存量必须一起收拾，否则用户看到的还是刷屏。
final class LegacyNoiseCleanupTests: XCTestCase {
    private func releaseSource(_ repo: String, versionLikeOnly: Bool = true) -> WatchSource {
        WatchSource(kind: .release, repository: repo, versionLikeOnly: versionLikeOnly)
    }

    private func finding(sourceID: UUID, upstreamID: String, status: FindingStatus = .unread) -> Finding {
        Finding(sourceID: sourceID, upstreamID: upstreamID, title: "t", body: "", url: "u",
                foundAt: .now, relevance: .uncertain, reason: "r", status: status)
    }

    @MainActor private func makeModel(_ data: LocalData) -> AppModel {
        AppModel(initialData: data, saveData: { _ in }, publishSnapshot: { _ in })
    }

    /// 内容寻址的 release id 属于噪音，应被清出待处理列表。
    @MainActor func testContentAddressedReleaseFindingsAreCleared() {
        let source = releaseSource("NousResearch/hermes-agent")
        let noisy = ["399277019", "399277020", "399277021"].map { finding(sourceID: source.id, upstreamID: $0) }
        let model = makeModel(LocalData(sources: [source], findings: noisy))

        XCTAssertEqual(model.findings.filter { $0.status != .handled }.count, 0,
                       "存量噪音必须离开待处理列表")
        XCTAssertEqual(model.findings.count, 3, "记录本身不能删除，只是标记为已处理")
    }

    /// 真正的版本号记录绝不能被误清。
    @MainActor func testVersionLikeFindingsSurvive() {
        let source = releaseSource("owner/repo")
        let good = finding(sourceID: source.id, upstreamID: "v2026.9.24")
        let model = makeModel(LocalData(sources: [source], findings: [good]))
        XCTAssertEqual(model.findings.first?.status, .unread)
    }

    /// path 模式的 upstreamID 是提交 SHA，本来就不像版本号，绝不能误伤。
    @MainActor func testPathModeFindingsAreNeverTouched() {
        let source = WatchSource(kind: .path, repository: "owner/repo", path: "a/b.md")
        let commit = finding(sourceID: source.id, upstreamID: "36699ac9aa11bb22cc33dd44ee55ff6677889900")
        let model = makeModel(LocalData(sources: [source], findings: [commit]))
        XCTAssertEqual(model.findings.first?.status, .unread, "path 模式不在清理范围内")
    }

    /// 用户主动关掉版本过滤，说明他就是要看这些，不能替他清掉。
    @MainActor func testSourcesWithFilterDisabledAreRespected() {
        let source = releaseSource("owner/repo", versionLikeOnly: false)
        let kept = finding(sourceID: source.id, upstreamID: "inputs-a")
        let model = makeModel(LocalData(sources: [source], findings: [kept]))
        XCTAssertEqual(model.findings.first?.status, .unread)
    }

    /// 已经处理过的记录不动。
    @MainActor func testAlreadyHandledFindingsAreNotRewritten() {
        let source = releaseSource("owner/repo")
        let done = finding(sourceID: source.id, upstreamID: "399277019", status: .handled)
        let model = makeModel(LocalData(sources: [source], findings: [done]))
        XCTAssertEqual(model.findings.first?.status, .handled)
    }

    /// 只跑一次：之后用户新产生的非版本号记录（例如手动关过滤又打开）不再被动过。
    @MainActor func testCleanupRunsOnlyOnce() {
        let source = releaseSource("owner/repo")
        var data = LocalData(sources: [source], findings: [finding(sourceID: source.id, upstreamID: "399277019")])
        data.didCleanLegacyNoise = true
        let model = makeModel(data)
        XCTAssertEqual(model.findings.first?.status, .unread, "已标记清理过就不该再动")
    }

    /// 清理条件必须收紧到"纯数字 id"：UUID 等防御性标识不是 release 数字 id，
    /// 用"不像版本号"当条件会把它们一起误伤（这正是收紧前踩到的坑）。
    @MainActor func testNonNumericIdentifiersAreNeverTouched() {
        let source = releaseSource("owner/repo")
        let uuidLike = finding(sourceID: source.id, upstreamID: UUID().uuidString)
        let tagLike = finding(sourceID: source.id, upstreamID: "inputs-a")
        let model = makeModel(LocalData(sources: [source], findings: [uuidLike, tagLike]))
        XCTAssertTrue(model.findings.allSatisfy { $0.status == .unread },
                      "非纯数字标识不在清理范围内")
    }

    /// 纯数字但已在版本号量级内（小 id）也不动，避免把合法记录当噪音。
    @MainActor func testSmallNumericIdentifierIsKept() {
        let source = releaseSource("owner/repo")
        let small = finding(sourceID: source.id, upstreamID: "1234")
        let model = makeModel(LocalData(sources: [source], findings: [small]))
        XCTAssertEqual(model.findings.first?.status, .unread)
    }

    func testNumericIdentifierDetection() {
        XCTAssertTrue(ChangeDetector.isNumericIdentifier("399277019"))
        XCTAssertFalse(ChangeDetector.isNumericIdentifier(""))
        XCTAssertFalse(ChangeDetector.isNumericIdentifier("v1.0.0"))
        XCTAssertFalse(ChangeDetector.isNumericIdentifier("36699ac9aa11bb22cc33dd44ee55ff6677889900"))
        XCTAssertFalse(ChangeDetector.isNumericIdentifier("inputs-a"))
    }

    /// 清理后标记要落盘，避免每次启动都重跑。
    @MainActor func testCleanupMarksItselfDone() {
        let source = releaseSource("owner/repo")
        var saved: LocalData?
        let model = AppModel(initialData: LocalData(sources: [source],
                                                    findings: [finding(sourceID: source.id, upstreamID: "399277019")]),
                             saveData: { saved = $0 }, publishSnapshot: { _ in })
        _ = model
        XCTAssertEqual(saved?.didCleanLegacyNoise, true)
    }
}
