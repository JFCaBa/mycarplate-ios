//
//  PlateScanRecord.swift
//  PlateTracker
//

import Foundation
import CoreLocation

struct PlateScanRecord {
    let plate: String
    let location: CLLocationCoordinate2D
    let timestamp: Date
    var vehicleData: VehicleData?
}
