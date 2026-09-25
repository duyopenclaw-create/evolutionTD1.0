import SpriteKit

enum HUDMode { case title, shop, ready, fall, results }

struct HUDState {
    var money = 0
    var mapIdx = 0, heightIdx = 0
    var fallCash: Float = 0
    var broken = 0, shattered = 0, hurt = 0
    var speed: Float = 0, altitude: Float = 0
    var combo = 0
    var warp: Float = 1
    var abilities: [(Bool, Int)] = []
    var ownedAbilities: [Bool] = []
    var effects = ""
    var runSpeed: Float = 0, runMax: Float = 1, toEdge: Float = 0, jumped = false
    var prompt = ""
    var controls = ""
    // shop
    var ownedMaps: [Bool] = [], ownedHeights: [Bool] = []
    var upLevels: [Int] = []
    var cursorCol = 0, cursorRow = 0
    var hover: String?
    var musicOn = true
    var falls = 0, bestFall = 0, totalBones = 0
}

struct ResultsData {
    var damage: [Float]
    var states: [Injury]
    var hits: [(region: Region, severity: Float)]
    var cash: Int
    var bonus: Int
    var topSpeed: Float
    var height: Float
    var time: Float
    var bestCombo: Int
    var record: Bool
}

func injuryColor(_ s: Injury) -> NSColor {
    switch s {
    case .fine: return color(0.93, 0.91, 0.84)
    case .bruised: return color(1, 0.66, 0.66)
    case .cracked: return color(0.93, 0.22, 0.18)
    case .broken: return color(0.52, 0.04, 0.05)
    case .shattered: return color(0.04, 0.03, 0.03)
    }
}

