//
//  InfoSheetViewController.swift
//  PlateTracker
//

import UIKit
import MapKit
import Combine
import SDWebImage

final class InfoSheetViewController: UIViewController {

    private let plate: String
    private let scanViewModel: ScanViewModel
    private let detailViewModel: VehicleDetailViewModel

    private let brandLogoView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.isHidden = true
        return iv
    }()
    private let plateLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .headline)
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 1
        return l
    }()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.adjustsFontForContentSizeCategory = true
        l.textColor = .secondaryLabel
        l.numberOfLines = 1
        return l
    }()
    private let envLabelView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.isHidden = true
        iv.isAccessibilityElement = true
        return iv
    }()
    private lazy var headerStack: UIStackView = {
        let titleStack = UIStackView(arrangedSubviews: [plateLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2
        let s = UIStackView(arrangedSubviews: [brandLogoView, titleStack, envLabelView])
        s.axis = .horizontal
        s.alignment = .center
        s.spacing = 12
        return s
    }()

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

    private let fetchDetailsButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Fetch Details"
        config.image = UIImage(systemName: "arrow.down.circle")
        config.imagePadding = 8
        config.cornerStyle = .medium
        let b = UIButton(configuration: config)
        return b
    }()
    private lazy var fetchContainer: UIStackView = {
        let s = UIStackView(arrangedSubviews: [fetchDetailsButton])
        s.axis = .horizontal
        s.alignment = .center
        s.distribution = .fill
        return s
    }()

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
        renderHeader()
        renderMap()
        bind()
    }

    private func setupViews() {
        let topStack = UIStackView(arrangedSubviews: [headerStack, mapView, fetchContainer])
        topStack.axis = .vertical
        topStack.spacing = 12

        view.addSubview(topStack)
        view.addSubview(mapEmptyLabel)
        view.addSubview(tableView)
        for v in [topStack, mapEmptyLabel, tableView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        mapView.layer.cornerRadius = 12
        mapView.layer.masksToBounds = true
        mapView.isUserInteractionEnabled = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "metadata")

        fetchDetailsButton.addTarget(self, action: #selector(fetchDetailsTapped), for: .touchUpInside)
        // Hidden by default; shown only when there's no vehicleData yet.
        fetchContainer.isHidden = true

        plateLabel.text = plate

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            topStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            topStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            brandLogoView.widthAnchor.constraint(equalToConstant: 44),
            brandLogoView.heightAnchor.constraint(equalToConstant: 44),
            envLabelView.widthAnchor.constraint(equalToConstant: 44),
            envLabelView.heightAnchor.constraint(equalToConstant: 44),

            mapView.heightAnchor.constraint(equalToConstant: 140),

            mapEmptyLabel.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            mapEmptyLabel.centerYAnchor.constraint(equalTo: mapView.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func renderHeader() {
        plateLabel.text = plate
        let subtitle = detailViewModel.headerSubtitle
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty

        if let url = detailViewModel.brandLogoURL {
            brandLogoView.isHidden = false
            brandLogoView.sd_setImage(with: url, placeholderImage: nil)
        } else {
            brandLogoView.isHidden = true
            brandLogoView.image = nil
        }

        if let env = detailViewModel.envLabel {
            envLabelView.isHidden = false
            envLabelView.accessibilityLabel = "DGT environmental label \(env.code)"
            envLabelView.sd_setImage(with: env.url, placeholderImage: nil)
        } else {
            envLabelView.isHidden = true
            envLabelView.image = nil
            envLabelView.accessibilityLabel = nil
        }
    }

    @objc private func fetchDetailsTapped() {
        detailViewModel.refresh()
    }

    private func updateFetchVisibility() {
        let shouldShow = !detailViewModel.hasVehicleData
        if fetchContainer.isHidden == shouldShow {
            fetchContainer.isHidden = !shouldShow
        }
    }

    private func renderMap() {
        guard let record = scanViewModel.scanRecords.first(where: { $0.plate == plate }) else {
            mapEmptyLabel.isHidden = false
            return
        }
        let coords = record.sightings.compactMap { $0.location?.clCoordinate }
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
        if annotations.count == 1 {
            let region = MKCoordinateRegion(
                center: annotations[0].coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: false)
        } else {
            mapView.showAnnotations(annotations, animated: false)
        }
    }

    private func bind() {
        detailViewModel.$sections
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.updateFetchVisibility()
                self?.renderHeader()
            }
            .store(in: &subscriptions)

        detailViewModel.$isRefreshing
            .receive(on: RunLoop.main)
            .sink { [weak self] busy in
                guard let self = self else { return }
                self.fetchDetailsButton.isEnabled = !busy
                self.fetchDetailsButton.configuration?.showsActivityIndicator = busy
            }
            .store(in: &subscriptions)

        detailViewModel.$lastFetchError
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.presentFetchError(message)
            }
            .store(in: &subscriptions)
    }

    private func presentFetchError(_ message: String) {
        let alert = UIAlertController(title: "Fetch failed", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension InfoSheetViewController: UITableViewDataSource, UITableViewDelegate {
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
        let section = detailViewModel.sections[indexPath.section]
        let row = section.rows[indexPath.row]
        let style: UITableViewCell.CellStyle = section.multiline ? .subtitle : .value1
        let cell = UITableViewCell(style: style, reuseIdentifier: nil)
        cell.textLabel?.text = row.label
        cell.detailTextLabel?.text = row.value
        if section.multiline {
            cell.textLabel?.numberOfLines = 0
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.textColor = .secondaryLabel
        }
        if row.coordinate != nil {
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        } else {
            cell.accessoryType = .none
            cell.selectionStyle = .none
        }
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt indexPath: IndexPath) {
        tv.deselectRow(at: indexPath, animated: true)
        let row = detailViewModel.sections[indexPath.section].rows[indexPath.row]
        guard let coord = row.coordinate else { return }
        focusMap(on: coord)
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D) {
        // Walk up to the root tab bar, dismiss any modally presented stack
        // (this sheet, the photo viewer above it), then switch to the Map tab
        // and ask it to center on the chosen coordinate.
        guard let window = view.window,
              let tabBar = window.rootViewController as? UITabBarController else { return }

        let mapTabIndex = (tabBar.viewControllers ?? []).firstIndex { vc in
            (vc as? UINavigationController)?.viewControllers.first is MapViewController
                || vc is MapViewController
        }
        guard let mapIndex = mapTabIndex else { return }

        let mapVC: MapViewController? = {
            let target = tabBar.viewControllers?[mapIndex]
            if let nav = target as? UINavigationController {
                nav.popToRootViewController(animated: false)
                return nav.viewControllers.first as? MapViewController
            }
            return target as? MapViewController
        }()

        let activate = {
            tabBar.selectedIndex = mapIndex
            mapVC?.centerOn(coordinate: coordinate)
        }

        if tabBar.presentedViewController != nil {
            tabBar.dismiss(animated: true, completion: activate)
        } else {
            activate()
        }
    }
}
