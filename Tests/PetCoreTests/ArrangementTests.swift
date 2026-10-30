import XCTest
import CoreGraphics
@testable import PetCore

final class ArrangementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 500, height: 400)
    private let standardSize = CGSize(width: 140, height: 164)

    func testGridFillsRowsRightToLeftAndWrapsUpward() {
        let positions = Arrangement.grid.positions(
            for: Array(repeating: standardSize, count: 5),
            in: screen, spacing: 10, margin: 12
        )
        XCTAssertEqual(positions, [
            CGPoint(x: 348, y: 12),
            CGPoint(x: 198, y: 12),
            CGPoint(x: 48, y: 12),
            CGPoint(x: 348, y: 186),
            CGPoint(x: 198, y: 186)
        ])
    }

    func testLeftAndRightStylesAlignToTheirEdgeAndWrapIntoAnotherColumn() {
        let sizes = Array(repeating: standardSize, count: 4)
        let left = Arrangement.left.positions(for: sizes, in: screen, spacing: 10, margin: 12)
        let right = Arrangement.right.positions(for: sizes, in: screen, spacing: 10, margin: 12)

        XCTAssertEqual(left, [
            CGPoint(x: 12, y: 224),
            CGPoint(x: 12, y: 50),
            CGPoint(x: 162, y: 224),
            CGPoint(x: 162, y: 50)
        ])
        XCTAssertEqual(right, [
            CGPoint(x: 348, y: 224),
            CGPoint(x: 348, y: 50),
            CGPoint(x: 198, y: 224),
            CGPoint(x: 198, y: 50)
        ])
    }

    func testTopAndBottomStylesAlignToTheirEdgeAndWrapIntoAnotherRow() {
        let sizes = Array(repeating: standardSize, count: 4)
        let bottom = Arrangement.bottom.positions(for: sizes, in: screen, spacing: 10, margin: 12)
        let top = Arrangement.top.positions(for: sizes, in: screen, spacing: 10, margin: 12)

        XCTAssertEqual(bottom, [
            CGPoint(x: 12, y: 12),
            CGPoint(x: 162, y: 12),
            CGPoint(x: 312, y: 12),
            CGPoint(x: 12, y: 186)
        ])
        XCTAssertEqual(top, [
            CGPoint(x: 12, y: 224),
            CGPoint(x: 162, y: 224),
            CGPoint(x: 312, y: 224),
            CGPoint(x: 12, y: 50)
        ])
    }

    func testEdgeStylesAlignWindowsOfDifferentSizes() {
        let frame = CGRect(x: -100, y: 50, width: 900, height: 700)
        let sizes = [
            CGSize(width: 80, height: 100),
            CGSize(width: 200, height: 240),
            CGSize(width: 130, height: 150)
        ]
        let left = Arrangement.left.positions(for: sizes, in: frame, spacing: 10, margin: 20)
        let right = Arrangement.right.positions(for: sizes, in: frame, spacing: 10, margin: 20)
        let top = Arrangement.top.positions(for: sizes, in: frame, spacing: 10, margin: 20)
        let bottom = Arrangement.bottom.positions(for: sizes, in: frame, spacing: 10, margin: 20)

        XCTAssertEqual(left.map(\.x), [-80, -80, -80])
        XCTAssertEqual(zip(right, sizes).map { $0.0.x + $0.1.width }, [780, 780, 780])
        XCTAssertEqual(zip(top, sizes).map { $0.0.y + $0.1.height }, [730, 730, 730])
        XCTAssertEqual(bottom.map(\.y), [70, 70, 70])
    }

    func testCenterStyleBuildsABlockAroundTheMiddleOfTheScreen() {
        let sizes = Array(repeating: CGSize(width: 100, height: 120), count: 5)
        let positions = Arrangement.center.positions(for: sizes, in: CGRect(x: 0, y: 0, width: 800, height: 600),
                                                     spacing: 8, margin: 16)
        XCTAssertEqual(positions, [
            CGPoint(x: 242, y: 304),
            CGPoint(x: 350, y: 304),
            CGPoint(x: 458, y: 304),
            CGPoint(x: 242, y: 176),
            CGPoint(x: 350, y: 176)
        ])
        let bounds = zip(positions, sizes).reduce(CGRect.null) { partial, item in
            partial.union(CGRect(origin: item.0, size: item.1))
        }
        XCTAssertEqual(bounds.midX, 400, accuracy: 0.001)
        XCTAssertEqual(bounds.midY, 300, accuracy: 0.001)
    }

    func testCenterStyleCentersMixedSizes() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let sizes = [
            CGSize(width: 80, height: 100), CGSize(width: 200, height: 240),
            CGSize(width: 130, height: 150), CGSize(width: 90, height: 110)
        ]
        let positions = Arrangement.center.positions(for: sizes, in: frame, spacing: 10, margin: 20)
        let bounds = zip(positions, sizes).reduce(CGRect.null) { partial, item in
            partial.union(CGRect(origin: item.0, size: item.1))
        }
        XCTAssertEqual(bounds.midX, frame.midX, accuracy: 0.001)
        XCTAssertEqual(bounds.midY, frame.midY, accuracy: 0.001)
    }

    func testRandomStyleScattersWindowsAndAvoidsOverlap() {
        var seed: UInt64 = 0x5EED
        func nextRandom(_ range: ClosedRange<CGFloat>) -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = CGFloat((seed >> 11) % 10_000) / 10_000
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }
        let sizes = Array(repeating: CGSize(width: 120, height: 144), count: 8)
        let positions = Arrangement.random.positions(
            for: sizes, in: CGRect(x: 0, y: 0, width: 1000, height: 700),
            spacing: 8, margin: 16, randomSource: nextRandom
        )
        let rects = zip(positions, sizes).map { CGRect(origin: $0, size: $1) }
        for rect in rects {
            XCTAssertGreaterThanOrEqual(rect.minX, 16)
            XCTAssertLessThanOrEqual(rect.maxX, 984)
            XCTAssertGreaterThanOrEqual(rect.minY, 16)
            XCTAssertLessThanOrEqual(rect.maxY, 684)
        }
        for first in rects.indices {
            for second in rects.indices where second > first {
                XCTAssertFalse(rects[first].intersects(rects[second]),
                               "Random layout placed two pets on top of each other")
            }
        }
        XCTAssertGreaterThan(Set(positions.map(\.x)).count, 1)
        XCTAssertGreaterThan(Set(positions.map(\.y)).count, 1)
    }

    func testEveryStyleKeepsAllWindowsInsideAnOffsetScreen() {
        let frame = CGRect(x: -1200, y: 24, width: 1200, height: 800)
        let sizes = [
            CGSize(width: 100, height: 124), CGSize(width: 140, height: 164),
            CGSize(width: 200, height: 224), CGSize(width: 100, height: 124),
            CGSize(width: 140, height: 164), CGSize(width: 100, height: 124),
            CGSize(width: 200, height: 224), CGSize(width: 140, height: 164),
            CGSize(width: 100, height: 124)
        ]
        var seed: UInt64 = 99
        for style in Arrangement.allCases {
            let positions = style.positions(for: sizes, in: frame, spacing: 10, margin: 16) { range in
                seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
                let unit = CGFloat((seed >> 11) % 10_000) / 10_000
                return range.lowerBound + (range.upperBound - range.lowerBound) * unit
            }
            XCTAssertEqual(positions.count, sizes.count, "\(style)")
            for (point, size) in zip(positions, sizes) {
                XCTAssertGreaterThanOrEqual(point.x, frame.minX - 0.001, "\(style)")
                XCTAssertLessThanOrEqual(point.x + size.width, frame.maxX + 0.001, "\(style)")
                XCTAssertGreaterThanOrEqual(point.y, frame.minY - 0.001, "\(style)")
                XCTAssertLessThanOrEqual(point.y + size.height, frame.maxY + 0.001, "\(style)")
            }
        }
    }

    func testArrangementMetadataAndDegenerateInputs() {
        XCTAssertEqual(Arrangement.allCases.count, 7)
        XCTAssertEqual(Set(Arrangement.allCases.map(\.displayName)).count, Arrangement.allCases.count)
        XCTAssertEqual(Arrangement(rawValue: "random"), .random)
        XCTAssertTrue(Arrangement.grid.positions(for: [], in: screen).isEmpty)
        XCTAssertTrue(Arrangement.grid.positions(for: [standardSize], in: .zero).isEmpty)
        let odd = Arrangement.bottom.positions(for: [standardSize], in: screen, spacing: -10, margin: -20)
        XCTAssertEqual(odd, [CGPoint(x: 0, y: 0)])
    }
}
