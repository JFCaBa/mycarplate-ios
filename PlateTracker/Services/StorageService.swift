//
//  StorageService.swift
//  PlateTracker
//

import UIKit

final class StorageService {

    static let shared = StorageService()

    private let recordsFileName = "scan_records.json"
    private let photosDirectoryName = "vehicle_photos"
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var recordsFileURL: URL {
        documentsDirectory.appendingPathComponent(recordsFileName)
    }

    private var photosDirectory: URL {
        documentsDirectory.appendingPathComponent(photosDirectoryName)
    }

    private init() {
        try? fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Records

    func loadRecords() -> [PlateScanRecord] {
        guard let data = try? Data(contentsOf: recordsFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PlateScanRecord].self, from: data)) ?? []
    }

    func saveRecords(_ records: [PlateScanRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: recordsFileURL, options: .atomic)
    }

    // MARK: - Photos

    func savePhoto(_ image: UIImage, fileName: String) {
        guard let data = image.jpegData(compressionQuality: 0.4) else { return }
        let url = photosDirectory.appendingPathComponent(fileName)
        try? data.write(to: url, options: .atomic)
    }

    func loadPhoto(fileName: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func deletePhoto(fileName: String) {
        let url = photosDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Edited photos (non-destructive)

    /// Writes an edited copy alongside the original. Returns the new file name,
    /// or nil if the image couldn't be encoded.
    func saveEditedPhoto(originalFileName: String, image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.4) else { return nil }
        let stem = (originalFileName as NSString).deletingPathExtension
        let ext = (originalFileName as NSString).pathExtension.isEmpty ? "jpg" : (originalFileName as NSString).pathExtension
        let editedName = "\(stem)__edit-\(UUID().uuidString).\(ext)"
        let url = photosDirectory.appendingPathComponent(editedName)
        do {
            try data.write(to: url, options: .atomic)
            return editedName
        } catch {
            return nil
        }
    }

    func deleteEditedPhoto(fileName: String) {
        let url = photosDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Storage metrics

    func photoFileSize(fileName: String) -> Int64 {
        let url = photosDirectory.appendingPathComponent(fileName)
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    func storagePerRecord(_ record: PlateScanRecord) -> Int64 {
        record.sightings.compactMap(\.photoFileName).reduce(into: Int64(0)) {
            $0 += photoFileSize(fileName: $1)
        }
    }

    func totalStorageUsed() -> Int64 {
        var total: Int64 = 0
        if let attrs = try? fileManager.attributesOfItem(atPath: recordsFileURL.path) {
            total += (attrs[.size] as? Int64) ?? 0
        }
        if let files = try? fileManager.contentsOfDirectory(atPath: photosDirectory.path) {
            for file in files {
                total += photoFileSize(fileName: file)
            }
        }
        return total
    }

    func deleteAllData() {
        try? fileManager.removeItem(at: recordsFileURL)
        try? fileManager.removeItem(at: photosDirectory)
        try? fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }
}
