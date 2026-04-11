//
//  VehicleDetailViewController.swift
//  PlateTracker
//

import UIKit

final class VehicleDetailViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var viewModel: VehicleDetailViewModel!

    private static let countryFlags: [String: String] = [
        "ES": "\u{1F1EA}\u{1F1F8}",
        "UK": "\u{1F1EC}\u{1F1E7}",
        "NL": "\u{1F1F3}\u{1F1F1}",
        "NO": "\u{1F1F3}\u{1F1F4}"
    ]

    func configure(with vehicleData: VehicleData) {
        self.viewModel = VehicleDetailViewModel(vehicleData: vehicleData)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let flag = Self.countryFlags[viewModel.country] ?? ""
        title = "\(flag) \(viewModel.plate)"
        view.backgroundColor = .systemBackground
        setupTableView()
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
        tableView.dataSource = self
    }
}

extension VehicleDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return viewModel.sections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = viewModel.sections[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "detailCell")
        cell.textLabel?.text = row.label
        cell.detailTextLabel?.text = row.value
        cell.selectionStyle = .none
        return cell
    }
}
