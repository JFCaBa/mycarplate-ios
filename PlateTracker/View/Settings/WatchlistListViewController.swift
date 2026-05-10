//
//  WatchlistListViewController.swift
//  PlateTracker
//

import UIKit

final class WatchlistListViewController: UITableViewController {

    private var entries: [WatchlistEntry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Watchlist"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear",
            style: .plain,
            target: self,
            action: #selector(confirmClear)
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reload),
            name: WatchlistStore.didChangeNotification,
            object: nil
        )
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func reload() {
        entries = WatchlistStore.shared.entries
        navigationItem.rightBarButtonItem?.isEnabled = !entries.isEmpty
        tableView.reloadData()
    }

    @objc private func confirmClear() {
        let alert = UIAlertController(
            title: "Clear watchlist?",
            message: "This removes all \(entries.count) entries. The CSV file you imported is not affected.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            WatchlistStore.shared.clear()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - UITableView

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(entries.count, 1) // 1 = the empty-state row
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "cell")
        if entries.isEmpty {
            cell.textLabel?.text = "No entries"
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
            return cell
        }
        let entry = entries[indexPath.row]
        cell.textLabel?.text = entry.name.isEmpty ? "—" : entry.name
        cell.detailTextLabel?.text = entry.plate
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !entries.isEmpty, indexPath.row < entries.count else { return }
        let detailVC = WatchlistEntryDetailViewController(entry: entries[indexPath.row])
        navigationController?.pushViewController(detailVC, animated: true)
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        !entries.isEmpty
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.row < entries.count else { return }
        let plate = entries[indexPath.row].plate
        WatchlistStore.shared.delete(plate: plate)
    }
}
