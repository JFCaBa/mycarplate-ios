# Settings: Country, Lookup Mode, Results Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add country selector and lookup toggle to Settings, make ScanViewModel settings-aware, and improve Results with search + date grouping.

**Architecture:** UserDefaults stores two preferences (country, lookup mode). ScanViewModel reads them per-frame to decide validation country and whether to call the API. PlateValidator's `cleanEUBandPrefix` gains a country parameter to validate the remainder against only the selected country. ResultsViewModel adds filtering and date-grouped sectioning.

**Tech Stack:** UIKit, Combine, UserDefaults, Vision (OCR — untouched)

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Modify | `PlateTracker/Services/PlateValidatorService.swift` | Add `cleanEUBandPrefix(_:for:)` overload |
| Modify | `PlateTracker/ViewModel/ScanViewModel.swift` | Read settings, country-aware validation, plate-only mode |
| Modify | `PlateTracker/View/Settings/SettingsViewController.swift` | Country picker row, lookup toggle row |
| Modify | `PlateTracker/ViewModel/ResultsViewModel.swift` | Search filter, date-grouped sections |
| Modify | `PlateTracker/View/Results/ResultsViewController.swift` | Search bar, sectioned table, section headers |

---

### Task 1: Add Country-Aware Band Prefix Stripping

**Files:**
- Modify: `PlateTracker/Services/PlateValidatorService.swift:21-32`

Currently `cleanEUBandPrefix` strips prefixes and validates the remainder against *any* country. We need an overload that validates only against the selected country, so partial plates don't leak through to wrong countries.

- [ ] **Step 1: Add the country-specific overload**

