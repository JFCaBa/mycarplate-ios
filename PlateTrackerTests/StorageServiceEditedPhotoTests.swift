import XCTest
@testable import PlateTracker

final class StorageServiceEditedPhotoTests: XCTestCase {

    private let originalFileName = "test_original_\(UUID().uuidString).jpg"
    private var editedFileName: String?

    override func tearDown() {
        StorageService.shared.deletePhoto(fileName: originalFileName)
        if let edited = editedFileName {
            StorageService.shared.deleteEditedPhoto(fileName: edited)
        }
        super.tearDown()
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func test_saveEditedPhoto_writesNewFile_originalUntouched() {
        let original = makeImage()
        StorageService.shared.savePhoto(original, fileName: originalFileName)
        let originalSize = StorageService.shared.photoFileSize(fileName: originalFileName)
        XCTAssertGreaterThan(originalSize, 0)

        let edited = makeImage()
        let name = StorageService.shared.saveEditedPhoto(originalFileName: originalFileName, image: edited)
        editedFileName = name
        XCTAssertNotNil(name)
        XCTAssertNotEqual(name, originalFileName)
        XCTAssertNotNil(StorageService.shared.loadPhoto(fileName: name!))
        // original still loadable & same size
        XCTAssertEqual(StorageService.shared.photoFileSize(fileName: originalFileName), originalSize)
    }

    func test_deleteEditedPhoto_removesOnlyTheEditedFile() {
        let original = makeImage()
        StorageService.shared.savePhoto(original, fileName: originalFileName)

        let edited = makeImage()
        let name = StorageService.shared.saveEditedPhoto(originalFileName: originalFileName, image: edited)!
        editedFileName = name

        StorageService.shared.deleteEditedPhoto(fileName: name)
        XCTAssertNil(StorageService.shared.loadPhoto(fileName: name))
        XCTAssertNotNil(StorageService.shared.loadPhoto(fileName: originalFileName))
    }
}
