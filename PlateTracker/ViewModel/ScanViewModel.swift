//
//  ScanViewModel.swift
//  PlateTracker
//

import UIKit
import Combine
import CoreLocation

final class ScanViewModel {

    @Published private(set) var scanRecords: [PlateScanRecord] = []
    @Published private(set) var isFetching = false
    @Published private(set) var detectedPlate: String?
    @Published private(set) var lastError: String?

    private let locationService = LocationService()
    private var currentLocation: CLLocationCoordinate2D?
    private var subscriptions = Set<AnyCancellable>()
    private var cooldownPlates: [String: Date] = [:]

    init() {
        scanRecords = StorageService.shared.loadRecords()

        locationService.currentLocationPublisher
            .sink { [weak self] location in
                self?.currentLocation = location
            }
            .store(in: &subscriptions)
    }

    // MARK: - Scan flow

    /// Called by ScanViewController when OCR detects text.
    /// `capturedFrame` is the camera image at detection time.
    func processRecognizedText(_ text: String, capturedFrame: UIImage?) {
        let raw = text.replacingOccurrences(of: " ", with: "").uppercased()
        let plate = PlateValidator.cleanEUBandPrefix(raw)

        print("[ScanVM] raw=\(raw) plate=\(plate) isSpanish=\(PlateValidator.isValid(plate: plate, for: .spain)) hasLocation=\(currentLocation != nil)")

        // Only accept Spanish plates — reject partial reads that match other countries
        guard PlateValidator.isValid(plate: plate, for: .spain),
              let location = currentLocation else {
            if !PlateValidator.isValid(plate: plate, for: .spain) {
                print("[ScanVM] ❌ Not a valid Spanish plate: '\(plate)'")
            }
            if currentLocation == nil {
                print("[ScanVM] ❌ No GPS location available yet")
            }
            return
        }

        let countryCode = "ES"

        // Show detected plate immediately (before API call)
        detectedPlate = plate

        // Existing plate — just add a new sighting, no API call
        if let index = scanRecords.firstIndex(where: { $0.plate == plate }) {
            let photoFileName = saveFrameIfNeeded(capturedFrame, plate: plate)
            let sighting = Sighting(
                location: CodableCoordinate(location),
                date: Date(),
                photoFileName: photoFileName
            )
            scanRecords[index].sightings.append(sighting)
            StorageService.shared.saveRecords(scanRecords)
            return
        }

        // Skip if already fetching
        guard !isFetching else { return }

        // Skip if plate was recently rate-limited
        if let cooldownUntil = cooldownPlates[plate], Date() < cooldownUntil {
            return
        }
        cooldownPlates = cooldownPlates.filter { Date() < $0.value }

        // New plate — call API; only persist on success
        fetchAndStore(plate: plate, country: countryCode, location: location, capturedFrame: capturedFrame)
    }

    // MARK: - Refresh (detail screen)

    func refreshVehicleData(for plate: String, completion: @escaping (Bool) -> Void) {
        guard let record = scanRecords.first(where: { $0.plate == plate }) else {
            completion(false)
            return
        }
        let country = record.vehicleData?.country ?? "ES"
        NetworkService.shared.fetchVehicle(plate: plate, country: country)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { c in
                if case .failure = c { completion(false) }
            }, receiveValue: { [weak self] vehicleData in
                guard let self = self,
                      let idx = self.scanRecords.firstIndex(where: { $0.plate == plate }) else { return }
                self.scanRecords[idx].vehicleData = vehicleData
                StorageService.shared.saveRecords(self.scanRecords)
                completion(true)
            })
            .store(in: &subscriptions)
    }

    // MARK: - Deletion (storage management)

    func deleteRecord(for plate: String) {
        guard let idx = scanRecords.firstIndex(where: { $0.plate == plate }) else { return }
        let record = scanRecords[idx]
        record.sightings.compactMap(\.photoFileName).forEach {
            StorageService.shared.deletePhoto(fileName: $0)
        }
        scanRecords.remove(at: idx)
        StorageService.shared.saveRecords(scanRecords)
    }

    func clearAllRecords() {
        StorageService.shared.deleteAllData()
        scanRecords = []
    }

    // MARK: - Private

    private func fetchAndStore(plate: String, country: String, location: CLLocationCoordinate2D, capturedFrame: UIImage?) {
        isFetching = true
        lastError = nil
        print("[ScanVM] 🌐 Fetching API for plate=\(plate) country=\(country)")
        NetworkService.shared.fetchVehicle(plate: plate, country: country)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isFetching = false
                if case .failure(let error) = completion {
                    print("[ScanVM] ❌ API error for \(plate): \(error)")
                    // On rate limit, cooldown this plate for the server-specified duration
                    if case .rateLimited(let retryAfter) = error {
                        self?.cooldownPlates[plate] = Date().addingTimeInterval(TimeInterval(retryAfter))
                        self?.lastError = "Rate limited — wait \(retryAfter)s"
                    } else {
                        self?.lastError = error.localizedDescription
                    }
                    // Auto-clear error after 3 seconds
                    let msg = self?.lastError
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        if self?.lastError == msg {
                            self?.lastError = nil
                        }
                    }
                }
            }, receiveValue: { [weak self] vehicleData in
                print("[ScanVM] ✅ API success for \(plate): \(vehicleData.make ?? "?") \(vehicleData.model ?? "?")")
                guard let self = self else { return }
                let photoFileName = self.saveFrameIfNeeded(capturedFrame, plate: plate)
                let sighting = Sighting(
                    location: CodableCoordinate(location),
                    date: Date(),
                    photoFileName: photoFileName
                )
                let record = PlateScanRecord(
                    plate: plate,
                    vehicleData: vehicleData,
                    sightings: [sighting]
                )
                self.scanRecords.append(record)
                StorageService.shared.saveRecords(self.scanRecords)
            })
            .store(in: &subscriptions)
    }

    private func saveFrameIfNeeded(_ frame: UIImage?, plate: String) -> String? {
        guard let frame = frame else { return nil }
        let fileName = "\(plate)_\(Int(Date().timeIntervalSince1970)).jpg"
        StorageService.shared.savePhoto(frame, fileName: fileName)
        return fileName
    }
}
