import XCTest
import CoreGraphics
@testable import PetCore

final class WalkingTests: XCTestCase {
    func testWalkingPreferenceMigratesOldLayoutAndPersistsPerPet() throws {
        let legacy = Data("""
        {"id":"00000000-0000-4000-8000-000000000001","petID":"codex","x":10,"y":20,"size":140}
        """.utf8)
        var first = try JSONDecoder().decode(PetInstance.self, from: legacy)
        let second = PetInstance(petID: "dewey", x: 50, y: 20)
        XCTAssertFalse(first.walksAround)
        first.walksAround = true
        let restored = try JSONDecoder().decode([PetInstance].self, from: JSONEncoder().encode([first, second]))
        XCTAssertTrue(restored[0].walksAround)
        XCTAssertFalse(restored[1].walksAround)
        XCTAssertEqual(restored[0].id, first.id)
        XCTAssertEqual(restored[0].size, 140)
    }

    func testStrollMovesAtConstantSpeedAndStopsAtDestination() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let route = try XCTUnwrap(WalkingRoute(origin: CGPoint(x: 100, y: 40), windowSize: CGSize(width: 140, height: 164),
                                             visibleFrame: screen, distance: 128, direction: 1))
        XCTAssertEqual(route.animationName, "walkRight")
        XCTAssertEqual(route.position(at: 0), CGPoint(x: 100, y: 40))
        XCTAssertEqual(route.position(at: 2), CGPoint(x: 164, y: 40))
        XCTAssertEqual(route.duration, 4)
        XCTAssertEqual(route.position(at: 4), CGPoint(x: 228, y: 40))
        XCTAssertEqual(route.position(at: 100), route.end)
        XCTAssertEqual(route.position(at: -5), route.start)
    }

    func testScreenEdgesTurnPetBackAndKeepWholeWindowOnScreen() throws {
        // A secondary monitor may have negative coordinates and an offset menu bar.
        let screen = CGRect(x: -1000, y: 24, width: 1000, height: 700)
        let windowSize = CGSize(width: 140, height: 164)
        let route = try XCTUnwrap(WalkingRoute(origin: CGPoint(x: -140, y: 650), windowSize: windowSize,
                                             visibleFrame: screen, distance: 180, direction: 1))
        XCTAssertEqual(route.animationName, "walkLeft")
        XCTAssertEqual(route.end.x, -320)
        for elapsed in stride(from: 0.0, through: 10.0, by: 0.1) {
            let point = route.position(at: elapsed)
            XCTAssertGreaterThanOrEqual(point.x, screen.minX)
            XCTAssertLessThanOrEqual(point.x + windowSize.width, screen.maxX)
            XCTAssertGreaterThanOrEqual(point.y, screen.minY)
            XCTAssertLessThanOrEqual(point.y + windowSize.height, screen.maxY)
        }
        let left = try XCTUnwrap(WalkingRoute(origin: CGPoint(x: -1000, y: 24), windowSize: windowSize,
                                            visibleFrame: screen, distance: 100, direction: -1))
        XCTAssertEqual(left.animationName, "walkRight")
        XCTAssertNil(WalkingRoute(origin: .zero, windowSize: screen.size, visibleFrame: screen, distance: 100, direction: 1))
    }
}
