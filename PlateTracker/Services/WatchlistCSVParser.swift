//
//  WatchlistCSVParser.swift
//  PlateTracker
//

import Foundation

/// Pure parser. No file IO. Caller reads bytes and hands us a `String`.
enum WatchlistCSVParser {

    /// Hard cap matching the spec. Imports above this fail fast; the parser
    /// never produces a partial result above the cap.
    static let maxRows = 10_000

    enum ParseError: Error, Equatable {
        case tooManyRows
    }

    struct Result {
        /// Parsed entries in order, with duplicates collapsed (last-wins).
        let entries: [WatchlistEntry]
        /// Number of non-blank rows we couldn't parse (e.g. missing plate column).
        let skipped: Int
    }

    static func parse(text: String) throws -> Result {
        let rawLines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        let nonBlank = rawLines.map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonBlank.count <= maxRows + 1 /* header tolerance */ else {
            throw ParseError.tooManyRows
        }

        let separator = detectSeparator(in: nonBlank)
        var rows = nonBlank
        if shouldDropHeader(rows: rows, separator: separator) {
            rows.removeFirst()
        }

        if rows.count > maxRows {
            throw ParseError.tooManyRows
        }

        var byPlate: [String: WatchlistEntry] = [:]
        var ordered: [String] = [] // preserves insertion order, dedup by plate
        var skipped = 0
        for row in rows {
            let cells = row.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard cells.count == 2 else {
                skipped += 1
                continue
            }
            let name = cells[0].trimmingCharacters(in: .whitespaces)
            let plate = normalizePlate(cells[1])
            guard !plate.isEmpty else {
                skipped += 1
                continue
            }
            if byPlate[plate] == nil {
                ordered.append(plate)
            }
            byPlate[plate] = WatchlistEntry(name: name, plate: plate)
        }

        return Result(entries: ordered.compactMap { byPlate[$0] }, skipped: skipped)
    }

    /// Picks `;` if it appears more often than `,` across all rows. Defaults to `,`.
    private static func detectSeparator(in rows: [String]) -> Character {
        var commas = 0
        var semis = 0
        for row in rows {
            for ch in row {
                if ch == "," { commas += 1 }
                else if ch == ";" { semis += 1 }
            }
        }
        return semis > commas ? ";" : ","
    }

    /// Treats row 1 as a header IFF the second cell does NOT look plate-shaped
    /// (contains at least one letter AND one digit after normalization). Mirrors
    /// the spec's auto-detect rule.
    private static func shouldDropHeader(rows: [String], separator: Character) -> Bool {
        guard let first = rows.first else { return false }
        let cells = first.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard cells.count == 2 else { return false }
        let candidate = normalizePlate(cells[1])
        let hasLetter = candidate.contains(where: { $0.isLetter })
        let hasDigit = candidate.contains(where: { $0.isNumber })
        return !(hasLetter && hasDigit)
    }

    /// Mirrors `ScanViewModel.processRecognizedText` normalization: uppercase,
    /// keep only letters and digits.
    static func normalizePlate(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
