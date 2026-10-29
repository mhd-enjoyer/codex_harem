import AppKit
import PetCore

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class PetView: NSView {
    let pet: LoadedPet
    var instance: PetInstance
    var status: PetStatus = .idle { didSet { if status != oldValue { cancelWalking(); statusStarted = Date(); animationStart = statusStarted; gesture = nil } } }
    var onPositionChange: ((NSPoint, Bool) -> Void)?
    var menuBuilder: (() -> NSMenu)?
    private var timer: Timer?
    private var animationStart = Date()
    private var statusStarted = Date()
    private var gesture: String?
    private var gestureEnd = Date.distantPast
    private var nextGesture = Date().addingTimeInterval(Double.random(in: 8...20))
    private var dragAnimation: String?
    private var walk: WalkingRoute?
    private var walkStarted = Date()
    private var nextWalk = Date()
    private var wasWalkAllowed = false
    private var dragStart: NSPoint?
    private var originalOrigin = NSPoint.zero
    private var hovering = false
    private var frames: [Int: CGImage] = [:]
    private var currentFrame = -1
    private var tracking: NSTrackingArea?
    init(pet: LoadedPet, instance: PetInstance) {
        self.pet = pet; self.instance = instance
        super.init(frame: NSRect(x: 0, y: 0, width: instance.size, height: instance.size + 24))
        toolTip = "\(pet.manifest.displayName) · drag to move, right-click for options"
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel(pet.manifest.displayName)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func stop() { timer?.invalidate(); timer = nil; walk = nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; cancelWalking(); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func menu(for event: NSEvent) -> NSMenu? { cancelWalking(); return menuBuilder?() }
    override func mouseDown(with event: NSEvent) {
        cancelWalking()
        dragStart = NSEvent.mouseLocation; originalOrigin = window?.frame.origin ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = NSEvent.mouseLocation
        dragAnimation = point.x >= dragStart.x ? "walkRight" : "walkLeft"
        window?.setFrameOrigin(NSPoint(x: originalOrigin.x + point.x - dragStart.x, y: originalOrigin.y + point.y - dragStart.y))
    }
    override func mouseUp(with event: NSEvent) {
        if let dragStart, hypot(NSEvent.mouseLocation.x - dragStart.x, NSEvent.mouseLocation.y - dragStart.y) < 4 {
            playGesture("wave", now: Date())
        }
        self.dragStart = nil; dragAnimation = nil
        keepOnScreen()
        recordPosition(save: true)
    }
    private func recordPosition(save: Bool) {
        guard let origin = window?.frame.origin else { return }
        instance.x = origin.x; instance.y = origin.y
        onPositionChange?(origin, save)
    }
    func cancelWalking() {
        guard walk != nil else { return }
        walk = nil; recordPosition(save: true)
        nextWalk = Date().addingTimeInterval(Double.random(in: 8...18))
    }
    func resetPlayback() {
        cancelWalking(); gesture = nil; animationStart = Date()
    }
    private func playGesture(_ name: String, now: Date) {
        gesture = name; animationStart = now
        let repeats = name == "wave" ? 2.0 : 1.0
        gestureEnd = now.addingTimeInterval(pet.manifest.animation(name).cycleDuration / instance.playbackSpeed * repeats)
    }
    private func updateWalking(now: Date, allowed: Bool) {
        guard allowed, let window, let screen = window.screen else {
            cancelWalking(); wasWalkAllowed = false; return
        }
        if !wasWalkAllowed { nextWalk = now.addingTimeInterval(Double.random(in: 1...3)) }
        wasWalkAllowed = true
        if let walk {
            let elapsed = now.timeIntervalSince(walkStarted)
            window.setFrameOrigin(walk.position(at: elapsed))
            keepOnScreen()
            // Update the model as we move; write layout to disk only on stopping.
            recordPosition(save: false)
            if elapsed >= walk.duration { cancelWalking() }
        } else if now >= nextWalk {
            walk = WalkingRoute(origin: window.frame.origin, windowSize: window.frame.size,
                                visibleFrame: screen.visibleFrame, distance: Double.random(in: 70...180),
                                direction: Bool.random() ? 1 : -1, speed: 32 * instance.playbackSpeed)
            walkStarted = now; animationStart = now
            if walk == nil { nextWalk = now.addingTimeInterval(10) }
        }
    }
    func keepOnScreen() {
        guard let window, let screen = NSScreen.screens.max(by: { a, b in
            a.visibleFrame.intersection(window.frame).width * a.visibleFrame.intersection(window.frame).height < b.visibleFrame.intersection(window.frame).width * b.visibleFrame.intersection(window.frame).height
        }) else { return }
        let bounds = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: min(max(window.frame.minX, bounds.minX), bounds.maxX - window.frame.width), y: min(max(window.frame.minY, bounds.minY), bounds.maxY - window.frame.height)))
    }
    private func tick() {
        let now = Date()
        if gesture != nil && now > gestureEnd { gesture = nil; animationStart = now }
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let reviewDuration = max(3, pet.manifest.animation("completed").cycleDuration / instance.playbackSpeed * 2)
        let reviewComplete = now.timeIntervalSince(statusStarted) >= reviewDuration
        let resting = status == .idle || (status == .completed && reviewComplete)
        updateWalking(now: now, allowed: instance.walksAround && resting && !reducedMotion && !hovering &&
                      dragStart == nil && gesture == nil && window?.isVisible == true)
        if resting {
            if now > nextGesture && dragStart == nil && walk == nil {
                playGesture(["wave", "hop"].randomElement()!, now: now)
                nextGesture = now.addingTimeInterval(Double.random(in: 12...28))
            }
        }
        let elapsed = now.timeIntervalSince(animationStart)
        var name: String
        switch status {
        case .thinking: name = "working"
        case .waiting: name = "thinking"
        case .working: name = "working"
        case .failed, .interrupted: name = "failed"
        case .completed: name = reviewComplete ? "idle" : "completed"
        default: name = "idle"
        }
        if let gesture, !reducedMotion { name = gesture }
        if let walk, !reducedMotion { name = walk.animationName }
        if let dragAnimation, !reducedMotion { name = dragAnimation }
        var index = pet.manifest.animation(name).frame(at: reducedMotion ? 0 : elapsed, speed: instance.playbackSpeed)
        if pet.manifest.spriteVersionNumber == 2 && name == "idle" && !reducedMotion, let window {
            let delta = NSPoint(x: NSEvent.mouseLocation.x - window.frame.midX, y: NSEvent.mouseLocation.y - window.frame.midY)
            if hypot(delta.x, delta.y) < 500 {
                // v2 look directions run clockwise, starting up, across the last two rows.
                let angle = atan2(delta.x, delta.y)
                let direction = (Int((angle / (2 * .pi) * 16).rounded()) + 16) % 16
                index = 9 * pet.manifest.columns + direction
            }
        }
        if currentFrame != index { currentFrame = index; needsDisplay = true }
        setAccessibilityValue(status.rawValue)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard currentFrame >= 0, let context = NSGraphicsContext.current?.cgContext else { return }
        if frames[currentFrame] == nil { frames[currentFrame] = pet.frame(currentFrame) }
        if let image = frames[currentFrame] {
            let area = NSRect(x: 0, y: 22, width: bounds.width, height: bounds.height - 22)
            let ratio = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
            let rect = NSRect(x: area.midX - CGFloat(image.width) * ratio / 2, y: area.minY, width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
            context.saveGState(); context.interpolationQuality = .high
            if status == .offline { context.setAlpha(0.5) }
            context.draw(image, in: rect); context.restoreGState()
        }
        if hovering || status == .waiting || status == .failed {
            let text = status.rawValue.capitalized as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attributes)
            let pill = NSRect(x: bounds.midX - (size.width + 16) / 2, y: 1, width: size.width + 16, height: 19)
            (status == .failed ? NSColor.systemRed.withAlphaComponent(0.9) : NSColor.black.withAlphaComponent(0.72)).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
            text.draw(at: NSPoint(x: pill.minX + 8, y: pill.minY + 3), withAttributes: attributes)
        }
    }
}
