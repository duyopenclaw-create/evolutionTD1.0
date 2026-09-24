import SpriteKit

struct HUDState {
    var seedText = "27"
    var typing = false
    var seedInfo = ""
    var balls = 0, maxBalls = 0, running = 0
    var longest = "", highest = "", spawned = 0
    var flags: [String] = []
}

final class HUD {
    let scene: SKScene
    private var size = CGSize(width: 1440, height: 900)
    private let sans = "AvenirNext-DemiBold", sansR = "AvenirNext-Regular", heavy = "AvenirNext-Heavy", mono = "Menlo-Bold"
    private let root = SKNode(), topLeft = SKNode(), topRight = SKNode(), bottom = SKNode(), bottomLeft = SKNode(), center = SKNode()
    private let help = SKNode()
    private var labels: [String: SKLabelNode] = [:]
    private let graphBG = SKShapeNode(), graphLine = SKShapeNode(), graphDot = SKShapeNode(circleOfRadius: 4), graphBase = SKShapeNode()
    private var feed: [SKLabelNode] = []
    private let toast = SKLabelNode(), toastSub = SKLabelNode()
    private var toastUntil = 0.0
    private let saved = SKLabelNode()
    private var savedUntil = 0.0
    private let graphW: CGFloat = 520, graphH: CGFloat = 110
    var helpVisible: Bool { !help.isHidden }

    init() {
        scene = SKScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.isUserInteractionEnabled = false
        for n in [topLeft, topRight, bottom, bottomLeft, center] { root.addChild(n) }
        scene.addChild(root)
        scene.addChild(help)
        build()
        buildHelp()
        layout(size)
    }

