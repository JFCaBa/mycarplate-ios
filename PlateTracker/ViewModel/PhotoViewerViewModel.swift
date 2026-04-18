//
//  PhotoViewerViewModel.swift
//  PlateTracker
//

import Foundation

@MainActor
final class PhotoViewerViewModel {

    private(set) var vehicles: [PlateScanRecord]
    var currentIndex: Int

    /// Per-vehicle (by plate) currently-selected sighting index.
    private var sightingIndexByPlate: [String: Int] = [:]

    init(vehicles: [PlateScanRecord], startIndex: Int) {
        self.vehicles = vehicles
        self.currentIndex = max(0, min(startIndex, vehicles.count - 1))
    }

    var currentVehicle: PlateScanRecord? {
        guard !vehicles.isEmpty, currentIndex >= 0, currentIndex < vehicles.count else { return nil }
        return vehicles[currentIndex]
    }

    var isEmpty: Bool { vehicles.isEmpty }

    func advance() {
        guard currentIndex < vehicles.count - 1 else { return }
        currentIndex += 1
    }

    func retreat() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func currentSightingIndex(forVehicle index: Int) -> Int {
        guard index >= 0, index < vehicles.count else { return 0 }
        let plate = vehicles[index].plate
        if let stored = sightingIndexByPlate[plate] { return stored }
        return max(0, vehicles[index].sightings.count - 1) // latest
    }

    func setCurrentSightingIndex(_ value: Int, forVehicle index: Int) {
        guard index >= 0, index < vehicles.count else { return }
        sightingIndexByPlate[vehicles[index].plate] = value
    }

    func replaceVehicle(at index: Int, with record: PlateScanRecord) {
        guard index >= 0, index < vehicles.count else { return }
        vehicles[index] = record
    }

    /// Removes the currently displayed vehicle from the in-memory list.
    /// Caller is responsible for persisting the deletion.
    func removeCurrentVehicle() {
        guard !vehicles.isEmpty else { return }
        vehicles.remove(at: currentIndex)
        if vehicles.isEmpty {
            currentIndex = 0
        } else if currentIndex >= vehicles.count {
            currentIndex = vehicles.count - 1
        }
        // currentIndex stays put, which now points to the next vehicle.
    }
}
