import XCTest
@testable import UpstreamLens

final class DiagnosticsTests: XCTestCase {
    func testByteSearchFindsGroupIdentifier() {
        let data = Data("junk before group.com.upstreamlens.ios junk after".utf8)
        XCTAssertTrue(Diagnostics.contains(data, needle: "group.com.upstreamlens.ios"))
        XCTAssertFalse(Diagnostics.contains(data, needle: "group.com.other.app"))
        XCTAssertFalse(Diagnostics.contains(Data(), needle: "group.com.upstreamlens.ios"))
        // 空needle视为无需查找
        XCTAssertTrue(Diagnostics.contains(data, needle: ""))
    }

    func testRoundTripFailsWithUnavailableGroup() {
        // 无效 App Group 在测试环境拿不到容器，应返回错误说明而不是崩溃。
        let error = Diagnostics.appGroupRoundTrip(groupID: "group.invalid.diagnostics.test")
        XCTAssertNotNil(error)
    }

    func testContainerExistenceMatchesAvailability() {
        // 不能假设测试环境有或没有容器，只验证函数可调用且类型正确。
        let exists = Diagnostics.appGroupContainerExists(groupID: "group.invalid.diagnostics.test")
        XCTAssertFalse(exists)
    }

    func testProfileDataIsOptionalAndSafe() {
        // 宿主 App 未重签时没有 embedded.mobileprovision；此调用不应崩溃。
        _ = Diagnostics.provisionProfileData()
        _ = Diagnostics.executableData()
    }
}

final class RetentionTests: XCTestCase {
    private func finding(status: FindingStatus, daysAgo: Int) -> Finding {
        Finding(sourceID: UUID(), upstreamID: "id-\(status.rawValue)-\(daysAgo)", title: "t", body: "",
                url: "https://github.com/o/r", foundAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
                relevance: .routine, reason: "r", status: status)
    }

    func testDefaultRetentionIs90Days() {
        XCTAssertEqual(LocalData().effectiveRetentionDays, 90)
        XCTAssertEqual(LocalData(retentionDays: nil).effectiveRetentionDays, 90)
        XCTAssertEqual(LocalData(retentionDays: 0).effectiveRetentionDays, 0)
        XCTAssertEqual(LocalData(retentionDays: 30).effectiveRetentionDays, 30)
    }

    func testPruneRemovesOnlyOldHandledRecords() {
        var data = LocalData()
        data.findings = [
            finding(status: .handled, daysAgo: 100),
            finding(status: .handled, daysAgo: 10),
            finding(status: .unread, daysAgo: 100),
            finding(status: .viewed, daysAgo: 100),
        ]
        let pruned = data.pruned(now: Date())
        XCTAssertEqual(pruned.findings.count, 3)
        XCTAssertTrue(pruned.findings.contains { $0.status == .unread })
        XCTAssertTrue(pruned.findings.contains { $0.status == .viewed })
        XCTAssertTrue(pruned.findings.contains { $0.status == .handled && $0.foundAt > Date().addingTimeInterval(-20 * 86_400) })
    }

    func testRetentionZeroKeepsEverything() {
        var data = LocalData(retentionDays: 0)
        data.findings = [finding(status: .handled, daysAgo: 3650)]
        XCTAssertEqual(data.pruned(now: Date()).findings.count, 1)
    }

    func testLegacyBackupWithoutNewFieldsDecodes() throws {
        // 模拟 v1 备份：没有 schemaVersion、retentionDays，来源也没有元数据字段。
        let legacy = """
        {
          "sources": [{"id": "AABBCCDD-1122-3344-5566-77889900AABB", "kind": "Release", "repository": "acme/tool",
                       "path": "", "branch": "", "displayName": "", "purpose": "my NAS", "installedVersion": "1.0.0",
                       "keywords": "config", "rationale": "", "isPaused": false,
                       "baselineIdentifier": "v1.0.0", "baselineContent": null, "etag": null,
                       "lastCheckedAt": null, "lastError": null}],
          "findings": [],
          "lastSuccessfulCheck": null
        }
        """
        let decoded = try JSONDecoder().decode(LocalData.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.sources.count, 1)
        XCTAssertEqual(decoded.sources.first?.purpose, "my NAS")
        XCTAssertNil(decoded.sources.first?.topics)
        XCTAssertNil(decoded.schemaVersion)
        XCTAssertEqual(decoded.effectiveRetentionDays, 90)
    }

    func testExportImportRoundTripKeepsNewFields() throws {
        var source = WatchSource(repository: "acme/tool", purpose: "test")
        source.topics = ["swift", "ci"]
        source.defaultBranch = "main"
        source.repoDescription = "A tool"
        var data = LocalData()
        data.schemaVersion = 2
        data.retentionDays = 180
        data.sources = [source]
        let bytes = try LocalStore.export(data)
        let decoded = try LocalStore.importData(bytes)
        XCTAssertEqual(decoded.retentionDays, 180)
        XCTAssertEqual(decoded.sources.first?.topics, ["swift", "ci"])
        XCTAssertEqual(decoded.sources.first?.defaultBranch, "main")
        XCTAssertEqual(decoded.sources.first?.repoDescription, "A tool")
        XCTAssertEqual(decoded.schemaVersion, 2)
    }
}
