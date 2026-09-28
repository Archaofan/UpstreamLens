import XCTest
@testable import UpstreamLens

final class FindingQueueTests: XCTestCase {
    private let sourceID = UUID()

    private func finding(_ title: String, status: FindingStatus, relevance: Relevance,
                         time: TimeInterval) -> Finding {
        Finding(sourceID: sourceID, upstreamID: title, title: title, body: "",
                url: "https://github.com/acme/tool", foundAt: Date(timeIntervalSince1970: time),
                relevance: relevance, reason: "", status: status)
    }

    func testViewedFindingStaysPendingUntilHandled() {
        let unread = finding("Unopened", status: .unread, relevance: .routine, time: 20)
        let viewed = finding("Read", status: .viewed, relevance: .routine, time: 10)
        let handled = finding("Done", status: .handled, relevance: .routine, time: 30)

        XCTAssertEqual(FindingQueue.pending([viewed, handled, unread]).map(\.title), ["Unopened", "Read"])
        XCTAssertEqual(FindingQueue.completed([viewed, handled, unread]).map(\.title), ["Done"])
    }

    func testImportantFilterAndPriorityAreStable() {
        let routine = finding("Routine", status: .unread, relevance: .routine, time: 50)
        let importantOld = finding("Important old", status: .viewed, relevance: .important, time: 10)
        let uncertain = finding("Uncertain", status: .unread, relevance: .uncertain, time: 40)
        let importantNew = finding("Important new", status: .unread, relevance: .important, time: 20)
        let input = [routine, importantOld, uncertain, importantNew]

        XCTAssertEqual(FindingQueue.pending(input).map(\.title),
                       ["Important new", "Important old", "Uncertain", "Routine"])
        XCTAssertEqual(FindingQueue.pending(input, importantOnly: true).map(\.title),
                       ["Important new", "Important old"])
        XCTAssertEqual(input.map(\.status), [.unread, .viewed, .unread, .unread])
    }

    @MainActor func testHandledFindingCanReturnToPending() {
        let source = WatchSource(repository: "acme/tool")
        let item = Finding(sourceID: source.id, upstreamID: "v2", title: "v2", body: "",
                           url: "https://github.com/acme/tool", foundAt: .now,
                           relevance: .important, reason: "")
        let model = AppModel(initialData: LocalData(sources: [source], findings: [item]),
                             saveData: { _ in }, publishSnapshot: { _ in })

        model.setStatus(.viewed, for: item.id)
        XCTAssertEqual(FindingQueue.pending(model.findings).count, 1)
        model.setStatus(.handled, for: item.id)
        XCTAssertTrue(FindingQueue.pending(model.findings).isEmpty)
        XCTAssertEqual(FindingQueue.completed(model.findings).count, 1)
        model.setStatus(.viewed, for: item.id)
        XCTAssertEqual(FindingQueue.pending(model.findings).count, 1)
    }
}
