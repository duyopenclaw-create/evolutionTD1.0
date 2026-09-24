import SceneKit
import simd

enum FoodKind: Int, CaseIterable {
    case crumb, cheerio, fry, kibble, cheese, bread, grape, crust, cookie, peel, bone, core, popcorn, peanut, bacon, bait

    var name: String {
        ["bread crumb", "cereal loop", "french fry", "cat kibble", "cheese", "bread crust", "grape", "pizza crust",
         "cookie", "banana peel", "chicken bone", "apple core", "popcorn", "peanut", "bacon bit", "trap bait"][rawValue]
    }
    /// Belly filled by eating all of it.
    var nutrition: Float { [0.04, 0.05, 0.12, 0.06, 0.4, 0.35, 0.1, 0.3, 0.25, 0.08, 0.2, 0.15, 0.04, 0.12, 0.1, 0.15][rawValue] }
    /// Stash points when carried home.
    var value: Int { [1, 1, 3, 1, 12, 9, 3, 8, 6, 2, 5, 4, 1, 4, 3, 5][rawValue] }
    var carriable: Bool { ![FoodKind.cheese, .bread, .bait].contains(self) }
    var reach: Float { [0.04, 0.04, 0.06, 0.04, 0.08, 0.08, 0.045, 0.08, 0.06, 0.07, 0.07, 0.06, 0.04, 0.045, 0.045, 0.05][rawValue] }
}

final class Food {
    let kind: FoodKind
    let node: SCNNode
    var pos: SIMD3<Float>
    var left: Float = 1          // fraction remaining
    var carried = false
    var gone = false
    weak var trap: Trap?

    init(kind: FoodKind, node: SCNNode, pos: SIMD3<Float>) {
        self.kind = kind; self.node = node; self.pos = pos
    }
}

final class Trap {
    let node = SCNNode()
    let bail = SCNNode()
    let pos: SIMD3<Float>
    let yaw: Float
    var armed = true
    var springT: Float = 0
    var bait: Food?

    init(pos: SIMD3<Float>, yaw: Float) { self.pos = pos; self.yaw = yaw }

    /// Trigger pedal centre in world space.
    var pedal: SIMD3<Float> {
        let f = SIMD3<Float>(sinf(yaw), 0, cosf(yaw))
        return pos + f * 0.022
    }
}

/// A light object that can be shoved off an edge: a mug, a glass, a spoon.
final class Knockable {
    enum Kind { case mug, glass, spoon }
    let kind: Kind
    let node: SCNNode
    var pos: SIMD3<Float>
    var vel = SIMD3<Float>.zero
    var spin = SIMD3<Float>.zero
    let r: Float
    var falling = false
    var broken = false
    var resting = true

    init(kind: Kind, node: SCNNode, pos: SIMD3<Float>, r: Float) {
        self.kind = kind; self.node = node; self.pos = pos; self.r = r
    }
}

/// Builds food, traps and knockables for a night.
final class Props {
    let root = SCNNode()
    private(set) var foods: [Food] = []
    private(set) var traps: [Trap] = []
    private(set) var knockables: [Knockable] = []
    private var mats: [FoodKind: SCNMaterial] = [:]
    private let kitchen: Kitchen
    private let trapWood: SCNMaterial
    private let wire: SCNMaterial
    private let ceramic: SCNMaterial
    private let glassMat: SCNMaterial

