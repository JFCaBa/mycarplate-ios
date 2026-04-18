//
//  PhotoEditorViewController.swift
//  PlateTracker
//

import UIKit
import PencilKit

final class PhotoEditorViewController: UIViewController {

    typealias Completion = (UIImage?) -> Void

    private enum Mode { case crop, markup }

    private let viewModel: PhotoEditorViewModel
    private let onComplete: Completion

    private var mode: Mode = .crop

    private let scrollView = UIScrollView()
    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    private let cropOverlay = CropOverlayView()
    private let canvasView = PKCanvasView()

    private let modeSegmented = UISegmentedControl(items: ["Crop", "Markup"])
    private let rotateButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "rotate.right"), for: .normal)
        b.accessibilityLabel = "Rotate 90 degrees"
        return b
    }()
    private let resetButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Reset", for: .normal)
        return b
    }()

    init(image: UIImage, onComplete: @escaping Completion) {
        self.viewModel = PhotoEditorViewModel(image: image)
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))

        setupViews()
        applyMode()
    }

    private func setupViews() {
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.maximumZoomScale = 4
        scrollView.minimumZoomScale = 1
        scrollView.delegate = self

        scrollView.addSubview(imageView)
        imageView.image = viewModel.originalImage
        imageView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(cropOverlay)
        cropOverlay.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(canvasView)
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.tool = PKInkingTool(.pen, color: .red, width: 6)
        canvasView.drawingPolicy = .anyInput
        canvasView.isOpaque = false

        let bottomBar = UIStackView(arrangedSubviews: [modeSegmented, rotateButton, resetButton])
        bottomBar.axis = .horizontal
        bottomBar.spacing = 16
        bottomBar.alignment = .center
        bottomBar.distribution = .equalSpacing
        view.addSubview(bottomBar)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        modeSegmented.selectedSegmentIndex = 0
        modeSegmented.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        rotateButton.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        rotateButton.tintColor = .white
        resetButton.tintColor = .white

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            cropOverlay.topAnchor.constraint(equalTo: scrollView.topAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            cropOverlay.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            canvasView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func applyMode() {
        switch mode {
        case .crop:
            cropOverlay.isHidden = false
            canvasView.isHidden = true
            canvasView.isUserInteractionEnabled = false
        case .markup:
            cropOverlay.isHidden = true
            canvasView.isHidden = false
            canvasView.isUserInteractionEnabled = true
        }
    }

    @objc private func modeChanged() {
        mode = modeSegmented.selectedSegmentIndex == 0 ? .crop : .markup
        applyMode()
    }

    @objc private func rotateTapped() {
        viewModel.rotateClockwise()
        // Live preview: render and replace image.
        imageView.image = viewModel.renderedImage()
    }

    @objc private func resetTapped() {
        viewModel.reset()
        canvasView.drawing = PKDrawing()
        cropOverlay.reset()
        imageView.image = viewModel.originalImage
    }

    @objc private func cancelTapped() {
        onComplete(nil)
    }

    @objc private func doneTapped() {
        // Capture markup overlay if any strokes exist.
        if !canvasView.drawing.bounds.isEmpty {
            // Render the canvas at the original image's pixel size so it composes correctly.
            let originalSize = viewModel.originalImage.size
            let scale = viewModel.originalImage.scale
            UIGraphicsBeginImageContextWithOptions(originalSize, false, scale)
            // Map canvas content coords (in canvasView size) onto the original image size.
            let scaleX = originalSize.width / canvasView.bounds.width
            let scaleY = originalSize.height / canvasView.bounds.height
            UIGraphicsGetCurrentContext()?.scaleBy(x: scaleX, y: scaleY)
            canvasView.drawHierarchy(in: canvasView.bounds, afterScreenUpdates: true)
            let overlay = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            viewModel.markupOverlay = overlay
        }

        // Capture crop in image-pixel coordinates.
        if let imageRectInOverlay = cropOverlay.normalizedCropRect {
            let original = viewModel.originalImage
            viewModel.cropRect = CGRect(
                x: imageRectInOverlay.origin.x * original.size.width,
                y: imageRectInOverlay.origin.y * original.size.height,
                width: imageRectInOverlay.size.width * original.size.width,
                height: imageRectInOverlay.size.height * original.size.height
            )
        }

        let final = viewModel.renderedImage()
        onComplete(final)
    }
}

extension PhotoEditorViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}

