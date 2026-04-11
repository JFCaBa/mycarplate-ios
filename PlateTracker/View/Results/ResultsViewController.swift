//
//  ResultsViewController.swift
//  PlateTracker
//

import Combine
import UIKit
import CoreLocation

final class ResultsViewController: UIViewController {

    private let tableView = UITableView()
    private var viewModel: ResultsViewModel!
    private var subscriptions = Set<AnyCancellable>()

    func configure(with scanViewModel: ScanViewModel) {
        viewModel = ResultsViewModel(scanViewModel: scanViewModel)
        viewModel.$records
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
    }
}

extension ResultsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel?.records.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = viewModel.records[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")

        if let data = record.vehicleData {
            let makeModel = [data.make, data.model].compactMap { $0 }.joined(separator: " ")
            cell.textLabel?.text = makeModel.isEmpty ? record.plate : "\(record.plate) — \(makeModel)"
            let details = [
                data.year.map { String($0) },
                data.color,
                data.fuelType
            ].compactMap { $0 }.joined(separator: " | ")
            cell.detailTextLabel?.text = details.isEmpty ? nil : details
        } else {
            cell.textLabel?.text = record.plate
            cell.detailTextLabel?.text = "Loading..."
        }

        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

extension ResultsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = viewModel.records[indexPath.row]
        guard let vehicleData = record.vehicleData else { return }
        let detailVC = VehicleDetailViewController()
        detailVC.configure(with: vehicleData)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
