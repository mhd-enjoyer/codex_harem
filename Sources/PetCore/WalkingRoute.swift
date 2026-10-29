import Foundation
import CoreGraphics

/// One horizontal stroll, constrained to keep the entire pet window on its screen.
/// Sampling by elapsed time makes movement independent of the animation frame rate.
public struct WalkingRoute {
    public let start: CGPoint
    public let end: CGPoint
    public let duration: TimeInterval
    public var animationName: String { end.x > start.x ? "walkRight" : "walkLeft" }

    public init?(origin: CGPoint, windowSize: CGSize, visibleFrame: CGRect,
                 distance: Double, direction: Int, speed: Double = 32) {
        guard [origin.x, origin.y, windowSize.width, windowSize.height,
               visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height,
               distance, speed].allSatisfy({ $0.isFinite }),
              speed > 0, distance > 0, windowSize.width > 0, windowSize.height > 0,
              visibleFrame.width > windowSize.width, visibleFrame.height >= windowSize.height else { return nil }
        let minX = visibleFrame.minX, maxX = visibleFrame.maxX - windowSize.width
        let x = min(max(origin.x, minX), maxX)
        let y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - windowSize.height)
        let sign = direction < 0 ? -1.0 : 1.0
        var destination = min(max(x + sign * distance, minX), maxX)
        // At an edge, turn back instead of repeatedly trying to leave the screen.
        if abs(destination - x) < 1 { destination = min(max(x - sign * distance, minX), maxX) }
        guard abs(destination - x) >= 1 else { return nil }
        start = CGPoint(x: x, y: y); end = CGPoint(x: destination, y: y)
        duration = abs(destination - x) / speed
    }

    public func position(at elapsed: TimeInterval) -> CGPoint {
        let progress = min(1, max(0, elapsed.isFinite ? elapsed / duration : 0))
        return CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y)
    }
}
