//
//  ResultsViewModel.swift
//  PlateTracker
//

import Foundation
import Combine

final class ResultsViewModel {

    struct Section {
        let title: String       // e.g. "15 Apr 2026"
        let records: [PlateScanRecord]
    }

    @Published private(set) var sections: [Section] = []
    @Published var searchText: String = ""

    private var allRecords: [PlateScanRecord] = []
    private var subscriptions = Set<AnyCancellable>()

    private static let sectionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    init(scanViewModel: ScanViewModel) {
        scanViewModel.$scanRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                self?.allRecords = records
                self?.rebuild()
            }
            .store(in: &subscriptions)

        $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &subscriptions)
    }

    private func rebuild() {
        let filtered: [PlateScanRecord]
        let query = searchText.trimmingCharacters(in: .whitespaces).uppercased()
        if query.isEmpty {
            filtered = allRecords
        } else {
            filtered = allRecords.filter { $0.plate.contains(query) }
        }

        // Group by discovery date (first sighting date)
        var groups: [String: [PlateScanRecord]] = [:]
        var groupOrder: [String] = []
        for record in filtered {
            let date = record.sightings.first?.date ?? Date()
            let key = Self.sectionDateFormatter.string(from: date)
            if groups[key] == nil {
                groups[key] = []
                groupOrder.append(key)
            }
            groups[key]!.append(record)
        }

        // Sort sections newest-first, records within each section newest-first
        sections = groupOrder.reversed().map { key in
            let records = groups[key]!.sorted { a, b in
                let aDate = a.sightings.first?.date ?? .distantPast
                let bDate = b.sightings.first?.date ?? .distantPast
                return aDate > bDate
            }
            return Section(title: key, records: records)
        }
    }
}
