//
//  PhotoViewerViewController.swift
//  PlateTracker
//

import UIKit

final class PhotoViewerViewController: UIViewController {

    private let viewModel: PhotoViewerViewModel
    private let scanViewModel: ScanViewModel
    private var pageController: UIPageViewController!

    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.textColor = .white
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textAlignment = .center
        return l
    }()
    private let backButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Done", for: .normal)
        b.tintColor = .white
        return b
    }()
    private let infoButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "info.circle"), for: .normal)
        b.tintColor = .white
        b.accessibilityLabel = "Info"
        return b
    }()
    private let deleteButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "trash"), for: .normal)
        b.tintColor = .white
        b.accessibilityLabel = "Delete"
        return b
    }()
    private let noteButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        b.tintColor = .white
        b.accessibilityLabel = "Note"
        return b
    }()
    private let editButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        b.tintColor = .white
        b.accessibilityLabel = "Edit"
        return b
    }()

    private let revertButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
        b.tintColor = .white
        b.accessibilityLabel = "Revert to original"
        b.isHidden = true
        return b
    }()

    init(vehicles: [PlateScanRecord], startIndex: Int, scanViewModel: ScanViewModel) {
        self.viewModel = PhotoViewerViewModel(vehicles: vehicles, startIndex: startIndex)
        self.scanViewModel = scanViewModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPageController()
        setupChrome()
        setupSwipeUpGesture()
        updateChromeForCurrentVehicle()
    }

    private func setupPageController() {
        pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pageController.dataSource = self
        pageController.delegate = self
        addChild(pageController)
        view.addSubview(pageController.view)
        pageController.view.frame = view.bounds
        pageController.didMove(toParent: self)

        if let initial = viewModel.currentVehicle {
            let page = makePage(for: initial)
            pageController.setViewControllers([page], direction: .forward, animated: false)
        }
    }

    private func setupChrome() {
        for bar in [topBar, bottomBar] {
            view.addSubview(bar)
            bar.translatesAutoresizingMaskIntoConstraints = false
        }
        topBar.contentView.addSubview(backButton)
        topBar.contentView.addSubview(titleLabel)
        topBar.contentView.addSubview(infoButton)
        bottomBar.contentView.addSubview(deleteButton)
        bottomBar.contentView.addSubview(noteButton)
        bottomBar.contentView.addSubview(editButton)
        bottomBar.contentView.addSubview(revertButton)
        for v in [backButton, titleLabel, infoButton, deleteButton, noteButton, editButton, revertButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            backButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),
            infoButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            infoButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -10),

            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),

            deleteButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -24),
            deleteButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),

            noteButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
            noteButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),

            editButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            editButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
            revertButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor, constant: 56),
            revertButton.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 12),
        ])

        backButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        infoButton.addTarget(self, action: #selector(infoTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        noteButton.addTarget(self, action: #selector(noteTapped), for: .touchUpInside)
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        revertButton.addTarget(self, action: #selector(revertTapped), for: .touchUpInside)
    }

    private func setupSwipeUpGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panUp(_:)))
        view.addGestureRecognizer(pan)
    }

    @objc private func panUp(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        if translation.y < -80 || velocity.y < -800 {
            presentInfoSheet()
        }
    }

    private func makePage(for record: PlateScanRecord) -> PhotoPageViewController {
        let index = viewModel.vehicles.firstIndex(where: { $0.plate == record.plate }) ?? 0
        let sightingIndex = viewModel.currentSightingIndex(forVehicle: index)
        let page = PhotoPageViewController(record: record, initialSightingIndex: sightingIndex)
        page.delegate = self
        return page
    }

    private func updateChromeForCurrentVehicle() {
        titleLabel.text = viewModel.currentVehicle?.plate
        revertButton.isHidden = !currentSightingHasEdit()
    }

    @objc private func dismissTapped() {
        dismiss(animated: true)
    }

    @objc private func infoTapped() {
        presentInfoSheet()
    }

    private func presentInfoSheet() {
        guard let vehicle = viewModel.currentVehicle else { return }
        let sheet = InfoSheetViewController(plate: vehicle.plate, scanViewModel: scanViewModel)
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    @objc private func deleteTapped() {
        guard let vehicle = viewModel.currentVehicle else { return }
        let alert = UIAlertController(
            title: "Delete \(vehicle.plate)?",
            message: vehicle.sightings.count > 1
                ? "This will delete the current sighting. \(vehicle.sightings.count - 1) other sighting(s) will remain."
                : "This is the only sighting for this vehicle. The vehicle will be removed.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // Required for iPad — actionSheet without a source view crashes there.
        alert.popoverPresentationController?.sourceView = deleteButton
        alert.popoverPresentationController?.sourceRect = deleteButton.bounds
        present(alert, animated: true)
    }

    private func performDelete() {
        guard let vehicle = viewModel.currentVehicle,
              let vehicleIdx = viewModel.vehicles.firstIndex(where: { $0.plate == vehicle.plate }) else { return }
        let sightingIdx = viewModel.currentSightingIndex(forVehicle: vehicleIdx)

        if vehicle.sightings.count > 1 {
            // Delete just this sighting; vehicle stays.
            scanViewModel.deleteSighting(plate: vehicle.plate, sightingIndex: sightingIdx)
            // Pull the updated record back from the scan VM and replace the page.
            if let updated = scanViewModel.scanRecords.first(where: { $0.plate == vehicle.plate }) {
                viewModel.replaceVehicle(at: vehicleIdx, with: updated)
                let page = makePage(for: updated)
                pageController.setViewControllers([page], direction: .forward, animated: false)
            }
            return
        }

        // Last sighting → remove the whole vehicle.
        scanViewModel.deleteRecord(for: vehicle.plate)
        viewModel.removeCurrentVehicle()
        if viewModel.isEmpty {
            dismiss(animated: true)
            return
        }
        if let next = viewModel.currentVehicle {
            let page = makePage(for: next)
            pageController.setViewControllers([page], direction: .forward, animated: true)
            updateChromeForCurrentVehicle()
        }
    }

    @objc private func noteTapped() {
        guard let vehicle = viewModel.currentVehicle,
              let vehicleIdx = viewModel.vehicles.firstIndex(where: { $0.plate == vehicle.plate }) else { return }
        let sightingIdx = viewModel.currentSightingIndex(forVehicle: vehicleIdx)
        let initial = vehicle.sightings[sightingIdx].note
        let editor = NoteEditorViewController(initialText: initial) { [weak self] newText in
            guard let self = self else { return }
            self.scanViewModel.updateSightingNote(plate: vehicle.plate, sightingIndex: sightingIdx, note: newText)
            // Refresh local copy so subsequent reads see the new note.
            if let updated = self.scanViewModel.scanRecords.first(where: { $0.plate == vehicle.plate }) {
                self.viewModel.replaceVehicle(at: vehicleIdx, with: updated)
            }
            // Trigger the current page to reload its filmstrip.
            (self.pageController.viewControllers?.first as? PhotoPageViewController)?.reloadFilmstrip()
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func currentSighting() -> (vehicleIdx: Int, sighting: Sighting)? {
        guard let vehicle = viewModel.currentVehicle,
              let vehicleIdx = viewModel.vehicles.firstIndex(where: { $0.plate == vehicle.plate }) else { return nil }
        let sIdx = viewModel.currentSightingIndex(forVehicle: vehicleIdx)
        return (vehicleIdx, vehicle.sightings[sIdx])
    }

    private func currentSightingHasEdit() -> Bool {
        currentSighting()?.sighting.editedPhotoFileName != nil
    }

    @objc private func editTapped() {
        guard let info = currentSighting() else { return }
        let activeFileName = info.sighting.editedPhotoFileName ?? info.sighting.photoFileName
        guard let fileName = activeFileName,
              let image = StorageService.shared.loadPhoto(fileName: fileName) else { return }

        let editor = PhotoEditorViewController(image: image) { [weak self] edited in
            self?.dismiss(animated: true) {
                guard let self = self, let edited = edited, let vehicle = self.viewModel.currentVehicle else { return }
                let sIdx = self.viewModel.currentSightingIndex(forVehicle: info.vehicleIdx)
                self.scanViewModel.saveEditedPhoto(plate: vehicle.plate, sightingIndex: sIdx, image: edited)
                self.refreshCurrentVehicleFromScanVM()
            }
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func revertTapped() {
        guard let info = currentSighting(), let vehicle = viewModel.currentVehicle else { return }
        let alert = UIAlertController(title: "Revert to original?", message: "Your edits to this photo will be discarded.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Revert", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let sIdx = self.viewModel.currentSightingIndex(forVehicle: info.vehicleIdx)
            self.scanViewModel.revertSightingEdit(plate: vehicle.plate, sightingIndex: sIdx)
            self.refreshCurrentVehicleFromScanVM()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func refreshCurrentVehicleFromScanVM() {
        guard let vehicle = viewModel.currentVehicle,
              let vehicleIdx = viewModel.vehicles.firstIndex(where: { $0.plate == vehicle.plate }),
              let updated = scanViewModel.scanRecords.first(where: { $0.plate == vehicle.plate }) else { return }
        viewModel.replaceVehicle(at: vehicleIdx, with: updated)
        // Pre-warm the new edited file in cache (its name is unique so no stale entry to evict).
        if let edited = updated.sightings.last?.editedPhotoFileName {
            PhotoCache.shared.loadAsync(fileName: edited) { _ in }
        }
        // Replace the current page so loadCurrentPhoto reads the new file.
        let page = makePage(for: updated)
        pageController.setViewControllers([page], direction: .forward, animated: false)
        updateChromeForCurrentVehicle()
    }
}

extension PhotoViewerViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let page = vc as? PhotoPageViewController,
              let idx = viewModel.vehicles.firstIndex(where: { $0.plate == page.record.plate }),
              idx > 0 else { return nil }
        return makePage(for: viewModel.vehicles[idx - 1])
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let page = vc as? PhotoPageViewController,
              let idx = viewModel.vehicles.firstIndex(where: { $0.plate == page.record.plate }),
              idx < viewModel.vehicles.count - 1 else { return nil }
        return makePage(for: viewModel.vehicles[idx + 1])
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let current = pvc.viewControllers?.first as? PhotoPageViewController,
              let idx = viewModel.vehicles.firstIndex(where: { $0.plate == current.record.plate }) else { return }
        viewModel.currentIndex = idx
        updateChromeForCurrentVehicle()
    }
}

extension PhotoViewerViewController: PhotoPageViewControllerDelegate {
    func photoPage(_ page: PhotoPageViewController, didChangeSightingIndex index: Int) {
        guard let vehicleIndex = viewModel.vehicles.firstIndex(where: { $0.plate == page.record.plate }) else { return }
        viewModel.setCurrentSightingIndex(index, forVehicle: vehicleIndex)
    }
}
