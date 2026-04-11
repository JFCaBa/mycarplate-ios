//
//  VehicleData.swift
//  PlateTracker
//

import Foundation

struct VehicleData: Decodable {
    let plate: String
    let country: String
    let make: String?
    let model: String?
    let version: String?
    let year: Int?
    let color: String?
    let engineSize: String?
    let fuelType: String?
    let doors: Int?
    let horsePower: Int?
    let versionOptions: [String]?
    let doorsOptions: [Int]?
    let co2Emissions: String?
    let fuelConsumptionCombined: String?
    let fuelConsumptionCity: String?
    let fuelConsumptionHighway: String?
    let noiseLevel: String?
    let emissionClass: String?
    let netMaximumPower: String?
    let source: String?
    let confidence: Double?
}

struct ApiResponse: Decodable {
    let success: Bool
    let data: VehicleData?
    let error: String?
}