In `PlateValidatorService.swift`, add a new method below the existing `cleanEUBandPrefix`. Keep the old one for backward compatibility (it's used nowhere else now, but safe to keep):

```swift
    /// Country-specific variant: only strips if the remainder is valid for the given country.
    static func cleanEUBandPrefix(_ raw: String, for country: PlateCountry) -> String {
        let maxStrip = min(4, raw.count - 4)
        guard maxStrip > 0 else { return raw }
        for length in (1...maxStrip).reversed() {
            let stripped = String(raw.dropFirst(length))
            if isValid(plate: stripped, for: country) {
                return stripped
            }
        }
        return raw
    }
```

- [ ] **Step 2: Build the project in Xcode**

Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add PlateTracker/Services/PlateValidatorService.swift
git commit -m "feat(ios): add country-specific cleanEUBandPrefix overload"
```

---

### Task 2: Settings-Aware ScanViewModel

**Files:**
- Modify: `PlateTracker/ViewModel/ScanViewModel.swift`

- [ ] **Step 1: Add settings helpers at the top of ScanViewModel**

Add these computed properties inside the `ScanViewModel` class, after the `cooldownPlates` declaration (line 20):

```swift
    private var selectedCountry: PlateCountry {
        let raw = UserDefaults.standard.string(forKey: "selectedCountry") ?? "ES"
        return PlateCountry(rawValue: raw) ?? .spain
    }

    private var isLookupEnabled: Bool {
        if UserDefaults.standard.object(forKey: "lookupEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "lookupEnabled")
    }
```

- [ ] **Step 2: Update processRecognizedText to use settings**

Replace the entire `processRecognizedText` method (lines 36-83) with:

```swift
    func processRecognizedText(_ text: String, capturedFrame: UIImage?) {
        let raw = text.replacingOccurrences(of: " ", with: "").uppercased()
        let country = selectedCountry
        let plate = PlateValidator.cleanEUBandPrefix(raw, for: country)

        print("[ScanVM] raw=\(raw) plate=\(plate) country=\(country.rawValue) valid=\(PlateValidator.isValid(plate: plate, for: country)) hasLocation=\(currentLocation != nil)")

        guard PlateValidator.isValid(plate: plate, for: country),
              let location = currentLocation else {
            if !PlateValidator.isValid(plate: plate, for: country) {
                print("[ScanVM] ❌ Not a valid \(country.rawValue) plate: '\(plate)'")
            }
            if currentLocation == nil {
                print("[ScanVM] ❌ No GPS location available yet")
            }
            return
        }

        let countryCode = country.rawValue

        // Show detected plate immediately (before API call)
        detectedPlate = plate

        // Existing plate — just add a new sighting, no API call
        if let index = scanRecords.firstIndex(where: { $0.plate == plate }) {
            let photoFileName = saveFrameIfNeeded(capturedFrame, plate: plate)
            let sighting = Sighting(
                location: CodableCoordinate(location),
                date: Date(),
                photoFileName: photoFileName
            )
            scanRecords[index].sightings.append(sighting)
            StorageService.shared.saveRecords(scanRecords)
            return
        }

        // Skip if already fetching
        guard !isFetching else { return }

        // Skip if plate was recently rate-limited
        if let cooldownUntil = cooldownPlates[plate], Date() < cooldownUntil {
            return
        }
        cooldownPlates = cooldownPlates.filter { Date() < $0.value }

        // Plate-only mode — store without API call
        if !isLookupEnabled {
            let photoFileName = saveFrameIfNeeded(capturedFrame, plate: plate)
            let sighting = Sighting(
                location: CodableCoordinate(location),
                date: Date(),
                photoFileName: photoFileName
            )
            let record = PlateScanRecord(
                plate: plate,
                vehicleData: nil,
                sightings: [sighting]
            )
            scanRecords.append(record)
            StorageService.shared.saveRecords(scanRecords)
            return
        }

        // Lookup mode — call API
        fetchAndStore(plate: plate, country: countryCode, location: location, capturedFrame: capturedFrame)
    }
```

- [ ] **Step 3: Build the project in Xcode**

Expected: Compiles without errors. OCR pipeline is untouched — only the validation and post-detection path changed.

- [ ] **Step 4: Commit**

```bash
git add PlateTracker/ViewModel/ScanViewModel.swift
git commit -m "feat(ios): settings-aware country validation and plate-only mode"
```

---

### Task 3: Settings UI — Country Picker and Lookup Toggle

**Files:**
- Modify: `PlateTracker/View/Settings/SettingsViewController.swift`

- [ ] **Step 1: Replace the entire file content**

Replace `SettingsViewController.swift` with:

```swift
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
```

- [ ] **Step 2: Build and test in Xcode**

Expected: Settings tab shows two sections. Country row shows "🇪🇸 Spain" by default. Tapping it shows action sheet with 4 countries. Toggle defaults to ON. Both persist across app restarts.

- [ ] **Step 3: Commit**

```bash
git add PlateTracker/View/Settings/SettingsViewController.swift
git commit -m "feat(ios): add country selector and lookup toggle to settings"
```

---

### Task 4: ResultsViewModel — Search and Date Grouping

**Files:**
- Modify: `PlateTracker/ViewModel/ResultsViewModel.swift`

- [ ] **Step 1: Replace the entire file content**

Replace `ResultsViewModel.swift` with:

```swift
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
```

- [ ] **Step 2: Build the project in Xcode**

Expected: Compiles without errors.

- [ ] **Step 3: Commit**

```bash
git add PlateTracker/ViewModel/ResultsViewModel.swift
git commit -m "feat(ios): add search filtering and date grouping to ResultsViewModel"
```

---

### Task 5: ResultsViewController — Search Bar and Sectioned Table

**Files:**
- Modify: `PlateTracker/View/Results/ResultsViewController.swift`

- [ ] **Step 1: Replace the entire file content**

Replace `ResultsViewController.swift` with:

```swift
//
//  ResultsViewController.swift
//  PlateTracker
//

import Combine
import UIKit
import CoreLocation

final class ResultsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private var viewModel: ResultsViewModel!
    private var scanViewModel: ScanViewModel!
    private var subscriptions = Set<AnyCancellable>()

    func configure(with scanViewModel: ScanViewModel) {
        self.scanViewModel = scanViewModel
        viewModel = ResultsViewModel(scanViewModel: scanViewModel)
        viewModel.$sections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &subscriptions)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Results"
        view.backgroundColor = .systemBackground
        setupSearchBar()
        setupTableView()
    }

    private func setupSearchBar() {
        searchBar.placeholder = "Search plates..."
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        tableView.tableHeaderView = searchBar
        searchBar.sizeToFit()
        tableView.register(VehicleCell.self, forCellReuseIdentifier: VehicleCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
    }
}

// MARK: - UISearchBarDelegate

extension ResultsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.searchText = searchText
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource

extension ResultsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel?.sections.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.sections[section].records.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel.sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VehicleCell.reuseIdentifier, for: indexPath) as! VehicleCell
        let record = viewModel.sections[indexPath.section].records[indexPath.row]
        cell.configure(with: record)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ResultsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = viewModel.sections[indexPath.section].records[indexPath.row]
        let detailVC = VehicleDetailViewController()
        detailVC.configure(with: record.plate, scanViewModel: scanViewModel)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
```

Note: The `didSelectRowAt` no longer guards on `record.vehicleData != nil` — tapping a plate-only record opens the detail screen where the user can pull-to-refresh to fetch vehicle data.

- [ ] **Step 2: Build and test in Xcode**

Expected:
- Search bar appears at the top of the Results tab
- Records are grouped by date with section headers ("16 Apr 2026")
- Typing in search filters records by plate substring
- Tapping a record (with or without vehicle data) opens the detail screen
- Dragging the table dismisses the keyboard

- [ ] **Step 3: Commit**

```bash
git add PlateTracker/View/Results/ResultsViewController.swift
git commit -m "feat(ios): add search bar and date-grouped sections to Results tab"
```
