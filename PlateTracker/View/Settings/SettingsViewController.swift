//
//  SettingsViewController.swift
//  PlateTracker
//

import UIKit

final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case scan = 0
        case recognition
        case captureArea
        case storage

        var title: String {
            switch self {
            case .scan: return "Scan Preferences"
            case .recognition: return "Recognition"
            case .captureArea: return "Capture Area"
            case .storage: return "Storage"
            }
        }

        var footer: String? {
            switch self {
            case .recognition:
                return "Minimum confidence required to accept a plate. Lower values trigger captures more often but may produce false reads; higher values are stricter but slower to fire."
            case .captureArea:
                return "How much of the car to capture around the plate, in multiples of plate size. Width is symmetric; above/below adjust the vertical crop independently so you can bias toward the hood or rear."
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
    }

    // MARK: - Sections

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .scan: return 4
        case .recognition: return 1
        case .captureArea: return 3
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
            default: return repeatAlertCell()
            }
        case .recognition:
            return recognitionCell()
        case .captureArea:
            return captureAreaCell(for: indexPath.row)
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
