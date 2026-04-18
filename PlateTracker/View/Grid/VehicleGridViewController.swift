//
//  VehicleGridViewController.swift
//  PlateTracker
//

import UIKit
import Combine

final class VehicleGridViewController: UIViewController {

    private var collectionView: UICollectionView!
    private let searchController = UISearchController(searchResultsController: nil)

    private var viewModel: VehicleGridViewModel!
    private var scanViewModel: ScanViewModel!
    private var subscriptions = Set<AnyCancellable>()

    private enum SupplementaryKind {
        static let header = "VehicleGridSectionHeader"
    }

    func configure(with scanViewModel: ScanViewModel) {
        self.scanViewModel = scanViewModel
        self.viewModel = VehicleGridViewModel(scanViewModel: scanViewModel)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vehicles"
        view.backgroundColor = .systemBackground

        setupCollectionView()
        setupSearchController()
        bindViewModel()
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .systemBackground
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(VehicleTileCell.self, forCellWithReuseIdentifier: VehicleTileCell.reuseIdentifier)
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: SupplementaryKind.header,
                                withReuseIdentifier: SectionHeaderView.reuseIdentifier)
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0/3.0),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .fractionalWidth(1.0/3.0))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                heightDimension: .estimated(36))
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: SupplementaryKind.header,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search plates, make, model"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func bindViewModel() {
        viewModel.$sections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.collectionView.reloadData() }
            .store(in: &subscriptions)
    }
}

extension VehicleGridViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        viewModel.sections.count
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        viewModel.sections[section].records.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: VehicleTileCell.reuseIdentifier, for: indexPath) as! VehicleTileCell
        let record = viewModel.sections[indexPath.section].records[indexPath.item]
        cell.configure(with: record)
        return cell
    }

    func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = cv.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: SectionHeaderView.reuseIdentifier,
            for: indexPath
        ) as! SectionHeaderView
        let section = viewModel.sections[indexPath.section]
        header.configure(title: section.title, count: section.records.count)
        return header
    }
}

extension VehicleGridViewController: UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        cv.deselectItem(at: indexPath, animated: true)
        // Build the linear list of all currently-displayed vehicles in the order they appear in the grid.
        let vehicles = viewModel.sections.flatMap { $0.records }
        let tappedRecord = viewModel.sections[indexPath.section].records[indexPath.item]
        guard let startIndex = vehicles.firstIndex(where: { $0.plate == tappedRecord.plate }) else { return }
        let viewer = PhotoViewerViewController(vehicles: vehicles, startIndex: startIndex, scanViewModel: scanViewModel)
        present(viewer, animated: true)
    }
}

extension VehicleGridViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
    }
}

final class SectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "SectionHeaderView"

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        return l
    }()
    private let countLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        stack.axis = .horizontal
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, count: Int) {
        titleLabel.text = title
        countLabel.text = String(count)
    }
}
