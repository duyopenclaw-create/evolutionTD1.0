import AppKit
import SceneKit

enum Key {
    static let a: UInt16 = 0, s: UInt16 = 1, h: UInt16 = 4, c: UInt16 = 8, v: UInt16 = 9, r: UInt16 = 15, t: UInt16 = 17
    static let ret: UInt16 = 36, m: UInt16 = 46, tab: UInt16 = 48, space: UInt16 = 49, backspace: UInt16 = 51, esc: UInt16 = 53
    static let enter: UInt16 = 76, equals: UInt16 = 24, minus: UInt16 = 27, f: UInt16 = 3, b: UInt16 = 11
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
}

enum Click {
    case floor(SIMD3<Float>)
    case ball(SCNNode)
}

/// Keyboard/mouse state shared between the main thread (events) and the render thread (game loop).
final class InputState {
    private let lock = NSLock()
    private var presses: [(UInt16, Bool)] = []
    private var digits: [Character] = []
    private var clicks: [Click] = []
    private var mdx: Float = 0, mdy: Float = 0, scroll: Float = 0

    func keyDown(_ k: UInt16, shift: Bool, chars: String?) {
        lock.lock(); defer { lock.unlock() }
        if let c = chars?.first, c.isASCII, c.isNumber { digits.append(c); return }
        presses.append((k, shift))
    }
    func drainPresses() -> [(UInt16, Bool)] { lock.lock(); defer { lock.unlock() }; let p = presses; presses.removeAll(); return p }
    func drainDigits() -> [Character] { lock.lock(); defer { lock.unlock() }; let p = digits; digits.removeAll(); return p }
    func addClick(_ c: Click) { lock.lock(); clicks.append(c); lock.unlock() }
    func drainClicks() -> [Click] { lock.lock(); defer { lock.unlock() }; let p = clicks; clicks.removeAll(); return p }

    func mouse(dx: Float, dy: Float) { lock.lock(); mdx += dx; mdy += dy; lock.unlock() }
    func addScroll(_ s: Float) { lock.lock(); scroll += s; lock.unlock() }
    func takeMouse() -> (Float, Float, Float) {
        lock.lock(); defer { lock.unlock() }
        let r = (mdx, mdy, scroll)
        mdx = 0; mdy = 0; scroll = 0
        return r
    }
    func clear() { lock.lock(); presses.removeAll(); digits.removeAll(); lock.unlock() }
}

final class GameView: SCNView {
    let input = InputState()
    var inputEnabled = true
    private var moved: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command) || !inputEnabled { super.keyDown(with: e); return }
        if e.isARepeat && ![Key.up, Key.down, Key.left, Key.right, Key.backspace].contains(e.keyCode) { return }
        input.keyDown(e.keyCode, shift: e.modifierFlags.contains(.shift), chars: e.charactersIgnoringModifiers)
    }
    override func keyUp(with e: NSEvent) {}
    override func mouseDown(with e: NSEvent) { moved = 0 }
    override func mouseDragged(with e: NSEvent) {
        guard inputEnabled else { return }
        moved += abs(e.deltaX) + abs(e.deltaY)
        input.mouse(dx: Float(e.deltaX), dy: Float(e.deltaY))
    }
    override func rightMouseDragged(with e: NSEvent) { mouseDragged(with: e) }
    override func mouseUp(with e: NSEvent) {
        guard inputEnabled, moved < 5 else { return }
        let p = convert(e.locationInWindow, from: nil)
        let hits = hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: 2, .ignoreHiddenNodes: true])
        guard let h = hits.first else { return }
        if h.node.name == "ball" { input.addClick(.ball(h.node)) }
        else { input.addClick(.floor(SIMD3(Float(h.worldCoordinates.x), Float(h.worldCoordinates.y), Float(h.worldCoordinates.z)))) }
    }
    override func scrollWheel(with e: NSEvent) {
        guard inputEnabled else { return }
        input.addScroll(Float(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.01 : 0.12))
    }
    override func magnify(with e: NSEvent) { guard inputEnabled else { return }; input.addScroll(Float(e.magnification) * 2) }
    override func resignFirstResponder() -> Bool { input.clear(); return super.resignFirstResponder() }
}
