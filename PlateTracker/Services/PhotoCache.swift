//
//  PhotoCache.swift
//  PlateTracker
//

import UIKit

/// In-memory thumbnail cache keyed by photo file name. Backed by NSCache so
/// memory pressure evicts entries automatically.
final class PhotoCache {

    static let shared = PhotoCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    private init() {}

    func image(for fileName: String) -> UIImage? {
        cache.object(forKey: fileName as NSString)
    }

    func store(_ image: UIImage, for fileName: String) {
        cache.setObject(image, forKey: fileName as NSString)
    }

    /// Loads from cache, or from disk on a background queue; calls back on main.
    /// `completion` is called at most once.
    func loadAsync(fileName: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = image(for: fileName) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = StorageService.shared.loadPhoto(fileName: fileName)
            if let image = image {
                self?.store(image, for: fileName)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
