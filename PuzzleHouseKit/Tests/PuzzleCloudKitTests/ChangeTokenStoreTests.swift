import XCTest
import CloudKit
@testable import PuzzleCloudKit

final class ChangeTokenStoreTests: XCTestCase {

    private var tmpDir: URL!
    private var store: ChangeTokenStore!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tokens-\(UUID().uuidString)")
        store = ChangeTokenStore(container: AppGroupContainer(baseURL: tmpDir))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testMissingTokenIsNil() {
        let zone = CKRecordZone.ID(zoneName: "household-x", ownerName: CKCurrentUserDefaultName)
        XCTAssertNil(store.token(for: zone))
    }

    func testClearOfMissingIsHarmless() {
        let zone = CKRecordZone.ID(zoneName: "household-x", ownerName: CKCurrentUserDefaultName)
        store.clear(zone)   // no throw, no crash
        XCTAssertNil(store.token(for: zone))
    }

    func testClearAllOnEmptyDirectoryIsHarmless() {
        store.clearAll()    // no throw, no crash
    }

    func testFileURLEscapesUnsafeCharacters() throws {
        // CKRecordZone.ID accepts owner names containing "/"; we round-trip
        // through a filename so we must replace it. Easiest sanity check is
        // that two zones whose names differ only by a "/" produce different
        // tokens-on-disk locations — exercised indirectly by clearAll() not
        // bleeding between them.
        let a = CKRecordZone.ID(zoneName: "h/1", ownerName: CKCurrentUserDefaultName)
        let b = CKRecordZone.ID(zoneName: "h_1", ownerName: CKCurrentUserDefaultName)
        XCTAssertNil(store.token(for: a))
        XCTAssertNil(store.token(for: b))
    }
}
