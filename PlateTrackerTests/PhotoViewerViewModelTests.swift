import XCTest
import CoreLocation
@testable import PlateTracker

@MainActor
final class PhotoViewerViewModelTests: XCTestCase {

    private func makeRecord(plate: String, sightingCount: Int = 1) -> PlateScanRecord {
        let coord = CodableCoordinate(.init(latitude: 0, longitude: 0))
        let sightings = (0..<sightingCount).map {
            Sighting(location: coord, date: Date().addingTimeInterval(Double($0) * 60), photoFileName: "p\($0).jpg")
        }
        return PlateScanRecord(plate: plate, vehicleData: nil, sightings: sightings)
    }

    func test_initialState_indexPointsToStart() {
        let records = [makeRecord(plate: "A"), makeRecord(plate: "B"), makeRecord(plate: "C")]
        let vm = PhotoViewerViewModel(vehicles: records, startIndex: 1)
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertEqual(vm.currentVehicle?.plate, "B")
    }

    func test_advance_movesForward_stopsAtEnd() {
        let records = [makeRecord(plate: "A"), makeRecord(plate: "B")]
        let vm = PhotoViewerViewModel(vehicles: records, startIndex: 0)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 1)
        vm.advance()
        XCTAssertEqual(vm.currentIndex, 1, "should not advance past last")
    }

    func test_retreat_movesBack_stopsAtStart() {
        let records = [makeRecord(plate: "A"), makeRecord(plate: "B")]
        let vm = PhotoViewerViewModel(vehicles: records, startIndex: 1)
        vm.retreat()
        XCTAssertEqual(vm.currentIndex, 0)
        vm.retreat()
        XCTAssertEqual(vm.currentIndex, 0, "should not retreat below 0")
    }

    func test_currentSightingIndex_defaultsToLatest() {
        let record = makeRecord(plate: "A", sightingCount: 3)
        let vm = PhotoViewerViewModel(vehicles: [record], startIndex: 0)
        XCTAssertEqual(vm.currentSightingIndex(forVehicle: 0), 2)
    }

    func test_setCurrentSightingIndex_perVehicle() {
        let records = [makeRecord(plate: "A", sightingCount: 3), makeRecord(plate: "B", sightingCount: 2)]
        let vm = PhotoViewerViewModel(vehicles: records, startIndex: 0)

        vm.setCurrentSightingIndex(0, forVehicle: 0)
        vm.setCurrentSightingIndex(1, forVehicle: 1)

        XCTAssertEqual(vm.currentSightingIndex(forVehicle: 0), 0)
        XCTAssertEqual(vm.currentSightingIndex(forVehicle: 1), 1)
    }

    func test_removeCurrentVehicle_advancesIfPossible_elseRetreats() {
        let records = [makeRecord(plate: "A"), makeRecord(plate: "B"), makeRecord(plate: "C")]
        let vm = PhotoViewerViewModel(vehicles: records, startIndex: 1)

        vm.removeCurrentVehicle()
        XCTAssertEqual(vm.currentVehicle?.plate, "C", "advances to next")

        vm.removeCurrentVehicle() // remove C; only A left, index should drop to 0
        XCTAssertEqual(vm.currentVehicle?.plate, "A")
    }

    func test_removeCurrentVehicle_lastOneEmpties() {
        let records = [makeRecord(plate: "A")]
        let vm = PhotoViewerViewModel(vehicles: records, startIndex: 0)
        vm.removeCurrentVehicle()
        XCTAssertNil(vm.currentVehicle)
        XCTAssertTrue(vm.isEmpty)
    }
}
