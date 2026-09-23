import SpriteKit
import simd

struct HUDState {
    var speedKts = 0.0, altFt = 0.0, aglFt = 0.0, vsFpm = 0.0, heading = 0.0, pitchDeg = 0.0, rollDeg = 0.0
    var throttle = 0.0, rpm = 0.0, flaps = 0, gearDown = true, gearPos = 1.0, brake = false, gLoad = 1.0
    var stall = 0.0, onGround = true, engineOn = false
    var ringIndex = 0, ringCount = 0, ringTime: Double? = nil, bestTime: Double? = nil
    var mapPos = SIMD2<Float>(0, 0), nextRingMap: SIMD2<Float>? = nil
    var marker: CGPoint? = nil, markerAngle: CGFloat? = nil, markerDist = 0.0
    var camName = "", timeName = "", musicOn = true, assist = true
}

final class HUD {
    let scene: SKScene
    private var size = CGSize.zero
    private let mono = "Menlo-Bold"
    private let display = "AvenirNext-Bold"

    private let instruments = SKNode()
    private let attCrop = SKCropNode()
    private let attRoll = SKNode()
    private let attPitch = SKNode()
    private let rollPointer = SKNode()
    private var labels: [String: SKLabelNode] = [:]
    private let throttleFill = SKSpriteNode(color: .white, size: CGSize(width: 14, height: 1))
    private let gearLamp = SKShapeNode(circleOfRadius: 6)
    private let tape = SKCropNode()
    private let tapeContent = SKNode()
    private var tapeMarks: [(SKNode, Int)] = []
    private let topLeft = SKNode()
    private let map = SKNode()
    private let mapPlane = SKShapeNode()
    private let mapRing = SKShapeNode(circleOfRadius: 5)
    private let mapSize: CGFloat = 210
    private let warning = SKLabelNode()
    private let toast = SKLabelNode()
    private let toastSub = SKLabelNode()
    private let marker = SKShapeNode()
    private let markerLabel = SKLabelNode()
    private let arrow = SKShapeNode()
    let title = SKNode()
    let help = SKNode()
    let pause = SKNode()
    private let hints = SKLabelNode()
    private var toastUntil = 0.0

    init(mapImage: CGImage, ringsMap: [SIMD2<Float>], airports: [(SIMD2<Float>, String)]) {
        scene = SKScene(size: CGSize(width: 1440, height: 900))
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.isUserInteractionEnabled = false

        buildInstruments()
        buildTape()
        buildMap(mapImage, ringsMap, airports)
        buildMessages()
        buildTitle()
        buildHelp()
        buildPause()
        scene.addChild(instruments)
        scene.addChild(tape)
        scene.addChild(topLeft)
        scene.addChild(map)
        scene.addChild(marker)
        scene.addChild(arrow)
        scene.addChild(warning)
        scene.addChild(toast)
        scene.addChild(toastSub)
        scene.addChild(hints)
        scene.addChild(title)
        scene.addChild(help)
        scene.addChild(pause)
        help.isHidden = true
        pause.isHidden = true
    }

