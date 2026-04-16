//
//  VehicleDetailViewController.swift
//  PlateTracker
//

import UIKit
import Combine

final class VehicleDetailViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var viewModel: VehicleDetailViewModel!
    private var subscriptions = Set<AnyCancellable>()

    private let heroImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .secondarySystemBackground
        iv.tintColor = .secondaryLabel
        return iv
    }()

    private let refreshButton = UIBarButtonItem(
        systemItem: .refresh
    )

    func configure(with plate: String, scanViewModel: ScanViewModel) {
        self.viewModel = VehicleDetailViewModel(plate: plate, scanViewModel: scanViewModel)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.navigationTitle
        view.backgroundColor = .systemBackground

        setupRefreshButton()
        setupHeroImage()
        setupTableView()
        bindViewModel()
    }

    private func setupRefreshButton() {
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        navigationItem.rightBarButtonItem = refreshButton
    }

    private func setupHeroImage() {
        if let photoName = viewModel.latestPhotoFileName,
           let image = StorageService.shared.loadPhoto(fileName: photoName) {
            heroImageView.image = image
        } else {
            heroImageView.image = UIImage(systemName: "car.fill")
            heroImageView.contentMode = .scaleAspectFit
        }

        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 200))
        headerView.addSubview(heroImageView)
        heroImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heroImageView.topAnchor.constraint(equalTo: headerView.topAnchor),
            heroImageView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            heroImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            heroImageView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])
        tableView.tableHeaderView = headerView
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

    private func bindViewModel() {
        viewModel.$sections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &subscriptions)

        viewModel.$isRefreshing
            .receive(on: RunLoop.main)
            .sink { [weak self] refreshing in
                if refreshing {
                    let spinner = UIActivityIndicatorView(style: .medium)
                    spinner.startAnimating()
                    self?.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
                } else {
                    self?.navigationItem.rightBarButtonItem = self?.refreshButton
                }
            }
            .store(in: &subscriptions)
    }

    @objc private func refreshTapped() {
        viewModel.refresh()
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
