import Foundation

public struct Animation: Codable, Equatable, Sendable {
    public var frames: [Int]
    public var fps: Double
    public init(frames: [Int], fps: Double = 8) { self.frames = frames; self.fps = fps }
    public var cycleDuration: TimeInterval { fps.isFinite && fps > 0 ? Double(frames.count) / fps : 0 }
    public func frame(at elapsed: Double, speed: Double = 1) -> Int {
        let progress = max(0, elapsed) * fps * speed
        guard !frames.isEmpty, fps.isFinite, fps > 0, speed.isFinite, speed > 0, progress.isFinite else { return frames.first ?? 0 }
        return frames[Int(floor(progress).truncatingRemainder(dividingBy: Double(frames.count)))]
    }
}
public struct FrameGrid: Codable, Sendable {
    public var width: Int
    public var height: Int
    public var columns: Int
    public var rows: Int
}
public struct PetManifest: Codable, Sendable {
    public var id: String
    public var displayName: String
    public var description: String?
    public var spritesheetPath: String
    public var spriteVersionNumber: Int?
    public var frame: FrameGrid?
    public var animations: [String: Animation]?
    public init(id: String, displayName: String, spritesheetPath: String, spriteVersionNumber: Int = 1) {
        self.id = id; self.displayName = displayName; self.spritesheetPath = spritesheetPath; self.spriteVersionNumber = spriteVersionNumber
    }
    public var rows: Int { frame?.rows ?? (spriteVersionNumber == 2 ? 11 : 9) }
    public var columns: Int { frame?.columns ?? 8 }
    public func animation(_ name: String) -> Animation {
        if let animation = animations?[name], !animation.frames.isEmpty { return animation }
        let defaults: [String: (Int, Int, Double)] = [
            "idle": (0, 6, 5), "walkRight": (1, 8, 10), "walkLeft": (2, 8, 10),
            "wave": (3, 4, 7), "hop": (4, 5, 9), "failed": (5, 8, 7),
            "thinking": (6, 6, 6), "working": (7, 6, 8), "completed": (8, 6, 8)
        ]
        let (row, count, fps) = defaults[name] ?? defaults["idle"]!
        return Animation(frames: Array(row * columns ..< row * columns + min(count, columns)), fps: fps)
    }
    public func validate(imageWidth: Int, imageHeight: Int) throws {
        guard !id.isEmpty, !displayName.isEmpty, [1, 2].contains(spriteVersionNumber ?? 1),
              columns > 0, columns <= 256, rows > 0, rows <= 256,
              imageWidth > 0, imageHeight > 0, imageWidth % columns == 0, imageHeight % rows == 0 else {
            throw PetError.invalid("Invalid pet version or sprite grid: \(id)")
        }
        if let frame, frame.width != imageWidth / columns || frame.height != imageHeight / rows {
            throw PetError.invalid("Frame dimensions do not cover spritesheet: \(id)")
        }
        for (name, animation) in animations ?? [:] {
            guard !animation.frames.isEmpty, animation.fps.isFinite, animation.fps > 0, animation.fps <= 120,
                  animation.frames.allSatisfy({ $0 >= 0 && $0 < columns * rows }) else {
                throw PetError.invalid("Invalid animation \(name): \(id)")
            }
        }
    }
    public func sheetURL(relativeTo directory: URL) throws -> URL {
        let base = directory.resolvingSymlinksInPath().standardizedFileURL
        let result = directory.appendingPathComponent(spritesheetPath).resolvingSymlinksInPath().standardizedFileURL
        guard result.path.hasPrefix(base.path + "/") else { throw PetError.invalid("Spritesheet must stay inside pet directory") }
        return result
    }
}
public enum PetError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String { switch self { case .invalid(let text): return text } }
}

public struct PetInstance: Codable, Identifiable {
    public var id: UUID = UUID()
    public var petID: String
    /// nil follows the most recently active thread; "*" follows all threads.
    public var threadID: String?
    public var x: Double
    public var y: Double
    public var size: Double = 140
    public var walksAround: Bool = false
    public var animationSpeed: Double = 0.65
    public var playbackSpeed: Double { animationSpeed.isFinite ? min(2, max(0.25, animationSpeed)) : 0.65 }
    public init(petID: String, threadID: String? = nil, x: Double, y: Double) {
        self.petID = petID; self.threadID = threadID; self.x = x; self.y = y
    }
    private enum CodingKeys: String, CodingKey {
        case id, petID, threadID, x, y, size, walksAround, animationSpeed
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        petID = try values.decode(String.self, forKey: .petID)
        threadID = try values.decodeIfPresent(String.self, forKey: .threadID)
        x = try values.decode(Double.self, forKey: .x)
        y = try values.decode(Double.self, forKey: .y)
        size = try values.decodeIfPresent(Double.self, forKey: .size) ?? 140
        walksAround = try values.decodeIfPresent(Bool.self, forKey: .walksAround) ?? false
        animationSpeed = try values.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? 0.65
    }
}
public enum Selection {
    public static func status(for binding: String?, threads: [ThreadState]) -> PetStatus {
        if let binding, binding != "*" { return threads.first { $0.id == binding }?.status ?? .offline }
        if binding == "*" {
            let priority: [PetStatus] = [.waiting, .working, .thinking]
            return priority.first { state in threads.contains { $0.status == state } }
                ?? threads.max(by: { $0.updatedAt < $1.updatedAt })?.status ?? .idle
        }
        return threads.max(by: { $0.updatedAt < $1.updatedAt })?.status ?? .idle
    }
}
