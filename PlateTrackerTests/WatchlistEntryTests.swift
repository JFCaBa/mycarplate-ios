//
//  WatchlistEntryTests.swift
//  PlateTrackerTests
//

import XCTest
@testable import PlateTracker

final class WatchlistEntryTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let entry = WatchlistEntry(name: "Mum's car", plate: "1234ABC")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WatchlistEntry.self, from: data)
        XCTAssertEqual(decoded.name, "Mum's car")
        XCTAssertEqual(decoded.plate, "1234ABC")
    }

    func testEntriesAreEquatableByPlate() {
        XCTAssertEqual(
            WatchlistEntry(name: "A", plate: "1234ABC"),
            WatchlistEntry(name: "B", plate: "1234ABC")
        )
        XCTAssertNotEqual(
            WatchlistEntry(name: "A", plate: "1234ABC"),
            WatchlistEntry(name: "A", plate: "5678XYZ")
        )
    }
}
