//
//  ScanViewModel.swift
//  PlateTracker
//

import Foundation
import Combine
import CoreLocation

final class ScanViewModel {

    @Published private(set) var scanRecords: [PlateScanRecord] = []

    private let locationService = LocationService()
    private var currentLocation: CLLocationCoordinate2D?
    private var subscriptions = Set<AnyCancellable>()

    init() {
        locationService.currentLocationPublisher
            .sink { [weak self] location in
                self?.currentLocation = location
            }
            .store(in: &subscriptions)
    }

    func processRecognizedText(_ text: String) {
        let plate = text.replacingOccurrences(of: " ", with: "").uppercased()

        let detectedCountry = PlateValidator.detectCountry(plate: plate)

        guard detectedCountry != nil,
              let location = currentLocation else { return }

        let countryCode = detectedCountry?.rawValue ?? "ES"

        // Skip if already found
        if scanRecords.contains(where: { $0.plate == plate }) { return }

        fetchInfo(for: plate, country: countryCode, location: location)
    }

    private func fetchInfo(for plate: String, country: String, location: CLLocationCoordinate2D) {
        NetworkService.shared.fetchVehicle(plate: plate, country: country)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in },
                  receiveValue: { [weak self] vehicleData in
                guard let self = self else { return }
                if let index = self.scanRecords.firstIndex(where: { $0.plate == plate }) {
                    self.scanRecords[index].vehicleData = vehicleData
                } else {
                    var record = PlateScanRecord(plate: plate, location: location, timestamp: Date())
                    record.vehicleData = vehicleData
                    self.scanRecords.append(record)
                }
            })
            .store(in: &subscriptions)
    }
}
