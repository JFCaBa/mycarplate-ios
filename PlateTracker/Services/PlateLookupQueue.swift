//
//  PlateLookupQueue.swift
//  PlateTracker
//

import Foundation
import Combine

enum PlateLookupOutcome {
    case success(VehicleData)
    case failure
    case rateLimited(retryAfterSeconds: Int)
    case cancelled
}

@MainActor
final class PlateLookupQueue {

    @Published private(set) var items: [PlateQueueItem] = []

    private let fetcher: VehicleFetching
    private var onComplete: ((PlateQueueItem, PlateLookupOutcome) -> Void)?
    private var activeSubscription: AnyCancellable?

    init(fetcher: VehicleFetching) {
        self.fetcher = fetcher
    }

    func setCompletionHandler(_ handler: @escaping (PlateQueueItem, PlateLookupOutcome) -> Void) {
        self.onComplete = handler
    }

    /// Enqueue a new plate. Returns false if the plate is already present
    /// (pending or processing); caller should treat false as "no-op".
    @discardableResult
    func enqueue(_ item: PlateQueueItem) -> Bool {
        guard !items.contains(where: { $0.plate == item.plate }) else {
            return false
        }
        items.append(item)
        processNextIfIdle()
        return true
    }

    /// Remove a pending item (user-driven deletion). Returns `true` if an
    /// item was removed; `false` if the plate is not in the queue or is
    /// currently `.processing` (the UI does not expose delete on the active
    /// row, but belt-and-suspenders).
    @discardableResult
    func remove(plate: String) -> Bool {
        guard let idx = items.firstIndex(where: { $0.plate == plate }) else { return false }
        guard items[idx].state == .pending else { return false }
        items.remove(at: idx)
        return true
    }

    /// Called on app termination. Cancels the in-flight subscription and
    /// emits `.cancelled` for every remaining item so callers can persist
    /// plate-only records.
    func flushAllToFallback() {
        activeSubscription?.cancel()
        activeSubscription = nil
        let drained = items
        items.removeAll()
        for item in drained {
            onComplete?(item, .cancelled)
        }
    }

    // MARK: - Private

    private func processNextIfIdle() {
        // Already processing something?
        guard activeSubscription == nil else { return }
        // Find first pending.
        guard let idx = items.firstIndex(where: { $0.state == .pending }) else { return }
        items[idx].state = .processing
        let processing = items[idx]

        activeSubscription = fetcher
            .fetchVehicle(plate: processing.plate, country: processing.country)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure(let error) = completion {
                        self.finishCurrent(plate: processing.plate, outcome: self.outcome(for: error))
                    }
                },
                receiveValue: { [weak self] vehicleData in
                    self?.finishCurrent(plate: processing.plate, outcome: .success(vehicleData))
                }
            )
    }

    private func finishCurrent(plate: String, outcome: PlateLookupOutcome) {
        activeSubscription = nil
        guard let idx = items.firstIndex(where: { $0.plate == plate }) else {
            // Item already removed (e.g., via flushAllToFallback). Don't
            // double-report.
            processNextIfIdle()
            return
        }
        let item = items.remove(at: idx)
        onComplete?(item, outcome)
        processNextIfIdle()
    }

    private func outcome(for error: NetworkError) -> PlateLookupOutcome {
        if case .rateLimited(let seconds) = error {
            return .rateLimited(retryAfterSeconds: seconds)
        }
        return .failure
    }
}
