//
//  StorageViewController.swift
//  PlateTracker
//

import UIKit
import Combine

final class StorageViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var viewModel: StorageViewModel!
    private var subscriptions = Set<AnyCancellable>()

    private let headerLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 34, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.text = "Total storage used"
        return label
    }()

    func configure(with scanViewModel: ScanViewModel) {
        self.viewModel = StorageViewModel(scanViewModel: scanViewModel)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Manage Storage"
        view.backgroundColor = .systemGroupedBackground

        setupHeader()
        setupTableView()
        setupClearAllButton()
        bindViewModel()
    }

    private func setupHeader() {
        let stack = UIStackView(arrangedSubviews: [headerLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center

        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 80))
        headerView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
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
        tableView.delegate = self
    }

    private func setupClearAllButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear All",
            style: .plain,
            target: self,
            action: #selector(clearAllTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = .systemRed
    }

    private func bindViewModel() {
        viewModel.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &subscriptions)

        viewModel.$totalSize
            .receive(on: RunLoop.main)
            .sink { [weak self] total in
                self?.headerLabel.text = StorageViewModel.formattedSize(total)
            }
            .store(in: &subscriptions)
    }

    @objc private func clearAllTapped() {
        let alert = UIAlertController(
            title: "Clear All Data",
            message: "This will delete all saved vehicles and photos. This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            self?.viewModel.clearAll()
        })
        present(alert, animated: true)
    }
}

extension StorageViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = viewModel.items[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "storageCell")

        if let photoName = item.photoFileName {
            cell.imageView?.image = StorageService.shared.loadPhoto(fileName: photoName)
        } else {
            cell.imageView?.image = UIImage(systemName: "car.fill")
        }
        cell.imageView?.layer.cornerRadius = 6
        cell.imageView?.clipsToBounds = true
        cell.imageView?.contentMode = .scaleAspectFill

        let title = item.makeModel.isEmpty ? item.plate : "\(item.plate) — \(item.makeModel)"
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = "\(item.sightingsCount) sighting\(item.sightingsCount == 1 ? "" : "s") · \(StorageViewModel.formattedSize(item.size))"
        cell.detailTextLabel?.textColor = .secondaryLabel

        return cell
    }
}

extension StorageViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.viewModel.deleteItem(at: indexPath.row)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}
