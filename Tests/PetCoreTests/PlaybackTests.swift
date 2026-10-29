import XCTest
@testable import PetCore

final class PlaybackTests: XCTestCase {
    func testRelaxedPlaybackUsesTimeScalingRatherThanDroppingFrames() {
        let animation = Animation(frames: Array(0..<6), fps: 8)
        let pet = PetInstance(petID: "codex", x: 0, y: 0)
        XCTAssertEqual(pet.playbackSpeed, 0.65)
        XCTAssertEqual(animation.frame(at: 0.25, speed: pet.playbackSpeed), 1)
        XCTAssertEqual(animation.frame(at: 0.25, speed: 1), 2)
        let cycle = animation.cycleDuration / pet.playbackSpeed
        for frame in 0..<6 {
            let time = (Double(frame) + 0.5) / (animation.fps * pet.playbackSpeed)
            XCTAssertEqual(animation.frame(at: time, speed: pet.playbackSpeed), frame)
        }
        XCTAssertEqual(animation.frame(at: cycle + 0.01, speed: pet.playbackSpeed), 0)
        XCTAssertEqual(animation.frame(at: 1, speed: 0), 0)
    }
    func testSpeedMigrationAndIndependentPreferences() throws {
        let old = Data("""
        {"id":"00000000-0000-4000-8000-000000000001","petID":"codex","x":10,"y":20,"size":140,"walksAround":true}
        """.utf8)
        var first = try JSONDecoder().decode(PetInstance.self, from: old)
        XCTAssertEqual(first.playbackSpeed, 0.65)
        XCTAssertTrue(first.walksAround)
        first.animationSpeed = 0.4
        let second = PetInstance(petID: "dewey", x: 0, y: 0)
        let restored = try JSONDecoder().decode([PetInstance].self, from: JSONEncoder().encode([first, second]))
        XCTAssertEqual(restored.map(\.playbackSpeed), [0.4, 0.65])
    }
}
