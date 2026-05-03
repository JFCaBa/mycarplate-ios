//
//  VehicleFetching.swift
//  PlateTracker
//

import Foundation
import Combine

protocol VehicleFetching {
    func fetchVehicle(plate: String,
                      country: String,
                      latitude: Double?,
                      longitude: Double?) -> AnyPublisher<VehicleData, NetworkError>
}

extension NetworkService: VehicleFetching {}
