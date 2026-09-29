import XCTest
@testable import UpstreamLens

final class AvatarCacheTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvatarCacheTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        dir = nil
        super.tearDown()
    }

    func testCachedFileURLIsDeterministicAndDistinct() {
        let a = RepoAvatar.url(for: "n8n-io/n8n")!
        let b = RepoAvatar.url(for: "openclaw/openclaw")!
        XCTAssertEqual(AvatarCache.cachedFileURL(for: a, in: dir), AvatarCache.cachedFileURL(for: a, in: dir))
        XCTAssertNotEqual(AvatarCache.cachedFileURL(for: a, in: dir), AvatarCache.cachedFileURL(for: b, in: dir))
        XCTAssertTrue(AvatarCache.cachedFileURL(for: a, in: dir).lastPathComponent.hasSuffix(".png"))
    }

    func testTotalBytesSumsFiles() {
        XCTAssertEqual(AvatarCache.totalBytes(in: dir), 0)
        try? Data(repeating: 0x01, count: 10).write(to: dir.appendingPathComponent("a.png"))
        try? Data(repeating: 0x02, count: 25).write(to: dir.appendingPathComponent("b.png"))
        XCTAssertEqual(AvatarCache.totalBytes(in: dir), 35)
    }

    func testClearAllRemovesEverythingAndReportsFreedBytes() {
        write(bytes: 10, name: "a.png")
        write(bytes: 20, name: "b.png")
        let freed = AvatarCache.clear(keepExistingSources: false, currentOwners: ["n8n-io"], in: dir)
        XCTAssertEqual(freed, 30)
        XCTAssertEqual(AvatarCache.totalBytes(in: dir), 0)
    }

    /// 关键语义：保留已有来源头像时，只删没有对应来源的文件。
    func testClearKeepingExistingSourcesOnlyRemovesOrphans() {
        let keepOwner = RepoAvatar.url(for: "n8n-io/n8n")!
        let orphanOwner = RepoAvatar.url(for: "openclaw/openclaw")!
        let keepURL = AvatarCache.cachedFileURL(for: keepOwner, in: dir)
        let orphanURL = AvatarCache.cachedFileURL(for: orphanOwner, in: dir)
        try? Data(repeating: 0x01, count: 12).write(to: keepURL)
        try? Data(repeating: 0x02, count: 8).write(to: orphanURL)

        let freed = AvatarCache.clear(keepExistingSources: true, currentOwners: ["n8n-io"], in: dir)

        XCTAssertEqual(freed, 8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepURL.path), "已有来源的头像必须保留")
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
    }

    func testClearWithNoOwnersRemovesEverythingEvenWhenKeeping() {
        write(bytes: 15, name: "x.png")
        let freed = AvatarCache.clear(keepExistingSources: true, currentOwners: [], in: dir)
        XCTAssertEqual(freed, 15)
        XCTAssertEqual(AvatarCache.totalBytes(in: dir), 0)
    }

    func testClearOnMissingDirectoryIsSafe() {
        let missing = dir.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertEqual(AvatarCache.clear(keepExistingSources: false, currentOwners: [], in: missing), 0)
        XCTAssertEqual(AvatarCache.totalBytes(in: missing), 0)
    }

    func testImageReturnsNilForNilURL() async {
        let image = await AvatarCache.image(url: nil, in: dir)
        XCTAssertNil(image)
    }

    func testImageReadsFromDiskWithoutNetwork() async {
        // 用一个确定可解码的 PNG（1x1 透明像素）验证磁盘命中路径不发起网络请求。
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")!
        let url = RepoAvatar.url(for: "n8n-io/n8n")!
        let file = AvatarCache.cachedFileURL(for: url, in: dir)
        try? png.write(to: file)

        let image = await AvatarCache.image(url: url, in: dir)
        XCTAssertNotNil(image, "磁盘已命中时应直接返回，不应依赖网络")
    }

    private func write(bytes: Int, name: String) {
        try? Data(repeating: 0x01, count: bytes).write(to: dir.appendingPathComponent(name))
    }
}
