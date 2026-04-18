//
//  PhotoEditorViewModel.swift
//  PlateTracker
//

import UIKit

@MainActor
final class PhotoEditorViewModel {

    let originalImage: UIImage
    private(set) var rotationDegrees: Int = 0
    /// Crop rect in original-image point coordinates (origin top-left).
    /// Internally scaled by `originalImage.scale` to map onto cgImage pixel space.
    var cropRect: CGRect?
    /// Optional flattened markup overlay drawn in original-image point coordinates.
    var markupOverlay: UIImage?

    init(image: UIImage) {
        self.originalImage = image
    }

    func rotateClockwise() {
        rotationDegrees = (rotationDegrees + 90) % 360
    }

    func reset() {
        rotationDegrees = 0
        cropRect = nil
        markupOverlay = nil
    }

    /// Produces the final edited UIImage by applying crop, then rotation, then markup.
    func renderedImage() -> UIImage {
        var working = originalImage

        // 1. Markup overlay (drawn at full original size before crop/rotate).
        if let overlay = markupOverlay {
            let renderer = UIGraphicsImageRenderer(size: working.size)
            working = renderer.image { _ in
                working.draw(in: CGRect(origin: .zero, size: working.size))
                overlay.draw(in: CGRect(origin: .zero, size: working.size))
            }
        }

        // 2. Crop. cropRect is in points; cgImage works in pixels, so scale up.
        if let crop = cropRect {
            let scale = working.scale
            let pixelRect = CGRect(
                x: crop.origin.x * scale,
                y: crop.origin.y * scale,
                width: crop.size.width * scale,
                height: crop.size.height * scale
            )
            if let cg = working.cgImage?.cropping(to: pixelRect) {
                working = UIImage(cgImage: cg, scale: scale, orientation: working.imageOrientation)
            }
        }

        // 3. Rotate.
        if rotationDegrees != 0 {
            working = rotated(working, degrees: rotationDegrees)
        }

        return working
    }

    private func rotated(_ image: UIImage, degrees: Int) -> UIImage {
        let radians = CGFloat(degrees) * .pi / 180
        let rotatedSize: CGSize = (degrees % 180 == 0)
            ? image.size
            : CGSize(width: image.size.height, height: image.size.width)

        let renderer = UIGraphicsImageRenderer(size: rotatedSize)
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            ctx.rotate(by: radians)
            image.draw(in: CGRect(x: -image.size.width / 2,
                                  y: -image.size.height / 2,
                                  width: image.size.width,
                                  height: image.size.height))
        }
    }
}
