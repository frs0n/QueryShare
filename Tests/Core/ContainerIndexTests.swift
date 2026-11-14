import XCTest
@testable import QueryShareCore
final class ContainerIndexTests: XCTestCase {
    func testDiscoveryYieldsDuringRequestsAndResumesAfterIdle() {
        let store = FileStore()
        XCTAssertFalse(store.shouldYieldDiscovery(at: 100))
        store.noteFileRequest(at: 100)
        XCTAssertTrue(store.shouldYieldDiscovery(at: 100.1))
        store.noteFileRequest(at: 100.1)
        XCTAssertTrue(store.shouldYieldDiscovery(at: 100.2))
        XCTAssertFalse(store.shouldYieldDiscovery(at: 100.3))
    }
    func testCompletedScanOnlyChecksNewIDsAndCacheRoundTrips() throws {
        var index = ContainerIndex(volume: "v1", build: "b1")
        index.advance(next: 101)
        let restored = try JSONDecoder().decode(ContainerIndex.self, from: JSONEncoder().encode(index))
        XCTAssertEqual(restored.nextInode, 101)
        XCTAssertEqual(restored.scannedThrough, 100)
        index.validate(volume: "v1", build: "b1", upper: 120, resolve: { _ in nil })
        XCTAssertEqual(index.nextInode, 101)
        index.validate(volume: "v1", build: "b1", upper: 90, resolve: { _ in nil })
        XCTAssertEqual(index.nextInode, 1)
    }
    func testOldUnverifiedVolumeCacheIsInvalidated() {
        var index = ContainerIndex(volume: "v1", build: "b1")
        index.version = 1; index.advance(next: 100)
        index.validate(volume: "v1", build: "b1", upper: 200, resolve: { _ in nil })
        XCTAssertEqual(index.version, 2); XCTAssertEqual(index.nextInode, 1)
    }
    func testNestedFileWitnessKeepsContainerIdentity() {
        var index = ContainerIndex(volume: "v1", build: "b1")
        var record = ContainerIndex.Record(path: "/container", inode: 42)
        record.witnessPath = "/container/Library/a.db"; index.records[record.path] = record
        index.validate(volume: "v1", build: "b1", upper: 100, resolve: { _ in "/container/Library/a.db" })
        XCTAssertNotNil(index.records["/container"])
        index.validate(volume: "v1", build: "b1", upper: 100, resolve: { _ in "/different/file" })
        XCTAssertNil(index.records["/container"])
    }
    func testEnglishConnectionNotice() {
        let banner = SFTPServer.connectionNotice(username: "research")
        XCTAssertTrue(banner.contains("worse_query")); XCTAssertTrue(banner.contains("Account: research"))
        XCTAssertTrue(banner.contains("virtual index")); XCTAssertTrue(banner.contains("not root access"))
        XCTAssertTrue(banner.contains("/Agent/README.md"))
        XCTAssertLessThan(banner.utf8.count, 1500)
    }
    func testTutorialsRemainAccessibleWhenDiscoveryReplacesAliases() throws {
        let store = FileStore()
        store.directRoot = FileManager.default.temporaryDirectory
        store.aliases = ["/Containers/Apps/Example": "/tmp/example"]
        store.aliases = [:]
        XCTAssertTrue(try store.listedChildren("/").contains("Agent"))
        let tutorials = try store.listedChildren("/Agent")
        XCTAssertTrue(tutorials.contains("README.md"))
        XCTAssertTrue(tutorials.contains("qs.py"))
        let url = try store.resolve("/Agent/10-display.md").0
        XCTAssertTrue(store.isTutorial(url))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("YlEtTtHlNesRBMal1CqRaA"))
        XCTAssertThrowsError(try store.resolve("/Agent/../outside"))
    }
    func testStalePathsAreRemovedAndVolumeChangesResetProgress() {
        var index = ContainerIndex(volume: "v1", build: "b1")
        index.records["/a"] = .init(path: "/a", inode: 30)
        index.records["/b"] = .init(path: "/b", inode: 40)
        index.advance(next: 100)
        index.validate(volume: "v1", build: "b1", upper: 150, resolve: { $0 == 30 ? "/a" : "/replaced" })
        XCTAssertNotNil(index.records["/a"]); XCTAssertNil(index.records["/b"])
        index.validate(volume: "v2", build: "b1", upper: 150, resolve: { _ in "/a" })
        XCTAssertTrue(index.records.isEmpty); XCTAssertEqual(index.nextInode, 1)
    }
    func testAliasesAreNavigableAndRouteToActualContainer() throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = fixture.appendingPathComponent("test.txt"); try Data("hello".utf8).write(to: file)
        let store = FileStore(); store.directRoot = URL(fileURLWithPath: "/")
        store.aliases = ["/Containers/Apps/测试 [com.example.app]": fixture.path]
        XCTAssertTrue(try store.listedChildren("/").contains("Containers"))
        XCTAssertEqual(try store.listedChildren("/Containers"), ["Apps"])
        XCTAssertEqual(try store.listedChildren("/Containers/Apps"), ["测试 [com.example.app]"])
        XCTAssertTrue(store.virtualDirectory("/Containers/Apps"))
        XCTAssertEqual(try store.resolve("/Containers/Apps/测试 [com.example.app]/test.txt").0.path, file.path)
        XCTAssertEqual(try store.listedChildren("/Containers/Apps/测试 [com.example.app]"), ["test.txt"])
    }
    func testUnknownLayoutUsesUUIDAndSanitizesNames() {
        var index = ContainerIndex(volume: "v", build: "b")
        let p = "/private/var/mobile/Containers/Data/Application/12345678-1234-1234-1234-123456789ABC"
        index.records[p] = .init(path: p, name: "a/b\n")
        let aliases = index.aliases()
        XCTAssertEqual(aliases.count, 1)
        XCTAssertTrue(aliases.keys.first!.hasPrefix("/Containers/Apps/a_b_"))
    }
}
