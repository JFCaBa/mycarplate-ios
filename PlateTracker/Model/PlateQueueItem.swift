//
//  PlateQueueItem.swift
//  PlateTracker
//

import Foundation

extension CodableCoordinate: Equatable {
    static func == (lhs: CodableCoordinate, rhs: CodableCoordinate) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct PlateQueueItem: Equatable, Codable {
    enum State: String, Equatable, Codable {
        case pending
        case processing
    }

    let plate: String
    let country: String
    let location: CodableCoordinate?
    let enqueuedAt: Date
    let capturedFrameFileName: String?
    var state: State
}
