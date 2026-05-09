//
//  ScanViewController.swift
//  PlateTracker
//

import UIKit
import AVFoundation
import AudioToolbox
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
    private let flashOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.alpha = 0
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private var repeatAlertVibrationTimer: Timer?

    private var sleepWindow: UIWindow?
    private var brightnessBeforeSleep: CGFloat?

    func configure(with viewModel: ScanViewModel) {
        self.viewModel = viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan"
        view.backgroundColor = .black

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "moon.fill"),
            style: .plain,
            target: self,
            action: #selector(enterSleepMode)
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        setupZoomControl()
        setupQueuePanel()
        setupFlashOverlay()
        setupCamera()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Keep the screen awake while the scan view is showing — the user is
        // actively looking at the camera (or has the app fake-sleeping) and
        // doesn't want iOS to auto-lock and stop the capture session.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        exitSleepMode()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        view.bringSubviewToFront(zoomControl)
        view.bringSubviewToFront(queuePanel)
        view.bringSubviewToFront(flashOverlay)
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

    private func setupFlashOverlay() {
        view.addSubview(flashOverlay)
        NSLayoutConstraint.activate([
            flashOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            flashOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            flashOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            flashOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
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

        viewModel.$repeatSighting
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] sighting in
                self?.handleRepeatSighting(sighting)
            }
            .store(in: &subscriptions)

        viewModel.$watchlistMatch
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] match in
                self?.handleWatchlistMatch(match)
            }
            .store(in: &subscriptions)
    }

    private func handleRepeatSighting(_ sighting: ScanViewModel.RepeatSighting) {
        if UserDefaults.standard.bool(forKey: "repeatSpotNotificationEnabled") {
            NotificationService.shared.notifyRepeatSpot(plate: sighting.plate)
        }
        fireRepeatSpotAlertIfEnabled()
    }

    private func fireRepeatSpotAlertIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "repeatSpotAlertEnabled") else { return }

        // Vibration: iOS doesn't expose continuous vibration like Android,
        // so we trigger the system vibration four times spaced 0.5s apart
        // for the requested ~2-second feel.
        repeatAlertVibrationTimer?.invalidate()
        var pulses = 0
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        repeatAlertVibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            pulses += 1
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            if pulses >= 3 {
                timer.invalidate()
                self?.repeatAlertVibrationTimer = nil
            }
        }

        // Flash: two pulses of a white overlay over the full 2-second window.
        flashOverlay.layer.removeAllAnimations()
        flashOverlay.alpha = 0
        UIView.animateKeyframes(withDuration: 2.0, delay: 0, options: [.calculationModeCubic]) { [flashOverlay] in
            UIView.addKeyframe(withRelativeStartTime: 0.00, relativeDuration: 0.20) { flashOverlay.alpha = 0.7 }
            UIView.addKeyframe(withRelativeStartTime: 0.20, relativeDuration: 0.30) { flashOverlay.alpha = 0.0 }
            UIView.addKeyframe(withRelativeStartTime: 0.50, relativeDuration: 0.20) { flashOverlay.alpha = 0.7 }
            UIView.addKeyframe(withRelativeStartTime: 0.70, relativeDuration: 0.30) { flashOverlay.alpha = 0.0 }
        }
    }

    private func handleWatchlistMatch(_ match: ScanViewModel.WatchlistMatch) {
        guard viewModel.isWatchlistAlertEnabled else {
            viewModel.consumeWatchlistMatch()
            return
        }

        // 1. Flash overlay — reuse the same keyframe animation as repeat-spot.
        flashOverlay.layer.removeAllAnimations()
        flashOverlay.alpha = 0
        UIView.animateKeyframes(withDuration: 2.0, delay: 0, options: [.calculationModeCubic]) { [flashOverlay] in
            UIView.addKeyframe(withRelativeStartTime: 0.00, relativeDuration: 0.20) { flashOverlay.alpha = 0.7 }
            UIView.addKeyframe(withRelativeStartTime: 0.20, relativeDuration: 0.30) { flashOverlay.alpha = 0.0 }
            UIView.addKeyframe(withRelativeStartTime: 0.50, relativeDuration: 0.20) { flashOverlay.alpha = 0.7 }
            UIView.addKeyframe(withRelativeStartTime: 0.70, relativeDuration: 0.30) { flashOverlay.alpha = 0.0 }
        }

        // 2. Vibrate — same 4-pulse pattern as repeat-spot.
        repeatAlertVibrationTimer?.invalidate()
        var pulses = 0
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        repeatAlertVibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            pulses += 1
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            if pulses >= 3 {
                timer.invalidate()
                self?.repeatAlertVibrationTimer = nil
            }
        }

        // 3. Banner with the alarm sound (or silent if the user toggled it off).
        NotificationService.shared.notifyWatchlistMatch(
            plate: match.plate,
            name: match.name,
            silent: !viewModel.isWatchlistSoundEnabled
        )

        viewModel.consumeWatchlistMatch()
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

    @objc private func enterSleepMode() {
        guard sleepWindow == nil, let scene = view.window?.windowScene else { return }

        brightnessBeforeSleep = UIScreen.main.brightness
        UIScreen.main.brightness = 0

        let overlay = SleepOverlayViewController()
        overlay.onDoubleTap = { [weak self] in self?.exitSleepMode() }

        let window = UIWindow(windowScene: scene)
        // Just above the status-bar layer (1000) so we cover the nav bar and
        // tab bar but stay below the notification banner (≥ .alert = 2000).
        // The overlay VC hides the status bar via prefersStatusBarHidden, so
        // we don't need to outrank that layer to look fully dark.
        window.windowLevel = .statusBar + 1
        window.rootViewController = overlay
        window.makeKeyAndVisible()
        sleepWindow = window
    }

    private func exitSleepMode() {
        guard let window = sleepWindow else { return }
        if let saved = brightnessBeforeSleep {
            UIScreen.main.brightness = saved
            brightnessBeforeSleep = nil
        }
        window.isHidden = true
        sleepWindow = nil
        view.window?.makeKeyAndVisible()
    }

    @objc private func handleAppWillResignActive() {
        // If the app is leaving the foreground, drop sleep mode so the user's
        // system brightness isn't left at 0.
        exitSleepMode()
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

extension ScanViewController {
    /// True when all non-whitespace characters in the candidate sit at
    /// roughly the same height — a stand-in for "all from the same physical
    /// plate". Vision will sometimes merge text from adjacent regions (EU
    /// band, stickers, plate digits) into one observation if they happen to
    /// horizontally align; the heights then disagree even though the
    /// observation looks like a single line.
    fileprivate static func charactersHaveConsistentHeight(in cand: VNRecognizedText) -> Bool {
        let str = cand.string
        guard str.count >= 4 else { return true }
        var heights: [CGFloat] = []
        var idx = str.startIndex
        while idx < str.endIndex {
            let next = str.index(after: idx)
            if !str[idx].isWhitespace,
               let rect = try? cand.boundingBox(for: idx..<next) {
                let h = abs(rect.topLeft.y - rect.bottomLeft.y)
                if h > 0 { heights.append(h) }
            }
            idx = next
        }
        guard heights.count >= 4,
              let maxH = heights.max(),
              let minH = heights.min(),
              minH > 0 else { return true }
        // Allow up to ~60% deviation between tallest and shortest character —
        // accounts for descenders and OCR jitter while still catching mixed
        // physical regions.
        return (maxH / minH) < 1.6
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
            let observations: [(text: String, box: CGRect)] = results.compactMap { obs in
                guard obs.confidence >= threshold,
                      let cand = obs.topCandidates(1).first,
                      cand.confidence >= threshold else { return nil }
                // Reject observations whose characters sit at clearly different
                // heights — the OCR sometimes glues "L" + "E" (band/sticker)
                // onto plate digits "7302" because they roughly align
                // horizontally. Real plate text has uniform character height.
                guard ScanViewController.charactersHaveConsistentHeight(in: cand) else { return nil }
                return (cand.string, obs.boundingBox)
            }
            guard !observations.isEmpty else { return }

            // Two-line plates (Spanish motorcycle, square plates) come back as
            // separate Vision observations — neither line passes validation on
            // its own. Pair vertically-stacked observations with similar widths
            // and emit the joined text as an additional candidate.
            var matches: [(String, CGRect)] = observations.map { ($0.text, $0.box) }
            for i in 0..<observations.count {
                for j in 0..<observations.count where i != j {
                    let top = observations[i]
                    let bottom = observations[j]
                    // Vision normalized box: origin bottom-left, y grows up,
                    // so "above" means top.minY > bottom.maxY.
                    guard top.box.minY >= bottom.box.maxY else { continue }
                    let gap = top.box.minY - bottom.box.maxY
                    let avgH = (top.box.height + bottom.box.height) / 2
                    guard avgH > 0, gap < avgH * 0.8 else { continue }
                    let widerWidth = max(top.box.width, bottom.box.width)
                    guard widerWidth > 0,
                          abs(top.box.midX - bottom.box.midX) < widerWidth * 0.4 else { continue }
                    let widthRatio = min(top.box.width, bottom.box.width) / widerWidth
                    guard widthRatio > 0.4 else { continue }
                    // Both lines on a real two-line plate are the same physical
                    // height; mismatched line heights typically mean we'd be
                    // gluing band/sticker text to the plate.
                    let heightRatio = min(top.box.height, bottom.box.height) / max(top.box.height, bottom.box.height)
                    guard heightRatio > 0.7 else { continue }
                    matches.append((top.text + bottom.text, top.box.union(bottom.box)))
                }
            }

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
