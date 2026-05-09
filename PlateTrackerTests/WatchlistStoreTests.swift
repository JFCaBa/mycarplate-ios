//
//  WatchlistStoreTests.swift
//  PlateTrackerTests
//

import XCTest
@testable import PlateTracker

final class WatchlistStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() -> WatchlistStore {
        WatchlistStore(directory: tempDir)
    }

    func testEmptyStoreReportsZeroAndNoMatch() {
        let store = makeStore()
        XCTAssertEqual(store.count, 0)
        XCTAssertFalse(store.contains(plate: "1234ABC"))
        XCTAssertNil(store.name(for: "1234ABC"))
    }

    func testReplaceThenContains() {
        let store = makeStore()
        store.replace(with: [
            WatchlistEntry(name: "Mum", plate: "1234ABC"),
            WatchlistEntry(name: "Dad", plate: "5678XYZ"),
        ])
        XCTAssertEqual(store.count, 2)
        XCTAssertTrue(store.contains(plate: "1234ABC"))
        XCTAssertEqual(store.name(for: "1234ABC"), "Mum")
        XCTAssertFalse(store.contains(plate: "9999ZZZ"))
    }

    func testMergeAddsAndOverwrites() {
        let store = makeStore()
        store.replace(with: [WatchlistEntry(name: "Old", plate: "1234ABC")])
        store.merge(with: [
            WatchlistEntry(name: "New", plate: "1234ABC"), // overwrite
            WatchlistEntry(name: "Sister", plate: "5678XYZ"), // add
        ])
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.name(for: "1234ABC"), "New")
        XCTAssertEqual(store.name(for: "5678XYZ"), "Sister")
    }

    func testDeleteRemovesEntry() {
        let store = makeStore()
        store.replace(with: [WatchlistEntry(name: "Mum", plate: "1234ABC")])
        store.delete(plate: "1234ABC")
        XCTAssertEqual(store.count, 0)
        XCTAssertFalse(store.contains(plate: "1234ABC"))
    }

    func testClearRemovesAll() {
        let store = makeStore()
        store.replace(with: [
            WatchlistEntry(name: "Mum", plate: "1234ABC"),
            WatchlistEntry(name: "Dad", plate: "5678XYZ"),
        ])
        store.clear()
        XCTAssertEqual(store.count, 0)
    }

    func testPersistsAcrossInstances() {
        let store1 = makeStore()
        store1.replace(with: [WatchlistEntry(name: "Mum", plate: "1234ABC")])
        let store2 = makeStore() // re-read from disk
        XCTAssertTrue(store2.contains(plate: "1234ABC"))
        XCTAssertEqual(store2.name(for: "1234ABC"), "Mum")
    }
}
