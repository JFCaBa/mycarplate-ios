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
    private var videoCaptureDevice: AVCaptureDevice?
    private let cameraDeviceQueue = DispatchQueue(label: "cameraDeviceQueue")
    private var minZoomFactor: CGFloat = 1
    private var maxZoomFactor: CGFloat = 1

    // We grab a frame straight from the video output instead of using
    // AVCapturePhotoOutput — the OS shutter sound on capturePhoto can't be
    // suppressed in an App Store-safe way, and the video frame is sharp
    // enough for the accurate Vision pass.
    private let ciContext = CIContext(options: nil)

    private let queuePanel = QueuePanelView()
    private let zoomControl = CameraZoomControlView()

    func configure(with viewModel: ScanViewModel) {
        self.viewModel = viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan"
        view.backgroundColor = .black

        setupZoomControl()
        setupQueuePanel()
        setupCamera()
        bindViewModel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        view.bringSubviewToFront(zoomControl)
        view.bringSubviewToFront(queuePanel)
    }

    private func setupZoomControl() {
        zoomControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomControl)
        NSLayoutConstraint.activate([
            zoomControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            zoomControl.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            zoomControl.heightAnchor.constraint(equalToConstant: 64),
        ])

        zoomControl.onZoomChanged = { [weak self] factor, animated in
            self?.applyZoomFactor(factor, animated: animated)
        }
    }

    private func setupQueuePanel() {
        queuePanel.translatesAutoresizingMaskIntoConstraints = false
        queuePanel.isHidden = true
        view.addSubview(queuePanel)
        NSLayoutConstraint.activate([
            queuePanel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.33),
            queuePanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            queuePanel.bottomAnchor.constraint(equalTo: zoomControl.topAnchor, constant: -8),
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
            .sink { plate in
                guard plate != nil else { return }
            }
            .store(in: &subscriptions)

        viewModel.$lastError
            .receive(on: RunLoop.main)
            .sink { error in
                guard error != nil else { return }
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
        self.videoCaptureDevice = videoCaptureDevice

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

        configureZoom(for: videoCaptureDevice)

        DispatchQueue(label: "cameraQueue").async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    private func configureZoom(for device: AVCaptureDevice) {
        // Respect what the device actually exposes — for a virtual multi-cam
        // (triple/dual-wide) `minAvailableVideoZoomFactor` can be 0.5; for the
        // plain wide camera it's 1. Cap the upper end at a sensible UX value
        // so we don't surface 30× digital crops nobody wants.
        let deviceMin = device.minAvailableVideoZoomFactor
        let deviceMax = min(device.maxAvailableVideoZoomFactor, device.activeFormat.videoMaxZoomFactor)
        minZoomFactor = max(0.5, min(deviceMin, 1))
        maxZoomFactor = max(minZoomFactor, min(deviceMax, 10))

        // Default to 1× (the wide lens) on launch — the device's baseline.
        let initial = max(minZoomFactor, min(1, maxZoomFactor))
        zoomControl.configure(minZoomFactor: minZoomFactor,
                              maxZoomFactor: maxZoomFactor,
                              initialZoomFactor: initial)
        // Hide the control if the device offers effectively no range.
        zoomControl.isHidden = (maxZoomFactor - minZoomFactor) < 0.1
    }

    private func applyZoomFactor(_ factor: CGFloat, animated: Bool) {
        guard let device = videoCaptureDevice else { return }
        let clamped = min(max(factor, minZoomFactor), maxZoomFactor)
        cameraDeviceQueue.async { [weak self] in
            do {
                try device.lockForConfiguration()
                if animated {
                    // Slower ramp so the preview transition feels like the
                    // system Camera (~0.25s for a typical jump) instead of
                    // snapping abruptly.
                    device.ramp(toVideoZoomFactor: clamped, withRate: 4)
                } else {
                    device.cancelVideoZoomRamp()
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self?.zoomControl.setZoomFactor(clamped, animated: false, emitChange: false)
                }
            } catch {
                print("[Scan] Failed to apply zoom factor: \(error.localizedDescription)")
            }
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
