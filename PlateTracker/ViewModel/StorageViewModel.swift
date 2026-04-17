//
//  StorageViewModel.swift
//  PlateTracker
//

import Foundation
import Combine

@MainActor
final class StorageViewModel {

    struct StorageItem {
        let plate: String
        let makeModel: String
        let photoFileName: String?
        let sightingsCount: Int
        let size: Int64
    }

    @Published private(set) var items: [StorageItem] = []
    @Published private(set) var totalSize: Int64 = 0

    private let scanViewModel: ScanViewModel
    private var subscriptions = Set<AnyCancellable>()

    init(scanViewModel: ScanViewModel) {
        self.scanViewModel = scanViewModel

        scanViewModel.$scanRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &subscriptions)

        reload()
    }

    func reload() {
        let records = scanViewModel.scanRecords
        items = records.map { record in
            let makeModel = [record.vehicleData?.make, record.vehicleData?.model]
                .compactMap { $0 }.joined(separator: " ")
            return StorageItem(
                plate: record.plate,
                makeModel: makeModel,
                photoFileName: record.sightings.last?.photoFileName,
                sightingsCount: record.sightings.count,
                size: StorageService.shared.storagePerRecord(record)
            )
        }.sorted { $0.size > $1.size }
        totalSize = StorageService.shared.totalStorageUsed()
    }

    func deleteItem(at index: Int) {
        let item = items[index]
        scanViewModel.deleteRecord(for: item.plate)
    }

    func clearAll() {
        scanViewModel.clearAllRecords()
    }

    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
