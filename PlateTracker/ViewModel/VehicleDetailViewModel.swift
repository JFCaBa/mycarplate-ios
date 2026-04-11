//
//  VehicleDetailViewModel.swift
//  PlateTracker
//

import Foundation

struct DetailRow {
    let label: String
    let value: String
}

struct DetailSection {
    let title: String
    let rows: [DetailRow]
}

final class VehicleDetailViewModel {

    let plate: String
    let country: String
    let sections: [DetailSection]

    init(vehicleData: VehicleData) {
        self.plate = vehicleData.plate
        self.country = vehicleData.country

        var allSections: [DetailSection] = []

        // Basic Info
        let basicRows: [DetailRow] = [
            vehicleData.make.map { DetailRow(label: "Make", value: $0) },
            vehicleData.model.map { DetailRow(label: "Model", value: $0) },
            vehicleData.version.map { DetailRow(label: "Version", value: $0) },
            vehicleData.year.map { DetailRow(label: "Year", value: String($0)) },
            vehicleData.color.map { DetailRow(label: "Color", value: $0) },
            vehicleData.doors.map { DetailRow(label: "Doors", value: String($0)) },
        ].compactMap { $0 }
        if !basicRows.isEmpty {
            allSections.append(DetailSection(title: "Basic Info", rows: basicRows))
        }

        // Engine
        let engineRows: [DetailRow] = [
            vehicleData.engineSize.map { DetailRow(label: "Engine Size", value: $0) },
            vehicleData.fuelType.map { DetailRow(label: "Fuel Type", value: $0) },
            vehicleData.horsePower.map { DetailRow(label: "Horse Power", value: "\($0) HP") },
            vehicleData.netMaximumPower.map { DetailRow(label: "Net Max Power", value: $0) },
        ].compactMap { $0 }
        if !engineRows.isEmpty {
            allSections.append(DetailSection(title: "Engine", rows: engineRows))
        }

        // Emissions
        let emissionsRows: [DetailRow] = [
            vehicleData.co2Emissions.map { DetailRow(label: "CO2 Emissions", value: $0) },
            vehicleData.emissionClass.map { DetailRow(label: "Emission Class", value: $0) },
            vehicleData.noiseLevel.map { DetailRow(label: "Noise Level", value: $0) },
        ].compactMap { $0 }
        if !emissionsRows.isEmpty {
            allSections.append(DetailSection(title: "Emissions", rows: emissionsRows))
        }

        // Fuel Consumption
        let fuelRows: [DetailRow] = [
            vehicleData.fuelConsumptionCombined.map { DetailRow(label: "Combined", value: $0) },
            vehicleData.fuelConsumptionCity.map { DetailRow(label: "City", value: $0) },
            vehicleData.fuelConsumptionHighway.map { DetailRow(label: "Highway", value: $0) },
        ].compactMap { $0 }
        if !fuelRows.isEmpty {
            allSections.append(DetailSection(title: "Fuel Consumption", rows: fuelRows))
        }

        // Metadata
        let metaRows: [DetailRow] = [
            vehicleData.source.map { DetailRow(label: "Source", value: $0) },
            vehicleData.confidence.map { DetailRow(label: "Confidence", value: String(format: "%.0f%%", $0 * 100)) },
        ].compactMap { $0 }
        if !metaRows.isEmpty {
            allSections.append(DetailSection(title: "Metadata", rows: metaRows))
        }

        self.sections = allSections
    }
}