    @discardableResult private func label(_ key: String, _ text: String, size: CGFloat, font: String? = nil, color: NSColor = .white, align: SKLabelHorizontalAlignmentMode = .left, parent: SKNode) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font ?? mono)
        l.text = text
        l.fontSize = size
        l.fontColor = color
        l.horizontalAlignmentMode = align
        l.verticalAlignmentMode = .center
        parent.addChild(l)
        if !key.isEmpty { labels[key] = l }
        return l
    }

    private func panel(_ w: CGFloat, _ h: CGFloat) -> SKShapeNode {
        let p = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 14)
        p.fillColor = NSColor(white: 0.02, alpha: 0.42)
        p.strokeColor = NSColor(white: 1, alpha: 0.12)
        p.lineWidth = 1
        return p
    }

    // MARK: Build

    private func buildInstruments() {
        let bg = panel(560, 176)
        instruments.addChild(bg)
        // attitude indicator
        let r: CGFloat = 70
        let mask = SKShapeNode(circleOfRadius: r)
        mask.fillColor = .white
        attCrop.maskNode = mask
        attCrop.position = CGPoint(x: 88, y: 88)
        instruments.addChild(attCrop)
        attCrop.addChild(attRoll)
        attRoll.addChild(attPitch)
        let sky = SKSpriteNode(color: NSColor(srgbRed: 0.18, green: 0.45, blue: 0.85, alpha: 1), size: CGSize(width: 600, height: 600))
        sky.anchorPoint = CGPoint(x: 0.5, y: 0)
        attPitch.addChild(sky)
        let gnd = SKSpriteNode(color: NSColor(srgbRed: 0.5, green: 0.33, blue: 0.16, alpha: 1), size: CGSize(width: 600, height: 600))
        gnd.anchorPoint = CGPoint(x: 0.5, y: 1)
        attPitch.addChild(gnd)
        let hl = SKSpriteNode(color: .white, size: CGSize(width: 600, height: 2))
        attPitch.addChild(hl)
        for deg in stride(from: -30, through: 30, by: 10) where deg != 0 {
            let w: CGFloat = deg % 20 == 0 ? 50 : 30
            let line = SKSpriteNode(color: .white, size: CGSize(width: w, height: 1.5))
            line.position = CGPoint(x: 0, y: CGFloat(deg) * 2.4)
            attPitch.addChild(line)
            if deg % 20 == 0 {
                let t = SKLabelNode(fontNamed: mono)
                t.text = "\(abs(deg))"; t.fontSize = 9; t.fontColor = .white
                t.verticalAlignmentMode = .center
                t.position = CGPoint(x: 36, y: CGFloat(deg) * 2.4)
                attPitch.addChild(t)
            }
        }
        let ringShape = SKShapeNode(circleOfRadius: r)
        ringShape.strokeColor = NSColor(white: 1, alpha: 0.7)
        ringShape.lineWidth = 2
        ringShape.position = attCrop.position
        instruments.addChild(ringShape)
        let wings = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -40, y: 0)); path.addLine(to: CGPoint(x: -14, y: 0)); path.addLine(to: CGPoint(x: 0, y: -9))
        path.addLine(to: CGPoint(x: 14, y: 0)); path.addLine(to: CGPoint(x: 40, y: 0))
        wings.path = path
        wings.strokeColor = NSColor(srgbRed: 1, green: 0.75, blue: 0.1, alpha: 1)
        wings.lineWidth = 4
        wings.lineCap = .round
        wings.position = attCrop.position
        instruments.addChild(wings)
        let tri = SKShapeNode()
        let tp = CGMutablePath()
        tp.move(to: CGPoint(x: 0, y: r - 2)); tp.addLine(to: CGPoint(x: -6, y: r - 13)); tp.addLine(to: CGPoint(x: 6, y: r - 13)); tp.closeSubpath()
        tri.path = tp
        tri.fillColor = .white; tri.strokeColor = .clear
        rollPointer.addChild(tri)
        rollPointer.position = attCrop.position
        instruments.addChild(rollPointer)

        // readouts
        let col1: CGFloat = 178, col2: CGFloat = 372
        label("", "AIRSPEED", size: 10, color: NSColor(white: 1, alpha: 0.55), parent: instruments).position = CGPoint(x: col1, y: 152)
        label("spd", "0", size: 30, parent: instruments).position = CGPoint(x: col1, y: 128)
        label("", "ALTITUDE", size: 10, color: NSColor(white: 1, alpha: 0.55), parent: instruments).position = CGPoint(x: col2, y: 152)
        label("alt", "0", size: 30, parent: instruments).position = CGPoint(x: col2, y: 128)
        label("vs", "", size: 13, parent: instruments).position = CGPoint(x: col2, y: 102)
        label("agl", "", size: 13, color: NSColor(white: 1, alpha: 0.7), parent: instruments).position = CGPoint(x: col2, y: 84)
        label("gload", "", size: 13, parent: instruments).position = CGPoint(x: col1, y: 102)
        label("hdgsmall", "", size: 13, color: NSColor(white: 1, alpha: 0.7), parent: instruments).position = CGPoint(x: col1, y: 84)

        // throttle
        let tbg = SKSpriteNode(color: NSColor(white: 1, alpha: 0.12), size: CGSize(width: 14, height: 120))
        tbg.anchorPoint = CGPoint(x: 0.5, y: 0)
        tbg.position = CGPoint(x: 530, y: 34)
        instruments.addChild(tbg)
        throttleFill.anchorPoint = CGPoint(x: 0.5, y: 0)
        throttleFill.position = tbg.position
        throttleFill.color = NSColor(srgbRed: 0.3, green: 0.9, blue: 1, alpha: 1)
        instruments.addChild(throttleFill)
        label("thr", "THR", size: 10, color: NSColor(white: 1, alpha: 0.7), align: .center, parent: instruments).position = CGPoint(x: 530, y: 20)

        // status row
        label("flaps", "FLAPS 0°", size: 12, parent: instruments).position = CGPoint(x: col1, y: 50)
        gearLamp.position = CGPoint(x: col1 + 110, y: 50)
        gearLamp.lineWidth = 0
        instruments.addChild(gearLamp)
        label("gear", "GEAR", size: 12, parent: instruments).position = CGPoint(x: col1 + 122, y: 50)
        label("brake", "", size: 12, color: NSColor(srgbRed: 1, green: 0.4, blue: 0.3, alpha: 1), parent: instruments).position = CGPoint(x: col1 + 214, y: 50)
        label("rpm", "", size: 12, color: NSColor(white: 1, alpha: 0.7), parent: instruments).position = CGPoint(x: col1, y: 26)
        label("mode", "", size: 11, color: NSColor(white: 1, alpha: 0.5), parent: instruments).position = CGPoint(x: col1 + 122, y: 26)
    }

    private func buildTape() {
        let w: CGFloat = 420, h: CGFloat = 40
        let mask = SKSpriteNode(color: .white, size: CGSize(width: w, height: h))
        tape.maskNode = mask
        let bg = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 10)
        bg.fillColor = NSColor(white: 0.02, alpha: 0.4)
        bg.strokeColor = .clear
        tape.addChild(bg)
        tape.addChild(tapeContent)
        for deg in stride(from: 0, to: 360, by: 5) {
            let n = SKNode()
            let tick = SKSpriteNode(color: NSColor(white: 1, alpha: 0.8), size: CGSize(width: 1.5, height: deg % 10 == 0 ? 10 : 5))
            tick.position = CGPoint(x: 0, y: -14)
            n.addChild(tick)
            if deg % 30 == 0 {
                let l = SKLabelNode(fontNamed: mono)
                let names = [0: "N", 90: "E", 180: "S", 270: "W"]
                l.text = names[deg] ?? String(format: "%02d", deg / 10)
                l.fontSize = names[deg] != nil ? 16 : 12
                l.fontColor = names[deg] != nil ? NSColor(srgbRed: 1, green: 0.8, blue: 0.3, alpha: 1) : .white
                l.verticalAlignmentMode = .center
                l.position = CGPoint(x: 0, y: 4)
                n.addChild(l)
            }
            tapeContent.addChild(n)
            tapeMarks.append((n, deg))
        }
        let caret = SKShapeNode()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -h / 2 + 12)); p.addLine(to: CGPoint(x: -6, y: -h / 2)); p.addLine(to: CGPoint(x: 6, y: -h / 2)); p.closeSubpath()
        caret.path = p
        caret.fillColor = NSColor(srgbRed: 1, green: 0.75, blue: 0.1, alpha: 1)
        caret.strokeColor = .clear
        tape.addChild(caret)
    }

    private func buildMap(_ img: CGImage, _ rings: [SIMD2<Float>], _ airports: [(SIMD2<Float>, String)]) {
        let bg = panel(mapSize + 16, mapSize + 16)
        bg.position = CGPoint(x: -mapSize / 2 - 8, y: -mapSize / 2 - 8)
        map.addChild(bg)
        let sprite = SKSpriteNode(texture: SKTexture(cgImage: img), size: CGSize(width: mapSize, height: mapSize))
        map.addChild(sprite)
        for r in rings {
            let dot = SKShapeNode(circleOfRadius: 2)
            dot.fillColor = NSColor(srgbRed: 1, green: 0.62, blue: 0.12, alpha: 0.8)
            dot.strokeColor = .clear
            dot.position = mapPoint(r)
            map.addChild(dot)
        }
        for (p, code) in airports {
            let l = SKLabelNode(fontNamed: mono)
            l.text = code; l.fontSize = 9; l.fontColor = .white
            l.position = mapPoint(p) + CGPoint(x: 16, y: -3)
            map.addChild(l)
        }
        mapRing.strokeColor = NSColor(srgbRed: 0.2, green: 1, blue: 0.95, alpha: 1)
        mapRing.lineWidth = 2
        mapRing.fillColor = .clear
        map.addChild(mapRing)
        let pp = CGMutablePath()
        pp.move(to: CGPoint(x: 0, y: 8)); pp.addLine(to: CGPoint(x: -5, y: -6)); pp.addLine(to: CGPoint(x: 0, y: -3)); pp.addLine(to: CGPoint(x: 5, y: -6)); pp.closeSubpath()
        mapPlane.path = pp
        mapPlane.fillColor = NSColor(srgbRed: 1, green: 0.9, blue: 0.2, alpha: 1)
        mapPlane.strokeColor = .black
        mapPlane.lineWidth = 1
        map.addChild(mapPlane)
    }

    private func mapPoint(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(p.x / Terrain.size) * mapSize, y: -CGFloat(p.y / Terrain.size) * mapSize)
    }

    private func buildMessages() {
        warning.fontName = display
        warning.fontSize = 34
        warning.fontColor = NSColor(srgbRed: 1, green: 0.25, blue: 0.2, alpha: 1)
        warning.verticalAlignmentMode = .center
        toast.fontName = display
        toast.fontSize = 30
        toast.verticalAlignmentMode = .center
        toast.alpha = 0
        toastSub.fontName = "AvenirNext-DemiBold"
        toastSub.fontSize = 17
        toastSub.verticalAlignmentMode = .center
        toastSub.alpha = 0
        let d = CGMutablePath()
        d.move(to: CGPoint(x: 0, y: 22)); d.addLine(to: CGPoint(x: 22, y: 0)); d.addLine(to: CGPoint(x: 0, y: -22)); d.addLine(to: CGPoint(x: -22, y: 0)); d.closeSubpath()
        marker.path = d
        marker.strokeColor = NSColor(srgbRed: 0.2, green: 1, blue: 0.95, alpha: 0.9)
        marker.lineWidth = 2
        marker.fillColor = .clear
        markerLabel.fontName = mono
        markerLabel.fontSize = 12
        markerLabel.fontColor = NSColor(srgbRed: 0.2, green: 1, blue: 0.95, alpha: 1)
        markerLabel.position = CGPoint(x: 0, y: -40)
        marker.addChild(markerLabel)
        let a = CGMutablePath()
        a.move(to: CGPoint(x: 16, y: 0)); a.addLine(to: CGPoint(x: -10, y: 12)); a.addLine(to: CGPoint(x: -4, y: 0)); a.addLine(to: CGPoint(x: -10, y: -12)); a.closeSubpath()
        arrow.path = a
        arrow.fillColor = NSColor(srgbRed: 0.2, green: 1, blue: 0.95, alpha: 0.85)
        arrow.strokeColor = .clear
        hints.fontName = mono
        hints.fontSize = 11
        hints.fontColor = NSColor(white: 1, alpha: 0.5)
        hints.horizontalAlignmentMode = .right
        label("rings", "", size: 15, parent: topLeft).position = CGPoint(x: 18, y: -22)
        label("time", "", size: 13, color: NSColor(white: 1, alpha: 0.75), parent: topLeft).position = CGPoint(x: 18, y: -44)
        label("best", "", size: 11, color: NSColor(white: 1, alpha: 0.55), parent: topLeft).position = CGPoint(x: 18, y: -63)
    }

    private func buildTitle() {
        let shade = SKSpriteNode(color: NSColor(white: 0, alpha: 0.35), size: CGSize(width: 4000, height: 4000))
        title.addChild(shade)
        let t = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        t.text = "S K Y B O U N D"
        t.fontSize = 84
        t.fontColor = .white
        t.position = CGPoint(x: 0, y: 130)
        title.addChild(t)
        let s = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        s.text = "ISLAND FLIGHT SIMULATOR"
        s.fontSize = 20
        s.fontColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.45, alpha: 1)
        s.position = CGPoint(x: 0, y: 92)
        title.addChild(s)
        let lines = [
            ("W / S  or  ↑ / ↓", "pitch (nose down / up)"), ("A / D  or  ← / →", "roll"), ("Q / E", "rudder & steering"),
            ("SHIFT / CTRL", "throttle up / down"), ("F / V", "flaps down / up"), ("G", "landing gear"), ("SPACE", "brakes (hold)"),
            ("C", "change camera"), ("drag / scroll", "look around / zoom"), ("H", "all controls"),
        ]
        for (i, l) in lines.enumerated() {
            let k = SKLabelNode(fontNamed: mono)
            k.text = l.0; k.fontSize = 15; k.fontColor = NSColor(srgbRed: 0.5, green: 0.9, blue: 1, alpha: 1)
            k.horizontalAlignmentMode = .right
            k.position = CGPoint(x: -14, y: 30 - CGFloat(i) * 24)
            title.addChild(k)
            let v = SKLabelNode(fontNamed: "AvenirNext-Medium")
            v.text = l.1; v.fontSize = 15; v.fontColor = .white
            v.horizontalAlignmentMode = .left
            v.position = CGPoint(x: 14, y: 30 - CGFloat(i) * 24)
            title.addChild(v)
        }
        let go = SKLabelNode(fontNamed: "AvenirNext-Bold")
        go.text = "PRESS  SPACE  TO  START  THE  ENGINE"
        go.fontSize = 22
        go.fontColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1)
        go.position = CGPoint(x: 0, y: -250)
        go.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))
        title.addChild(go)
        let tip = SKLabelNode(fontNamed: "AvenirNext-Medium")
        tip.text = "Take off from Harbor Field, fly the 15-ring island course, land at Summit Strip if you dare."
        tip.fontSize = 14
        tip.fontColor = NSColor(white: 1, alpha: 0.7)
        tip.position = CGPoint(x: 0, y: -285)
        title.addChild(tip)
    }

    private func buildHelp() {
        let bg = SKShapeNode(rect: CGRect(x: -330, y: -250, width: 660, height: 500), cornerRadius: 18)
        bg.fillColor = NSColor(white: 0.02, alpha: 0.8)
        bg.strokeColor = NSColor(white: 1, alpha: 0.15)
        help.addChild(bg)
        let h = SKLabelNode(fontNamed: display)
        h.text = "CONTROLS"; h.fontSize = 24; h.position = CGPoint(x: 0, y: 205)
        help.addChild(h)
        let rows = [
            ("W S / ↑ ↓", "pitch"), ("A D / ← →", "roll"), ("Q E", "rudder / nose-wheel"), ("SHIFT CTRL  or  = -", "throttle"),
            ("F / V", "flaps extend / retract"), ("G", "gear up / down"), ("SPACE", "wheel brakes"), ("C", "camera: chase · cockpit · fly-by · orbit"),
            ("mouse drag · scroll", "look around · zoom"), ("X", "air-show smoke"), ("T", "time of day"), ("M", "music on / off"),
            ("L", "wing leveller assist"), ("I", "invert pitch"), ("R", "restart at Harbor Field"), ("2 / 3", "air start: course / Summit approach"),
            ("N", "reset ring course"), ("P / ESC", "pause"), ("⌘F", "full screen"),
        ]
        for (i, r) in rows.enumerated() {
            let k = SKLabelNode(fontNamed: mono)
            k.text = r.0; k.fontSize = 13; k.fontColor = NSColor(srgbRed: 0.5, green: 0.9, blue: 1, alpha: 1)
            k.horizontalAlignmentMode = .right
            k.position = CGPoint(x: -20, y: 170 - CGFloat(i) * 21.5)
            help.addChild(k)
            let v = SKLabelNode(fontNamed: "AvenirNext-Medium")
            v.text = r.1; v.fontSize = 13; v.fontColor = .white
            v.horizontalAlignmentMode = .left
            v.position = CGPoint(x: 0, y: 170 - CGFloat(i) * 21.5)
            help.addChild(v)
        }
    }

    private func buildPause() {
        let shade = SKSpriteNode(color: NSColor(white: 0, alpha: 0.45), size: CGSize(width: 4000, height: 4000))
        pause.addChild(shade)
        let t = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        t.text = "PAUSED"; t.fontSize = 60; t.position = CGPoint(x: 0, y: 10)
        pause.addChild(t)
        let s = SKLabelNode(fontNamed: "AvenirNext-Medium")
        s.text = "P to resume  ·  H for controls"; s.fontSize = 17; s.fontColor = NSColor(white: 1, alpha: 0.7)
        s.position = CGPoint(x: 0, y: -30)
        pause.addChild(s)
    }

    // MARK: Runtime

    private func layout(_ s: CGSize) {
        size = s
        scene.size = s
        instruments.position = CGPoint(x: 18, y: 18)
        tape.position = CGPoint(x: s.width / 2, y: s.height - 36)
        topLeft.position = CGPoint(x: 0, y: s.height)
        map.position = CGPoint(x: s.width - mapSize / 2 - 26, y: s.height - mapSize / 2 - 26)
        warning.position = CGPoint(x: s.width / 2, y: s.height * 0.62)
        toast.position = CGPoint(x: s.width / 2, y: s.height * 0.74)
        toastSub.position = CGPoint(x: s.width / 2, y: s.height * 0.74 - 32)
        hints.position = CGPoint(x: s.width - 20, y: 20)
        title.position = CGPoint(x: s.width / 2, y: s.height / 2 + 40)
        help.position = CGPoint(x: s.width / 2, y: s.height / 2)
        pause.position = CGPoint(x: s.width / 2, y: s.height / 2)
    }

    private func set(_ key: String, _ text: String, _ color: NSColor? = nil) {
        guard let l = labels[key] else { return }
        if l.text != text { l.text = text }
        if let c = color, l.fontColor != c { l.fontColor = c }
    }

    func showToast(_ text: String, sub: String = "", color: NSColor = .white, duration: Double = 3, now: Double) {
        toast.text = text
        toast.fontColor = color
        toastSub.text = sub
        toast.alpha = 1
        toastSub.alpha = sub.isEmpty ? 0 : 1
        toastUntil = now + duration
    }

    func update(_ st: HUDState, viewSize: CGSize, now: Double, flying: Bool) {
        if viewSize != size && viewSize.width > 10 { layout(viewSize) }
        let showHUD = flying
        instruments.isHidden = !showHUD
        tape.isHidden = !showHUD
        topLeft.isHidden = !showHUD
        map.isHidden = !showHUD
        hints.isHidden = !showHUD

        if toastUntil > 0 {
            let left = toastUntil - now
            let a = CGFloat(clampd(left / 0.6, 0, 1))
            toast.alpha = a
            toastSub.alpha = toastSub.text?.isEmpty == false ? a : 0
            if left <= 0 { toastUntil = 0 }
        }
        guard showHUD else { warning.text = ""; marker.isHidden = true; arrow.isHidden = true; return }

        attRoll.zRotation = CGFloat(st.rollDeg * .pi / 180)
        rollPointer.zRotation = CGFloat(st.rollDeg * .pi / 180)
        attPitch.position = CGPoint(x: 0, y: -CGFloat(clampd(st.pitchDeg, -80, 80)) * 2.4)

        set("spd", String(format: "%3.0f kt", st.speedKts))
        set("alt", String(format: "%5.0f ft", st.altFt))
        let vsColor: NSColor = st.vsFpm < -1500 ? NSColor(srgbRed: 1, green: 0.4, blue: 0.3, alpha: 1) : .white
        set("vs", String(format: "V/S %+5.0f fpm", (st.vsFpm / 10).rounded() * 10), vsColor)
        set("agl", st.aglFt < 2500 ? String(format: "RADAR %4.0f ft", max(st.aglFt, 0)) : "")
        let gColor: NSColor = st.gLoad > 4 || st.gLoad < -1 ? NSColor(srgbRed: 1, green: 0.5, blue: 0.3, alpha: 1) : .white
        set("gload", String(format: "G %+.1f", st.gLoad), gColor)
        set("hdgsmall", String(format: "HDG %03.0f°", st.heading))
        throttleFill.size = CGSize(width: 14, height: max(1, 120 * st.throttle))
        set("thr", String(format: "%3.0f%%", st.throttle * 100))
        set("flaps", "FLAPS \(st.flaps * 10)°", st.flaps > 0 ? NSColor(srgbRed: 0.5, green: 0.9, blue: 1, alpha: 1) : .white)
        let moving = st.gearPos > 0.02 && st.gearPos < 0.98
        gearLamp.fillColor = moving ? NSColor(srgbRed: 1, green: 0.7, blue: 0.1, alpha: 1)
            : (st.gearPos >= 0.98 ? NSColor(srgbRed: 0.2, green: 0.95, blue: 0.3, alpha: 1) : NSColor(white: 0.4, alpha: 1))
        set("gear", moving ? "GEAR IN TRANSIT" : (st.gearPos >= 0.98 ? "GEAR DOWN" : "GEAR UP"))
        set("brake", st.brake ? "BRAKES" : "")
        set("rpm", st.engineOn ? String(format: "RPM %4.0f", 600 + st.rpm * 2100) : "ENGINE OFF")
        set("mode", "\(st.camName) · \(st.timeName)\(st.assist ? "" : " · MANUAL")")

        // heading tape: 3 px per degree
        let pxDeg: CGFloat = 3.2
        for (n, deg) in tapeMarks {
            var d = Double(deg) - st.heading
            while d > 180 { d -= 360 }
            while d < -180 { d += 360 }
            n.position = CGPoint(x: CGFloat(d) * pxDeg, y: 0)
            n.isHidden = abs(d) > 70
        }

        // rings
        if st.ringIndex < st.ringCount {
            set("rings", "RING \(st.ringIndex + 1) / \(st.ringCount)")
        } else {
            set("rings", "COURSE COMPLETE", NSColor(srgbRed: 0.3, green: 1, blue: 0.5, alpha: 1))
        }
        set("time", st.ringTime.map { "TIME  " + Self.fmt($0) } ?? "fly through the cyan ring to start the clock")
        set("best", st.bestTime.map { "BEST  " + Self.fmt($0) } ?? "")

        // minimap
        mapPlane.position = mapPoint(st.mapPos)
        mapPlane.zRotation = -CGFloat(st.heading * .pi / 180)
        if let r = st.nextRingMap {
            mapRing.isHidden = false
            mapRing.position = mapPoint(r)
            mapRing.setScale(1 + 0.3 * CGFloat(sin(now * 5)))
        } else { mapRing.isHidden = true }

        // ring marker
        if let m = st.marker {
            marker.isHidden = false
            arrow.isHidden = true
            marker.position = m
            marker.zRotation = 0
            markerLabel.text = st.markerDist > 1000 ? String(format: "%.1f km", st.markerDist / 1000) : String(format: "%.0f m", st.markerDist)
        } else if let a = st.markerAngle {
            marker.isHidden = true
            arrow.isHidden = false
            let rx = size.width * 0.42, ry = size.height * 0.4
            arrow.position = CGPoint(x: size.width / 2 + cos(a) * rx, y: size.height / 2 + sin(a) * ry)
            arrow.zRotation = a
        } else {
            marker.isHidden = true
            arrow.isHidden = true
        }

        // warnings
        var w = ""
        if st.stall > 0.5 && !st.onGround { w = "STALL" }
        else if !st.onGround && st.aglFt < 400 && st.vsFpm < -2200 { w = "PULL UP" }
        else if !st.onGround && st.aglFt < 300 && !st.gearDown && st.speedKts < 95 && st.vsFpm < -200 { w = "GEAR UP!" }
        warning.text = w
        warning.alpha = w.isEmpty ? 0 : (Int(now * 4) % 2 == 0 ? 1 : 0.35)

        hints.text = "H controls · C camera · M music \(st.musicOn ? "on" : "off") · T time · P pause"
    }

    static func fmt(_ t: Double) -> String {
        let m = Int(t) / 60, s = t - Double(m * 60)
        return String(format: "%d:%05.2f", m, s)
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
