//
//  SettingsViewController.swift
//  PlateTracker
//

import UIKit

final class SettingsViewController: UITableViewController {

    private var scanViewModel: ScanViewModel!

    private let countries: [(PlateCountry, String)] = [
        (.spain, "🇪🇸 Spain"),
        (.uk, "🇬🇧 United Kingdom"),
        (.netherlands, "🇳🇱 Netherlands"),
        (.norway, "🇳🇴 Norway"),
    ]

    private let lookupSwitch = UISwitch()

    func configure(with scanViewModel: ScanViewModel) {
        self.scanViewModel = scanViewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView = UITableView(frame: .zero, style: .insetGrouped)

        lookupSwitch.isOn = {
            if UserDefaults.standard.object(forKey: "lookupEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "lookupEnabled")
        }()
        lookupSwitch.addTarget(self, action: #selector(lookupToggled), for: .valueChanged)
    }

    // MARK: - Sections

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Scan Preferences" : "Storage"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 && indexPath.row == 0 {
            return countryCell()
        } else if indexPath.section == 0 && indexPath.row == 1 {
            return lookupCell()
        } else {
            return storageCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 && indexPath.row == 0 {
            showCountryPicker()
        } else if indexPath.section == 1 {
            let storageVC = StorageViewController()
            storageVC.configure(with: scanViewModel)
            navigationController?.pushViewController(storageVC, animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    // MARK: - Cells

    private func countryCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "countryCell")
        cell.imageView?.image = UIImage(systemName: "flag")
        cell.textLabel?.text = "Country"
        let current = UserDefaults.standard.string(forKey: "selectedCountry") ?? "ES"
        let country = PlateCountry(rawValue: current) ?? .spain
        cell.detailTextLabel?.text = countries.first(where: { $0.0 == country })?.1
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func lookupCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "lookupCell")
        cell.imageView?.image = UIImage(systemName: "network")
        cell.textLabel?.text = "Lookup vehicle data"
        cell.detailTextLabel?.text = "Fetch make, model & specs from API"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryView = lookupSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func storageCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "settingsCell")
        cell.imageView?.image = UIImage(systemName: "internaldrive")
        cell.textLabel?.text = "Manage Storage"
        let total = StorageService.shared.totalStorageUsed()
        cell.detailTextLabel?.text = StorageViewModel.formattedSize(total)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - Actions

    private func showCountryPicker() {
        let alert = UIAlertController(title: "Select Country", message: nil, preferredStyle: .actionSheet)
        for (country, label) in countries {
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                UserDefaults.standard.set(country.rawValue, forKey: "selectedCountry")
                self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
        }
        present(alert, animated: true)
    }

    @objc private func lookupToggled() {
        UserDefaults.standard.set(lookupSwitch.isOn, forKey: "lookupEnabled")
    }
}
