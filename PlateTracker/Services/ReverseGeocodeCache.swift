//
//  ReverseGeocodeCache.swift
//  PlateTracker
//

import Foundation
import CoreLocation

/// Disk-backed cache for reverse-geocoded coordinates. Same lat/lng for a
/// parked car shows up dozens of times across sightings, so memoising the
/// CLGeocoder result avoids hammering Apple's rate limit (≈50 req/min/app)
/// and keeps the detail screen responsive offline.
///
/// Coordinates are quantised to 4 decimal places (~11 m) so GPS jitter at the
/// same spot still hits the cache.
final class ReverseGeocodeCache {

    static let shared: ReverseGeocodeCache = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ReverseGeocodeCache(directory: dir)
    }()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "ReverseGeocodeCache")
    private var cache: [String: String] = [:]
    /// Multiple cells may request the same key while one is in flight.
    /// Coalesce them so we only fire one CLGeocoder request per key.
    private var inflight: [String: [(String?) -> Void]] = [:]
    private let geocoder = CLGeocoder()
    /// CLGeocoder cancels a prior request on the same instance when a new one
    /// arrives, so we serialise.
    private let opQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("geocode-cache.json")
        load()
    }

    /// Returns a cached value synchronously, or nil if not cached.
    func cached(_ coord: CodableCoordinate) -> String? {
        queue.sync { cache[Self.key(for: coord)] }
    }

    /// Looks up a coordinate. Cached values fire `completion` on the main
    /// thread immediately; misses fire after the network round-trip. `nil` =
    /// the geocoder returned no usable placemark; we don't cache misses so a
    /// later request can retry (e.g. once the device is back online).
    func lookup(_ coord: CodableCoordinate, completion: @escaping (String?) -> Void) {
        let key = Self.key(for: coord)

        enum Action { case cached(String); case waiting; case fire }
        let action: Action = queue.sync {
            if let value = cache[key] { return .cached(value) }
            if inflight[key] != nil {
                inflight[key]!.append(completion)
                return .waiting
            }
            inflight[key] = [completion]
            return .fire
        }

        switch action {
        case .cached(let value):
            DispatchQueue.main.async { completion(value) }
        case .waiting:
            return
        case .fire:
            opQueue.addOperation { [weak self] in
                self?.performGeocode(key: key, coord: coord)
            }
        }
    }

    func clear() {
        queue.sync {
            cache.removeAll(keepingCapacity: false)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    var count: Int {
        queue.sync { cache.count }
    }

    // MARK: - Private

    private static func key(for coord: CodableCoordinate) -> String {
        String(format: "%.4f,%.4f", coord.latitude, coord.longitude)
    }

    private func performGeocode(key: String, coord: CodableCoordinate) {
        let semaphore = DispatchSemaphore(value: 0)
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self = self else { semaphore.signal(); return }
            let formatted = placemarks?.first.flatMap(Self.format)
            self.queue.sync {
                if let formatted = formatted {
                    self.cache[key] = formatted
                    self.persist()
                }
                let waiters = self.inflight.removeValue(forKey: key) ?? []
                DispatchQueue.main.async {
                    for w in waiters { w(formatted) }
                }
            }
            semaphore.signal()
        }
        // Hold the operation slot until the request finishes so we don't
        // dispatch another reverseGeocodeLocation on the same CLGeocoder
        // instance and have it cancel the in-flight one. 30 s is generous
        // padding; CLGeocoder typically returns in well under 2 s.
        _ = semaphore.wait(timeout: .now() + 30)
    }

    private static func format(_ placemark: CLPlacemark) -> String? {
        // "Street, City" when both available; otherwise whatever the geocoder
        // gave us. Avoids duplicating the city when `name` already contains it.
        var parts: [String] = []
        if let name = placemark.name, !name.isEmpty {
            parts.append(name)
        } else if let thoroughfare = placemark.thoroughfare, !thoroughfare.isEmpty {
            parts.append(thoroughfare)
        }
        if let locality = placemark.locality,
           !locality.isEmpty,
           !parts.contains(where: { $0.localizedCaseInsensitiveContains(locality) }) {
            parts.append(locality)
        }
        if parts.isEmpty, let country = placemark.country {
            parts.append(country)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
            cache = dict
        }
    }

    /// Caller must hold `queue`.
    private func persist() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ReverseGeocodeCache] persist failed: \(error.localizedDescription)")
        }
    }
}
