//
//  WatchlistEntryDetailViewController.swift
//  PlateTracker
//

import UIKit
import CoreLocation
import MapKit

/// Sightings detail for a single watchlist entry. Reads from StorageService —
/// the same scan-record store the rest of the app uses — and reloads on
/// appearance so newly captured sightings show up without a manual refresh.
final class WatchlistEntryDetailViewController: UITableViewController {

    private let entry: WatchlistEntry
    private var sightings: [Sighting] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(entry: WatchlistEntry) {
        self.entry = entry
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = entry.name.isEmpty ? entry.plate : entry.name
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        let records = StorageService.shared.loadRecords()
        // Sort newest-first so recent sightings are at the top.
        sightings = (records.first(where: { $0.plate == entry.plate })?.sightings ?? [])
            .sorted { $0.date > $1.date }
        tableView.reloadData()
    }

    // MARK: - UITableView

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1                          // header info
        case 1: return max(sightings.count, 1)    // empty-state row when 0
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "Sightings (\(sightings.count))" : nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1, !sightings.isEmpty else { return nil }
        return "Tap a sighting to open its location in Maps."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "info")
            cell.textLabel?.text = "Plate"
            cell.detailTextLabel?.text = entry.plate
            cell.selectionStyle = .none
            return cell
        }

        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "sighting")

        if sightings.isEmpty {
            cell.textLabel?.text = "Not yet spotted"
            cell.textLabel?.textColor = .secondaryLabel
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }

        let sighting = sightings[indexPath.row]
        cell.textLabel?.text = dateFormatter.string(from: sighting.date)
        cell.textLabel?.textColor = .label

        if let coord = sighting.location {
            if let address = ReverseGeocodeCache.shared.cached(coord) {
                cell.detailTextLabel?.text = address
            } else {
                // Show coords as a placeholder, kick off geocoding, reload the
                // row when it returns. Match by sighting date because the
                // sightings array is stable for this VC's lifetime.
                cell.detailTextLabel?.text = String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
                let dateAtRequest = sighting.date
                ReverseGeocodeCache.shared.lookup(coord) { [weak self, weak tableView] _ in
                    guard let self = self, let tableView = tableView else { return }
                    guard let row = self.sightings.firstIndex(where: { $0.date == dateAtRequest }) else { return }
                    let path = IndexPath(row: row, section: 1)
                    if tableView.indexPathsForVisibleRows?.contains(path) == true {
                        tableView.reloadRows(at: [path], with: .none)
                    }
                }
            }
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.detailTextLabel?.text = "Location unavailable"
            cell.detailTextLabel?.textColor = .tertiaryLabel
            cell.selectionStyle = .none
            cell.accessoryType = .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1,
              !sightings.isEmpty,
              indexPath.row < sightings.count,
              let coord = sightings[indexPath.row].location else { return }
        let placemark = MKPlacemark(coordinate: coord.clCoordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = entry.name.isEmpty ? entry.plate : entry.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapTypeKey: NSNumber(value: MKMapType.standard.rawValue)
        ])
    }
}
