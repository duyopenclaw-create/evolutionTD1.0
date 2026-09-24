import SpriteKit

struct HUDState {
    var clock = "1:00 AM"
    var night = 1
    var stash = 0
    var carrying: String? = nil
    var belly: Float = 0.6
    var stamina: Float = 1
    var lives = 3
    var visibility: Float = 0
    var noise: Float = 0
    var threat = ""
    var threatColor = NSColor.white
    var prompt = ""
    var hidden: String? = nil
    var spotted: Float = 0
}

final class HUD {
    let scene: SKScene
    private var size = CGSize(width: 1440, height: 900)
    private let game = SKNode(), title = SKNode(), help = SKNode(), pause = SKNode(), summary = SKNode()
    private var labels: [String: SKLabelNode] = [:]
    private var bars: [String: SKShapeNode] = [:]
    private var lifeDots: [SKShapeNode] = []
    private let eye = SKShapeNode(ellipseOf: CGSize(width: 34, height: 18))
    private let pupil = SKShapeNode(circleOfRadius: 5)
    private let noiseRing = SKShapeNode(circleOfRadius: 10)
    private let toast = SKLabelNode(), toastSub = SKLabelNode()
    private var toastUntil = 0.0
    private let saved = SKLabelNode()
    private var savedUntil = 0.0
    private let fade = SKShapeNode(rect: CGRect(x: -4000, y: -4000, width: 8000, height: 8000))
    private let spotBar = SKShapeNode()
    private var summaryLines: [SKLabelNode] = []
    private let sans = "AvenirNext-DemiBold", sansR = "AvenirNext-Regular", serif = "Didot"
    var helpVisible: Bool { !help.isHidden }

    init() {
        scene = SKScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.isUserInteractionEnabled = false
        buildGame()
        buildTitle()
        buildHelp()
        buildPause()
        buildSummary()
        for n in [game, title, help, pause, summary] { scene.addChild(n) }
        fade.fillColor = .black
        fade.strokeColor = .clear
        fade.alpha = 0
        fade.zPosition = 100
        scene.addChild(fade)
        help.isHidden = true
        pause.isHidden = true
        summary.isHidden = true
        help.zPosition = 50
        pause.zPosition = 40
        summary.zPosition = 45
        title.zPosition = 30
        layout(size)
    }

