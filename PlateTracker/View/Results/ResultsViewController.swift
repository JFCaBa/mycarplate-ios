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