    init(kitchen: Kitchen) {
        self.kitchen = kitchen
        trapWood = Mat.pbr(Tex.wood(base: Tex.lin(0.78, 0.64, 0.45), dark: Tex.lin(0.6, 0.46, 0.3), seed: 91, rings: 30, gloss: 0.7))
        wire = Mat.plain(color(0.75, 0.75, 0.72), rough: 0.25, metal: 1)
        ceramic = Mat.plain(color(0.93, 0.92, 0.9), rough: 0.12)
        glassMat = Mat.plain(color(0.8, 0.85, 0.9), rough: 0.02)
        glassMat.transparency = 0.25
        glassMat.blendMode = .alpha
        let L = Tex.lin
        mats[.crumb] = Mat.pbr(Tex.food(L(0.82, 0.68, 0.45), L(0.55, 0.36, 0.18), freq: 8, seed: 1, rough: 0.8))
        mats[.cheerio] = Mat.pbr(Tex.food(L(0.85, 0.62, 0.28), L(0.7, 0.45, 0.18), freq: 16, seed: 2, rough: 0.7))
        mats[.fry] = Mat.pbr(Tex.food(L(0.95, 0.78, 0.35), L(0.8, 0.55, 0.2), freq: 6, seed: 3, rough: 0.35))
        mats[.kibble] = Mat.pbr(Tex.food(L(0.45, 0.28, 0.14), L(0.3, 0.18, 0.08), freq: 12, seed: 4, rough: 0.6))
        mats[.cheese] = Mat.pbr(Tex.cheese())
        mats[.bread] = Mat.pbr(Tex.food(L(0.62, 0.38, 0.16), L(0.9, 0.8, 0.6), freq: 10, seed: 5, rough: 0.8))
        mats[.grape] = Mat.plain(color(0.35, 0.12, 0.3), rough: 0.18)
        mats[.crust] = Mat.pbr(Tex.food(L(0.78, 0.5, 0.22), L(0.55, 0.3, 0.12), freq: 8, seed: 6, rough: 0.6))
        mats[.cookie] = Mat.pbr(Tex.food(L(0.78, 0.56, 0.3), L(0.25, 0.14, 0.08), freq: 10, seed: 7, rough: 0.7))
        mats[.peel] = Mat.pbr(Tex.food(L(0.95, 0.82, 0.25), L(0.35, 0.25, 0.1), freq: 12, seed: 8, rough: 0.4))
        mats[.bone] = Mat.pbr(Tex.food(L(0.88, 0.8, 0.66), L(0.6, 0.42, 0.28), freq: 6, seed: 9, rough: 0.5))
        mats[.core] = Mat.pbr(Tex.food(L(0.95, 0.9, 0.7), L(0.6, 0.45, 0.2), freq: 6, seed: 10, rough: 0.5))
        mats[.popcorn] = Mat.pbr(Tex.food(L(0.97, 0.95, 0.85), L(0.95, 0.8, 0.4), freq: 5, seed: 11, rough: 0.8))
        mats[.peanut] = Mat.pbr(Tex.food(L(0.75, 0.55, 0.32), L(0.6, 0.4, 0.22), freq: 8, seed: 12, rough: 0.7))
        mats[.bacon] = Mat.pbr(Tex.food(L(0.55, 0.15, 0.1), L(0.9, 0.7, 0.55), freq: 6, seed: 13, rough: 0.3))
        mats[.bait] = mats[.cheese]
        buildStatic()
    }

    /// Plates and bowls that don't change between nights.
    private func buildStatic() {
        let plate = SCNCylinder(radius: 0.12, height: 0.012)
        plate.radialSegmentCount = 40
        plate.materials = [ceramic]
        let pn = SCNNode(geometry: plate)
        pn.simdPosition = SIMD3(0.45, 0.766, 0.42)
        root.addChildNode(pn)
        kitchen.world.add(Solid(x: 0.45, z: 0.42, w: 0.2, d: 0.2, y0: 0.76, y1: 0.772, surface: .stone, name: "plate"))
        let napkin = texturedBox(0.16, 0.003, 0.16, kitchen.mLinen, span: 0.3)
        napkin.simdPosition = SIMD3(0.75, 0.7615, 0.6)
        napkin.simdEulerAngles = SIMD3(0, 0.3, 0)
        root.addChildNode(napkin)
    }

    // MARK: Night setup

