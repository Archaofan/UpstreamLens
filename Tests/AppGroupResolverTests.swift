import XCTest
@testable import UpstreamLens

final class AppGroupResolverTests: XCTestCase {
    private let requested = "group.com.upstreamlens.ios"
    private let prefixed = "ABCDEF1234.group.com.upstreamlens.ios"

    func testGrantedGroupsExtractsTeamPrefixedFromBinaryPlistShape() {
        // 二进制 plist 形态：组名前后是非组名字节（长度标记等）。
        let data = Data("\u{05}\u{40}\(prefixed)\u{05}\u{40}".utf8)
        XCTAssertEqual(AppGroupResolver.grantedGroups(in: data), [prefixed])
    }

    func testGrantedGroupsExtractsFromXMLProfileShape() {
        let xml = """
        <key>com.apple.security.application-groups</key>
        <array>
            <string>\(prefixed)</string>
        </array>
        """
        XCTAssertEqual(AppGroupResolver.grantedGroups(in: Data(xml.utf8)), [prefixed])
    }

    func testGrantedGroupsKeepsUnprefixedWhenGrantedVerbatim() {
        let data = Data("<string>\(requested)</string>".utf8)
        XCTAssertEqual(AppGroupResolver.grantedGroups(in: data), [requested])
    }

    func testGrantedGroupsExcludesUnrelatedGroups() {
        let xml = """
        <string>group.com.side-store.shared</string>
        <string>\(prefixed)</string>
        <string>group.com.apple.security</string>
        """
        XCTAssertEqual(AppGroupResolver.grantedGroups(in: Data(xml.utf8)), [prefixed])
    }

    func testGrantedGroupsReturnsEmptyForNilOrGarbage() {
        XCTAssertTrue(AppGroupResolver.grantedGroups(in: nil).isEmpty)
        XCTAssertTrue(AppGroupResolver.grantedGroups(in: Data()).isEmpty)
        XCTAssertTrue(AppGroupResolver.grantedGroups(in: Data("no groups here".utf8)).isEmpty)
    }

    func testPreferredGroupIDPrefersRequestedWhenGranted() {
        let granted = [prefixed, requested]
        XCTAssertEqual(AppGroupResolver.preferredGroupID(requested: requested, granted: granted), requested)
    }

    func testPreferredGroupIDFallsBackToTeamPrefixedVariant() {
        XCTAssertEqual(AppGroupResolver.preferredGroupID(requested: requested, granted: [prefixed]), prefixed)
    }

    func testPreferredGroupIDKeepsRequestedWhenNothingMatches() {
        XCTAssertEqual(AppGroupResolver.preferredGroupID(requested: requested, granted: ["group.com.other.app"]), requested)
        XCTAssertEqual(AppGroupResolver.preferredGroupID(requested: requested, granted: []), requested)
    }

    func testResolveReturnsRequestedWhenContainerUnavailable() {
        // 测试进程没有 App Group entitlement，所有 containerURL 都是 nil：应兜底返回原始 ID，不崩溃。
        let resolved = AppGroupResolver.resolve(requested: requested,
                                                profileData: Data("<string>\(prefixed)</string>".utf8),
                                                fileManager: .default)
        XCTAssertEqual(resolved, requested)
    }
}
