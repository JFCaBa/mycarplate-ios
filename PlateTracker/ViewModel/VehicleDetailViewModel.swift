//
//  VehicleDetailViewModel.swift
//  PlateTracker
//

import Foundation
import Combine

struct DetailRow {
    let label: String
    let value: String
}

struct DetailSection {
    let title: String
    let rows: [DetailRow]
}

@MainActor
final class VehicleDetailViewModel {

    @Published private(set) var sections: [DetailSection] = []
    @Published private(set) var isRefreshing = false

    let plate: String
    var country: String { record?.vehicleData?.country ?? "ES" }
    var latestPhotoFileName: String? { record?.sightings.last?.photoFileName }

    private var record: PlateScanRecord? {
        scanViewModel.scanRecords.first { $0.plate == plate }
    }
    private let scanViewModel: ScanViewModel
    private var subscriptions = Set<AnyCancellable>()

    private static let countryFlags: [String: String] = [
        "ES": "\u{1F1EA}\u{1F1F8}",
        "UK": "\u{1F1EC}\u{1F1E7}",
        "NL": "\u{1F1F3}\u{1F1F1}",
        "NO": "\u{1F1F3}\u{1F1F4}"
    ]

    var navigationTitle: String {
        let flag = Self.countryFlags[country] ?? ""
        return "\(flag) \(plate)"
    }

    init(plate: String, scanViewModel: ScanViewModel) {
        self.plate = plate
        self.scanViewModel = scanViewModel

        scanViewModel.$scanRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.buildSections() }
            .store(in: &subscriptions)

        buildSections()
    }

    func refresh() {
        isRefreshing = true
        scanViewModel.refreshVehicleData(for: plate) { [weak self] _ in
            self?.isRefreshing = false
        }
    }

    private func buildSections() {
        guard let record = record else { return }
        var allSections: [DetailSection] = []

        if let v = record.vehicleData {
            // Basic Info
            let basicRows: [DetailRow] = [
                v.make.map { DetailRow(label: "Make", value: $0) },
                v.model.map { DetailRow(label: "Model", value: $0) },
                v.version.map { DetailRow(label: "Version", value: $0) },
                v.year.map { DetailRow(label: "Year", value: String($0)) },
                v.color.map { DetailRow(label: "Color", value: $0) },
                v.doors.map { DetailRow(label: "Doors", value: String($0)) },
                v.firstRegistration.map { DetailRow(label: "First Registration", value: $0) },
                v.vin.map { DetailRow(label: "VIN", value: $0) },
                v.weight.map { DetailRow(label: "Weight", value: "\($0) kg") },
            ].compactMap { $0 }
            if !basicRows.isEmpty {
                allSections.append(DetailSection(title: "Basic Info", rows: basicRows))
            }

            // Engine
            let engineRows: [DetailRow] = [
                v.engineSize.map { DetailRow(label: "Engine Size", value: $0) },
                v.engineCode.map { DetailRow(label: "Engine Code", value: $0) },
                v.fuelType.map { DetailRow(label: "Fuel Type", value: $0) },
                v.horsePower.map { DetailRow(label: "Horse Power", value: "\($0) HP") },
                v.powerKw.map { DetailRow(label: "Power", value: "\($0) kW") },
                v.netMaximumPower.map { DetailRow(label: "Net Max Power", value: $0) },
            ].compactMap { $0 }
            if !engineRows.isEmpty {
                allSections.append(DetailSection(title: "Engine", rows: engineRows))
            }

            // Emissions
            let emissionsRows: [DetailRow] = [
                v.co2Emissions.map { DetailRow(label: "CO2 Emissions", value: $0) },
                v.emissionClass.map { DetailRow(label: "Emission Class", value: $0) },
                v.noiseLevel.map { DetailRow(label: "Noise Level", value: $0) },
            ].compactMap { $0 }
            if !emissionsRows.isEmpty {
                allSections.append(DetailSection(title: "Emissions", rows: emissionsRows))
            }

            // Fuel Consumption
            let fuelRows: [DetailRow] = [
                v.fuelConsumptionCombined.map { DetailRow(label: "Combined", value: $0) },
                v.fuelConsumptionCity.map { DetailRow(label: "City", value: $0) },
                v.fuelConsumptionHighway.map { DetailRow(label: "Highway", value: $0) },
            ].compactMap { $0 }
            if !fuelRows.isEmpty {
                allSections.append(DetailSection(title: "Fuel Consumption", rows: fuelRows))
            }

            // Tax & MOT (UK)
            let taxMotRows: [DetailRow] = [
                v.taxStatus.map { DetailRow(label: "Tax Status", value: $0) },
                v.taxDueDate.map { DetailRow(label: "Tax Due Date", value: $0) },
                v.motStatus.map { DetailRow(label: "MOT Status", value: $0) },
                v.motExpiryDate.map { DetailRow(label: "MOT Expiry", value: $0) },
            ].compactMap { $0 }
            if !taxMotRows.isEmpty {
                allSections.append(DetailSection(title: "Tax & MOT", rows: taxMotRows))
            }

            // Identifiers
            let idRows: [DetailRow] = [
                v.base7Code.map { DetailRow(label: "Base7 Code", value: $0) },
                v.source.map { DetailRow(label: "Source", value: $0) },
                v.confidence.map { DetailRow(label: "Confidence", value: String(format: "%.0f%%", $0 * 100)) },
            ].compactMap { $0 }
            if !idRows.isEmpty {
                allSections.append(DetailSection(title: "Metadata", rows: idRows))
            }
        }

        // Sightings history
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let sightingRows = record.sightings.reversed().map { sighting in
            DetailRow(
                label: dateFormatter.string(from: sighting.date),
                value: String(format: "%.4f, %.4f",
                              sighting.location.latitude,
                              sighting.location.longitude)
            )
        }
        if !sightingRows.isEmpty {
            allSections.append(DetailSection(
                title: "Sightings (\(record.sightings.count))",
                rows: sightingRows
            ))
        }

        self.sections = allSections
    }
}
