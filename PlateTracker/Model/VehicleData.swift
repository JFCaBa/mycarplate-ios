//
//  VehicleData.swift
//  PlateTracker
//

import Foundation

struct VehicleData: Codable {
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
    let taxStatus: String?
    let taxDueDate: String?
    let motStatus: String?
    let motExpiryDate: String?
    let firstRegistration: String?
    let powerKw: Double?
    let base7Code: String?
    let weight: Int?
    let vin: String?
    let engineCode: String?
    let source: String?
    let confidence: Double?
    let immoPin: String?
}

struct ApiResponse: Decodable {
    let success: Bool
    let data: VehicleData?
    let error: String?
}

struct RateLimitResponse: Decodable {
    let retryAfterSeconds: Int
}
