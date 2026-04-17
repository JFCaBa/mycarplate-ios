//
//  VehicleFetching.swift
//  PlateTracker
//

import Foundation
import Combine

protocol VehicleFetching {
    func fetchVehicle(plate: String, country: String) -> AnyPublisher<VehicleData, NetworkError>
}

extension NetworkService: VehicleFetching {}
