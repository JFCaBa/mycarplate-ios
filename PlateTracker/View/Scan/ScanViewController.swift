//
//  ScanViewController.swift
//  PlateTracker
//

import UIKit
import AVFoundation
import CoreImage
import Vision
import Combine

final class ScanViewController: UIViewController {

    private var viewModel: ScanViewModel!
    private var subscriptions = Set<AnyCancellable>()

    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // We grab a frame straight from the video output instead of using
    // AVCapturePhotoOutput — the OS shutter sound on capturePhoto can't be
    // suppressed in an App Store-safe way, and the video frame is sharp
    // enough for the accurate Vision pass.
    private let ciContext = CIContext(options: nil)

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

        // Higher-resolution video frames so distant plates remain legible to
        // Vision. AVCapturePhotoOutput previously gave us full-sensor stills;
        // since we now read directly from the video output we need to ask the
        // session for a high-quality preset.
        captureSession.beginConfiguration()
        if captureSession.canSetSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }

        captureSession.addInput(videoInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }
        captureSession.commitConfiguration()

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

            let threshold = ScanRecognitionConfig.confidence
            let matches: [(String, CGRect)] = results.compactMap { obs in
                guard obs.confidence >= threshold,
                      let cand = obs.topCandidates(1).first,
                      cand.confidence >= threshold else { return nil }
                return (cand.string, obs.boundingBox)
            }
            guard !matches.isEmpty else { return }

            self?.handleMatches(matches, pixelBuffer: pixelBuffer)
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

// MARK: - Frame processing

extension ScanViewController {
    func handleMatches(_ matches: [(String, CGRect)], pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        for (text, box) in matches {
            let cropped = cropAroundPlate(image: image, normalizedBox: box)
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.processRecognizedText(text, capturedFrame: cropped)
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

        let widthMult = ScanCropConfig.width
        let above = ScanCropConfig.above
        let below = ScanCropConfig.below

        let cropW = min(absW * widthMult, size.width)
        let cropH = min(absH * (1 + above + below), size.height)
        let centerX = absX + absW / 2
        // Top of crop sits `above × plateH` above the plate's top edge.
        let topY = absY - absH * above

        var cropRect = CGRect(x: centerX - cropW / 2,
                              y: topY,
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
