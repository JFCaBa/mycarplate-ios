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

    func configure(with viewModel: ScanViewModel) {
        self.viewModel = viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Scan"
        view.backgroundColor = .black

        setupCamera()
        setupPlateLabel()
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

    private func bindViewModel() {
        viewModel.$scanRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                guard let latest = records.last else { return }
                self?.plateLabel.text = "Plate: \(latest.plate)"
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
            guard let results = request.results as? [VNRecognizedTextObservation], error == nil else { return }
            let recognizedStrings = results.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                recognizedStrings.forEach { self?.viewModel.processRecognizedText($0) }
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? requestHandler.perform([request])
    }
}
