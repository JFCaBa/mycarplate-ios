//
//  SettingsViewController.swift
//  PlateTracker
//

import UIKit
import UniformTypeIdentifiers

final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case scan = 0
        case recognition
        case captureArea
        case watchlist
        case storage

        var title: String {
            switch self {
            case .scan: return "Scan Preferences"
            case .recognition: return "Recognition"
            case .captureArea: return "Capture Area"
            case .watchlist: return "Watchlist"
            case .storage: return "Storage"
            }
        }

        var footer: String? {
            switch self {
            case .recognition:
                return "Minimum confidence required to accept a plate. Lower values trigger captures more often but may produce false reads; higher values are stricter but slower to fire."
            case .captureArea:
                return "How much of the car to capture around the plate, in multiples of plate size. Width is symmetric; above/below adjust the vertical crop independently so you can bias toward the hood or rear."
            case .watchlist:
                return "Import a CSV (name,plate) to be alerted when one of those plates is read by the scanner."
            default: return nil
            }
        }
    }

    private var scanViewModel: ScanViewModel!

    private let countries: [(PlateCountry, String)] = [
        (.spain, "🇪🇸 Spain"),
        (.uk, "🇬🇧 United Kingdom"),
        (.netherlands, "🇳🇱 Netherlands"),
        (.norway, "🇳🇴 Norway"),
    ]

    private let lookupSwitch = UISwitch()
    private let sendLocationSwitch = UISwitch()
    private let repeatAlertSwitch = UISwitch()
    private let repeatNotificationSwitch = UISwitch()
    private let watchlistAlertSwitch = UISwitch()
    private let watchlistSoundSwitch = UISwitch()

    func configure(with scanViewModel: ScanViewModel) {
        self.scanViewModel = scanViewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.register(SliderSettingCell.self, forCellReuseIdentifier: SliderSettingCell.reuseIdentifier)

        lookupSwitch.isOn = {
            if UserDefaults.standard.object(forKey: "lookupEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "lookupEnabled")
        }()
        lookupSwitch.addTarget(self, action: #selector(lookupToggled), for: .valueChanged)

        sendLocationSwitch.isOn = {
            if UserDefaults.standard.object(forKey: "sendLocationEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "sendLocationEnabled")
        }()
        sendLocationSwitch.addTarget(self, action: #selector(sendLocationToggled), for: .valueChanged)

        // Off by default — vibration is intrusive, so users opt in.
        repeatAlertSwitch.isOn = UserDefaults.standard.bool(forKey: "repeatSpotAlertEnabled")
        repeatAlertSwitch.addTarget(self, action: #selector(repeatAlertToggled), for: .valueChanged)

        repeatNotificationSwitch.isOn = UserDefaults.standard.bool(forKey: "repeatSpotNotificationEnabled")
        repeatNotificationSwitch.addTarget(self, action: #selector(repeatNotificationToggled), for: .valueChanged)

        watchlistAlertSwitch.isOn = {
            if UserDefaults.standard.object(forKey: "watchlistAlertEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "watchlistAlertEnabled")
        }()
        watchlistAlertSwitch.addTarget(self, action: #selector(watchlistAlertToggled), for: .valueChanged)

        watchlistSoundSwitch.isOn = {
            if UserDefaults.standard.object(forKey: "watchlistSoundEnabled") == nil { return true }
            return UserDefaults.standard.bool(forKey: "watchlistSoundEnabled")
        }()
        watchlistSoundSwitch.addTarget(self, action: #selector(watchlistSoundToggled), for: .valueChanged)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(watchlistDidChange),
            name: WatchlistStore.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Sections

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .scan: return 5
        case .recognition: return 1
        case .captureArea: return 3
        case .watchlist: return 4
        case .storage: return 1
        case .none: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section)?.footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .scan:
            switch indexPath.row {
            case 0: return countryCell()
            case 1: return lookupCell()
            case 2: return sendLocationCell()
            case 3: return repeatAlertCell()
            default: return repeatNotificationCell()
            }
        case .recognition:
            return recognitionCell()
        case .captureArea:
            return captureAreaCell(for: indexPath.row)
        case .watchlist:
            switch indexPath.row {
            case 0: return watchlistImportCell()
            case 1: return watchlistViewCell()
            case 2: return watchlistAlertCell()
            default: return watchlistSoundCell()
            }
        case .storage:
            return storageCell()
        case .none:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }
        switch section {
        case .scan where indexPath.row == 0:
            showCountryPicker()
        case .watchlist where indexPath.row == 0:
            presentImportPicker()
        case .watchlist where indexPath.row == 1:
            let listVC = WatchlistListViewController()
            navigationController?.pushViewController(listVC, animated: true)
        case .storage:
            let storageVC = StorageViewController()
            storageVC.configure(with: scanViewModel)
            navigationController?.pushViewController(storageVC, animated: true)
        default:
            break
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
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryView = lookupSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func sendLocationCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "sendLocationCell")
        cell.imageView?.image = UIImage(systemName: "location")
        cell.textLabel?.text = "Send location"
        cell.detailTextLabel?.text = "Include GPS with each lookup so it appears on the dashboard"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryView = sendLocationSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func repeatAlertCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "repeatAlertCell")
        cell.imageView?.image = UIImage(systemName: "wave.3.right")
        cell.textLabel?.text = "Repeat-spot alert"
        cell.detailTextLabel?.text = "Vibrate and flash when the same plate is sighted in a new location"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryView = repeatAlertSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func repeatNotificationCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "repeatNotificationCell")
        cell.imageView?.image = UIImage(systemName: "bell.badge")
        cell.textLabel?.text = "Repeat-spot notification"
        cell.detailTextLabel?.text = "Push a banner when the same plate is sighted in a new location"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryView = repeatNotificationSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func recognitionCell() -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SliderSettingCell.reuseIdentifier) as! SliderSettingCell
        cell.selectionStyle = .none
        cell.configure(
            title: "Confidence",
            range: ScanRecognitionConfig.confidenceRange,
            value: ScanRecognitionConfig.confidence,
            step: 0.05,
            formatter: { String(format: "%.2f", $0) }
        )
        cell.onChange = { ScanRecognitionConfig.setConfidence($0) }
        return cell
    }

    private func captureAreaCell(for row: Int) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SliderSettingCell.reuseIdentifier) as! SliderSettingCell
        cell.selectionStyle = .none
        switch row {
        case 0:
            cell.configure(
                title: "Width",
                range: ScanCropConfig.widthRange,
                value: Float(ScanCropConfig.width),
                formatter: { String(format: "%.1f×", $0) }
            )
            cell.onChange = { ScanCropConfig.setWidth(CGFloat($0)) }
        case 1:
            cell.configure(
                title: "Above plate",
                range: ScanCropConfig.aboveRange,
                value: Float(ScanCropConfig.above),
                formatter: { String(format: "%.1f×", $0) }
            )
            cell.onChange = { ScanCropConfig.setAbove(CGFloat($0)) }
        case 2:
            cell.configure(
                title: "Below plate",
                range: ScanCropConfig.belowRange,
                value: Float(ScanCropConfig.below),
                formatter: { String(format: "%.1f×", $0) }
            )
            cell.onChange = { ScanCropConfig.setBelow(CGFloat($0)) }
        default:
            break
        }
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

    private func watchlistImportCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "watchlistImportCell")
        cell.imageView?.image = UIImage(systemName: "square.and.arrow.down")
        cell.textLabel?.text = "Import CSV…"
        cell.detailTextLabel?.text = "\(WatchlistStore.shared.count) entries"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func watchlistViewCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "watchlistViewCell")
        cell.imageView?.image = UIImage(systemName: "list.bullet.rectangle")
        cell.textLabel?.text = "View list"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func watchlistAlertCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "watchlistAlertCell")
        cell.imageView?.image = UIImage(systemName: "bell.and.waves.left.and.right")
        cell.textLabel?.text = "Watchlist alert"
        cell.detailTextLabel?.text = "Flash, vibrate and notify when an imported plate is read"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        watchlistAlertSwitch.isEnabled = WatchlistStore.shared.count > 0
        cell.accessoryView = watchlistAlertSwitch
        cell.selectionStyle = .none
        return cell
    }

    private func watchlistSoundCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "watchlistSoundCell")
        cell.imageView?.image = UIImage(systemName: "speaker.wave.2")
        cell.textLabel?.text = "Alarm sound"
        cell.detailTextLabel?.text = "Play the bundled alarm sound when a plate matches"
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        watchlistSoundSwitch.isEnabled = WatchlistStore.shared.count > 0
        cell.accessoryView = watchlistSoundSwitch
        cell.selectionStyle = .none
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

    @objc private func sendLocationToggled() {
        UserDefaults.standard.set(sendLocationSwitch.isOn, forKey: "sendLocationEnabled")
    }

    @objc private func repeatAlertToggled() {
        UserDefaults.standard.set(repeatAlertSwitch.isOn, forKey: "repeatSpotAlertEnabled")
    }

    @objc private func repeatNotificationToggled() {
        let isOn = repeatNotificationSwitch.isOn
        UserDefaults.standard.set(isOn, forKey: "repeatSpotNotificationEnabled")
        guard isOn else { return }
        NotificationService.shared.requestAuthorizationIfNeeded { [weak self] granted in
            guard let self = self, !granted else { return }
            // Permission denied — bounce the toggle back off and explain.
            UserDefaults.standard.set(false, forKey: "repeatSpotNotificationEnabled")
            self.repeatNotificationSwitch.setOn(false, animated: true)
            let alert = UIAlertController(
                title: "Notifications disabled",
                message: "Enable notifications for PlateTracker in Settings to receive repeat-spot banners.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    @objc private func watchlistAlertToggled() {
        UserDefaults.standard.set(watchlistAlertSwitch.isOn, forKey: "watchlistAlertEnabled")
    }

    @objc private func watchlistSoundToggled() {
        UserDefaults.standard.set(watchlistSoundSwitch.isOn, forKey: "watchlistSoundEnabled")
    }

    @objc private func watchlistDidChange() {
        tableView.reloadData()
    }

    private func presentImportPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.commaSeparatedText, .text])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func handleImportedFile(at url: URL) {
        // Security-scoped resource: required for files from outside the app sandbox.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            presentAlert(title: "Couldn't read that file.", message: "Use a UTF-8 plain-text CSV.")
            return
        }
        do {
            let result = try WatchlistCSVParser.parse(text: text)
            guard !result.entries.isEmpty else {
                presentAlert(title: "No rows found.", message: nil)
                return
            }
            promptMergeOrReplace(parsed: result)
        } catch WatchlistCSVParser.ParseError.tooManyRows {
            presentAlert(title: "Too many rows.", message: "The watchlist accepts up to \(WatchlistCSVParser.maxRows) entries.")
        } catch {
            presentAlert(title: "Import failed.", message: error.localizedDescription)
        }
    }

    private func promptMergeOrReplace(parsed: WatchlistCSVParser.Result) {
        let summary = "Imported \(parsed.entries.count) · Skipped \(parsed.skipped)"
        if WatchlistStore.shared.count == 0 {
            // Nothing to merge against — just commit.
            WatchlistStore.shared.replace(with: parsed.entries)
            presentAlert(title: summary, message: nil)
            return
        }
        let alert = UIAlertController(title: summary, message: "Replace your existing list or merge into it?", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Replace existing", style: .destructive) { _ in
            WatchlistStore.shared.replace(with: parsed.entries)
        })
        alert.addAction(UIAlertAction(title: "Merge", style: .default) { _ in
            WatchlistStore.shared.merge(with: parsed.entries)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(row: 0, section: Section.watchlist.rawValue))
        }
        present(alert, animated: true)
    }

    private func presentAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension SettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        handleImportedFile(at: url)
    }
}

