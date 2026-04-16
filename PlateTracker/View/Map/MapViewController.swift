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
                let annotation = MKPointAnnotation()
                annotation.coordinate = sighting.location.clCoordinate
                annotation.title = record.plate
                annotation.subtitle = formatter.string(from: sighting.date)
                mapView.addAnnotation(annotation)
                lastCoordinate = sighting.location.clCoordinate
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