    @discardableResult
    private func label(_ key: String, _ text: String, size: CGFloat, font: String? = nil, color: NSColor = .white,
                       align: SKLabelHorizontalAlignmentMode = .left, parent: SKNode, at p: CGPoint = .zero, shadow: Bool = true) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font ?? sans)
        l.text = text
        l.fontSize = size
        l.fontColor = color
        l.horizontalAlignmentMode = align
        l.verticalAlignmentMode = .center
        l.position = p
        parent.addChild(l)
        if !key.isEmpty { labels[key] = l }
        if shadow {
            let s = SKLabelNode(fontNamed: l.fontName)
            s.name = "shadow"
            s.text = text
            s.fontSize = size
            s.fontColor = NSColor(white: 0, alpha: 0.55)
            s.horizontalAlignmentMode = align
            s.verticalAlignmentMode = .center
            s.position = CGPoint(x: 1.5, y: -1.5)
            s.zPosition = -1
            l.addChild(s)
        }
        return l
    }

    private func set(_ key: String, _ text: String, color: NSColor? = nil) {
        guard let l = labels[key], l.text != text || (color != nil && l.fontColor != color) else { return }
        l.text = text
        if let c = color { l.fontColor = c }
        (l.childNode(withName: "shadow") as? SKLabelNode)?.text = text
    }

    private func build() {
        label("title", "HAILSTONE", size: 22, font: heavy, parent: topLeft, at: CGPoint(x: 0, y: 0))
        label("", "n → n/2 if even  ·  n → 3n+1 if odd  ·  every bounce spawns the next number", size: 12, font: sansR,
              color: NSColor(white: 0.85, alpha: 1), parent: topLeft, at: CGPoint(x: 0, y: -20))
        label("", "NEXT SEED", size: 11, font: sans, color: NSColor(white: 0.75, alpha: 1), parent: topLeft, at: CGPoint(x: 0, y: -50))
        label("seed", "27", size: 44, font: heavy, parent: topLeft, at: CGPoint(x: -2, y: -80))
        label("seedInfo", "", size: 13, font: sansR, color: NSColor(white: 0.9, alpha: 1), parent: topLeft, at: CGPoint(x: 0, y: -112))

        for (i, k) in ["balls", "running", "longest", "highest", "spawned", "flags"].enumerated() {
            label(k, "", size: k == "flags" ? 13 : 14, font: k == "flags" ? heavy : sans,
                  color: k == "flags" ? NSColor(srgbRed: 1, green: 0.75, blue: 0.3, alpha: 1) : .white,
                  align: .right, parent: topRight, at: CGPoint(x: 0, y: CGFloat(-i) * 21))
        }

        graphBG.path = CGPath(roundedRect: CGRect(x: -graphW / 2 - 14, y: -12, width: graphW + 28, height: graphH + 44), cornerWidth: 10, cornerHeight: 10, transform: nil)
        graphBG.fillColor = NSColor(white: 0, alpha: 0.38)
        graphBG.strokeColor = NSColor(white: 1, alpha: 0.12)
        bottom.addChild(graphBG)
        graphBase.strokeColor = NSColor(white: 1, alpha: 0.2)
        graphBase.lineWidth = 1
        bottom.addChild(graphBase)
        graphLine.strokeColor = NSColor(srgbRed: 1, green: 0.78, blue: 0.35, alpha: 1)
        graphLine.lineWidth = 2
        graphLine.lineJoin = .round
        graphLine.isAntialiased = true
        bottom.addChild(graphLine)
        graphDot.fillColor = .white
        graphDot.strokeColor = .clear
        bottom.addChild(graphDot)
        label("graphTitle", "Drop a seed to begin", size: 13, font: sans, parent: bottom, at: CGPoint(x: -graphW / 2, y: graphH + 16))
        label("graphNow", "", size: 13, font: mono, color: NSColor(srgbRed: 1, green: 0.8, blue: 0.4, alpha: 1), align: .right, parent: bottom, at: CGPoint(x: graphW / 2, y: graphH + 16))
        label("hint", "SPACE drop  ·  click the floor to aim  ·  type a number  ·  ↑↓ seed  ·  R random  ·  H help", size: 12, font: sansR,
              color: NSColor(white: 0.85, alpha: 1), align: .center, parent: bottom, at: CGPoint(x: 0, y: -30))

        for i in 0..<7 {
            let l = label("", "", size: 13, font: mono, parent: bottomLeft, at: CGPoint(x: 0, y: CGFloat(i) * 19))
            l.alpha = 1 - CGFloat(i) * 0.12
            feed.append(l)
        }

        toast.fontName = heavy; toast.fontSize = 30; toast.fontColor = .white
        toast.horizontalAlignmentMode = .center; toast.verticalAlignmentMode = .center
        toastSub.fontName = sans; toastSub.fontSize = 16; toastSub.fontColor = NSColor(white: 0.92, alpha: 1)
        toastSub.horizontalAlignmentMode = .center; toastSub.verticalAlignmentMode = .center
        toastSub.position = CGPoint(x: 0, y: -30)
        center.addChild(toast); center.addChild(toastSub)
        toast.alpha = 0; toastSub.alpha = 0

        saved.fontName = heavy; saved.fontSize = 14
        saved.fontColor = NSColor(srgbRed: 0.5, green: 1, blue: 0.6, alpha: 1)
        saved.text = "SAVED"
        saved.horizontalAlignmentMode = .right
        saved.alpha = 0
        root.addChild(saved)
    }

    private func buildHelp() {
        help.zPosition = 50
        help.isHidden = true
        let w: CGFloat = 640, h: CGFloat = 560
        let bg = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 14)
        bg.fillColor = NSColor(white: 0.04, alpha: 0.86)
        bg.strokeColor = NSColor(white: 1, alpha: 0.18)
        help.addChild(bg)
        label("", "HOW THE MACHINE WORKS", size: 20, font: heavy, align: .center, parent: help, at: CGPoint(x: 0, y: h / 2 - 34))
        let lines: [String] = [
            "Every ball carries a number. On its first real bounce it gives birth to the next",
            "number in its Collatz (hailstone) sequence: half of it if it is even, 3n+1 if odd.",
            "The chain keeps going until a ball numbered 1 lands and the chime rings.",
            "Nobody has proved that every seed gets there. So far, every seed ever tried has.",
            "",
            "Solid balls are even and striped balls are odd. The colour is the number's size band",
            "(1, 2–3, 4–7, 8–15, …), so a halving always steps down exactly one colour.",
            "Size grows with the number, and so does weight.",
            "",
            "SPACE / RETURN     drop the seed from the gantry     SHIFT+SPACE  drop 5 in a row",
            "click the floor    aim the gantry there and drop    click a ball  follow it",
            "0–9, ⌫             type a seed                       ↑ ↓  ±1 (⇧ ±10)   ← →  ÷2 / ×2",
            "R                  random seed                       A  auto-rain seeds",
            "T                  slow motion                       C  clear the pen",
            "drag / scroll      orbit / zoom                      V  cinematic orbit",
            "M                  music on/off                      − =  volume",
            "TAB                hide the HUD                      H  this card    ⌘F  full screen",
        ]
        for (i, s) in lines.enumerated() {
            let mono = i >= 9
            label("", s, size: mono ? 12.5 : 14, font: mono ? "Menlo-Regular" : sansR, color: NSColor(white: 0.92, alpha: 1),
                  align: .left, parent: help, at: CGPoint(x: -w / 2 + 34, y: h / 2 - 80 - CGFloat(i) * 25), shadow: false)
        }
        // colour legend
        for i in 0..<10 {
            let c = BallFactory.palette[i]
            let dot = SKShapeNode(circleOfRadius: 11)
            dot.fillColor = NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
            dot.strokeColor = NSColor(white: 1, alpha: 0.4)
            let x = -w / 2 + 50 + CGFloat(i) * 60
            dot.position = CGPoint(x: x, y: -h / 2 + 50)
            help.addChild(dot)
            let lo = 1 << i, hi = (1 << (i + 1)) - 1
            label("", i == 0 ? "1" : "\(lo)–\(hi)", size: 10, font: sansR, align: .center, parent: help, at: CGPoint(x: x, y: -h / 2 + 26), shadow: false)
        }
    }

    func layout(_ s: CGSize) {
        size = s
        topLeft.position = CGPoint(x: 26, y: s.height - 30)
        topRight.position = CGPoint(x: s.width - 26, y: s.height - 30)
        bottom.position = CGPoint(x: s.width / 2, y: 58)
        bottomLeft.position = CGPoint(x: 26, y: 40)
        center.position = CGPoint(x: s.width / 2, y: s.height * 0.72)
        help.position = CGPoint(x: s.width / 2, y: s.height / 2)
        saved.position = CGPoint(x: s.width - 26, y: 26)
        let narrow = s.width < 1250
        bottomLeft.isHidden = narrow
    }

    func update(_ st: HUDState, now: Double) {
        if scene.size != size { layout(scene.size) }
        set("seed", st.typing ? st.seedText + "▏" : st.seedText,
            color: st.typing ? NSColor(srgbRed: 1, green: 0.85, blue: 0.45, alpha: 1) : .white)
        set("seedInfo", st.seedInfo)
        set("balls", "BALLS  \(st.balls) / \(st.maxBalls)")
        set("running", "CHAINS RUNNING  \(st.running)")
        set("longest", st.longest)
        set("highest", st.highest)
        set("spawned", "BALLS BORN  \(st.spawned.formatted())")
        set("flags", st.flags.joined(separator: "  ·  "))
        let tA = CGFloat(clampd((toastUntil - now) / 0.6, 0, 1))
        toast.alpha = tA; toastSub.alpha = tA
        saved.alpha = CGFloat(clampd((savedUntil - now) / 0.5, 0, 1))
    }

    /// The hailstone plot of the chain being watched (log scale), with the full length known up front.
    func setGraph(title: String, values: [Int], total: Int, peak: Int) {
        set("graphTitle", title)
        guard values.count > 0 else { graphLine.path = nil; set("graphNow", ""); return }
        let top = log2(Double(max(2, peak)))
        let path = CGMutablePath()
        let W = graphW, H = graphH
        var last = CGPoint.zero
        for (i, v) in values.enumerated() {
            let x = -W / 2 + W * CGFloat(i) / CGFloat(max(1, total - 1))
            let y = H * CGFloat(log2(Double(v)) / top)
            let p = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            last = p
        }
        graphLine.path = path
        graphDot.position = last
        let base = CGMutablePath()
        base.move(to: CGPoint(x: -W / 2, y: 0)); base.addLine(to: CGPoint(x: W / 2, y: 0))
        graphBase.path = base
        set("graphNow", "\(values.last!.formatted())   step \(values.count - 1)/\(total - 1)")
    }

    func pushFeed(_ text: String, color: NSColor) {
        for i in stride(from: feed.count - 1, to: 0, by: -1) {
            feed[i].text = feed[i - 1].text
            feed[i].fontColor = feed[i - 1].fontColor
            (feed[i].childNode(withName: "shadow") as? SKLabelNode)?.text = feed[i].text
        }
        feed[0].text = text
        feed[0].fontColor = color
        (feed[0].childNode(withName: "shadow") as? SKLabelNode)?.text = text
    }

    func showToast(_ t: String, sub: String = "", color: NSColor = .white, duration: Double = 3, now: Double) {
        toast.text = t
        toast.fontColor = color
        toastSub.text = sub
        toastUntil = now + duration
    }

    func flashSaved(now: Double) { savedUntil = now + 1.4 }
    func toggleHelp() { help.isHidden.toggle() }
    func setHelp(_ on: Bool) { help.isHidden = !on }
    var visible: Bool {
        get { !root.isHidden }
        set { root.isHidden = !newValue }
    }
}