// MARK: - SliderSettingCell

final class SliderSettingCell: UITableViewCell {

    static let reuseIdentifier = "SliderSettingCell"

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .body)
        return l
    }()

    private let valueLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: UIFont.systemFontSize, weight: .semibold)
        l.textColor = .secondaryLabel
        l.textAlignment = .right
        return l
    }()

    private let slider = UISlider()
    var onChange: ((Float) -> Void)?
    private var formatter: ((Float) -> String)?
    private var step: Float = 0.1

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        if #available(iOS 18.0, *) {
            backgroundConfiguration = .listCell()
        } else {
            backgroundConfiguration = .listGroupedCell()
        }

        let topRow = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        topRow.axis = .horizontal
        topRow.distribution = .fill
        topRow.alignment = .firstBaseline

        let stack = UIStackView(arrangedSubviews: [topRow, slider])
        stack.axis = .vertical
        stack.spacing = 6

        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])

        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
    }

    func configure(title: String,
                   range: ClosedRange<Float>,
                   value: Float,
                   step: Float = 0.1,
                   formatter: @escaping (Float) -> String) {
        titleLabel.text = title
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.value = value
        self.step = step
        self.formatter = formatter
        valueLabel.text = formatter(value)
    }

    @objc private func sliderChanged() {
        // Snap to the configured step for tactile control.
        let s = max(step, 0.001)
        let snapped = (slider.value / s).rounded() * s
        slider.value = snapped
        valueLabel.text = formatter?(snapped) ?? String(snapped)
        onChange?(snapped)
    }
}
