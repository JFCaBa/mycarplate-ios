//
//  PlateScanRecord.swift
//  PlateTracker
//

import Foundation
import CoreLocation

struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct Sighting: Codable {
    let location: CodableCoordinate
    let date: Date
    let photoFileName: String?
    var note: String?
}

struct PlateScanRecord: Codable {
    let plate: String
    var vehicleData: VehicleData?
    var sightings: [Sighting]
    var lastLookupAttempt: Date?

    var latestSighting: Sighting? { sightings.last }
    var latestLocation: CLLocationCoordinate2D? { latestSighting?.location.clCoordinate }
    var latestDate: Date? { latestSighting?.date }
}
