//
//  WatchlistCSVParserTests.swift
//  PlateTrackerTests
//

import XCTest
@testable import PlateTracker

final class WatchlistCSVParserTests: XCTestCase {
    private func parse(_ text: String) throws -> WatchlistCSVParser.Result {
        try WatchlistCSVParser.parse(text: text)
    }

    func testParsesCommaSeparatedNoHeader() throws {
        let result = try parse("Mum,1234ABC\nDad,5678XYZ\n")
        XCTAssertEqual(result.entries.map(\.plate), ["1234ABC", "5678XYZ"])
        XCTAssertEqual(result.entries.map(\.name), ["Mum", "Dad"])
        XCTAssertEqual(result.skipped, 0)
    }

    func testParsesSemicolonSeparatedNoHeader() throws {
        let result = try parse("Mum;1234ABC\nDad;5678XYZ\n")
        XCTAssertEqual(result.entries.map(\.plate), ["1234ABC", "5678XYZ"])
    }

    func testStripsHeaderRowWhenFirstRowSecondCellIsNotPlateShaped() throws {
        let result = try parse("name,plate\nMum,1234ABC\n")
        XCTAssertEqual(result.entries.map(\.plate), ["1234ABC"])
        XCTAssertEqual(result.entries.map(\.name), ["Mum"])
    }

    func testKeepsFirstRowWhenSecondCellLooksPlateShaped() throws {
        // First row's second cell has both letters and digits → treat as data.
        let result = try parse("Mum,1234ABC\nDad,5678XYZ\n")
        XCTAssertEqual(result.entries.count, 2)
    }

    func testNormalizesPlate() throws {
        let result = try parse("Mum, 1234-abc \n")
        XCTAssertEqual(result.entries.first?.plate, "1234ABC")
    }

    func testTrimsName() throws {
        let result = try parse("  Mum  ,1234ABC\n")
        XCTAssertEqual(result.entries.first?.name, "Mum")
    }

    func testDuplicatePlateLastWins() throws {
        let result = try parse("First,1234ABC\nSecond,1234ABC\n")
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "Second")
    }

    func testEmptyNameAllowed() throws {
        let result = try parse(",1234ABC\n")
        XCTAssertEqual(result.entries.first?.name, "")
        XCTAssertEqual(result.entries.first?.plate, "1234ABC")
    }

    func testSkipsRowsWithMissingPlate() throws {
        let result = try parse("Only one column\nMum,1234ABC\n,\n")
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.skipped, 2)
    }

    func testSkipsBlankLines() throws {
        let result = try parse("Mum,1234ABC\n\n\nDad,5678XYZ\n")
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.skipped, 0)
    }

    func testStripsLeadingBOM() throws {
        let result = try parse("\u{FEFF}Mum,1234ABC\n")
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "Mum")
        XCTAssertEqual(result.entries.first?.plate, "1234ABC")
    }

    func testThrowsWhenAboveMaxRows() {
        let lines = (0..<10_001).map { "Name\($0),PLATE\($0)X" }.joined(separator: "\n")
        XCTAssertThrowsError(try parse(lines)) { error in
            guard case WatchlistCSVParser.ParseError.tooManyRows = error else {
                return XCTFail("Expected .tooManyRows, got \(error)")
            }
        }
    }
}
