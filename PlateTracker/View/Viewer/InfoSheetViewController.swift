//
//  InfoSheetViewController.swift
//  PlateTracker
//

import UIKit
import MapKit
import Combine

final class InfoSheetViewController: UIViewController {

    private let plate: String
    private let scanViewModel: ScanViewModel
    private let detailViewModel: VehicleDetailViewModel

    private let mapView = MKMapView()
    private let mapEmptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No location data"
        l.font = .preferredFont(forTextStyle: .footnote)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.isHidden = true
        return l
    }()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var subscriptions = Set<AnyCancellable>()

    init(plate: String, scanViewModel: ScanViewModel) {
        self.plate = plate
        self.scanViewModel = scanViewModel
        self.detailViewModel = VehicleDetailViewModel(plate: plate, scanViewModel: scanViewModel)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViews()
        renderMap()
        bind()
    }

    private func setupViews() {
        view.addSubview(mapView)
        view.addSubview(mapEmptyLabel)
        view.addSubview(tableView)
        for v in [mapView, mapEmptyLabel, tableView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        mapView.layer.cornerRadius = 12
        mapView.layer.masksToBounds = true
        mapView.isUserInteractionEnabled = false

        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "metadata")

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            mapView.heightAnchor.constraint(equalToConstant: 140),

            mapEmptyLabel.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            mapEmptyLabel.centerYAnchor.constraint(equalTo: mapView.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func renderMap() {
        guard let record = scanViewModel.scanRecords.first(where: { $0.plate == plate }) else {
            mapEmptyLabel.isHidden = false
            return
        }
        let coords = record.sightings.map { $0.location.clCoordinate }
        guard !coords.isEmpty else {
            mapEmptyLabel.isHidden = false
            return
        }
        let annotations: [MKPointAnnotation] = coords.map {
            let a = MKPointAnnotation()
            a.coordinate = $0
            return a
        }
        mapView.addAnnotations(annotations)
        let rect = annotations.reduce(MKMapRect.null) { acc, ann in
            let p = MKMapPoint(ann.coordinate)
            return acc.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
    }

    private func bind() {
        detailViewModel.$sections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &subscriptions)
    }
}

extension InfoSheetViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        detailViewModel.sections.count
    }
    func tableView(_ tv: UITableView, titleForHeaderInSection section: Int) -> String? {
        detailViewModel.sections[section].title
    }
    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        detailViewModel.sections[section].rows.count
    }
    func tableView(_ tv: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = detailViewModel.sections[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "metadata")
        cell.textLabel?.text = row.label
        cell.detailTextLabel?.text = row.value
        cell.selectionStyle = .none
        return cell
    }
}