/// Minimal crop overlay: a draggable rectangle inside the bounds.
/// Stores its rect as normalized [0,1] coords relative to its own bounds (= image fit area).
final class CropOverlayView: UIView {

    private let cropRectLayer = CAShapeLayer()
    private let dim = CALayer()

    private var cropFrame: CGRect = .zero
    private var initialFrame: CGRect = .zero
    private var dragHandle: DragHandle?

    private enum DragHandle { case move, topLeft, topRight, bottomLeft, bottomRight }

    /// Crop rect normalized to [0,1] in this view's bounds, or nil if no crop.
    var normalizedCropRect: CGRect? {
        guard cropFrame != .zero, cropFrame != bounds else { return nil }
        return CGRect(
            x: cropFrame.origin.x / bounds.width,
            y: cropFrame.origin.y / bounds.height,
            width: cropFrame.size.width / bounds.width,
            height: cropFrame.size.height / bounds.height
        )
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.4).cgColor
        layer.addSublayer(dim)
        cropRectLayer.strokeColor = UIColor.white.cgColor
        cropRectLayer.fillColor = UIColor.clear.cgColor
        cropRectLayer.lineWidth = 1.5
        layer.addSublayer(cropRectLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if cropFrame == .zero {
            // Default to a centered 80% rect.
            cropFrame = bounds.insetBy(dx: bounds.width * 0.1, dy: bounds.height * 0.1)
        }
        update()
    }

    func reset() {
        cropFrame = bounds.insetBy(dx: bounds.width * 0.1, dy: bounds.height * 0.1)
        update()
    }

    private func update() {
        cropRectLayer.path = UIBezierPath(rect: cropFrame).cgPath
        // Build a dim mask with the crop hole punched out.
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(rect: cropFrame).reversing())
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        dim.frame = bounds
        dim.mask = mask
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began:
            initialFrame = cropFrame
            dragHandle = handle(at: location)
        case .changed:
            guard let h = dragHandle else { return }
            switch h {
            case .move:
                cropFrame = initialFrame.offsetBy(dx: translation.x, dy: translation.y)
            case .topLeft:
                cropFrame = CGRect(x: initialFrame.minX + translation.x,
                                   y: initialFrame.minY + translation.y,
                                   width: initialFrame.width - translation.x,
                                   height: initialFrame.height - translation.y)
            case .topRight:
                cropFrame = CGRect(x: initialFrame.minX,
                                   y: initialFrame.minY + translation.y,
                                   width: initialFrame.width + translation.x,
                                   height: initialFrame.height - translation.y)
            case .bottomLeft:
                cropFrame = CGRect(x: initialFrame.minX + translation.x,
                                   y: initialFrame.minY,
                                   width: initialFrame.width - translation.x,
                                   height: initialFrame.height + translation.y)
            case .bottomRight:
                cropFrame = CGRect(x: initialFrame.minX,
                                   y: initialFrame.minY,
                                   width: initialFrame.width + translation.x,
                                   height: initialFrame.height + translation.y)
            }
            cropFrame = cropFrame.intersection(bounds).standardized
            update()
        default:
            dragHandle = nil
        }
    }

    private func handle(at point: CGPoint) -> DragHandle {
        let r: CGFloat = 30
        if hypot(point.x - cropFrame.minX, point.y - cropFrame.minY) < r { return .topLeft }
        if hypot(point.x - cropFrame.maxX, point.y - cropFrame.minY) < r { return .topRight }
        if hypot(point.x - cropFrame.minX, point.y - cropFrame.maxY) < r { return .bottomLeft }
        if hypot(point.x - cropFrame.maxX, point.y - cropFrame.maxY) < r { return .bottomRight }
        return .move
    }
}
