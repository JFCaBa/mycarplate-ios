import XCTest
import CoreLocation
@testable import PlateTracker

/// Test-only convenience init: VehicleData has 30+ fields and no convenience
/// initializer in production. Tests need only make/model.
extension VehicleData {
    static func test(make: String? = nil, model: String? = nil) -> VehicleData {
        VehicleData(
            plate: "", country: "ES",
            make: make, model: model, version: nil,
            year: nil, color: nil, engineSize: nil, fuelType: nil,
            doors: nil, horsePower: nil,
            versionOptions: nil, doorsOptions: nil,
            co2Emissions: nil, fuelConsumptionCombined: nil,
            fuelConsumptionCity: nil, fuelConsumptionHighway: nil,
            noiseLevel: nil, emissionClass: nil, netMaximumPower: nil,
            taxStatus: nil, taxDueDate: nil,
            motStatus: nil, motExpiryDate: nil,
            firstRegistration: nil, powerKw: nil,
            base7Code: nil, base7CodeOptions: nil,
            weight: nil, vin: nil, engineCode: nil,
            source: nil, confidence: nil, immoPin: nil
        )
    }
}

@MainActor
final class VehicleGridViewModelTests: XCTestCase {

    private func makeRecord(plate: String,
                            make: String? = nil,
                            model: String? = nil,
                            sightingDates: [Date],
                            photoFileName: String? = "photo.jpg") -> PlateScanRecord {
        let coord = CodableCoordinate(.init(latitude: 0, longitude: 0))
        let sightings = sightingDates.map {
            Sighting(location: coord, date: $0, photoFileName: photoFileName)
        }
        var v: VehicleData? = nil
        if make != nil || model != nil {
            v = VehicleData.test(make: make, model: model)
        }
        return PlateScanRecord(plate: plate, vehicleData: v, sightings: sightings)
    }

    func test_groupsByLastSightingDay_newestFirst() {
        let today = Date()
        let yesterday = today.addingTimeInterval(-86_400)
        let twoDaysAgo = today.addingTimeInterval(-86_400 * 2)
        let records = [
            makeRecord(plate: "AAA", sightingDates: [twoDaysAgo]),
            makeRecord(plate: "BBB", sightingDates: [today]),
            makeRecord(plate: "CCC", sightingDates: [yesterday]),
        ]

        let vm = VehicleGridViewModel()
        vm.update(records: records)

        XCTAssertEqual(vm.sections.count, 3)
        XCTAssertEqual(vm.sections[0].records.first?.plate, "BBB") // newest day first
        XCTAssertEqual(vm.sections[1].records.first?.plate, "CCC")
        XCTAssertEqual(vm.sections[2].records.first?.plate, "AAA")
    }

    func test_search_matchesPlatePrefix() {
        let records = [
            makeRecord(plate: "AB12 CDE", sightingDates: [Date()]),
            makeRecord(plate: "XY99 ZZZ", sightingDates: [Date()]),
        ]
        let vm = VehicleGridViewModel()
        vm.update(records: records)
        vm.searchText = "AB"

        let allPlates = vm.sections.flatMap { $0.records.map(\.plate) }
        XCTAssertEqual(allPlates, ["AB12 CDE"])
    }

    func test_search_matchesMakeAndModel_caseInsensitive() {
        let records = [
            makeRecord(plate: "AAA", make: "BMW", model: "320d", sightingDates: [Date()]),
            makeRecord(plate: "BBB", make: "SEAT", model: "Ibiza", sightingDates: [Date()]),
        ]
        let vm = VehicleGridViewModel()
        vm.update(records: records)
        vm.searchText = "bmw"

        let allPlates = vm.sections.flatMap { $0.records.map(\.plate) }
        XCTAssertEqual(allPlates, ["AAA"])
    }

    func test_search_emptyReturnsAll() {
        let records = [
            makeRecord(plate: "AAA", sightingDates: [Date()]),
            makeRecord(plate: "BBB", sightingDates: [Date()]),
        ]
        let vm = VehicleGridViewModel()
        vm.update(records: records)
        vm.searchText = ""

        let allPlates = vm.sections.flatMap { $0.records.map(\.plate) }
        XCTAssertEqual(Set(allPlates), Set(["AAA", "BBB"]))
    }

    func test_search_matchesAcrossSightingNotes() {
        let coord = CodableCoordinate(.init(latitude: 0, longitude: 0))
        let withNote = PlateScanRecord(
            plate: "AAA",
            vehicleData: nil,
            sightings: [
                Sighting(location: coord, date: Date(), photoFileName: nil, note: "near the marina"),
                Sighting(location: coord, date: Date(), photoFileName: nil, note: nil),
            ]
        )
        let without = PlateScanRecord(
            plate: "BBB",
            vehicleData: nil,
            sightings: [Sighting(location: coord, date: Date(), photoFileName: nil, note: nil)]
        )
        let vm = VehicleGridViewModel()
        vm.update(records: [withNote, without])
        vm.searchText = "marina"

        let plates = vm.sections.flatMap { $0.records.map(\.plate) }
        XCTAssertEqual(plates, ["AAA"])
    }
}
