//
//  VehicleGridViewModel.swift
//  PlateTracker
//

import Foundation
import Combine

@MainActor
final class VehicleGridViewModel {

    struct Section {
        let title: String       // "Today", "Yesterday", or "15 Apr 2026"
        let date: Date          // start-of-day, used for sorting
        let records: [PlateScanRecord]
    }

    @Published private(set) var sections: [Section] = []

    /// Setting this immediately rebuilds sections (synchronous) and also
    /// queues a debounced rebuild for rapid-typing UI scenarios.
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            rebuild()
            searchSubject.send(searchText)
        }
    }

    private var allRecords: [PlateScanRecord] = []
    private var subscriptions = Set<AnyCancellable>()
    private let searchSubject = PassthroughSubject<String, Never>()

    private static let absoluteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// Designated init for testing: no Combine subscription.
    init() {
        // Debounced pipeline handles rapid-typing in production UI;
        // the didSet already rebuilt synchronously so we only need
        // the debounced path for performance (UI binding may also
        // observe $sections directly).
        searchSubject
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &subscriptions)
    }

    /// Convenience init for production: subscribes to the scan VM.
    convenience init(scanViewModel: ScanViewModel) {
        self.init()
        scanViewModel.$scanRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in self?.update(records: records) }
            .store(in: &subscriptions)
    }

    /// Test seam: synchronously seed records and rebuild sections.
    func update(records: [PlateScanRecord]) {
        self.allRecords = records
        rebuild()
    }

    private func rebuild() {
        let filtered = filter(allRecords, query: searchText)
        let calendar = Calendar.current

        // Group by start-of-day of last sighting.
        var groups: [Date: [PlateScanRecord]] = [:]
        for record in filtered {
            let date = record.sightings.last?.date ?? Date()
            let day = calendar.startOfDay(for: date)
            groups[day, default: []].append(record)
        }

        // Sort sections newest-day first; records within sections newest-first.
        let sorted = groups.keys.sorted(by: >)
        sections = sorted.map { day in
            let records = groups[day]!.sorted { ($0.sightings.last?.date ?? .distantPast) > ($1.sightings.last?.date ?? .distantPast) }
            return Section(title: title(for: day, calendar: calendar), date: day, records: records)
        }
    }

    private func filter(_ records: [PlateScanRecord], query: String) -> [PlateScanRecord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return records }
        return records.filter { record in
            if record.plate.lowercased().contains(q) { return true }
            if let make = record.vehicleData?.make?.lowercased(), make.contains(q) { return true }
            if let model = record.vehicleData?.model?.lowercased(), model.contains(q) { return true }
            return false
        }
    }

    private func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return Self.absoluteDateFormatter.string(from: day)
    }
}
