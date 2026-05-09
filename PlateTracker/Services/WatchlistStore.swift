//
//  WatchlistStore.swift
//  PlateTracker
//

import Foundation

/// On-device watchlist. JSON-on-disk + in-memory dictionary for O(1) match.
/// Init takes a directory so unit tests can use a temp folder; production code
/// uses `WatchlistStore.shared` which writes to Application Support.
final class WatchlistStore {

    static let shared: WatchlistStore = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return WatchlistStore(directory: appSupport)
    }()

    /// Posted on the main thread whenever the in-memory list changes.
    static let didChangeNotification = Notification.Name("WatchlistStoreDidChange")

    private let fileURL: URL
    private let queue = DispatchQueue(label: "WatchlistStore")
    private var entriesByPlate: [String: WatchlistEntry] = [:]

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("watchlist.json")
        load()
    }

    var count: Int {
        queue.sync { entriesByPlate.count }
    }

    /// Sorted by name (case-insensitive) for predictable list-screen order.
    var entries: [WatchlistEntry] {
        queue.sync {
            entriesByPlate.values.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    func contains(plate: String) -> Bool {
        queue.sync { entriesByPlate[plate] != nil }
    }

    func name(for plate: String) -> String? {
        queue.sync { entriesByPlate[plate]?.name }
    }

    func replace(with newEntries: [WatchlistEntry]) {
        queue.sync {
            entriesByPlate.removeAll(keepingCapacity: false)
            for entry in newEntries { entriesByPlate[entry.plate] = entry }
            persist()
        }
        notifyChanged()
    }

    func merge(with newEntries: [WatchlistEntry]) {
        queue.sync {
            for entry in newEntries { entriesByPlate[entry.plate] = entry }
            persist()
        }
        notifyChanged()
    }

    func delete(plate: String) {
        queue.sync {
            entriesByPlate.removeValue(forKey: plate)
            persist()
        }
        notifyChanged()
    }

    func clear() {
        queue.sync {
            entriesByPlate.removeAll(keepingCapacity: false)
            persist()
        }
        notifyChanged()
    }

    // MARK: - Private

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let array = try? JSONDecoder().decode([WatchlistEntry].self, from: data) else { return }
            for entry in array { entriesByPlate[entry.plate] = entry }
        }
    }

    /// Caller must already hold `queue`.
    private func persist() {
        let array = Array(entriesByPlate.values)
        do {
            let data = try JSONEncoder().encode(array)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[WatchlistStore] persist failed: \(error.localizedDescription)")
        }
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WatchlistStore.didChangeNotification, object: self)
        }
    }
}
