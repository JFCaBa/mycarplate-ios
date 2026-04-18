import XCTest
@testable import PlateTracker

@MainActor
final class PhotoEditorViewModelTests: XCTestCase {

    private func image(width: Int, height: Int, color: UIColor = .red) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func test_rotation_accumulatesIn90Increments_wrapsAt360() {
        let vm = PhotoEditorViewModel(image: image(width: 4, height: 4))
        XCTAssertEqual(vm.rotationDegrees, 0)
        vm.rotateClockwise(); XCTAssertEqual(vm.rotationDegrees, 90)
        vm.rotateClockwise(); XCTAssertEqual(vm.rotationDegrees, 180)
        vm.rotateClockwise(); XCTAssertEqual(vm.rotationDegrees, 270)
        vm.rotateClockwise(); XCTAssertEqual(vm.rotationDegrees, 0)
    }

    func test_render_appliesRotation_swapsDimensionsFor90() {
        let vm = PhotoEditorViewModel(image: image(width: 100, height: 50))
        vm.rotateClockwise()
        let rendered = vm.renderedImage()
        XCTAssertEqual(Int(rendered.size.width.rounded()), 50)
        XCTAssertEqual(Int(rendered.size.height.rounded()), 100)
    }

    func test_render_appliesCrop_returnsCroppedSize() {
        let vm = PhotoEditorViewModel(image: image(width: 100, height: 100))
        vm.cropRect = CGRect(x: 25, y: 25, width: 50, height: 50) // pixel coords
        let rendered = vm.renderedImage()
        XCTAssertEqual(Int(rendered.size.width.rounded()), 50)
        XCTAssertEqual(Int(rendered.size.height.rounded()), 50)
    }

    func test_reset_restoresOriginal() {
        let vm = PhotoEditorViewModel(image: image(width: 100, height: 50))
        vm.rotateClockwise()
        vm.cropRect = CGRect(x: 0, y: 0, width: 50, height: 50)
        vm.reset()
        XCTAssertEqual(vm.rotationDegrees, 0)
        XCTAssertNil(vm.cropRect)
    }
}
