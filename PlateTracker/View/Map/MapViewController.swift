//
//  MapViewController.swift
//  PlateTracker
//

import UIKit
import MapKit
import Combine

final class MapViewController: UIViewController {

    private let mapView = MKMapView()
    private var viewModel: MapViewModel!
    private var subscriptions = Set<AnyCancellable>()

    // Set when another screen asks us to focus a specific sighting before the
    // Map tab has been visited. Applied once the view appears.
    private var pendingFocusCoordinate: CLLocationCoordinate2D?

    func configure(with scanViewModel: ScanViewModel) {
        self.viewModel = MapViewModel(scanViewModel: scanViewModel)
        viewModel.$records
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                self?.updateMapAnnotations(records)
            }
            .store(in: &subscriptions)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Map"
        view.backgroundColor = .systemBackground
        setupMapView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let coord = pendingFocusCoordinate {
            pendingFocusCoordinate = nil
            applyFocus(on: coord, animated: animated)
        }
    }

    /// Center the map on the given coordinate. Safe to call before the Map tab
    /// has ever been displayed — the focus is queued and applied once the view
    /// finishes appearing.
    func centerOn(coordinate: CLLocationCoordinate2D) {
        guard isViewLoaded, view.window != nil else {
            pendingFocusCoordinate = coordinate
            return
        }
        applyFocus(on: coordinate, animated: true)
    }

    private func applyFocus(on coordinate: CLLocationCoordinate2D, animated: Bool) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 400,
            longitudinalMeters: 400
        )
        mapView.setRegion(region, animated: animated)
        if let match = mapView.annotations.first(where: { ann in
            abs(ann.coordinate.latitude - coordinate.latitude) < 1e-6 &&
            abs(ann.coordinate.longitude - coordinate.longitude) < 1e-6
        }) {
            mapView.selectAnnotation(match, animated: animated)
        }
    }

    private func setupMapView() {
        view.addSubview(mapView)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func updateMapAnnotations(_ records: [PlateScanRecord]) {
        mapView.removeAnnotations(mapView.annotations)

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var lastCoordinate: CLLocationCoordinate2D?

        records.forEach { record in
            record.sightings.forEach { sighting in
                guard let location = sighting.location else { return }
                let annotation = MKPointAnnotation()
                annotation.coordinate = location.clCoordinate
                annotation.title = record.plate
                annotation.subtitle = formatter.string(from: sighting.date)
                mapView.addAnnotation(annotation)
                lastCoordinate = location.clCoordinate
            }
        }

        if let center = lastCoordinate {
            let region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            mapView.setRegion(region, animated: true)
        }
    }
}
