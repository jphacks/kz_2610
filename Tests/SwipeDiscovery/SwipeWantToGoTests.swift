import XCTest
@testable import meshinowa

final class SwipeWantToGoTests: XCTestCase {
    private func entry(_ id: String, synced: Bool, at time: TimeInterval = 0) -> SwipeWantToGoEntry {
        SwipeWantToGoEntry(id: id, name: id, genre: nil, address: nil, latitude: 35, longitude: 139,
                           addedAt: Date(timeIntervalSince1970: time), remoteRestaurantID: synced ? "r-\(id)" : nil,
                           isSynced: synced)
    }

    private func remote(_ key: String, at time: TimeInterval = 0) -> SwipeWantToGoRemoteItem {
        SwipeWantToGoRemoteItem(restaurantID: "r-\(key)", externalKey: key, name: key, category: nil, address: nil,
                                latitude: 35, longitude: 139, addedAt: Date(timeIntervalSince1970: time))
    }

    func testMergeKeepsUnsentAddsDropsServerRemovalsAndAddsServerOnlyItems() {
        let merged = SwipeWantToGoMerge.merge(
            local: [entry("unsent", synced: false, at: 3), entry("removedOnServer", synced: true, at: 2),
                    entry("both", synced: false, at: 1)],
            pendingRemovalIDs: ["pending"],
            remote: [remote("both"), remote("fromOtherDevice", at: 4), remote("pending")])
        XCTAssertEqual(merged.map(\.id), ["fromOtherDevice", "unsent", "both"])
        XCTAssertTrue(merged.first { $0.id == "both" }!.isSynced)
        XCTAssertEqual(merged.first { $0.id == "both" }?.remoteRestaurantID, "r-both")
    }

    @MainActor
    func testStoreAddsRemovesAndSyncs() async throws {
        let server = MockWantToGoRemote()
        let store = SwipeWantToGoStore(fileURL: SwipeFixtures.temporaryURL("want_to_go.json"), remote: server, syncsAutomatically: false)
        try store.add(SwipeFixtures.candidate("a"))
        XCTAssertTrue(store.contains("a"))
        await store.sync()
        XCTAssertEqual(server.items.keys.sorted(), ["a"])
        XCTAssertTrue(store.entries[0].isSynced)

        try store.remove(shopID: "a")
        XCTAssertFalse(store.contains("a"))
        await store.sync()
        XCTAssertTrue(server.items.isEmpty)
        XCTAssertEqual(server.removedKeys, ["a"])
    }

    @MainActor
    func testOfflineChangesStayLocalAndAreSentLater() async throws {
        let server = MockWantToGoRemote()
        server.fails = true
        let url = SwipeFixtures.temporaryURL("want_to_go.json")
        let store = SwipeWantToGoStore(fileURL: url, remote: server, syncsAutomatically: false)
        try store.add(SwipeFixtures.candidate("a"))
        await store.sync()
        XCTAssertFalse(store.entries[0].isSynced)

        server.fails = false
        let reopened = SwipeWantToGoStore(fileURL: url, remote: server, syncsAutomatically: false)
        XCTAssertTrue(reopened.contains("a"))
        await reopened.sync()
        XCTAssertEqual(server.items.keys.sorted(), ["a"])
    }

    @MainActor
    func testVisitedShopsAreRemoved() throws {
        let store = SwipeWantToGoStore(fileURL: SwipeFixtures.temporaryURL("want_to_go.json"))
        try store.add(SwipeFixtures.candidate("a"))
        try store.add(SwipeFixtures.candidate("b"))
        store.removeVisited { $0 == "a" }
        XCTAssertEqual(store.entries.map(\.id), ["b"])
    }
}