func grouped(_ v: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

func money(_ v: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return "$" + (f.string(from: NSNumber(value: v)) ?? "\(v)")
}

/// A lightbox with all 206 bones, each its own shape.
final class XRay {
    let node = SKNode()
    let skeleton = SKNode()
    let markers = SKNode()
    private(set) var bones: [SKShapeNode] = []
    private var shown: [Injury] = []

    init(title: Bool) {
        let bg = SKShapeNode(path: CGPath(roundedRect: CGRect(x: -170, y: -380, width: 340, height: 640), cornerWidth: 18, cornerHeight: 18, transform: nil))
        bg.fillColor = color(0.2, 0.31, 0.43, 0.94)
        bg.strokeColor = color(0.7, 0.85, 1, 0.5)
        bg.lineWidth = 2
        node.addChild(bg)
        for k in 0..<12 {
            let l = SKShapeNode(rect: CGRect(x: -168, y: -378 + CGFloat(k) * 53, width: 336, height: 1))
            l.fillColor = NSColor(white: 1, alpha: 0.05); l.strokeColor = .clear
            node.addChild(l)
        }
        if title {
            for (t, x, y, a) in [("X-RAY  ·  206 BONES", CGFloat(-150), CGFloat(236), SKLabelHorizontalAlignmentMode.left), ("R", -145, -355, .center), ("L", 145, -355, .center)] {
                let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
                l.text = t; l.fontSize = t.count > 2 ? 15 : 20; l.fontColor = color(0.75, 0.9, 1, 0.8)
                l.horizontalAlignmentMode = a; l.verticalAlignmentMode = .center; l.position = CGPoint(x: x, y: y)
                node.addChild(l)
            }
        }
        node.addChild(skeleton)
        for b in Skeleton.bones {
            let n = SKShapeNode(path: b.path)
            n.fillColor = injuryColor(.fine)
            n.strokeColor = NSColor(white: 1, alpha: 0.5)
            n.lineWidth = b.path.boundingBoxOfPath.width < 8 ? 0.6 : 1.1
            n.zPosition = b.z
            skeleton.addChild(n)
            bones.append(n)
        }
        for d in Skeleton.decorations {
            let n = SKShapeNode(path: d)
            n.fillColor = color(0.1, 0.13, 0.19); n.strokeColor = .clear; n.zPosition = 1.5
            skeleton.addChild(n)
        }
        skeleton.addChild(markers)
        markers.zPosition = 10
        shown = [Injury](repeating: .fine, count: bones.count)
    }

    func set(_ states: [Injury], flash: Bool) {
        for (i, s) in states.enumerated() where i < bones.count && shown[i] != s {
            shown[i] = s
            let n = bones[i]
            n.fillColor = injuryColor(s)
            n.strokeColor = s == .shattered ? color(1, 0.3, 0.25, 0.9) : NSColor(white: 1, alpha: 0.5)
            if flash {
                n.removeAllActions()
                n.run(SKAction.sequence([SKAction.run { n.strokeColor = color(1, 0.9, 0.3) }, SKAction.wait(forDuration: 0.35),
                                         SKAction.run { n.strokeColor = s == .shattered ? color(1, 0.3, 0.25, 0.9) : NSColor(white: 1, alpha: 0.5) }]))
            }
        }
    }
}

final class HUD {
    let scene: SKScene
    private(set) var size = CGSize(width: 1440, height: 900)
    let heavy = "AvenirNext-Heavy", bold = "AvenirNext-Bold", demi = "AvenirNext-DemiBold", reg = "AvenirNext-Medium"
    private let titleLayer = SKNode(), shopLayer = SKNode(), readyLayer = SKNode(), fallLayer = SKNode(), resultsLayer = SKNode(), common = SKNode()
    let floatLayer = SKNode()
    private(set) var mode: HUDMode = .title

    private let moneyLabel = SKLabelNode(), placeLabel = SKLabelNode(), saved = SKLabelNode(), musicLabel = SKLabelNode()
    private var savedUntil = 0.0
    private let promptLabel = SKLabelNode(), promptBG = SKShapeNode(), controlsLabel = SKLabelNode()
    private let toast = SKLabelNode(), toastSub = SKLabelNode()
    private var toastStart = -9.0, toastDur = 1.2
    private let logo = SKNode(), pressStart = SKLabelNode()
    // shop
    private typealias Row = (bg: SKShapeNode, name: SKLabelNode, info: SKLabelNode)
    private var mapRows: [Row] = [], heightRows: [Row] = [], upRows: [(Row, pips: [SKShapeNode], desc: SKLabelNode)] = [], abRows: [Row] = []
    private var abSlots: [(bg: SKShapeNode, label: SKLabelNode, uses: SKLabelNode)] = []
    private let effectsLabel = SKLabelNode(), abBar = SKNode()
    private let shopPanel = SKNode()
    private let blurb = SKLabelNode(), blurb2 = SKLabelNode(), statsLabel = SKLabelNode()
    private let jumpBtn = SKShapeNode(), jumpLabel = SKLabelNode()
    // ready
    private let runBG = SKShapeNode(), runFill = SKShapeNode(), runLabel = SKLabelNode(), edgeLabel = SKLabelNode()
    // fall
    private let fallCash = SKLabelNode(), fallBones = SKLabelNode(), speedLabel = SKLabelNode(), altLabel = SKLabelNode(), comboLabel = SKLabelNode()
    private var feed: [(node: SKNode, born: Double)] = []
    private let feedLayer = SKNode()
    let mini = XRay(title: false)
    // results
    let xray = XRay(title: true)
    private let resTitle = SKLabelNode(), resCash = SKLabelNode(), resLines = SKNode(), resHint = SKLabelNode()
    private let resRight = SKNode(), resPanel = SKShapeNode(), legend = SKNode()
    private var resShownAt = 0.0, resCashTarget = 0, resCashShown = 0
    var now = 0.0

    init() {
        scene = SKScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.isUserInteractionEnabled = false
        for n in [floatLayer, titleLayer, shopLayer, readyLayer, fallLayer, resultsLayer, common] { scene.addChild(n) }
        buildCommon(); buildTitle(); buildShop(); buildReady(); buildFall(); buildResults()
        layout(size)
        setMode(.title)
    }

    // MARK: helpers

    @discardableResult
    func label(_ text: String, _ size: CGFloat, font: String? = nil, color: NSColor = .white, align: SKLabelHorizontalAlignmentMode = .center,
               parent: SKNode, at p: CGPoint = .zero, shadow: Bool = true) -> SKLabelNode {
        let l = SKLabelNode(fontNamed: font ?? demi)
        l.text = text; l.fontSize = size; l.fontColor = color
        l.horizontalAlignmentMode = align; l.verticalAlignmentMode = .center
        l.position = p
        parent.addChild(l)
        if shadow { addShadow(l) }
        return l
    }

    private func style(_ l: SKLabelNode, _ size: CGFloat, font: String, align: SKLabelHorizontalAlignmentMode = .center, color: NSColor = .white, parent: SKNode, shadow: Bool = true, text: String = "") {
        l.fontName = font; l.fontSize = size; l.horizontalAlignmentMode = align; l.verticalAlignmentMode = .center; l.fontColor = color
        l.text = text
        parent.addChild(l)
        if shadow { addShadow(l) }
    }

    private func addShadow(_ l: SKLabelNode, offset: CGFloat = 2) {
        let s = SKLabelNode(fontNamed: l.fontName)
        s.name = "shadow"
        s.text = l.text; s.fontSize = l.fontSize
        s.fontColor = NSColor(white: 0, alpha: 0.65)
        s.horizontalAlignmentMode = l.horizontalAlignmentMode; s.verticalAlignmentMode = l.verticalAlignmentMode
        s.position = CGPoint(x: offset * 0.75, y: -offset)
        s.zPosition = -1
        l.addChild(s)
    }

    private func setText(_ l: SKLabelNode, _ t: String, color: NSColor? = nil) {
        if l.text != t {
            l.text = t
            for c in l.children where c.name == "shadow" { (c as? SKLabelNode)?.text = t }
        }
        if let c = color, l.fontColor != c { l.fontColor = c }
    }

    // MARK: build

    private func buildCommon() {
        style(moneyLabel, 40, font: heavy, align: .left, color: color(0.55, 1, 0.45), parent: common)
        style(placeLabel, 15, font: demi, align: .left, color: NSColor(white: 0.92, alpha: 1), parent: common)
        style(saved, 13, font: bold, align: .right, color: color(0.6, 1, 0.6), parent: common, text: "SAVED")
        style(musicLabel, 12, font: demi, align: .right, color: NSColor(white: 0.8, alpha: 1), parent: common)
        promptBG.fillColor = NSColor(white: 0, alpha: 0.55)
        promptBG.strokeColor = .clear
        common.addChild(promptBG)
        style(promptLabel, 20, font: bold, parent: common)
        style(controlsLabel, 13, font: demi, color: NSColor(white: 0.85, alpha: 1), parent: common)
        style(toast, 72, font: heavy, parent: common)
        style(toastSub, 22, font: bold, parent: common)
        toast.zPosition = 20; toastSub.zPosition = 20
    }

    private func buildTitle() {
        titleLayer.addChild(logo)
        let text = "BONEFALL"
        for (dx, dy, c) in [(CGFloat(0), CGFloat(-12), color(0.3, 0.02, 0.03)), (0, -7, color(0.55, 0.05, 0.06)),
                            (-4, 0, NSColor(white: 0.02, alpha: 1)), (4, 0, NSColor(white: 0.02, alpha: 1)), (0, 4, NSColor(white: 0.02, alpha: 1)), (0, -4, NSColor(white: 0.02, alpha: 1))] {
            let l = SKLabelNode(fontNamed: heavy)
            l.text = text; l.fontSize = 140; l.fontColor = c
            l.verticalAlignmentMode = .center
            l.position = CGPoint(x: dx, y: dy)
            logo.addChild(l)
        }
        let face = SKLabelNode(fontNamed: heavy)
        face.text = text; face.fontSize = 140; face.fontColor = color(0.96, 0.94, 0.86)
        face.verticalAlignmentMode = .center
        logo.addChild(face)
        let crack = SKShapeNode()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -40, y: 70))
        for (x, y) in [(-22, 38), (-36, 14), (-8, -6), (-20, -30), (4, -52), (-6, -72)] { p.addLine(to: CGPoint(x: x, y: y)) }
        crack.path = p
        crack.strokeColor = NSColor(white: 0.02, alpha: 1)
        crack.lineWidth = 6
        logo.addChild(crack)
        label("Run. Jump. Break all 206 bones. Get paid.", 24, font: bold, color: color(1, 0.85, 0.7), parent: logo, at: CGPoint(x: 0, y: -110))
        style(pressStart, 22, font: heavy, color: .white, parent: titleLayer, text: "CLICK OR PRESS SPACE")
    }

    private func row(_ w: CGFloat, name: String, parent: SKNode, h: CGFloat = 34) -> Row {
        let bg = SKShapeNode(rect: CGRect(x: 0, y: -h / 2, width: w, height: h), cornerRadius: 8)
        bg.fillColor = NSColor(white: 0, alpha: 0.35)
        bg.strokeColor = NSColor(white: 1, alpha: 0.1)
        bg.name = name
        parent.addChild(bg)
        let n = label("", 16, font: bold, align: .left, parent: bg, at: CGPoint(x: 12, y: h > 40 ? 9 : 0), shadow: false)
        let i = label("", 14, font: demi, align: .right, parent: bg, at: CGPoint(x: w - 10, y: h > 40 ? 9 : 0), shadow: false)
        return (bg, n, i)
    }

    private func buildShop() {
        shopLayer.addChild(shopPanel)
        let back = SKShapeNode(rect: CGRect(x: -24, y: -655, width: 1044, height: 690), cornerRadius: 18)
        back.fillColor = NSColor(white: 0.03, alpha: 0.74)
        back.strokeColor = NSColor(white: 1, alpha: 0.15)
        back.lineWidth = 1.5
        back.zPosition = -5
        shopPanel.addChild(back)
        for (t, x) in [("CLIFFS", CGFloat(4)), ("HEIGHT", 404), ("UPGRADES", 654)] {
            label(t, 20, font: heavy, color: color(1, 0.8, 0.5), align: .left, parent: shopPanel, at: CGPoint(x: x, y: 0))
        }
        for i in 0..<maps.count {
            let r = row(380, name: "map:\(i)", parent: shopPanel, h: 30)
            r.bg.position = CGPoint(x: 0, y: -36 - CGFloat(i) * 34)
            mapRows.append(r)
        }
        for i in 0..<heights.count {
            let r = row(230, name: "h:\(i)", parent: shopPanel, h: 30)
            r.bg.position = CGPoint(x: 400, y: -36 - CGFloat(i) * 34)
            heightRows.append(r)
        }
        for i in 0..<upgrades.count {
            let r = row(340, name: "up:\(i)", parent: shopPanel, h: 36)
            r.bg.position = CGPoint(x: 650, y: -38 - CGFloat(i) * 41)
            var pips: [SKShapeNode] = []
            for k in 0..<upgrades[i].max {
                let pip = SKShapeNode(rect: CGRect(x: 150 + CGFloat(k) * 14, y: -4, width: 11, height: 8), cornerRadius: 2)
                pip.strokeColor = NSColor(white: 1, alpha: 0.3)
                r.bg.addChild(pip)
                pips.append(pip)
            }
            let d = label("", 1, parent: r.bg, shadow: false)
            upRows.append((r, pips, d))
        }
        label("ABILITIES  (keys 1-7 while falling)", 16, font: heavy, color: color(0.5, 0.85, 1), align: .left, parent: shopPanel, at: CGPoint(x: 654, y: -38 - 5 * 41 + 4))
        for i in 0..<abilities.count {
            let r = row(340, name: "ab:\(i)", parent: shopPanel, h: 32)
            r.bg.position = CGPoint(x: 650, y: -38 - 5 * 41 - 30 - CGFloat(i) * 37)
            abRows.append(r)
        }
        style(blurb, 17, font: bold, align: .left, color: .white, parent: shopPanel)
        style(blurb2, 14, font: demi, align: .left, color: NSColor(white: 0.85, alpha: 1), parent: shopPanel)
        style(statsLabel, 13, font: demi, align: .left, color: NSColor(white: 0.75, alpha: 1), parent: shopPanel)
        jumpBtn.path = CGPath(roundedRect: CGRect(x: -150, y: -34, width: 300, height: 68), cornerWidth: 16, cornerHeight: 16, transform: nil)
        jumpBtn.fillColor = color(0.85, 0.15, 0.1)
        jumpBtn.strokeColor = color(1, 0.8, 0.6)
        jumpBtn.lineWidth = 3
        jumpBtn.name = "jump"
        shopLayer.addChild(jumpBtn)
        style(jumpLabel, 30, font: heavy, parent: jumpBtn, text: "GO!  SPACE")
    }

    private func buildReady() {
        runBG.path = CGPath(roundedRect: CGRect(x: -200, y: -12, width: 400, height: 24), cornerWidth: 12, cornerHeight: 12, transform: nil)
        runBG.fillColor = NSColor(white: 0, alpha: 0.55)
        runBG.strokeColor = NSColor(white: 1, alpha: 0.6)
        runBG.lineWidth = 2
        readyLayer.addChild(runBG)
        runFill.strokeColor = .clear
        runBG.addChild(runFill)
        style(runLabel, 14, font: heavy, parent: runBG)
        runLabel.position = CGPoint(x: 0, y: 28)
        style(edgeLabel, 30, font: heavy, color: color(1, 0.85, 0.3), parent: readyLayer)
    }

    private func buildFall() {
        style(fallCash, 46, font: heavy, color: color(0.55, 1, 0.45), parent: fallLayer)
        style(fallBones, 18, font: bold, parent: fallLayer)
        style(speedLabel, 26, font: heavy, align: .right, parent: fallLayer)
        style(altLabel, 15, font: demi, align: .right, color: NSColor(white: 0.85, alpha: 1), parent: fallLayer)
        style(comboLabel, 28, font: heavy, color: color(1, 0.8, 0.2), parent: fallLayer)
        style(effectsLabel, 20, font: heavy, color: color(0.5, 0.85, 1), parent: fallLayer)
        fallLayer.addChild(abBar)
        for i in 0..<abilities.count {
            let bg = SKShapeNode(rect: CGRect(x: -62, y: -22, width: 124, height: 44), cornerRadius: 8)
            bg.fillColor = NSColor(white: 0, alpha: 0.5); bg.strokeColor = color(0.5, 0.85, 1, 0.6); bg.lineWidth = 1.5
            bg.position = CGPoint(x: (CGFloat(i) - 3) * 132, y: 0)
            abBar.addChild(bg)
            let l = label("\(i + 1)  \(abilities[i].name)", 12, font: bold, parent: bg, at: CGPoint(x: 0, y: 7), shadow: false)
            let u = label("", 12, font: heavy, color: color(0.5, 0.85, 1), parent: bg, at: CGPoint(x: 0, y: -10), shadow: false)
            abSlots.append((bg, l, u))
        }
        fallLayer.addChild(feedLayer)
        fallLayer.addChild(mini.node)
    }

    private func buildResults() {
        resultsLayer.addChild(resPanel)
        resultsLayer.addChild(xray.node)
        resultsLayer.addChild(resRight)
        style(resTitle, 30, font: heavy, align: .left, color: color(1, 0.85, 0.6), parent: resRight)
        style(resCash, 64, font: heavy, align: .left, color: color(0.55, 1, 0.45), parent: resRight)
        resRight.addChild(resLines)
        style(resHint, 18, font: bold, align: .left, color: .white, parent: resRight)
        for (k, s) in [Injury.fine, .bruised, .cracked, .broken, .shattered].enumerated() {
            let sw = SKShapeNode(rect: CGRect(x: 0, y: -8, width: 26, height: 16), cornerRadius: 4)
            sw.fillColor = injuryColor(s); sw.strokeColor = NSColor(white: 1, alpha: 0.5)
            sw.position = CGPoint(x: CGFloat(k) * 104, y: 0)
            legend.addChild(sw)
            label(s.label, 12, font: bold, color: NSColor(white: 0.9, alpha: 1), align: .left, parent: legend, at: CGPoint(x: CGFloat(k) * 104 + 32, y: 0), shadow: false)
        }
        resRight.addChild(legend)
    }

    // MARK: layout

    func layout(_ s: CGSize) {
        size = s
        let W = s.width, H = s.height
        moneyLabel.position = CGPoint(x: 28, y: H - 42)
        placeLabel.position = CGPoint(x: 30, y: H - 76)
        saved.position = CGPoint(x: W - 24, y: H - 28)
        musicLabel.position = CGPoint(x: W - 24, y: 20)
        promptLabel.position = CGPoint(x: W / 2, y: 110)
        controlsLabel.position = CGPoint(x: W / 2, y: 30)
        toast.position = CGPoint(x: W / 2, y: H * 0.62)
        toastSub.position = CGPoint(x: W / 2, y: H * 0.62 - 56)
        logo.position = CGPoint(x: W / 2, y: H * 0.64)
        pressStart.position = CGPoint(x: W / 2, y: H * 0.22)
        let shopW: CGFloat = 1000
        shopPanel.position = CGPoint(x: max(30, W / 2 - shopW / 2), y: H - 120)
        blurb.position = CGPoint(x: 4, y: -36 - 15 * 34 - 4)
        blurb2.position = CGPoint(x: 4, y: -36 - 15 * 34 - 30)
        statsLabel.position = CGPoint(x: 4, y: -36 - 15 * 34 - 54)
        jumpBtn.position = CGPoint(x: W / 2, y: 76)
        runBG.position = CGPoint(x: W / 2, y: 150)
        edgeLabel.position = CGPoint(x: W / 2, y: H * 0.72)
        fallCash.position = CGPoint(x: W / 2, y: H - 50)
        fallBones.position = CGPoint(x: W / 2, y: H - 90)
        comboLabel.position = CGPoint(x: W / 2, y: H - 128)
        speedLabel.position = CGPoint(x: W - 28, y: H - 110)
        altLabel.position = CGPoint(x: W - 28, y: H - 138)
        feedLayer.position = CGPoint(x: W - 28, y: H - 180)
        abBar.position = CGPoint(x: W / 2 + 60, y: 80)
        effectsLabel.position = CGPoint(x: W / 2, y: H - 162)
        let ms = min(0.42, (H - 200) / 640 * 0.6)
        mini.node.setScale(ms)
        mini.node.position = CGPoint(x: 20 + 170 * ms, y: 60 + 380 * ms)
        let sc = min(1, (H - 60) / 660)
        xray.node.setScale(sc)
        xray.node.position = CGPoint(x: max(200 * sc, W * 0.3), y: H / 2 + 50 * sc)
        let rx = xray.node.position.x + 210 * sc
        resRight.position = CGPoint(x: rx, y: H / 2 + 200)
        resPanel.path = CGPath(roundedRect: CGRect(x: rx - 24, y: H / 2 - 290, width: min(640, W - rx - 10), height: 540), cornerWidth: 16, cornerHeight: 16, transform: nil)
        resPanel.fillColor = NSColor(white: 0.02, alpha: 0.6)
        resPanel.strokeColor = NSColor(white: 1, alpha: 0.12)
        resTitle.position = CGPoint(x: 0, y: 20)
        resCash.position = CGPoint(x: 0, y: -40)
        resLines.position = CGPoint(x: 0, y: -100)
        legend.position = CGPoint(x: 0, y: -410)
        resHint.position = CGPoint(x: 0, y: -460)
    }

    func setMode(_ m: HUDMode) {
        mode = m
        titleLayer.isHidden = m != .title
        shopLayer.isHidden = m != .shop
        readyLayer.isHidden = m != .ready
        fallLayer.isHidden = m != .fall
        resultsLayer.isHidden = m != .results
        floatLayer.isHidden = m != .fall
        moneyLabel.isHidden = m == .title
        placeLabel.isHidden = m == .title || m == .results
        if m != .fall { for f in feed { f.node.removeFromParent() }; feed.removeAll(); floatLayer.removeAllChildren() }
    }

    func hit(_ p: CGPoint) -> String? {
        for n in scene.nodes(at: p) {
            var c: SKNode? = n
            while let x = c { if let nm = x.name, nm.contains(":") || nm == "jump" { return nm }; c = x.parent }
        }
        return nil
    }

    // MARK: events

    func flashSaved() { savedUntil = now + 1.5 }

    func showToast(_ big: String, _ sub: String = "", color c: NSColor = .white, dur: Double = 1.2) {
        setText(toast, big, color: c)
        setText(toastSub, sub)
        toastStart = now
        toastDur = dur
        toast.setScale(1.6)
        toast.run(SKAction.scale(to: 1, duration: 0.15))
    }

    func feedEvent(_ text: String, _ cash: String, color c: NSColor) {
        let n = SKNode()
        let bg = SKShapeNode(rect: CGRect(x: -380, y: -15, width: 380, height: 30), cornerRadius: 7)
        bg.fillColor = NSColor(white: 0, alpha: 0.5); bg.strokeColor = c.withAlphaComponent(0.8); bg.lineWidth = 1.5
        n.addChild(bg)
        label(text, 14, font: bold, color: c == injuryColor(.shattered) || c == injuryColor(.broken) ? color(1, 0.45, 0.4) : c, align: .left, parent: n, at: CGPoint(x: -368, y: 0), shadow: false)
        label(cash, 15, font: heavy, color: color(0.55, 1, 0.45), align: .right, parent: n, at: CGPoint(x: -10, y: 0), shadow: false)
        feedLayer.addChild(n)
        feed.insert((n, now), at: 0)
        while feed.count > 9 { feed.removeLast().node.removeFromParent() }
        n.setScale(1.2)
        n.run(SKAction.scale(to: 1, duration: 0.12))
    }

    /// A "+$12" that rises from a screen point and fades.
    @discardableResult
    func floater(_ text: String, at p: CGPoint, color c: NSColor, size: CGFloat = 22) -> SKNode {
        let l = label(text, size, font: heavy, color: c, parent: floatLayer, at: p)
        l.setScale(0.4)
        l.run(SKAction.sequence([SKAction.group([SKAction.scale(to: 1, duration: 0.12),
                                                 SKAction.sequence([SKAction.wait(forDuration: 0.6), SKAction.fadeOut(withDuration: 0.5)])]),
                                 SKAction.removeFromParent()]))
        return l
    }

    func showResults(_ r: ResultsData) {
        xray.set(r.states, flash: false)
        let mk = xray.markers
        mk.removeAllChildren()
        var byRegion: [Region: (Int, Float)] = [:]
        for h in r.hits { let v = byRegion[h.region] ?? (0, 0); byRegion[h.region] = (v.0 + 1, v.1 + h.severity) }
        var rng = RNG(7)
        for (reg, v) in byRegion {
            let c = Skeleton.regionCenter[reg.rawValue]
            let rad = CGFloat(min(26, 7 + sqrtf(v.1) * 1.2))
            let ring = SKShapeNode(circleOfRadius: rad)
            ring.strokeColor = color(1, 0.85, 0.2, 0.95)
            ring.fillColor = color(1, 0.85, 0.2, 0.12)
            ring.lineWidth = 2.5
            ring.position = CGPoint(x: c.x + CGFloat(rng.range(-4, 4)), y: c.y + CGFloat(rng.range(-4, 4)))
            mk.addChild(ring)
            if v.0 > 1 {
                label("×\(v.0)", 13, font: heavy, color: color(1, 0.9, 0.3), align: .left, parent: mk, at: CGPoint(x: ring.position.x + rad + 2, y: ring.position.y + rad * 0.6), shadow: true)
            }
            ring.setScale(0.1)
            ring.run(SKAction.sequence([SKAction.wait(forDuration: 0.3 + Double(rng.range(0, 1.2))), SKAction.scale(to: 1, duration: 0.18)]))
        }
        let counts = (0..<5).map { k in r.states.filter { $0.rawValue == k }.count }
        setText(resTitle, r.record ? "NEW RECORD FALL!" : "X-RAY REPORT")
        resCashTarget = r.cash + r.bonus
        resCashShown = 0
        resShownAt = now
        resLines.removeAllChildren()
        var y: CGFloat = 0
        func line(_ t: String, _ c: NSColor = .white, _ s: CGFloat = 18) {
            label(t, s, font: bold, color: c, align: .left, parent: resLines, at: CGPoint(x: 0, y: y), shadow: true)
            y -= s + 10
        }
        line(String(format: "%.0f m cliff  ·  %.1f s  ·  top speed %.0f m/s", r.height, r.time, r.topSpeed), NSColor(white: 0.85, alpha: 1), 16)
        line("\(counts[3] + counts[4]) of 206 bones broken", .white, 22)
        line("Shattered: \(counts[4])     Broken: \(counts[3])", color(1, 0.45, 0.4))
        line("Cracked: \(counts[2])     Bruised: \(counts[1])     Untouched: \(counts[0])", color(1, 0.7, 0.65), 16)
        if r.bestCombo > 1 { line("Best combo: ×\(r.bestCombo)", color(1, 0.8, 0.2)) }
        if r.bonus > 0 { line("SKELETON BONUS  +\(money(r.bonus))", color(1, 0.85, 0.3)) }
        let worst = (0..<r.damage.count).sorted { r.damage[$0] > r.damage[$1] }.prefix(4).filter { r.damage[$0] > 38 }
        if !worst.isEmpty {
            line("Worst:", NSColor(white: 0.8, alpha: 1), 14)
            for w in worst { line("   \(Skeleton.bones[w].name) — \(r.states[w].label.lowercased())", NSColor(white: 0.78, alpha: 1), 14) }
        }
        setText(resHint, "SPACE  fall again     ⏎  shop")
    }

    // MARK: per-frame

    func update(_ s: HUDState, dt: Double) {
        now += dt
        setText(moneyLabel, money(s.money))
        setText(placeLabel, "\(maps[s.mapIdx].name)  ·  \(grouped(Int(heights[s.heightIdx]))) m  ·  ×\(String(format: "%g", maps[s.mapIdx].mult)) cash")
        saved.alpha = CGFloat(max(0, min(1, (savedUntil - now) * 2)))
        setText(musicLabel, "M  music \(s.musicOn ? "on" : "off")")
        setText(promptLabel, s.prompt)
        promptLabel.isHidden = s.prompt.isEmpty
        promptBG.isHidden = s.prompt.isEmpty
        if !s.prompt.isEmpty {
            let w = promptLabel.frame.width + 40
            promptBG.path = CGPath(roundedRect: CGRect(x: size.width / 2 - w / 2, y: 92, width: w, height: 38), cornerWidth: 10, cornerHeight: 10, transform: nil)
        }
        setText(controlsLabel, s.controls)
        let ta = now - toastStart
        let a = ta < toastDur ? 1 : max(0, 1 - (ta - toastDur) * 3)
        toast.alpha = CGFloat(a); toastSub.alpha = CGFloat(a)

        switch mode {
        case .title:
            pressStart.alpha = CGFloat(0.55 + 0.45 * sin(now * 3))
            logo.position.y = size.height * 0.64 + CGFloat(sin(now * 1.3) * 6)
        case .shop:
            updateShop(s)
        case .ready:
            let p = CGFloat(min(1, s.runSpeed / max(0.1, s.runMax)))
            runFill.path = CGPath(roundedRect: CGRect(x: -198, y: -10, width: max(1, 396 * p), height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil)
            runFill.fillColor = color(CGFloat(0.4 + 0.6 * p), CGFloat(1 - 0.6 * p), 0.15)
            setText(runLabel, String(format: "SPEED %.1f m/s", s.runSpeed))
            let e = s.toEdge
            setText(edgeLabel, e < 4 && e > 0 ? "JUMP!" : String(format: "%.0f m to the edge", max(0, e)))
            edgeLabel.alpha = e < 4 ? CGFloat(0.6 + 0.4 * sin(now * 20)) : 1
        case .fall:
            setText(fallCash, "+" + money(Int(s.fallCash)))
            setText(fallBones, "\(s.broken) of 206 bones broken  ·  \(s.shattered) shattered  ·  \(s.hurt) hurt")
            setText(speedLabel, String(format: "%.0f m/s", s.speed))
            setText(altLabel, (s.warp > 1.5 ? String(format: "⏩ ×%.0f   ", s.warp) : "") + "\(grouped(Int(max(0, s.altitude)))) m above the rocks")
            setText(comboLabel, s.combo > 1 ? "COMBO ×\(s.combo)" : "")
            setText(effectsLabel, s.effects)
            var shown = 0
            for (i, slot) in abSlots.enumerated() {
                let (owned, uses) = i < s.abilities.count ? s.abilities[i] : (false, 0)
                slot.bg.isHidden = !owned
                guard owned else { continue }
                slot.bg.position = CGPoint(x: CGFloat(shown) * 132 - CGFloat(s.abilities.filter { $0.0 }.count - 1) * 66, y: 0)
                shown += 1
                let txt = i == 6 ? (uses > 0 ? "FUEL \(uses)%" : "empty") : (uses > 0 ? "×\(uses)" : "used")
                setText(slot.uses, txt, color: uses > 0 ? color(0.5, 0.85, 1) : NSColor(white: 0.5, alpha: 1))
                slot.bg.alpha = uses > 0 ? 1 : 0.5
            }
            for (k, f) in feed.enumerated() {
                let age = now - f.born
                f.node.position = CGPoint(x: 0, y: -CGFloat(k) * 34)
                f.node.alpha = CGFloat(age < 5 ? 1 : max(0, 1 - (age - 5)))
            }
        case .results:
            let t = now - resShownAt
            if t > 0.4 && resCashShown < resCashTarget {
                resCashShown = min(resCashTarget, resCashShown + max(1, resCashTarget / 50))
            }
            setText(resCash, "+" + money(resCashShown))
        }
    }

    private func updateShop(_ s: HUDState) {
        let gold = color(1, 0.84, 0.3)
        func paint(_ r: Row, sel: Bool, cursor: Bool, hover: Bool) {
            r.bg.fillColor = sel ? color(0.2, 0.45, 0.2, 0.6) : (cursor || hover ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.4))
            r.bg.strokeColor = cursor ? gold : NSColor(white: 1, alpha: 0.1)
            r.bg.lineWidth = cursor ? 2.5 : 1
        }
        for i in 0..<maps.count {
            let m = maps[i], r = mapRows[i], owned = s.ownedMaps[i], sel = i == s.mapIdx
            setText(r.name, "\(i + 1).  \(m.name)", color: owned ? .white : NSColor(white: 0.6, alpha: 1))
            let mult = "×\(String(format: "%g", m.mult))"
            setText(r.info, owned ? (sel ? "✓  \(mult)" : mult) : "\(money(m.cost))  \(mult)",
                    color: owned ? (sel ? color(0.55, 1, 0.45) : NSColor(white: 0.8, alpha: 1)) : (s.money >= m.cost ? gold : color(0.9, 0.45, 0.4)))
            paint(r, sel: sel, cursor: s.cursorCol == 0 && s.cursorRow == i, hover: s.hover == "map:\(i)")
        }
        for i in 0..<heights.count {
            let r = heightRows[i], owned = s.ownedHeights[i], sel = i == s.heightIdx
            setText(r.name, "\(grouped(Int(heights[i]))) m", color: owned ? .white : NSColor(white: 0.6, alpha: 1))
            setText(r.info, owned ? (sel ? "✓" : String(format: "×%.1f", heightMult(heights[i]))) : money(heightCosts[i]),
                    color: owned ? (sel ? color(0.55, 1, 0.45) : NSColor(white: 0.8, alpha: 1)) : (s.money >= heightCosts[i] ? gold : color(0.9, 0.45, 0.4)))
            paint(r, sel: sel, cursor: s.cursorCol == 1 && s.cursorRow == i, hover: s.hover == "h:\(i)")
        }
        for i in 0..<upgrades.count {
            let u = upgrades[i], (r, pips, _) = upRows[i]
            let lvl = s.upLevels[i]
            setText(r.name, u.name)
            let maxed = lvl >= u.max
            setText(r.info, maxed ? "MAX" : money(u.costs[lvl]), color: maxed ? color(0.55, 1, 0.45) : (s.money >= u.costs[lvl] ? gold : color(0.9, 0.45, 0.4)))
            for (k, p) in pips.enumerated() { p.fillColor = k < lvl ? color(0.4, 0.9, 0.35) : NSColor(white: 1, alpha: 0.08) }
            paint(r, sel: false, cursor: s.cursorCol == 2 && s.cursorRow == i, hover: s.hover == "up:\(i)")
        }
        for i in 0..<abilities.count {
            let a = abilities[i], r = abRows[i]
            let owned = i < s.ownedAbilities.count && s.ownedAbilities[i]
            setText(r.name, "\(i + 1)  \(a.name)", color: owned ? .white : NSColor(white: 0.65, alpha: 1))
            setText(r.info, owned ? (i == 6 ? "OWNED" : "OWNED ×\(a.uses)") : money(a.cost), color: owned ? color(0.5, 0.85, 1) : (s.money >= a.cost ? gold : color(0.9, 0.45, 0.4)))
            paint(r, sel: owned, cursor: s.cursorCol == 2 && s.cursorRow == upgrades.count + i, hover: s.hover == "ab:\(i)")
        }
        let m = maps[s.cursorCol == 0 ? s.cursorRow : s.mapIdx]
        setText(blurb, "\(m.name): \(m.blurb)")
        var focusUp: Int? = s.cursorCol == 2 ? s.cursorRow : nil
        if let h = s.hover, h.hasPrefix("up:") { focusUp = Int(h.dropFirst(3)) }
        if let h = s.hover, h.hasPrefix("ab:"), let j = Int(h.dropFirst(3)) { focusUp = upgrades.count + j }
        if let fu = focusUp {
            if fu < upgrades.count { setText(blurb, "\(upgrades[fu].name): \(upgrades[fu].desc)") }
            else { let a = abilities[fu - upgrades.count]; setText(blurb, "\(a.name) (key \(fu - upgrades.count + 1)): \(a.desc). \(a.uses) use\(a.uses > 1 ? "s" : "") per fall.") }
        }
        var tags: [String] = []
        if m.sharp > 0.4 { tags.append("sharp rocks") }
        if m.friction < 0.3 { tags.append("slippery") }
        if m.hardness > 1.2 { tags.append("hard ground") }
        if m.rockDensity > 0.15 { tags.append("lots of boulders") }
        setText(blurb2, "Cash ×\(String(format: "%g", m.mult)) per bone" + (tags.isEmpty ? "" : "  ·  " + tags.joined(separator: " · ")) + String(format: "   ·   height bonus ×%.1f", heightMult(heights[s.heightIdx])))
        setText(statsLabel, "Falls: \(s.falls)   ·   Best fall: \(money(s.bestFall))   ·   Bones broken all-time: \(s.totalBones)")
        let pulse = s.hover == "jump" || s.cursorCol == 3 ? 1.08 : 1 + 0.03 * sin(now * 4)
        jumpBtn.setScale(CGFloat(pulse))
        jumpBtn.strokeColor = s.cursorCol == 3 ? gold : color(1, 0.8, 0.6)
    }
}
