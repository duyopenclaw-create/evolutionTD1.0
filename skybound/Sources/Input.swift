import AppKit
import SceneKit

enum Key {
    static let a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, f: UInt16 = 3, h: UInt16 = 4, g: UInt16 = 5
    static let z: UInt16 = 6, x: UInt16 = 7, c: UInt16 = 8, v: UInt16 = 9, b: UInt16 = 11, q: UInt16 = 12
    static let w: UInt16 = 13, e: UInt16 = 14, r: UInt16 = 15, y: UInt16 = 16, t: UInt16 = 17
    static let one: UInt16 = 18, two: UInt16 = 19, three: UInt16 = 20, four: UInt16 = 21
    static let equals: UInt16 = 24, minus: UInt16 = 27, o: UInt16 = 31, i: UInt16 = 34, p: UInt16 = 35
    static let ret: UInt16 = 36, l: UInt16 = 37, n: UInt16 = 45, m: UInt16 = 46, tab: UInt16 = 48
    static let space: UInt16 = 49, esc: UInt16 = 53
    static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
}

/// Keyboard/mouse state shared between the main thread (events) and the render thread (game loop).
final class InputState {
    private let lock = NSLock()
    private var down = Set<UInt16>()
    private var presses: [UInt16] = []
    private var shiftDown = false, ctrlDown = false
    private var mdx: Float = 0, mdy: Float = 0, scroll: Float = 0
    private var dragFlag = false

    func keyDown(_ k: UInt16, isRepeat: Bool) {
        lock.lock(); defer { lock.unlock() }
        down.insert(k)
        if !isRepeat { presses.append(k) }
    }
    func keyUp(_ k: UInt16) { lock.lock(); down.remove(k); lock.unlock() }
    func setModifiers(shift: Bool, ctrl: Bool) { lock.lock(); shiftDown = shift; ctrlDown = ctrl; lock.unlock() }
    func clear() { lock.lock(); down.removeAll(); shiftDown = false; ctrlDown = false; lock.unlock() }

    func isDown(_ k: UInt16) -> Bool { lock.lock(); defer { lock.unlock() }; return down.contains(k) }
    var shift: Bool { lock.lock(); defer { lock.unlock() }; return shiftDown }
    var ctrl: Bool { lock.lock(); defer { lock.unlock() }; return ctrlDown }

    func drainPresses() -> [UInt16] {
        lock.lock(); defer { lock.unlock() }
        let p = presses
        presses.removeAll()
        return p
    }

    func mouse(dx: Float, dy: Float) { lock.lock(); mdx += dx; mdy += dy; lock.unlock() }
    func addScroll(_ s: Float) { lock.lock(); scroll += s; lock.unlock() }
    func setDragging(_ d: Bool) { lock.lock(); dragFlag = d; lock.unlock() }
    var dragging: Bool { lock.lock(); defer { lock.unlock() }; return dragFlag }
    func takeMouse() -> (Float, Float, Float) {
        lock.lock(); defer { lock.unlock() }
        let r = (mdx, mdy, scroll)
        mdx = 0; mdy = 0; scroll = 0
        return r
    }
}

final class GameView: SCNView {
    let input = InputState()

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with e: NSEvent) {
        if e.modifierFlags.contains(.command) { super.keyDown(with: e); return }
        input.keyDown(e.keyCode, isRepeat: e.isARepeat)
    }
    override func keyUp(with e: NSEvent) { input.keyUp(e.keyCode) }
    override func flagsChanged(with e: NSEvent) {
        input.setModifiers(shift: e.modifierFlags.contains(.shift), ctrl: e.modifierFlags.contains(.control))
    }
    override func mouseDown(with e: NSEvent) { input.setDragging(true) }
    override func mouseUp(with e: NSEvent) { input.setDragging(false) }
    override func mouseDragged(with e: NSEvent) { input.mouse(dx: Float(e.deltaX), dy: Float(e.deltaY)) }
    override func rightMouseDragged(with e: NSEvent) { input.mouse(dx: Float(e.deltaX), dy: Float(e.deltaY)) }
    override func scrollWheel(with e: NSEvent) { input.addScroll(Float(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.02 : 0.25)) }
    override func resignFirstResponder() -> Bool { input.clear(); return super.resignFirstResponder() }
}
