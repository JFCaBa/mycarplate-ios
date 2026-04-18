//
//  ScanViewController.swift
//  PlateTracker
//

import UIKit
import AVFoundation
import Vision
import Combine

final class ScanViewController: UIViewController {

    private var viewModel: ScanViewModel!
    private var subscriptions = Set<AnyCancellable>()

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var photoOutput: AVCapturePhotoOutput!

    // Throttle to avoid triggering a still capture on every detected video frame.
    // The video path only *triggers* captures; the photo delegate runs Vision
    // on the resulting sharp still and feeds the ViewModel.
    private var isCapturingPhoto = false
    private var lastPhotoCaptureAt: Date?
    private let photoCaptureInterval: TimeInterval = 1.0

    // Crop expansion around the plate's bounding box (multiples of the plate size).
    // ~3–4× keeps the car body in frame while dropping sky/road.
    private let plateCropWidthMultiplier: CGFloat = 4.0
    private let plateCropHeightMultiplier: CGFloat = 3.5

    private let plateLabel: UILabel = {
        let label = UILabel()
        label.text = "Plate: ---"
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        return label
    }()

    private let queuePanel = QueuePanelView()

    func configure(with viewModel: ScanViewModel) {
        self.viewModel = viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan"
        view.backgroundColor = .black

        setupCamera()
        setupPlateLabel()
        setupQueuePanel()
        bindViewModel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func setupPlateLabel() {
        view.addSubview(plateLabel)
        plateLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            plateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            plateLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            plateLabel.widthAnchor.constraint(equalToConstant: 250),
            plateLabel.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupQueuePanel() {
        queuePanel.translatesAutoresizingMaskIntoConstraints = false
        queuePanel.isHidden = true
        view.addSubview(queuePanel)
        NSLayoutConstraint.activate([
            queuePanel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.33),
            queuePanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            queuePanel.bottomAnchor.constraint(equalTo: plateLabel.topAnchor, constant: -16),
            queuePanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])

        queuePanel.onDeleteRequested = { [weak self] plate in
            guard let self = self else { return }
            let fileName = self.viewModel.lookupQueue.items
                .first(where: { $0.plate == plate })?
                .capturedFrameFileName
            let didRemove = self.viewModel.lookupQueue.remove(plate: plate)
            if didRemove, let fileName = fileName {
                StorageService.shared.deletePhoto(fileName: fileName)
            }
        }
    }

    private func bindViewModel() {
        viewModel.$detectedPlate
            .receive(on: RunLoop.main)
            .sink { [weak self] plate in
                guard let plate = plate else { return }
                self?.plateLabel.text = "Plate: \(plate)"
                self?.plateLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            }
            .store(in: &subscriptions)

        viewModel.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                guard let error = error else { return }
                self?.plateLabel.text = error
                self?.plateLabel.backgroundColor = UIColor.red.withAlphaComponent(0.6)
            }
            .store(in: &subscriptions)

        viewModel.lookupQueue.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                self.queuePanel.update(items: items)
                let shouldShow = !items.isEmpty
                if self.queuePanel.isHidden != !shouldShow {
                    UIView.animate(withDuration: 0.2) {
                        self.queuePanel.isHidden = !shouldShow
                    }
                }
            }
            .store(in: &subscriptions)
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput)
        else { return }

        captureSession.addInput(videoInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            if let connection = photoOutput.connection(with: .video) {
                connection.videoRotationAngle = 90
            }
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        DispatchQueue(label: "cameraQueue").async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
}

extension ScanViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest { [weak self] (request, error) in
            if let error = error {
                print("[Scan] Vision error: \(error.localizedDescription)")
                return
            }
            guard let results = request.results as? [VNRecognizedTextObservation] else { return }

            let hasConfidentText = results.contains { obs in
                guard obs.confidence >= 0.8,
                      let cand = obs.topCandidates(1).first else { return false }
                return cand.confidence >= 0.8
            }
            guard hasConfidentText else { return }

            DispatchQueue.main.async {
                self?.triggerPhotoCaptureIfNeeded()
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try requestHandler.perform([request])
        } catch {
            print("[Scan] VNImageRequestHandler failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Photo capture

extension ScanViewController: AVCapturePhotoCaptureDelegate {
    func triggerPhotoCaptureIfNeeded() {
        if isCapturingPhoto { return }
        if let last = lastPhotoCaptureAt,
           Date().timeIntervalSince(last) < photoCaptureInterval { return }
        guard photoOutput != nil else { return }

        isCapturingPhoto = true
        lastPhotoCaptureAt = Date()

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { isCapturingPhoto = false }

        if let error = error {
            print("[Scan] Photo capture error: \(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("[Scan] Could not decode captured photo")
            return
        }

        recognizePlates(in: image) { [weak self] matches in
            guard let self = self else { return }
            guard !matches.isEmpty else {
                print("[Scan] Still-photo Vision found no plate; skipping frame")
                return
            }
            for (text, box) in matches {
                let cropped = self.cropAroundPlate(image: image, normalizedBox: box)
                DispatchQueue.main.async {
                    self.viewModel.processRecognizedText(text, capturedFrame: cropped)
                }
            }
        }
    }

    private func recognizePlates(in image: UIImage,
                                 completion: @escaping ([(String, CGRect)]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { request, _ in
                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    completion([])
                    return
                }
                let pairs: [(String, CGRect)] = results.compactMap { obs in
                    guard obs.confidence >= 0.8,
                          let cand = obs.topCandidates(1).first,
                          cand.confidence >= 0.8 else { return nil }
                    return (cand.string, obs.boundingBox)
                }
                completion(pairs)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: orientation,
                                                options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[Scan] Still-photo Vision failed: \(error.localizedDescription)")
                completion([])
            }
        }
    }

    private func cropAroundPlate(image: UIImage, normalizedBox: CGRect) -> UIImage {
        let size = image.size
        // Vision's boundingBox is normalized (0-1) with origin at bottom-left.
        // UIKit's coordinate space has origin at top-left.
        let absW = normalizedBox.width * size.width
        let absH = normalizedBox.height * size.height
        let absX = normalizedBox.origin.x * size.width
        let absY = size.height - (normalizedBox.origin.y * size.height) - absH

        let centerX = absX + absW / 2
        let centerY = absY + absH / 2
        let cropW = min(absW * plateCropWidthMultiplier, size.width)
        let cropH = min(absH * plateCropHeightMultiplier, size.height)

        var cropRect = CGRect(x: centerX - cropW / 2,
                              y: centerY - cropH / 2,
                              width: cropW,
                              height: cropH)
        if cropRect.minX < 0 { cropRect.origin.x = 0 }
        if cropRect.minY < 0 { cropRect.origin.y = 0 }
        if cropRect.maxX > size.width { cropRect.origin.x = size.width - cropRect.width }
        if cropRect.maxY > size.height { cropRect.origin.y = size.height - cropRect.height }

        let renderer = UIGraphicsImageRenderer(size: cropRect.size)
        return renderer.image { _ in
            image.draw(at: CGPoint(x: -cropRect.minX, y: -cropRect.minY))
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
