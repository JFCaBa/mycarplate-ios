//
//  ScanViewModel.swift
//  PlateTracker
//

import UIKit
import Combine
import CoreLocation

@MainActor
final class ScanViewModel {

    private static let minSightingDistanceMeters: CLLocationDistance = 25

    @Published private(set) var scanRecords: [PlateScanRecord] = []
    @Published private(set) var detectedPlate: String?
    @Published private(set) var lastError: String?

    let lookupQueue: PlateLookupQueue

    private let locationService = LocationService()
    private var currentLocation: CLLocationCoordinate2D?
    private var subscriptions = Set<AnyCancellable>()
    private var cooldownPlates: [String: Date] = [:]

    private var selectedCountry: PlateCountry {
        let raw = UserDefaults.standard.string(forKey: "selectedCountry") ?? "ES"
        return PlateCountry(rawValue: raw) ?? .spain
    }

    private var isLookupEnabled: Bool {
        if UserDefaults.standard.object(forKey: "lookupEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "lookupEnabled")
    }

    init() {
        self.lookupQueue = PlateLookupQueue(fetcher: NetworkService.shared)
        self.scanRecords = StorageService.shared.loadRecords()

        lookupQueue.setCompletionHandler { [weak self] item, outcome in
            guard let self = self else { return }
            switch outcome {
            case .success(let vehicleData):
                self.storeRecord(for: item, vehicleData: vehicleData)
            case .failure, .cancelled:
                self.storeRecord(for: item, vehicleData: nil)
            case .rateLimited(let retryAfter):
                self.cooldownPlates[item.plate] = Date().addingTimeInterval(TimeInterval(retryAfter))
                self.storeRecord(for: item, vehicleData: nil)
            }
        }

        locationService.currentLocationPublisher
            .sink { [weak self] location in
                self?.currentLocation = location
            }
            .store(in: &subscriptions)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Scan flow

    func processRecognizedText(_ text: String, capturedFrame: UIImage?) {
        let raw = text.replacingOccurrences(of: " ", with: "").uppercased()
        let country = selectedCountry
        let plate = PlateValidator.cleanEUBandPrefix(raw, for: country)

        print("[ScanVM] raw=\(raw) plate=\(plate) country=\(country.rawValue) valid=\(PlateValidator.isValid(plate: plate, for: country)) hasLocation=\(currentLocation != nil)")

        guard PlateValidator.isValid(plate: plate, for: country),
              let location = currentLocation else {
            if !PlateValidator.isValid(plate: plate, for: country) {
                print("[ScanVM] ❌ Not a valid \(country.rawValue) plate: '\(plate)'")
            }
            if currentLocation == nil {
                print("[ScanVM] ❌ No GPS location available yet")
            }
            return
        }

        let countryCode = country.rawValue

        // Show detected plate immediately.
        detectedPlate = plate

        // Existing plate — append a new sighting, or just refresh the last one
        // if we're within Self.minSightingDistanceMeters of it (stationary device
        // or same-car re-scan). Avoids piling up near-duplicate sightings.
        if let index = scanRecords.firstIndex(where: { $0.plate == plate }) {
            // No vehicle data and lookup was never attempted — re-enqueue (handles stale nil records).
            if scanRecords[index].vehicleData == nil,
               scanRecords[index].lastLookupAttempt == nil,
               isLookupEnabled,
               cooldownPlates[plate].map({ Date() < $0 }) != true,
               !lookupQueue.items.contains(where: { $0.plate == plate }) {
                let item = PlateQueueItem(
                    plate: plate,
                    country: countryCode,
                    location: CodableCoordinate(location),
                    enqueuedAt: Date(),
                    capturedFrameFileName: nil,
                    state: .pending
                )
                _ = lookupQueue.enqueue(item)
            }

            if let last = scanRecords[index].sightings.last {
                let lastCL = CLLocation(
                    latitude: last.location.latitude,
                    longitude: last.location.longitude
                )
                let newCL = CLLocation(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                if lastCL.distance(from: newCL) < Self.minSightingDistanceMeters {
                    let refreshed = Sighting(
                        location: last.location,
                        date: Date(),
                        photoFileName: last.photoFileName
                    )
                    let lastIdx = scanRecords[index].sightings.count - 1
                    scanRecords[index].sightings[lastIdx] = refreshed
                    StorageService.shared.saveRecords(scanRecords)
                    return
                }
            }
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

        // Skip if plate was recently rate-limited — write plate-only and skip API.
        if let cooldownUntil = cooldownPlates[plate], Date() < cooldownUntil {
            storePlateOnly(plate: plate, location: location, capturedFrame: capturedFrame)
            return
        }
        cooldownPlates = cooldownPlates.filter { Date() < $0.value }

        // Plate-only mode — store without API call.
        if !isLookupEnabled {
            storePlateOnly(plate: plate, location: location, capturedFrame: capturedFrame)
            return
        }

        // Lookup mode — enqueue for async API lookup.
        // Skip if the plate is already pending or processing in the queue.
        guard !lookupQueue.items.contains(where: { $0.plate == plate }) else { return }

        let photoFileName = saveFrameIfNeeded(capturedFrame, plate: plate)
        let item = PlateQueueItem(
            plate: plate,
            country: countryCode,
            location: CodableCoordinate(location),
            enqueuedAt: Date(),
            capturedFrameFileName: photoFileName,
            state: .pending
        )
        let didEnqueue = lookupQueue.enqueue(item)
        if !didEnqueue, let photoFileName = photoFileName {
            // Dedup: another enqueue for this plate is already in flight.
            // Delete the now-orphaned JPEG we just wrote.
            StorageService.shared.deletePhoto(fileName: photoFileName)
        }
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

    func deleteSighting(plate: String, sightingIndex: Int) {
        guard let recordIdx = scanRecords.firstIndex(where: { $0.plate == plate }),
              sightingIndex >= 0, sightingIndex < scanRecords[recordIdx].sightings.count else { return }
        let sighting = scanRecords[recordIdx].sightings[sightingIndex]
        if let photoName = sighting.photoFileName {
            StorageService.shared.deletePhoto(fileName: photoName)
        }
        if let editedName = sighting.editedPhotoFileName {
            StorageService.shared.deleteEditedPhoto(fileName: editedName)
        }
        scanRecords[recordIdx].sightings.remove(at: sightingIndex)
        StorageService.shared.saveRecords(scanRecords)
    }

    func deleteRecord(for plate: String) {
        guard let idx = scanRecords.firstIndex(where: { $0.plate == plate }) else { return }
        let record = scanRecords[idx]
        for sighting in record.sightings {
            if let original = sighting.photoFileName {
                StorageService.shared.deletePhoto(fileName: original)
            }
            if let edited = sighting.editedPhotoFileName {
                StorageService.shared.deleteEditedPhoto(fileName: edited)
            }
        }
        scanRecords.remove(at: idx)
        StorageService.shared.saveRecords(scanRecords)
    }

    func clearAllRecords() {
        StorageService.shared.deleteAllData()
        scanRecords = []
    }

    // MARK: - Sighting mutation

    func updateSightingNote(plate: String, sightingIndex: Int, note: String?) {
        guard let recordIdx = scanRecords.firstIndex(where: { $0.plate == plate }),
              sightingIndex >= 0, sightingIndex < scanRecords[recordIdx].sightings.count else { return }
        scanRecords[recordIdx].sightings[sightingIndex].note = note
        StorageService.shared.saveRecords(scanRecords)
    }

    func saveEditedPhoto(plate: String, sightingIndex: Int, image: UIImage) {
        guard let recordIdx = scanRecords.firstIndex(where: { $0.plate == plate }),
              sightingIndex >= 0, sightingIndex < scanRecords[recordIdx].sightings.count,
              let originalName = scanRecords[recordIdx].sightings[sightingIndex].photoFileName,
              let editedName = StorageService.shared.saveEditedPhoto(originalFileName: originalName, image: image) else { return }

        // Delete any previous edited file for this sighting.
        if let oldEdited = scanRecords[recordIdx].sightings[sightingIndex].editedPhotoFileName {
            StorageService.shared.deleteEditedPhoto(fileName: oldEdited)
        }
        scanRecords[recordIdx].sightings[sightingIndex].editedPhotoFileName = editedName
        StorageService.shared.saveRecords(scanRecords)
    }

    func revertSightingEdit(plate: String, sightingIndex: Int) {
        guard let recordIdx = scanRecords.firstIndex(where: { $0.plate == plate }),
              sightingIndex >= 0, sightingIndex < scanRecords[recordIdx].sightings.count,
              let editedName = scanRecords[recordIdx].sightings[sightingIndex].editedPhotoFileName else { return }
        StorageService.shared.deleteEditedPhoto(fileName: editedName)
        scanRecords[recordIdx].sightings[sightingIndex].editedPhotoFileName = nil
        StorageService.shared.saveRecords(scanRecords)
    }

    // MARK: - Private

    private func storePlateOnly(plate: String, location: CLLocationCoordinate2D, capturedFrame: UIImage?) {
        let photoFileName = saveFrameIfNeeded(capturedFrame, plate: plate)
        let sighting = Sighting(
            location: CodableCoordinate(location),
            date: Date(),
            photoFileName: photoFileName
        )
        let record = PlateScanRecord(
            plate: plate,
            vehicleData: nil,
            sightings: [sighting]
        )
        scanRecords.append(record)
        StorageService.shared.saveRecords(scanRecords)
    }

    private func storeRecord(for item: PlateQueueItem, vehicleData: VehicleData?) {
        let sighting = Sighting(
            location: item.location,
            date: Date(),
            photoFileName: item.capturedFrameFileName
        )
        var record = PlateScanRecord(
            plate: item.plate,
            vehicleData: vehicleData,
            sightings: [sighting]
        )
        record.lastLookupAttempt = Date()
        scanRecords.append(record)
        StorageService.shared.saveRecords(scanRecords)
    }

    private func saveFrameIfNeeded(_ frame: UIImage?, plate: String) -> String? {
        guard let frame = frame else { return nil }
        let fileName = "\(plate)_\(Int(Date().timeIntervalSince1970)).jpg"
        StorageService.shared.savePhoto(frame, fileName: fileName)
        return fileName
    }

    @objc private func handleWillTerminate() {
        lookupQueue.flushAllToFallback()
    }
}
