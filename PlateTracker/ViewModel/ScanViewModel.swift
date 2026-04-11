//
//  ScanViewModel.swift
//  PlateTracker
//

import Foundation
import Combine
import CoreLocation

final class ScanViewModel {

    @Published private(set) var scanRecords: [PlateScanRecord] = []
    @Published var errorMessage: String?

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

        // Allow re-fetch if previous lookup failed (vehicleData is nil)
        if let existingIndex = scanRecords.firstIndex(where: { $0.plate == plate }) {
            if scanRecords[existingIndex].vehicleData == nil {
                fetchInfo(for: plate, country: countryCode)
            }
            return
        }

        let record = PlateScanRecord(plate: plate, location: location, timestamp: Date())
        scanRecords.append(record)
        fetchInfo(for: plate, country: countryCode)
    }

    private func fetchInfo(for plate: String, country: String) {
        NetworkService.shared.fetchVehicle(plate: plate, country: country)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            }, receiveValue: { [weak self] vehicleData in
                guard let self = self,
                      let index = self.scanRecords.firstIndex(where: { $0.plate == plate }) else { return }
                self.scanRecords[index].vehicleData = vehicleData
            })
            .store(in: &subscriptions)
    }
}
