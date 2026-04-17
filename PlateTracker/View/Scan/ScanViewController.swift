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
            if let item = self.viewModel.lookupQueue.items.first(where: { $0.plate == plate }),
               let fileName = item.capturedFrameFileName {
                StorageService.shared.deletePhoto(fileName: fileName)
            }
            self.viewModel.lookupQueue.remove(plate: plate)
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
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                print("[Scan] Vision returned no results")
                return
            }
            if !results.isEmpty {
                print("[Scan] Vision found \(results.count) text observation(s)")
                for (i, obs) in results.enumerated() {
                    let top = obs.topCandidates(3).map { "\($0.string) (\(String(format: "%.2f", $0.confidence)))" }
                    print("[Scan]   #\(i) obsConf=\(String(format: "%.2f", obs.confidence)) candidates=\(top)")
                }
            }
            let recognizedStrings = results.compactMap { observation -> String? in
                guard observation.confidence >= 0.8,
                      let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.8 else { return nil }
                return candidate.string
            }
            if recognizedStrings.isEmpty {
                // Only log occasionally to avoid flooding
                return
            }
            print("[Scan] Passed confidence filter: \(recognizedStrings)")

            // Capture the frame that contained the plate
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            let frame: UIImage?
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                frame = UIImage(cgImage: cgImage)
            } else {
                frame = nil
            }

            DispatchQueue.main.async {
                recognizedStrings.forEach {
                    self?.viewModel.processRecognizedText($0, capturedFrame: frame)
                }
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