    func reset(night: Int, extraTraps: Int, seed: UInt64) {
        for f in foods { f.node.removeFromParentNode() }
        for t in traps { t.node.removeFromParentNode() }
        for k in knockables { k.node.removeFromParentNode() }
        foods = []; traps = []; knockables = []
        clearShards()
        var rng = RNG(seed)

        func scatter(_ kind: FoodKind, _ c: SIMD3<Float>, _ n: Int, _ spread: Float, chance: Float = 1) {
            for _ in 0..<n where rng.chance(chance) {
                let p = c + SIMD3(rng.range(-spread, spread), 0, rng.range(-spread, spread))
                add(kind, p, yaw: rng.range(0, 6.28), rng: &rng)
            }
        }
        // Floor
        scatter(.crumb, SIMD3(0.6, 0, 0.5), 6, 0.45)
        scatter(.cheerio, SIMD3(-0.75, 0, -1.25), 6, 0.18)
        add(.bone, SIMD3(-2.33, 0, -0.86), yaw: 0.6, rng: &rng)
        add(.peel, SIMD3(-2.5, 0, -0.68), yaw: 1.2, rng: &rng)
        add(.core, SIMD3(-2.18, 0, -1.02), yaw: 0, rng: &rng)
        scatter(.popcorn, SIMD3(-2.3, 0, -0.72), 3, 0.12)
        scatter(.fry, SIMD3(1.3, 0, -1.45), 2, 0.12)
        scatter(.kibble, SIMD3(2.72, 0.02, 0.9), 5, 0.04)
        scatter(.kibble, SIMD3(2.55, 0, 0.95), 3, 0.1)
        add(.peanut, SIMD3(1.35, 0, 1.75), yaw: 0.3, rng: &rng)
        // Counter
        add(.bread, SIMD3(-2.0, 0.92, -2.08), yaw: 0.4, rng: &rng)
        add(.cheese, SIMD3(-2.16, 0.92, -2.12), yaw: -0.3, rng: &rng)
        scatter(.crumb, SIMD3(-2.62, 0.9, -2.16), 3, 0.06)
        scatter(.grape, SIMD3(-0.22, 0.9, -2.12), 2, 0.05)
        scatter(.bacon, SIMD3(0.09, 0.936, -2.05), 3, 0.05)
        scatter(.cheerio, SIMD3(-1.3, 0.7, -2.12), 3, 0.06)
        // Table, chair, recycling
        add(.crust, SIMD3(0.45, 0.772, 0.42), yaw: 0.8, rng: &rng)
        add(.cookie, SIMD3(1.0, 0.76, 0.7), yaw: 0, rng: &rng)
        scatter(.crumb, SIMD3(0.7, 0.76, 0.55), 4, 0.18)
        add(.peanut, SIMD3(0.95, 0.46, -0.2), yaw: 1, rng: &rng)
        add(.crust, SIMD3(2.45, 0.46, -2.25), yaw: 2.2, rng: &rng)

        // Traps: more every night, and more again if the family saw you
        let count = min(kitchen.trapSpots.count, 2 + night + extraTraps)
        var spots = Array(kitchen.trapSpots.indices)
        for i in stride(from: spots.count - 1, to: 0, by: -1) { spots.swapAt(i, rng.int(i + 1)) }
        for i in 0..<count {
            let (p, yaw) = kitchen.trapSpots[spots[i]]
            addTrap(p, yaw: yaw, rng: &rng)
        }

        addKnockable(.mug, SIMD3(-0.24, 0.9, -1.93))
        addKnockable(.glass, SIMD3(1.2, 0.76, 0.96))
        addKnockable(.spoon, SIMD3(-0.03, 0.76, 0.62))
    }

    @discardableResult
    private func add(_ kind: FoodKind, _ p: SIMD3<Float>, yaw: Float, rng: inout RNG) -> Food {
        let n = model(kind, rng: &rng)
        n.simdPosition = p
        n.simdEulerAngles.y = yaw
        root.addChildNode(n)
        let f = Food(kind: kind, node: n, pos: p)
        foods.append(f)
        return f
    }

