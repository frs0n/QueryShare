import XCTest
@testable import QueryShareCore
final class ConnectionPasswordStoreTests: XCTestCase {
    func testPasswordSurvivesNewStoreInstancesAndEdits() throws {
        var saved: Data?
        var writes = 0
        func makeStore() -> ConnectionPasswordStore {
            .init(read: { saved }, write: { saved = $0; writes += 1 })
        }
        let initial = try makeStore().loadOrCreate()
        XCTAssertEqual(initial.count, 32)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try makeStore().loadOrCreate(), initial)
        XCTAssertEqual(writes, 1)
        try makeStore().save("custom-test-password")
        XCTAssertEqual(try makeStore().loadOrCreate(), "custom-test-password")
    }
    func testReadFailureDoesNotReplaceExistingCredential() {
        var wrote = false
        let store = ConnectionPasswordStore(read: { throw NSError(domain: "locked", code: 1) }, write: { _ in wrote = true })
        XCTAssertThrowsError(try store.loadOrCreate())
        XCTAssertFalse(wrote)
    }
    func testFirstSaveFailureIsReported() {
        let store = ConnectionPasswordStore(read: { nil }, write: { _ in throw NSError(domain: "denied", code: 1) })
        XCTAssertThrowsError(try store.loadOrCreate())
    }
}
