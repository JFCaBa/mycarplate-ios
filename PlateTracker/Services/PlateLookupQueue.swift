//
//  PlateLookupQueue.swift
//  PlateTracker
//

import Foundation

enum PlateLookupOutcome {
    case success(VehicleData)
    case failure
    case rateLimited(retryAfterSeconds: Int)
    case cancelled
}

@MainActor
final class PlateLookupQueue {

    @Published private(set) var items: [PlateQueueItem] = []

    private var onComplete: ((PlateQueueItem, PlateLookupOutcome) -> Void)?
    private var isDispatching = false

    init() {
        // Rehydrate any items left over from a previous run. Items that were
        // mid-flight (.processing) are reset to .pending so they re-dispatch:
        // a background URLSession task may have finished while the app was
        // dead, but we can't trust the outcome reached us — safest to retry.
        let persisted = StorageService.shared.loadQueueItems().map { item -> PlateQueueItem in
            var reset = item
            if item.state == .processing { reset.state = .pending }
            return reset
        }
        self.items = persisted

        // Route BackgroundVehicleFetcher callbacks back into the queue.
        BackgroundVehicleFetcher.shared.completionHandler = { [weak self] plate, outcome in
            self?.finishCurrent(plate: plate, outcome: outcome)
        }
    }

    private func persist() {
        StorageService.shared.saveQueueItems(items)
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
        persist()
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
        persist()
        return true
    }

    /// Called on app termination. Clears every remaining item and emits
    /// `.cancelled` for each so callers can persist plate-only records.
    /// Tasks already handed to the background URLSession continue to run
    /// in the system; their eventual completion hits `finishCurrent` and
    /// no-ops because the plate is no longer in `items`.
    func flushAllToFallback() {
        isDispatching = false
        let drained = items
        items.removeAll()
        persist()
        for item in drained {
            onComplete?(item, .cancelled)
        }
    }

    // MARK: - Private

    private func processNextIfIdle() {
        guard !isDispatching else { return }
        guard let idx = items.firstIndex(where: { $0.state == .pending }) else { return }
        items[idx].state = .processing
        persist()
        let processing = items[idx]
        isDispatching = true
        BackgroundVehicleFetcher.shared.dispatch(plate: processing.plate, country: processing.country)
    }

    private func finishCurrent(plate: String, outcome: PlateLookupOutcome) {
        isDispatching = false
        guard let idx = items.firstIndex(where: { $0.plate == plate }) else {
            // Item already removed (e.g., via flushAllToFallback). Don't
            // double-report.
            processNextIfIdle()
            return
        }
        let item = items.remove(at: idx)
        persist()
        onComplete?(item, outcome)
        processNextIfIdle()
    }
}
