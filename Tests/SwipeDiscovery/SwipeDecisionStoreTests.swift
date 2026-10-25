import XCTest
@testable import meshinowa

final class SwipeDecisionStoreTests: XCTestCase {
    func testRoundTripSurvivesNewInstance() async throws {
        let url = SwipeFixtures.temporaryURL()
        let store = SwipeDecisionStore(fileURL: url)
        try await store.upsert(SwipeFixtures.decision("a", kind: .interested, at: 10))
        try await store.upsert(SwipeFixtures.decision("b", kind: .notInterested, at: 20))
        try await store.upsert(SwipeFixtures.decision("a", kind: .notInterested, at: 30))
        let reloaded = await SwipeDecisionStore(fileURL: url).load()
        XCTAssertEqual(Set(reloaded.map(\.id)), ["a", "b"])
        XCTAssertEqual(reloaded.first { $0.id == "a" }?.kind, .notInterested)
        let file = try JSONDecoder().decode(SwipeDecisionFile.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.schemaVersion, 2)
    }

    func testRemove() async throws {
        let url = SwipeFixtures.temporaryURL()
        let store = SwipeDecisionStore(fileURL: url)
        try await store.upsert(SwipeFixtures.decision("a", kind: .interested, at: 10))
        try await store.remove(ids: ["a"])
        let reloaded = await SwipeDecisionStore(fileURL: url).load()
        XCTAssertTrue(reloaded.isEmpty)
    }

    func testBrokenFileIsMovedAsideAndTreatedAsEmpty() async throws {
        let url = SwipeFixtures.temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let store = SwipeDecisionStore(fileURL: url)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("broken").path))
        try await store.upsert(SwipeFixtures.decision("a", kind: .interested, at: 10))
        let reloaded = await SwipeDecisionStore(fileURL: url).load()
        XCTAssertEqual(reloaded.map(\.id), ["a"])
    }

    func testThousandDecisionsRoundTrip() async throws {
        let url = SwipeFixtures.temporaryURL()
        let decisions = (0..<1000).map { SwipeFixtures.decision("\($0)", kind: .notInterested, at: Double($0)) }
        try await SwipeDecisionStore(fileURL: url).replaceAll(decisions)
        let reloaded = await SwipeDecisionStore(fileURL: url).load()
        XCTAssertEqual(reloaded.count, 1000)
    }
}
