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
    // Re-fire repeat-spot / watchlist alerts only when the same plate appears
    // either ≥ minSightingDistanceMeters away OR after this much time. Prevents
    // notification spam when staring at the same parked car.
    private static let minSightingTimeIntervalSeconds: TimeInterval = 300

    @Published private(set) var scanRecords: [PlateScanRecord] = []
    @Published private(set) var detectedPlate: String?
    @Published private(set) var lastError: String?
    /// Fires when a known plate is sighted at a new location (>25m from its
    /// last sighting). Carries the plate so consumers can mention it in
    /// alerts/notifications.
    @Published private(set) var repeatSighting: RepeatSighting?

    /// Fires when a scanned plate matches the user's imported watchlist.
    /// Carries the plate and stored name so consumers can label the alert.
    @Published private(set) var watchlistMatch: WatchlistMatch?

    struct RepeatSighting: Equatable {
        let plate: String
        let at: Date
    }

    struct WatchlistMatch: Equatable {
        let plate: String
        let name: String?
        let at: Date
    }

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

    private var isSendLocationEnabled: Bool {
        if UserDefaults.standard.object(forKey: "sendLocationEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "sendLocationEnabled")
    }

    var isWatchlistAlertEnabled: Bool {
        // Defaults to true; the toggle UI guards against firing when the list
        // is empty (see SettingsViewController).
        if UserDefaults.standard.object(forKey: "watchlistAlertEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "watchlistAlertEnabled")
    }

    var isWatchlistSoundEnabled: Bool {
        if UserDefaults.standard.object(forKey: "watchlistSoundEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "watchlistSoundEnabled")
    }

    func consumeWatchlistMatch() {
        watchlistMatch = nil
    }

    init() {
        self.lookupQueue = PlateLookupQueue()
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
        // Drop spaces, dashes, dots, slashes — anything that isn't a letter or
        // digit. Historic Spanish motorcycle plates render as "GR-AP" / "7726"
        // and Vision may emit either "GR-AP" or "GR AP" depending on the font.
        let raw = text.uppercased().filter { $0.isLetter || $0.isNumber }
        let country = selectedCountry
        let plate = PlateValidator.cleanEUBandPrefix(raw, for: country)

//        print("[ScanVM] raw=\(raw) plate=\(plate) country=\(country.rawValue) valid=\(PlateValidator.isValid(plate: plate, for: country)) hasLocation=\(currentLocation != nil)")

        guard PlateValidator.isValid(plate: plate, for: country) else {
//            print("[ScanVM] ❌ Not a valid \(country.rawValue) plate: '\(plate)'")
            return
        }

        // Location is best-effort — scanning proceeds without it (services denied
        // or still warming up). Sightings without a location are stored with nil
        // and skipped from map views.
        let location = currentLocation
        let codableLocation = location.map(CodableCoordinate.init)
        let countryCode = country.rawValue

        // Show detected plate immediately.
        detectedPlate = plate

        let existingIdx = scanRecords.firstIndex(where: { $0.plate == plate })
        // A sighting is "fresh" (notification-worthy) when either the plate is
        // new, enough time has passed since its last sighting, or the device
        // has moved beyond the distance threshold. Without GPS, we can only
        // gate on time — so a parked-car re-read won't machinegun banners.
        let isFreshSighting: Bool = {
            guard let idx = existingIdx,
                  let last = scanRecords[idx].sightings.last else { return true }
            if Date().timeIntervalSince(last.date) >= Self.minSightingTimeIntervalSeconds {
                return true
            }
            guard let lastLoc = last.location, let newLoc = location else { return false }
            let lastCL = CLLocation(latitude: lastLoc.latitude, longitude: lastLoc.longitude)
            let newCL = CLLocation(latitude: newLoc.latitude, longitude: newLoc.longitude)
            return lastCL.distance(from: newCL) >= Self.minSightingDistanceMeters
        }()

        if isFreshSighting, WatchlistStore.shared.contains(plate: plate) {
            watchlistMatch = WatchlistMatch(
                plate: plate,
                name: WatchlistStore.shared.name(for: plate),
                at: Date()
            )
        }

        // Existing plate — refresh the last sighting in place when not fresh,
        // otherwise append a new sighting and signal a repeat-spot.
        if let index = existingIdx {
            // No vehicle data and lookup was never attempted — re-enqueue (handles stale nil records).
            if scanRecords[index].vehicleData == nil,
               scanRecords[index].lastLookupAttempt == nil,
               isLookupEnabled,
               cooldownPlates[plate].map({ Date() < $0 }) != true,
               !lookupQueue.items.contains(where: { $0.plate == plate }) {
                let item = PlateQueueItem(
                    plate: plate,
                    country: countryCode,
                    location: codableLocation,
                    enqueuedAt: Date(),
                    capturedFrameFileName: nil,
                    state: .pending
                )
                _ = lookupQueue.enqueue(item)
            }

            if !isFreshSighting, let last = scanRecords[index].sightings.last {
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

            let photoFileName = saveFrameIfNeeded(capturedFrame, plate: plate)
            let sighting = Sighting(
                location: codableLocation,
                date: Date(),
                photoFileName: photoFileName
            )
            scanRecords[index].sightings.append(sighting)
            StorageService.shared.saveRecords(scanRecords)
            repeatSighting = RepeatSighting(plate: plate, at: Date())
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
            location: codableLocation,
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
        let coord = isSendLocationEnabled ? currentLocation : nil
        NetworkService.shared.fetchVehicle(
            plate: plate,
            country: country,
            latitude: coord?.latitude,
            longitude: coord?.longitude
        )
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

    private func storePlateOnly(plate: String, location: CLLocationCoordinate2D?, capturedFrame: UIImage?) {
        let photoFileName = saveFrameIfNeeded(capturedFrame, plate: plate)
        let sighting = Sighting(
            location: location.map(CodableCoordinate.init),
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
        // If the plate already exists (e.g. a prior lookup failed and this
        // is a retry after re-scan), update in place — don't duplicate rows.
        if let idx = scanRecords.firstIndex(where: { $0.plate == item.plate }) {
            scanRecords[idx].vehicleData = vehicleData
            if vehicleData != nil {
                scanRecords[idx].lastLookupAttempt = Date()
            }
            StorageService.shared.saveRecords(scanRecords)
            return
        }

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
        // Mark as attempted only on success (definitive answer). Leaving it
        // nil on failure/cancelled/rate-limit means a later re-scan can
        // re-enqueue the lookup — same treatment as a plate captured with
        // Lookup disabled in Settings.
        if vehicleData != nil {
            record.lastLookupAttempt = Date()
        }
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