    /// Small food models at real size.
    private func model(_ kind: FoodKind, rng: inout RNG) -> SCNNode {
        let m = mats[kind]!
        let n = SCNNode()
        func sph(_ r: Float, _ s: SIMD3<Float>, _ at: SIMD3<Float>, _ mat: SCNMaterial? = nil) {
            let g = SCNSphere(radius: CGFloat(r))
            g.segmentCount = 16
            g.materials = [mat ?? m]
            let c = SCNNode(geometry: g)
            c.simdScale = s
            c.simdPosition = at
            n.addChildNode(c)
        }
        switch kind {
        case .crumb:
            let s = rng.range(0.004, 0.009)
            let b = SCNBox(width: CGFloat(s * rng.range(0.8, 1.5)), height: CGFloat(s * 0.7), length: CGFloat(s), chamferRadius: CGFloat(s * 0.3))
            b.materials = [m]
            let c = SCNNode(geometry: b)
            c.simdPosition.y = s * 0.35
            c.simdEulerAngles = SIMD3(rng.range(-0.4, 0.4), 0, rng.range(-0.4, 0.4))
            n.addChildNode(c)
        case .cheerio:
            let t = SCNTorus(ringRadius: 0.0055, pipeRadius: 0.0027)
            t.materials = [m]
            let c = SCNNode(geometry: t)
            c.simdPosition.y = 0.0027
            c.simdEulerAngles.x = rng.range(-0.3, 0.3)
            n.addChildNode(c)
        case .fry:
            let b = SCNBox(width: 0.009, height: 0.009, length: 0.075, chamferRadius: 0.002)
            b.materials = [m]
            let c = SCNNode(geometry: b)
            c.simdPosition.y = 0.0045
            n.addChildNode(c)
        case .kibble:
            let c = SCNCylinder(radius: 0.0055, height: 0.006)
            c.materials = [m]
            let cn = SCNNode(geometry: c)
            cn.simdPosition.y = 0.003
            cn.simdEulerAngles.x = rng.range(-0.5, 0.5)
            n.addChildNode(cn)
        case .cheese, .bait:
            let big = kind == .cheese
            let p = NSBezierPath()
            let L: CGFloat = big ? 0.11 : 0.016, W: CGFloat = big ? 0.07 : 0.014
            p.move(to: CGPoint(x: 0, y: 0)); p.line(to: CGPoint(x: L, y: -W / 2)); p.line(to: CGPoint(x: L, y: W / 2)); p.close()
            let s = SCNShape(path: p, extrusionDepth: big ? 0.045 : 0.01)
            s.chamferRadius = big ? 0.003 : 0.001
            s.materials = [m]
            let c = SCNNode(geometry: s)
            c.simdEulerAngles.x = -.pi / 2
            c.simdPosition = SIMD3(Float(-L) / 2, Float(big ? 0.0225 : 0.005), 0)
            n.addChildNode(c)
        case .bread:
            let b = SCNBox(width: 0.1, height: 0.075, length: 0.035, chamferRadius: 0.012)
            let crumb = Mat.pbr(Tex.food(Tex.lin(0.92, 0.84, 0.66), Tex.lin(0.82, 0.7, 0.5), freq: 24, seed: 21, rough: 0.9))
            b.materials = [crumb, m, m, m, m, m]
            let c = SCNNode(geometry: b)
            c.simdPosition.y = 0.0375
            n.addChildNode(c)
        case .grape:
            sph(0.0105, SIMD3(1, 1.15, 1), SIMD3(0, 0.011, 0))
        case .crust:
            let p = NSBezierPath()
            p.appendArc(withCenter: .zero, radius: 0.06, startAngle: 200, endAngle: 340)
            p.appendArc(withCenter: .zero, radius: 0.045, startAngle: 340, endAngle: 200, clockwise: true)
            p.close()
            p.flatness = 0.001
            let s = SCNShape(path: p, extrusionDepth: 0.014)
            s.chamferRadius = 0.005
            s.materials = [m]
            let c = SCNNode(geometry: s)
            c.simdEulerAngles.x = -.pi / 2
            c.simdPosition = SIMD3(0, 0.007, -0.05)
            n.addChildNode(c)
        case .cookie:
            let c = SCNCylinder(radius: 0.032, height: 0.009)
            c.materials = [m]
            let cn = SCNNode(geometry: c)
            cn.simdPosition.y = 0.0045
            n.addChildNode(cn)
            let choc = Mat.plain(color(0.16, 0.08, 0.04), rough: 0.4)
            for _ in 0..<6 {
                let a = rng.range(0, 6.28), r = rng.range(0, 0.024)
                sph(0.004, SIMD3(1, 0.6, 1), SIMD3(cosf(a) * r, 0.009, sinf(a) * r), choc)
            }
        case .peel:
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi + 0.3
                let b = SCNBox(width: 0.02, height: 0.004, length: 0.07, chamferRadius: 0.002)
                b.materials = [m]
                let c = SCNNode(geometry: b)
                c.simdPosition = SIMD3(sinf(a) * 0.035, 0.003, cosf(a) * 0.035)
                c.simdEulerAngles = SIMD3(0.1, a, 0)
                n.addChildNode(c)
            }
            sph(0.012, SIMD3(1, 1, 1.4), SIMD3(0, 0.01, 0))
        case .bone:
            let c = SCNCapsule(capRadius: 0.006, height: 0.07)
            c.materials = [m]
            let cn = SCNNode(geometry: c)
            cn.simdEulerAngles.x = .pi / 2
            cn.simdPosition.y = 0.008
            n.addChildNode(cn)
            sph(0.011, SIMD3(1, 0.8, 1), SIMD3(0, 0.009, 0.036))
            sph(0.009, SIMD3(1, 0.8, 1), SIMD3(0, 0.008, -0.036))
        case .core:
            let c = SCNCylinder(radius: 0.012, height: 0.05)
            c.materials = [m]
            let cn = SCNNode(geometry: c)
            cn.simdEulerAngles.z = .pi / 2
            cn.simdPosition.y = 0.014
            n.addChildNode(cn)
            let skin = Mat.plain(color(0.7, 0.12, 0.1), rough: 0.3)
            sph(0.022, SIMD3(0.5, 1, 1), SIMD3(0.026, 0.02, 0), skin)
            sph(0.022, SIMD3(0.5, 1, 1), SIMD3(-0.026, 0.02, 0), skin)
        case .popcorn:
            for _ in 0..<4 { sph(0.0055, SIMD3(1, 1, 1), SIMD3(rng.range(-0.005, 0.005), rng.range(0.005, 0.01), rng.range(-0.005, 0.005))) }
        case .peanut:
            sph(0.007, SIMD3(1, 1, 1), SIMD3(0, 0.007, 0.006))
            sph(0.0065, SIMD3(1, 1, 1), SIMD3(0, 0.0065, -0.006))
        case .bacon:
            let b = SCNBox(width: 0.012, height: 0.004, length: 0.02, chamferRadius: 0.0015)
            b.materials = [m]
            let c = SCNNode(geometry: b)
            c.simdPosition.y = 0.003
            c.simdEulerAngles = SIMD3(rng.range(-0.3, 0.3), 0, rng.range(-0.3, 0.3))
            n.addChildNode(c)
        }
        return n
    }

    private func addTrap(_ p: SIMD3<Float>, yaw: Float, rng: inout RNG) {
        let t = Trap(pos: p, yaw: yaw)
        t.node.simdPosition = p
        t.node.simdEulerAngles.y = yaw
        let base = texturedBox(0.046, 0.011, 0.1, trapWood, span: 0.15, chamfer: 0.001, grainVertical: false)
        base.simdPosition.y = 0.0055
        t.node.addChildNode(base)
        // printed brand stamp: a darker band
        let band = SCNBox(width: 0.03, height: 0.0005, length: 0.02, chamferRadius: 0)
        band.materials = [Mat.plain(color(0.35, 0.2, 0.1), rough: 0.8)]
        let bn = SCNNode(geometry: band)
        bn.simdPosition = SIMD3(0, 0.0112, -0.03)
        t.node.addChildNode(bn)
        // spring coils at the hinge
        for s in [-0.012, 0.012] as [Float] {
            let coil = SCNTube(innerRadius: 0.0035, outerRadius: 0.0048, height: 0.008)
            coil.materials = [wire]
            let cn = SCNNode(geometry: coil)
            cn.simdEulerAngles.z = .pi / 2
            cn.simdPosition = SIMD3(s, 0.015, 0)
            t.node.addChildNode(cn)
        }
        // bail: a U of wire hinged at the middle; armed it lies back over the far end
        t.bail.simdPosition = SIMD3(0, 0.013, 0)
        t.node.addChildNode(t.bail)
        func wireSeg(_ a: SIMD3<Float>, _ b: SIMD3<Float>, parent: SCNNode) {
            let d = b - a
            let c = SCNCylinder(radius: 0.0008, height: CGFloat(simd_length(d)))
            c.radialSegmentCount = 6
            c.materials = [wire]
            let n = SCNNode(geometry: c)
            n.simdPosition = (a + b) / 2
            n.simdLook(at: b, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 1, 0))
            parent.addChildNode(n)
        }
        wireSeg(SIMD3(-0.019, 0, 0), SIMD3(-0.019, 0, 0.042), parent: t.bail)
        wireSeg(SIMD3(0.019, 0, 0), SIMD3(0.019, 0, 0.042), parent: t.bail)
        wireSeg(SIMD3(-0.019, 0, 0.042), SIMD3(0.019, 0, 0.042), parent: t.bail)
        // pedal + arm
        let pedal = SCNBox(width: 0.018, height: 0.0015, length: 0.022, chamferRadius: 0.0005)
        pedal.materials = [wire]
        let pn = SCNNode(geometry: pedal)
        pn.simdPosition = SIMD3(0, 0.0118, 0.024)
        t.node.addChildNode(pn)
        wireSeg(SIMD3(0.004, 0.012, -0.045), SIMD3(0.004, 0.0135, 0.0), parent: t.node)
        t.bail.simdEulerAngles.x = -.pi + 0.08         // cocked back over the far end
        root.addChildNode(t.node)
        // bait on the pedal
        let bait = add(.bait, t.pedal + SIMD3(0, 0.012, 0), yaw: yaw, rng: &rng)
        bait.trap = t
        t.bait = bait
        traps.append(t)
    }

    private func addKnockable(_ kind: Knockable.Kind, _ p: SIMD3<Float>) {
        let n = SCNNode()
        var r: Float = 0.04
        switch kind {
        case .mug:
            let body = SCNTube(innerRadius: 0.037, outerRadius: 0.041, height: 0.095)
            body.radialSegmentCount = 32
            let glaze = Mat.plain(color(0.18, 0.32, 0.5), rough: 0.12)
            body.materials = [glaze]
            let b = SCNNode(geometry: body)
            b.simdPosition.y = 0.0475
            n.addChildNode(b)
            let bottom = SCNCylinder(radius: 0.038, height: 0.006)
            bottom.materials = [glaze]
            let bb = SCNNode(geometry: bottom)
            bb.simdPosition.y = 0.003
            n.addChildNode(bb)
            let coffee = SCNCylinder(radius: 0.037, height: 0.002)
            coffee.materials = [Mat.plain(color(0.1, 0.05, 0.02), rough: 0.05)]
            let cf = SCNNode(geometry: coffee)
            cf.simdPosition.y = 0.035
            n.addChildNode(cf)
            let h = SCNTorus(ringRadius: 0.022, pipeRadius: 0.005)
            h.materials = [glaze]
            let hn = SCNNode(geometry: h)
            hn.simdPosition = SIMD3(0.045, 0.05, 0)
            hn.simdEulerAngles.x = .pi / 2
            n.addChildNode(hn)
            r = 0.045
        case .glass:
            let body = SCNTube(innerRadius: 0.03, outerRadius: 0.033, height: 0.12)
            body.radialSegmentCount = 32
            body.materials = [glassMat]
            let b = SCNNode(geometry: body)
            b.simdPosition.y = 0.06
            b.castsShadow = false
            n.addChildNode(b)
            let water = SCNCylinder(radius: 0.03, height: 0.05)
            let wm = Mat.plain(color(0.7, 0.8, 0.85), rough: 0.02)
            wm.transparency = 0.2
            water.materials = [wm]
            let wn = SCNNode(geometry: water)
            wn.simdPosition.y = 0.028
            wn.castsShadow = false
            n.addChildNode(wn)
            r = 0.035
        case .spoon:
            let handle = SCNBox(width: 0.008, height: 0.002, length: 0.11, chamferRadius: 0.001)
            handle.materials = [wire]
            let hn = SCNNode(geometry: handle)
            hn.simdPosition = SIMD3(0, 0.003, -0.02)
            n.addChildNode(hn)
            let bowl = SCNSphere(radius: 0.018)
            bowl.materials = [wire]
            let bn = SCNNode(geometry: bowl)
            bn.simdScale = SIMD3(0.8, 0.2, 1.2)
            bn.simdPosition = SIMD3(0, 0.004, 0.05)
            n.addChildNode(bn)
            r = 0.03
        }
        n.simdPosition = p
        root.addChildNode(n)
        knockables.append(Knockable(kind: kind, node: n, pos: p, r: r))
    }

    // MARK: Updates

    func spring(_ t: Trap) {
        t.armed = false
        t.springT = 0
    }

    /// Animate sprung bails; returns nothing (game plays sounds on trigger).
    func animate(_ dt: Float) {
        for t in traps where !t.armed && t.springT < 1 {
            t.springT = min(1, t.springT + dt * 18)
            let a = mixf(-.pi + 0.08, -0.04, t.springT * t.springT)
            t.bail.simdEulerAngles.x = a
        }
    }

    /// Shatter a mug or glass into a handful of shards where it landed.
    func shatter(_ k: Knockable) {
        k.broken = true
        let at = k.node.simdPosition
        k.node.removeFromParentNode()
        let n = SCNNode()
        var rng = RNG(UInt64(abs(at.x * 1000 + at.z * 77)) + 5)
        let mat: SCNMaterial = k.kind == .mug ? Mat.plain(color(0.18, 0.32, 0.5), rough: 0.12) : glassMat
        for _ in 0..<(k.kind == .mug ? 9 : 12) {
            let s = rng.range(0.006, 0.02)
            let b = SCNBox(width: CGFloat(s), height: 0.003, length: CGFloat(s * rng.range(0.4, 1)), chamferRadius: 0.0005)
            b.materials = [mat]
            let c = SCNNode(geometry: b)
            let a = rng.range(0, 6.28), d = rng.range(0, 0.14) * rng.range(0.3, 1)
            c.simdPosition = SIMD3(cosf(a) * d, 0.0015, sinf(a) * d)
            c.simdEulerAngles = SIMD3(0, rng.range(0, 6.28), 0)
            n.addChildNode(c)
        }
        if k.kind == .mug {
            let spill = SCNCylinder(radius: 0.08, height: 0.0008)
            let sm = Mat.plain(color(0.08, 0.04, 0.02), rough: 0.02)
            spill.materials = [sm]
            let sn = SCNNode(geometry: spill)
            sn.simdScale = SIMD3(1.4, 1, 1)
            sn.simdPosition.y = 0.0004
            n.addChildNode(sn)
        }
        n.simdPosition = SIMD3(at.x, 0, at.z)
        root.addChildNode(n)
        k.node.name = "shards"
        // keep the shards around as this knockable's node so a reset clears them
        knockablesShards.append(n)
    }
    private var knockablesShards: [SCNNode] = []

    func clearShards() {
        for s in knockablesShards { s.removeFromParentNode() }
        knockablesShards = []
    }

    func remove(_ f: Food) {
        f.gone = true
        f.node.removeFromParentNode()
    }
}
