//
//  WatchlistEntry.swift
//  PlateTracker
//

import Foundation

/// A single user-imported watchlist row. `plate` is stored already-normalized
/// (uppercase, no whitespace/dashes). Equality is plate-based so the same plate
/// imported twice with different names collapses to one entry.
struct WatchlistEntry: Codable, Hashable {
    let name: String
    let plate: String

    static func == (lhs: WatchlistEntry, rhs: WatchlistEntry) -> Bool {
        lhs.plate == rhs.plate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(plate)
    }
}
