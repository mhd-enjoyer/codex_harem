import AppKit

enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Codex Harem — horned anime companion"
        return image
    }

    /// Reference-inspired dragon girl: swept horns, long hair, ahoge, and sleepy eyes.
    /// A monochrome template keeps the small silhouette readable on either menu bar.
    static func draw(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(1.05)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Tapered, swept-back horns rather than triangular cat ears.
        for mirrored in [false, true] {
            context.saveGState()
            if mirrored { context.translateBy(x: 22, y: 0); context.scaleBy(x: -1, y: 1) }
            context.move(to: CGPoint(x: 4.7, y: 11.7))
            context.addCurve(to: CGPoint(x: 2.6, y: 18.8), control1: CGPoint(x: 0.7, y: 13.8), control2: CGPoint(x: 3.6, y: 15.6))
            context.addCurve(to: CGPoint(x: 5.8, y: 13.5), control1: CGPoint(x: 5.8, y: 17.2), control2: CGPoint(x: 3.7, y: 16.0))
            context.strokePath()
            context.setLineWidth(0.65)
            context.move(to: CGPoint(x: 2.4, y: 14.3)); context.addLine(to: CGPoint(x: 4.6, y: 15.0))
            context.move(to: CGPoint(x: 2.9, y: 16.2)); context.addLine(to: CGPoint(x: 4.2, y: 16.5))
            context.strokePath()
            context.restoreGState()
        }

        // Long hair frames the face and ends in outward-pointing locks.
        context.move(to: CGPoint(x: 3.3, y: 1.3))
        context.addCurve(to: CGPoint(x: 4.4, y: 10.8), control1: CGPoint(x: 4.5, y: 4.5), control2: CGPoint(x: 2.8, y: 7.3))
        context.addCurve(to: CGPoint(x: 11, y: 15.4), control1: CGPoint(x: 5.5, y: 14.2), control2: CGPoint(x: 8.1, y: 15.4))
        context.addCurve(to: CGPoint(x: 17.6, y: 10.8), control1: CGPoint(x: 13.9, y: 15.4), control2: CGPoint(x: 16.5, y: 14.2))
        context.addCurve(to: CGPoint(x: 18.7, y: 1.3), control1: CGPoint(x: 19.2, y: 7.3), control2: CGPoint(x: 17.5, y: 4.5))
        context.addLine(to: CGPoint(x: 16.6, y: 2.6))
        context.move(to: CGPoint(x: 3.3, y: 1.3)); context.addLine(to: CGPoint(x: 5.4, y: 2.6))
        context.strokePath()

        // Single curled ahoge above the crown.
        context.move(to: CGPoint(x: 11.1, y: 15.5))
        context.addCurve(to: CGPoint(x: 10.2, y: 18.3), control1: CGPoint(x: 14.5, y: 18.1), control2: CGPoint(x: 12.5, y: 20.7))
        context.strokePath()

        // Face and narrow side locks.
        context.move(to: CGPoint(x: 5.9, y: 7.8))
        context.addCurve(to: CGPoint(x: 11, y: 1.7), control1: CGPoint(x: 5.8, y: 4.2), control2: CGPoint(x: 8.4, y: 2.1))
        context.addCurve(to: CGPoint(x: 16.1, y: 7.8), control1: CGPoint(x: 13.6, y: 2.1), control2: CGPoint(x: 16.2, y: 4.2))
        context.move(to: CGPoint(x: 4.6, y: 8.0)); context.addLine(to: CGPoint(x: 4.8, y: 1.1))
        context.move(to: CGPoint(x: 17.4, y: 8.0)); context.addLine(to: CGPoint(x: 17.2, y: 1.1))
        context.strokePath()

        // Center-parted fringe with a long pointed central bang.
        context.move(to: CGPoint(x: 10.7, y: 13.8))
        context.addQuadCurve(to: CGPoint(x: 6.1, y: 9.3), control: CGPoint(x: 7.2, y: 13.0))
        context.addLine(to: CGPoint(x: 7.8, y: 10.0))
        context.move(to: CGPoint(x: 10.8, y: 13.2))
        context.addQuadCurve(to: CGPoint(x: 11.2, y: 7.8), control: CGPoint(x: 8.5, y: 10.3))
        context.addQuadCurve(to: CGPoint(x: 12.6, y: 10.6), control: CGPoint(x: 12.3, y: 8.9))
        context.move(to: CGPoint(x: 11.6, y: 13.8))
        context.addQuadCurve(to: CGPoint(x: 15.9, y: 9.3), control: CGPoint(x: 15, y: 12.3))
        context.strokePath()

        // Low upper lashes and oval irises echo the reference's calm expression.
        context.setLineWidth(1.15)
        context.move(to: CGPoint(x: 6.5, y: 7.7))
        context.addQuadCurve(to: CGPoint(x: 9.1, y: 7.2), control: CGPoint(x: 7.4, y: 8.0))
        context.move(to: CGPoint(x: 12.9, y: 7.2))
        context.addQuadCurve(to: CGPoint(x: 15.5, y: 7.7), control: CGPoint(x: 14.6, y: 8.0))
        context.strokePath()
        context.fillEllipse(in: CGRect(x: 7.2, y: 5.6, width: 1.2, height: 1.8))
        context.fillEllipse(in: CGRect(x: 13.6, y: 5.6, width: 1.2, height: 1.8))
        context.setLineWidth(0.8)
        context.move(to: CGPoint(x: 10.5, y: 3.9)); context.addLine(to: CGPoint(x: 11.5, y: 3.9))
        context.strokePath()
    }
}