    @discardableResult
    private func label(_ key: String, _ text: String, size: CGFloat, font: String? = nil, color: NSColor = .white, align: SKLabelHorizontalAlignmentMode = .left, parent: SKNode) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font ?? sans)
        l.text = text
        l.fontSize = size
        l.fontColor = color
        l.horizontalAlignmentMode = align
        l.verticalAlignmentMode = .center
        parent.addChild(l)
        if !key.isEmpty { labels[key] = l }
        return l
    }

    private func shadowed(_ l: SKLabelNode) {
        let s = SKLabelNode(fontNamed: l.fontName)
        s.text = l.text
        s.fontSize = l.fontSize
        s.fontColor = NSColor(white: 0, alpha: 0.6)
        s.horizontalAlignmentMode = l.horizontalAlignmentMode
        s.verticalAlignmentMode = l.verticalAlignmentMode
        s.position = CGPoint(x: 1.5, y: -1.5)
        s.zPosition = -1
        l.addChild(s)
    }

    private let bottomLeft = SKNode(), topLeft = SKNode(), topRight = SKNode(), topCenter = SKNode(), bottomCenter = SKNode()

    private func buildGame() {
        for n in [bottomLeft, topLeft, topRight, topCenter, bottomCenter] { game.addChild(n) }
        shadowed(label("clock", "1:00 AM", size: 26, font: sans, parent: topLeft))
        labels["clock"]!.position = CGPoint(x: 0, y: 0)
        let nightL = label("night", "NIGHT 1", size: 12, font: sans, color: NSColor(white: 1, alpha: 0.6), parent: topLeft)
        nightL.position = CGPoint(x: 1, y: -24)
        shadowed(label("stash", "STASH 0", size: 22, font: sans, align: .right, parent: topRight))
        label("carry", "", size: 13, font: sansR, color: color(1, 0.85, 0.55), align: .right, parent: topRight).position = CGPoint(x: 0, y: -24)
        shadowed(label("threat", "", size: 15, font: sans, align: .center, parent: topCenter))
        spotBar.strokeColor = .clear
        spotBar.fillColor = color(1, 0.35, 0.25)
        spotBar.position = CGPoint(x: 0, y: -18)
        topCenter.addChild(spotBar)

        // bars live in bottomLeft
        let holder = bottomLeft
        func barIn(_ key: String, _ name: String, y: CGFloat, color c: NSColor) {
            let l = SKLabelNode(fontNamed: sans)
            l.text = name; l.fontSize = 11; l.fontColor = NSColor(white: 1, alpha: 0.65)
            l.horizontalAlignmentMode = .left; l.verticalAlignmentMode = .center
            l.position = CGPoint(x: 0, y: y + 13)
            holder.addChild(l)
            let bg = SKShapeNode(rect: CGRect(x: 0, y: y - 4, width: 180, height: 8), cornerRadius: 4)
            bg.fillColor = NSColor(white: 0, alpha: 0.45)
            bg.strokeColor = NSColor(white: 1, alpha: 0.15)
            holder.addChild(bg)
            let fill = SKShapeNode(rect: CGRect(x: 0, y: -4, width: 180, height: 8), cornerRadius: 4)
            fill.fillColor = c
            fill.strokeColor = .clear
            fill.position = CGPoint(x: 0, y: y)
            holder.addChild(fill)
            bars[key] = fill
        }
        barIn("belly", "BELLY", y: 60, color: color(0.95, 0.72, 0.3))
        barIn("stamina", "STAMINA", y: 26, color: color(0.55, 0.85, 0.95))
        for i in 0..<3 {
            let d = SKShapeNode(ellipseOf: CGSize(width: 16, height: 11))
            d.fillColor = color(0.85, 0.7, 0.65)
            d.strokeColor = NSColor(white: 0, alpha: 0.4)
            d.position = CGPoint(x: 8 + CGFloat(i) * 22, y: 96)
            holder.addChild(d)
            lifeDots.append(d)
        }
        // visibility eye + noise ring
        eye.fillColor = NSColor(white: 1, alpha: 0.85)
        eye.strokeColor = NSColor(white: 0, alpha: 0.5)
        eye.position = CGPoint(x: 220, y: 60)
        pupil.fillColor = .black
        pupil.strokeColor = .clear
        eye.addChild(pupil)
        holder.addChild(eye)
        label("eyeL", "SEEN", size: 10, font: sans, color: NSColor(white: 1, alpha: 0.6), align: .center, parent: holder).position = CGPoint(x: 220, y: 40)
        noiseRing.strokeColor = color(1, 0.9, 0.6)
        noiseRing.lineWidth = 2
        noiseRing.fillColor = .clear
        noiseRing.position = CGPoint(x: 270, y: 60)
        holder.addChild(noiseRing)
        label("noiseL", "NOISE", size: 10, font: sans, color: NSColor(white: 1, alpha: 0.6), align: .center, parent: holder).position = CGPoint(x: 270, y: 40)
        label("hidden", "", size: 13, font: sans, color: color(0.6, 1, 0.7), parent: holder).position = CGPoint(x: 0, y: 128)

        shadowed(label("prompt", "", size: 17, font: sans, align: .center, parent: bottomCenter))

        toast.fontName = sans
        toast.fontSize = 34
        toast.horizontalAlignmentMode = .center
        toast.verticalAlignmentMode = .center
        toastSub.fontName = sansR
        toastSub.fontSize = 17
        toastSub.horizontalAlignmentMode = .center
        toastSub.verticalAlignmentMode = .center
        game.addChild(toast)
        game.addChild(toastSub)
        saved.fontName = sans
        saved.fontSize = 13
        saved.fontColor = color(0.7, 1, 0.75)
        saved.text = "SAVED"
        saved.horizontalAlignmentMode = .right
        saved.alpha = 0
        scene.addChild(saved)
        label("hint", "H  help    ESC  pause", size: 11, font: sansR, color: NSColor(white: 1, alpha: 0.4), align: .right, parent: game)
    }

    private func buildTitle() {
        let shade = SKShapeNode(rect: CGRect(x: -3000, y: -3000, width: 6000, height: 6000))
        shade.fillColor = NSColor(white: 0, alpha: 0.35)
        shade.strokeColor = .clear
        shade.zPosition = -1
        title.addChild(shade)
        let t = label("", "SCURRY", size: 96, font: serif, color: color(0.97, 0.94, 0.88), align: .center, parent: title)
        t.position = CGPoint(x: 0, y: 150)
        shadowed(t)
        label("", "one night in the kitchen, as a rat", size: 20, font: sansR, color: color(0.9, 0.85, 0.75), align: .center, parent: title).position = CGPoint(x: 0, y: 88)
        let lines = [
            "Eat to keep your belly full. Carry food back to your hole to build your stash.",
            "The cat sleeps in the corner. Traps line the walls. Someone might come down for a snack.",
            "Get home before 5:30 AM.",
        ]
        for (i, s) in lines.enumerated() {
            label("", s, size: 15, font: sansR, color: NSColor(white: 1, alpha: 0.75), align: .center, parent: title).position = CGPoint(x: 0, y: 30 - CGFloat(i) * 24)
        }
        label("record", "", size: 13, font: sans, color: color(1, 0.85, 0.55), align: .center, parent: title).position = CGPoint(x: 0, y: -60)
        let go = label("", "PRESS  SPACE  TO  BEGIN", size: 18, font: sans, color: .white, align: .center, parent: title)
        go.position = CGPoint(x: 0, y: -120)
        go.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.9), .fadeAlpha(to: 1, duration: 0.9)])))
        label("", "H  controls     M  music on/off", size: 12, font: sansR, color: NSColor(white: 1, alpha: 0.5), align: .center, parent: title).position = CGPoint(x: 0, y: -160)
    }

    private func panel(_ w: CGFloat, _ h: CGFloat, parent: SKNode) {
        let p = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 16)
        p.fillColor = NSColor(white: 0.02, alpha: 0.93)
        p.strokeColor = NSColor(white: 1, alpha: 0.12)
        parent.addChild(p)
    }

    private func buildHelp() {
        panel(620, 470, parent: help)
        label("", "CONTROLS", size: 20, font: sans, align: .center, parent: help).position = CGPoint(x: 0, y: 200)
        let rows: [(String, String)] = [
            ("W A S D", "scurry (relative to the camera)"),
            ("SHIFT", "dash — burns stamina, loud on tiles"),
            ("C  /  CTRL", "creep — slow, silent; the safe way to take trap bait"),
            ("SPACE", "hop (about 55 cm)  ·  on a wall: kick off"),
            ("walk into", "table & chair legs, the dish towel, bin bag: climb"),
            ("E  (hold)", "eat"),
            ("F", "pick up / drop food  ·  bring it to your hole"),
            ("R", "rear up and sniff — nearby food glints"),
            ("Q", "squeak (the cat will hear)"),
            ("MOUSE DRAG / ARROWS", "look around  ·  SCROLL  zoom"),
            ("V", "rat's-eye view"),
            ("M", "music  ·  ESC pause  ·  H this help"),
        ]
        for (i, (k, d)) in rows.enumerated() {
            let y = 150 - CGFloat(i) * 29
            label("", k, size: 14, font: sans, color: color(1, 0.85, 0.55), align: .right, parent: help).position = CGPoint(x: -110, y: y)
            label("", d, size: 14, font: sansR, color: NSColor(white: 1, alpha: 0.85), parent: help).position = CGPoint(x: -90, y: y)
        }
        label("", "Hide under the stove or the fridge — the cat can't follow.", size: 13, font: sansR, color: color(0.6, 1, 0.7), align: .center, parent: help).position = CGPoint(x: 0, y: -210)
    }

    private func buildPause() {
        panel(360, 150, parent: pause)
        label("", "PAUSED", size: 28, font: sans, align: .center, parent: pause).position = CGPoint(x: 0, y: 25)
        label("", "ESC resume   ·   N new night   ·   ⌘Q quit", size: 13, font: sansR, color: NSColor(white: 1, alpha: 0.7), align: .center, parent: pause).position = CGPoint(x: 0, y: -25)
    }

    private func buildSummary() {
        panel(520, 330, parent: summary)
        label("sumTitle", "", size: 30, font: serif, align: .center, parent: summary).position = CGPoint(x: 0, y: 120)
        for i in 0..<6 {
            let l = label("", "", size: 16, font: sansR, color: NSColor(white: 1, alpha: 0.85), align: .center, parent: summary)
            l.position = CGPoint(x: 0, y: 60 - CGFloat(i) * 28)
            summaryLines.append(l)
        }
        label("", "SPACE  next night", size: 14, font: sans, color: color(1, 0.85, 0.55), align: .center, parent: summary).position = CGPoint(x: 0, y: -135)
    }

    private func layout(_ s: CGSize) {
        size = s
        scene.size = s
        topLeft.position = CGPoint(x: 26, y: s.height - 34)
        topRight.position = CGPoint(x: s.width - 26, y: s.height - 34)
        topCenter.position = CGPoint(x: s.width / 2, y: s.height - 34)
        bottomLeft.position = CGPoint(x: 26, y: 20)
        bottomCenter.position = CGPoint(x: s.width / 2, y: 70)
        toast.position = CGPoint(x: s.width / 2, y: s.height * 0.68)
        toastSub.position = CGPoint(x: s.width / 2, y: s.height * 0.68 - 34)
        saved.position = CGPoint(x: s.width - 24, y: 40)
        labels["hint"]?.position = CGPoint(x: s.width - 24, y: 20)
        for n in [title, help, pause, summary] { n.position = CGPoint(x: s.width / 2, y: s.height / 2) }
        fade.position = .zero
    }

    private func set(_ key: String, _ text: String, _ c: NSColor? = nil) {
        guard let l = labels[key] else { return }
        if l.text != text {
            l.text = text
            if let s = l.children.first as? SKLabelNode { s.text = text }
        }
        if let c = c, l.fontColor != c { l.fontColor = c }
    }

    func showToast(_ text: String, sub: String = "", color c: NSColor = .white, duration: Double = 3, now: Double) {
        toast.text = text
        toast.fontColor = c
        toastSub.text = sub
        toast.alpha = 1
        toastSub.alpha = sub.isEmpty ? 0 : 1
        toastUntil = now + duration
    }

    func flashSaved(now: Double) { savedUntil = now + 1.4 }

    func setMode(title showTitle: Bool, record: String) {
        title.isHidden = !showTitle
        game.isHidden = showTitle
        set("record", record)
    }
    func setPaused(_ p: Bool) { pause.isHidden = !p }
    func toggleHelp() { help.isHidden.toggle() }
    func hideHelp() { help.isHidden = true }
    func setFade(_ a: CGFloat) { fade.alpha = a }

    func showSummary(title t: String, lines: [String]) {
        set("sumTitle", t)
        for (i, l) in summaryLines.enumerated() { l.text = i < lines.count ? lines[i] : "" }
        summary.isHidden = false
        game.isHidden = true
    }
    func hideSummary() { summary.isHidden = true; game.isHidden = false }

    func update(_ st: HUDState, viewSize: CGSize, now: Double) {
        if viewSize != size && viewSize.width > 10 { layout(viewSize) }
        set("clock", st.clock)
        set("night", "NIGHT \(st.night)")
        set("stash", "STASH \(st.stash)")
        set("carry", st.carrying.map { "carrying \($0)" } ?? "")
        set("threat", st.threat, st.threatColor)
        set("prompt", st.prompt)
        set("hidden", st.hidden.map { "HIDDEN · \($0)" } ?? "")
        bars["belly"]?.xScale = CGFloat(max(0.001, st.belly))
        bars["belly"]?.fillColor = st.belly < 0.15 ? color(1, 0.35, 0.25) : color(0.95, 0.72, 0.3)
        bars["stamina"]?.xScale = CGFloat(max(0.001, st.stamina))
        for (i, d) in lifeDots.enumerated() { d.alpha = i < st.lives ? 1 : 0.15 }
        let v = CGFloat(st.visibility)
        eye.yScale = 0.25 + v * 0.75
        eye.fillColor = NSColor(white: 0.3 + v * 0.7, alpha: 0.85)
        pupil.setScale(0.6 + v * 0.8)
        noiseRing.setScale(0.4 + CGFloat(st.noise) * 1.6)
        noiseRing.alpha = 0.25 + CGFloat(st.noise) * 0.75
        let w = CGFloat(st.spotted) * 220
        spotBar.path = st.spotted > 0.01 ? CGPath(roundedRect: CGRect(x: -w / 2, y: -3, width: w, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil) : nil

        if now > toastUntil {
            toast.alpha = max(0, toast.alpha - 0.04)
            toastSub.alpha = max(0, toastSub.alpha - 0.04)
        }
        saved.alpha = now < savedUntil ? 1 : max(0, saved.alpha - 0.05)
    }
}
