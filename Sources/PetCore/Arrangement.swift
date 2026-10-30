import CoreGraphics

/// How a group of pet windows is placed inside a screen's visible frame.
///
/// Coordinates use AppKit's bottom-left origin, and `visibleFrame` is expected
/// to come from `NSScreen.visibleFrame` so the menu bar and Dock are already
/// excluded. Every returned origin keeps the whole window on screen whenever
/// that window fits.
public enum Arrangement: String, CaseIterable, Codable, Sendable {
    /// The original packed layout: rows filled right-to-left, bottom-up.
    case grid
    /// A vertical stack hugging the left edge, flowing top-to-bottom.
    case left
    /// A vertical stack hugging the right edge, flowing top-to-bottom.
    case right
    /// A horizontal row hugging the top edge, flowing left-to-right.
    case top
    /// A horizontal row hugging the bottom edge, flowing left-to-right.
    case bottom
    /// A compact block centered in the visible frame.
    case center
    /// Independent random positions spread across the whole visible frame.
    case random

    public var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .left: return "Align left"
        case .right: return "Align right"
        case .top: return "Align top"
        case .bottom: return "Align bottom"
        case .center: return "Center"
        case .random: return "Random scatter"
        }
    }

    /// Returns one origin per window size. The result always has the same
    /// count as `sizes`.
    ///
    /// `randomSource` exists so tests can make `random` deterministic; it
    /// should return a value inside the supplied range.
    public func positions(
        for sizes: [CGSize],
        in visibleFrame: CGRect,
        spacing: CGFloat = 8,
        margin: CGFloat = 16,
        randomSource: (ClosedRange<CGFloat>) -> CGFloat = { CGFloat.random(in: $0) }
    ) -> [CGPoint] {
        guard !sizes.isEmpty,
              visibleFrame.minX.isFinite, visibleFrame.minY.isFinite,
              visibleFrame.width.isFinite, visibleFrame.height.isFinite,
              visibleFrame.width > 0, visibleFrame.height > 0 else { return [] }
        let gap = spacing.isFinite ? max(0, spacing) : 0
        let inset = margin.isFinite ? max(0, margin) : 0
        let windows = sizes.map { size in
            CGSize(width: size.width.isFinite && size.width > 0 ? size.width : 1,
                   height: size.height.isFinite && size.height > 0 ? size.height : 1)
        }
        switch self {
        case .grid: return Self.gridLayout(windows, in: visibleFrame, gap: gap, margin: inset)
        case .left: return Self.columnLayout(windows, in: visibleFrame, gap: gap, margin: inset, fromRight: false)
        case .right: return Self.columnLayout(windows, in: visibleFrame, gap: gap, margin: inset, fromRight: true)
        case .top: return Self.rowLayout(windows, in: visibleFrame, gap: gap, margin: inset, atTop: true)
        case .bottom: return Self.rowLayout(windows, in: visibleFrame, gap: gap, margin: inset, atTop: false)
        case .center: return Self.centerLayout(windows, in: visibleFrame, gap: gap, margin: inset)
        case .random: return Self.randomLayout(windows, in: visibleFrame, gap: gap, margin: inset, randomSource: randomSource)
        }
    }

    private static func gridLayout(_ sizes: [CGSize], in frame: CGRect,
                                   gap: CGFloat, margin: CGFloat) -> [CGPoint] {
        let minX = frame.minX + margin
        let maxX = frame.maxX - margin
        var cursorX = maxX
        var cursorY = frame.minY + margin
        var rowHeight: CGFloat = 0
        var rowHasPet = false
        return sizes.map { size in
            if rowHasPet, cursorX - size.width < minX {
                cursorX = maxX
                cursorY += rowHeight + gap
                rowHeight = 0
                rowHasPet = false
            }
            cursorX -= size.width
            let origin = clamped(CGPoint(x: cursorX, y: cursorY), size: size, in: frame)
            cursorX -= gap
            rowHeight = max(rowHeight, size.height)
            rowHasPet = true
            return origin
        }
    }

    /// Stacks pets into columns that are aligned to the chosen vertical edge.
    /// Extra columns grow inward when the screen height is exhausted.
    private static func columnLayout(_ sizes: [CGSize], in frame: CGRect,
                                     gap: CGFloat, margin: CGFloat,
                                     fromRight: Bool) -> [CGPoint] {
        let edge = fromRight ? frame.maxX - margin : frame.minX + margin
        var columnEdge = edge
        var cursorY = frame.maxY - margin
        var columnWidth: CGFloat = 0
        var columnHasPet = false
        return sizes.map { size in
            let nextY = cursorY - size.height
            if columnHasPet, nextY < frame.minY + margin {
                // Extra columns grow inward when the screen height is exhausted.
                columnEdge += fromRight ? -(columnWidth + gap) : columnWidth + gap
                cursorY = frame.maxY - margin
                columnWidth = 0
                columnHasPet = false
            }
            cursorY -= size.height
            let x = fromRight ? columnEdge - size.width : columnEdge
            let origin = clamped(CGPoint(x: x, y: cursorY), size: size, in: frame)
            cursorY -= gap
            columnWidth = max(columnWidth, size.width)
            columnHasPet = true
            return origin
        }
    }

    /// Lays pets into rows aligned to the chosen horizontal edge. Extra rows
    /// grow inward when the screen width is exhausted.
    private static func rowLayout(_ sizes: [CGSize], in frame: CGRect,
                                  gap: CGFloat, margin: CGFloat,
                                  atTop: Bool) -> [CGPoint] {
        let edge = atTop ? frame.maxY - margin : frame.minY + margin
        var cursorX = frame.minX + margin
        var rowEdge = edge
        var rowHeight: CGFloat = 0
        var rowHasPet = false
        return sizes.map { size in
            if rowHasPet, cursorX + size.width > frame.maxX - margin {
                cursorX = frame.minX + margin
                rowEdge += atTop ? -(rowHeight + gap) : rowHeight + gap
                rowHeight = 0
                rowHasPet = false
            }
            let y = atTop ? rowEdge - size.height : rowEdge
            let origin = clamped(CGPoint(x: cursorX, y: y), size: size, in: frame)
            cursorX += size.width + gap
            rowHeight = max(rowHeight, size.height)
            rowHasPet = true
            return origin
        }
    }

    private static func centerLayout(_ sizes: [CGSize], in frame: CGRect,
                                     gap: CGFloat, margin: CGFloat) -> [CGPoint] {
        let count = sizes.count
        let maxWidth = sizes.map(\.width).max() ?? 1
        let maxHeight = sizes.map(\.height).max() ?? 1
        let usableWidth = max(maxWidth, frame.width - margin * 2)
        let usableHeight = max(maxHeight, frame.height - margin * 2)
        let maxColumns = max(1, Int(((usableWidth + gap) / (maxWidth + gap)).rounded(.down)))
        let maxRows = max(1, Int(((usableHeight + gap) / (maxHeight + gap)).rounded(.down)))
        var columns = min(maxColumns, max(1, Int(Double(count).squareRoot().rounded(.up))))
        func rowCount() -> Int { Int((Double(count) / Double(columns)).rounded(.up)) }
        while rowCount() > maxRows, columns < maxColumns { columns += 1 }
        let rows = rowCount()
        let blockWidth = CGFloat(columns) * maxWidth + CGFloat(columns - 1) * gap
        let blockHeight = CGFloat(rows) * maxHeight + CGFloat(rows - 1) * gap
        let left = frame.midX - blockWidth / 2
        let top = frame.midY + blockHeight / 2
        let raw = sizes.enumerated().map { index, size in
            let row = index / columns
            let column = index % columns
            let x = left + CGFloat(column) * (maxWidth + gap) + (maxWidth - size.width) / 2
            let y = top - CGFloat(row) * (maxHeight + gap) - maxHeight + (maxHeight - size.height) / 2
            return CGPoint(x: x, y: y)
        }
        // Center the block of cells, then nudge it so the actual painted
        // bounds (rather than the widest/tallest cells) sit in the middle.
        let bounds = zip(raw, sizes).reduce(CGRect.null) { partial, item in
            partial.union(CGRect(origin: item.0, size: item.1))
        }
        let dx = frame.midX - bounds.midX
        let dy = frame.midY - bounds.midY
        return zip(raw, sizes).map { clamped(CGPoint(x: $0.x + dx, y: $0.y + dy), size: $1, in: frame) }
    }

    private static func randomLayout(_ sizes: [CGSize], in frame: CGRect,
                                     gap: CGFloat, margin: CGFloat,
                                     randomSource: (ClosedRange<CGFloat>) -> CGFloat) -> [CGPoint] {
        var placed: [CGRect] = []
        return sizes.map { size in
            let lowX = frame.minX + margin
            let highX = max(lowX, frame.maxX - margin - size.width)
            let lowY = frame.minY + margin
            let highY = max(lowY, frame.maxY - margin - size.height)
            let xRange = lowX...highX
            let yRange = lowY...highY
            var chosen: CGPoint?
            // Rejection sampling keeps the scatter random while avoiding
            // overlaps; the limit prevents pathological loops on tiny screens.
            for _ in 0..<500 {
                let x = bounded(randomSource(xRange), to: xRange)
                let y = bounded(randomSource(yRange), to: yRange)
                let candidate = CGRect(x: x, y: y, width: size.width, height: size.height)
                if !placed.contains(where: { $0.insetBy(dx: -gap, dy: -gap).intersects(candidate) }) {
                    chosen = CGPoint(x: x, y: y)
                    break
                }
            }
            let origin = chosen ?? clamped(
                CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                size: size, in: frame
            )
            placed.append(CGRect(origin: origin, size: size))
            return origin
        }
    }

    private static func bounded(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value.isFinite ? value : range.lowerBound, range.lowerBound), range.upperBound)
    }

    private static func clamped(_ point: CGPoint, size: CGSize, in frame: CGRect) -> CGPoint {
        let maxX = max(frame.minX, frame.maxX - size.width)
        let maxY = max(frame.minY, frame.maxY - size.height)
        return CGPoint(x: min(max(point.x, frame.minX), maxX),
                       y: min(max(point.y, frame.minY), maxY))
    }
}
