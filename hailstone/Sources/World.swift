import SceneKit

/// A school sports hall (32 × 20 × 9 m) with a clear acrylic pen in the middle and an overhead gantry
/// that carries the ball dispenser.
final class World {
    let root = SCNNode()
    static let halfX: Float = 16, halfZ: Float = 10, ceiling: Float = 9
    /// Inner half-size of the acrylic pen.
    static let penX: Float = 5, penZ: Float = 3.5, penH: Float = 2.2
    static let nozzleY: Float = 3.3
    static let env = Tex.environment()

    let bridge = SCNNode()
    let carriage = SCNNode()
    let beacon: SCNMaterial
    let scoreMat = SCNMaterial()
    let keyLight = SCNNode()

    init() {
        beacon = World.pbr(NSColor(srgbRed: 1, green: 0.5, blue: 0.05, alpha: 1), rough: 0.3)
        buildFloor()
        buildWalls()
        buildCeiling()
        buildBleachers()
        buildHoops()
        buildScoreboard()
        buildPen()
        buildGantry()
        buildLights()
    }

    static func pbr(_ c: NSColor, rough: CGFloat, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    private func box(_ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial, at p: SIMD3<Float>, chamfer: Float = 0) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(chamfer))
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = p
        root.addChildNode(n)
        return n
    }

    private func staticBody(_ node: SCNNode, _ cat: Int, restitution: CGFloat, friction: CGFloat = 0.5) {
        let b = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: node.geometry!, options: nil))
        b.restitution = restitution
        b.friction = friction
        b.categoryBitMask = cat
        b.collisionBitMask = Mask.all
        b.contactTestBitMask = Mask.ball
        node.physicsBody = b
    }

    private func tiled(_ maps: SurfaceMaps, scale: SIMD2<Float>) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = maps.diffuse
        m.roughness.contents = maps.rough
        m.normal.contents = maps.normal
        m.metalness.contents = 0.0
        for p in [m.diffuse, m.roughness, m.normal] {
            p.wrapS = .repeat; p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 16
            p.contentsTransform = SCNMatrix4MakeScale(CGFloat(scale.x), CGFloat(scale.y), 1)
        }
        return m
    }

    // MARK: Floor and court markings

    private func buildFloor() {
        let maple = Tex.maple()
        let m = tiled(maple, scale: SIMD2(World.halfX * 2 / 4, World.halfZ * 2 / 4))
        // The visible floor is an SCNFloor so the varnish gives a true planar reflection.
        let vis = SCNFloor()
        vis.width = CGFloat(World.halfX * 2)
        vis.length = CGFloat(World.halfZ * 2)
        vis.reflectivity = CommandLine.arguments.contains("--norefl") ? 0 : 0.06
        vis.reflectionFalloffStart = 0
        vis.reflectionFalloffEnd = 1.2
        vis.reflectionResolutionScaleFactor = 0.6
        vis.reflectionCategoryBitMask = 1 | 2
        vis.materials = [m]
        let visNode = SCNNode(geometry: vis)
        root.addChildNode(visNode)
        // Invisible slab for physics and click picking.
        let slab = SCNMaterial()
        slab.colorBufferWriteMask = []
        slab.writesToDepthBuffer = false
        let floor = box(World.halfX * 2, 0.3, World.halfZ * 2, slab, at: SIMD3(0, -0.15, 0))
        floor.castsShadow = false
        floor.name = "floor"
        floor.categoryBitMask = 3
        staticBody(floor, Mask.floor, restitution: 0.9, friction: 0.55)

        let paint = World.pbr(NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1), rough: 0.35)
        let red = World.pbr(NSColor(srgbRed: 0.55, green: 0.07, blue: 0.06, alpha: 1), rough: 0.35)
        func strip(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float, _ w: Float = 0.05, _ mat: SCNMaterial? = nil) {
            let lx = max(abs(x1 - x0), w), lz = max(abs(z1 - z0), w)
            let p = SCNPlane(width: CGFloat(lx), height: CGFloat(lz))
            p.materials = [mat ?? paint]
            let n = SCNNode(geometry: p)
            n.eulerAngles.x = -.pi / 2
            n.simdPosition = SIMD3((x0 + x1) / 2, 0.0015, (z0 + z1) / 2)
            n.castsShadow = false
            root.addChildNode(n)
        }
        func ring(_ cx: Float, _ r: Float, from a0: CGFloat, to a1: CGFloat, w: CGFloat = 0.05, _ mat: SCNMaterial? = nil) {
            let path = NSBezierPath()
            path.appendArc(withCenter: .zero, radius: CGFloat(r) + w / 2, startAngle: a0, endAngle: a1)
            path.appendArc(withCenter: .zero, radius: CGFloat(r) - w / 2, startAngle: a1, endAngle: a0, clockwise: true)
            path.close()
            path.flatness = 0.002
            let s = SCNShape(path: path, extrusionDepth: 0)
            s.materials = [mat ?? paint]
            let n = SCNNode(geometry: s)
            n.eulerAngles.x = -.pi / 2
            n.simdPosition = SIMD3(cx, 0.0016, 0)
            n.castsShadow = false
            root.addChildNode(n)
        }
        let hx: Float = 14, hz: Float = 7.5
        strip(-hx, -hz, hx, -hz); strip(-hx, hz, hx, hz)
        strip(-hx, -hz, -hx, hz); strip(hx, -hz, hx, hz)
        strip(0, -hz, 0, hz)
        ring(0, 1.8, from: 0, to: 360)
        for s in [-1, 1] as [Float] {
            // painted key
            let kx = hx - 2.9
            let key = SCNPlane(width: 5.8, height: 4.9)
            key.materials = [red]
            let kn = SCNNode(geometry: key)
            kn.eulerAngles.x = -.pi / 2
            kn.simdPosition = SIMD3(s * kx, 0.0012, 0)
            kn.castsShadow = false
            root.addChildNode(kn)
            strip(s * (hx - 5.8), -2.45, s * (hx - 5.8), 2.45)
            strip(s * hx, -2.45, s * (hx - 5.8), -2.45); strip(s * hx, 2.45, s * (hx - 5.8), 2.45)
            ring(s * (hx - 5.8), 1.8, from: s > 0 ? 90 : -90, to: s > 0 ? 270 : 90)
            // three-point arc
            ring(s * (hx - 1.575), 6.75, from: s > 0 ? 113 : -67, to: s > 0 ? 247 : 67)
            strip(s * hx, -6.6, s * (hx - 1.575 - 2.6), -6.6); strip(s * hx, 6.6, s * (hx - 1.575 - 2.6), 6.6)
        }
    }

    // MARK: Walls, ceiling

    private func buildWalls() {
        let cream = Tex.blocks(paint: SIMD3(0.84, 0.81, 0.72))
        let blue = Tex.blocks(paint: SIMD3(0.13, 0.22, 0.42))
        let H = World.ceiling, lower: Float = 2.4
        let t: Float = 0.3
        for (i, len) in [World.halfX * 2, World.halfX * 2, World.halfZ * 2, World.halfZ * 2].enumerated() {
            let alongX = i < 2
            let sign: Float = i % 2 == 0 ? -1 : 1
            let up = tiled(cream, scale: SIMD2(len / 1.6, (H - lower) / 1.6))
            let lo = tiled(blue, scale: SIMD2(len / 1.6, lower / 1.6))
            let off = (alongX ? World.halfZ : World.halfX) + t / 2
            let pos: (Float) -> SIMD3<Float> = { y in alongX ? SIMD3(0, y, sign * off) : SIMD3(sign * off, y, 0) }
            let a = box(alongX ? len + 2 * t : t, H - lower, alongX ? t : len, up, at: pos(lower + (H - lower) / 2))
            let b = box(alongX ? len + 2 * t : t, lower, alongX ? t : len, lo, at: pos(lower / 2))
            staticBody(a, Mask.room, restitution: 0.6)
            staticBody(b, Mask.room, restitution: 0.6)
            // rubber cove base
            let cove = World.pbr(NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1), rough: 0.6)
            let inset = alongX ? World.halfZ - 0.006 : World.halfX - 0.006
            _ = box(alongX ? len : 0.012, 0.1, alongX ? 0.012 : len, cove, at: alongX ? SIMD3(0, 0.05, sign * inset) : SIMD3(sign * inset, 0.05, 0))
        }
    }

    private func buildCeiling() {
        let deck = World.pbr(NSColor(srgbRed: 0.2, green: 0.21, blue: 0.22, alpha: 1), rough: 0.5, metal: 0.6)
        _ = box(World.halfX * 2, 0.2, World.halfZ * 2, deck, at: SIMD3(0, World.ceiling + 0.1, 0))
        let steel = World.pbr(NSColor(srgbRed: 0.24, green: 0.25, blue: 0.27, alpha: 1), rough: 0.45, metal: 0.8)
        var x: Float = -14
        while x <= 14.01 {
            _ = box(0.25, 0.9, World.halfZ * 2, steel, at: SIMD3(x, World.ceiling - 0.45, 0))
            x += 4
        }
        let housing = World.pbr(NSColor(srgbRed: 0.6, green: 0.62, blue: 0.64, alpha: 1), rough: 0.25, metal: 1)
        let lens = SCNMaterial()
        lens.lightingModel = .constant
        lens.diffuse.contents = NSColor(srgbRed: 1, green: 0.97, blue: 0.9, alpha: 1)
        lens.emission.contents = NSColor(srgbRed: 1, green: 0.97, blue: 0.9, alpha: 1)
        lens.emission.intensity = 6
        for i in 0..<5 { for k in 0..<3 {
            let p = SIMD3<Float>(Float(i - 2) * 6, World.ceiling - 1.2, Float(k - 1) * 6)
            let bell = SCNCone(topRadius: 0.12, bottomRadius: 0.42, height: 0.45)
            bell.materials = [housing]
            let bn = SCNNode(geometry: bell)
            bn.simdPosition = p
            root.addChildNode(bn)
            let disc = SCNCylinder(radius: 0.38, height: 0.01)
            disc.materials = [lens]
            let dn = SCNNode(geometry: disc)
            dn.simdPosition = p - SIMD3(0, 0.23, 0)
            dn.castsShadow = false
            root.addChildNode(dn)
            let cord = SCNCylinder(radius: 0.01, height: 0.75)
            cord.materials = [steel]
            let cn = SCNNode(geometry: cord)
            cn.simdPosition = p + SIMD3(0, 0.6, 0)
            root.addChildNode(cn)
        }}
    }

    private func buildBleachers() {
        var wood = Tex.maple(size: 1024, meters: 4)
        wood = SurfaceMaps(diffuse: wood.diffuse, rough: wood.rough, normal: wood.normal)
        let seat = tiled(wood, scale: SIMD2(5, 0.2))
        seat.multiply.contents = NSColor(srgbRed: 0.85, green: 0.72, blue: 0.6, alpha: 1)
        let riser = World.pbr(NSColor(srgbRed: 0.1, green: 0.11, blue: 0.13, alpha: 1), rough: 0.5, metal: 0.3)
        let len: Float = 22
        for s in 0..<6 {
            let depth: Float = 0.75
            let z = -World.halfZ + 0.2 + Float(5 - s) * depth + depth / 2
            let top = 0.42 * Float(s + 1)
            let r = box(len, top, depth, riser, at: SIMD3(0, top / 2, z))
            staticBody(r, Mask.room, restitution: 0.5)
            _ = box(len, 0.05, depth * 0.96, seat, at: SIMD3(0, top + 0.025, z))
        }
        let rail = World.pbr(NSColor(srgbRed: 0.7, green: 0.72, blue: 0.74, alpha: 1), rough: 0.2, metal: 1)
        for sx in [-1, 1] as [Float] {
            let n = box(0.05, 1.0, 4.6, rail, at: SIMD3(sx * len / 2, 2.9, -World.halfZ + 2.5))
            n.eulerAngles.x = -0.5
        }
    }

    private func buildHoops() {
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = NSColor(white: 1, alpha: 1)
        glass.transparency = 0.12
        glass.roughness.contents = 0.02
        glass.metalness.contents = 0
        glass.isDoubleSided = true
        glass.writesToDepthBuffer = false
        let white = World.pbr(.white, rough: 0.4)
        let orange = World.pbr(NSColor(srgbRed: 0.9, green: 0.3, blue: 0.05, alpha: 1), rough: 0.35, metal: 0.4)
        let steel = World.pbr(NSColor(srgbRed: 0.35, green: 0.36, blue: 0.38, alpha: 1), rough: 0.4, metal: 0.8)
        for s in [-1, 1] as [Float] {
            let bx = s * (World.halfX - 1.2)
            let b = box(0.02, 1.05, 1.8, glass, at: SIMD3(bx, 3.45, 0))
            b.castsShadow = false
            for (dy, h) in [(0.52, 0.05), (-0.52, 0.05)] as [(Float, Float)] { _ = box(0.03, h, 1.8, white, at: SIMD3(bx, 3.45 + dy, 0)) }
            for dz in [-0.88, 0.88] as [Float] { _ = box(0.03, 1.05, 0.05, white, at: SIMD3(bx, 3.45, dz)) }
            _ = box(0.03, 0.45, 0.04, white, at: SIMD3(bx, 3.3, -0.3)); _ = box(0.03, 0.45, 0.04, white, at: SIMD3(bx, 3.3, 0.3))
            _ = box(0.03, 0.04, 0.6, white, at: SIMD3(bx, 3.52, 0)); _ = box(0.03, 0.04, 0.6, white, at: SIMD3(bx, 3.09, 0))
            let rim = SCNTorus(ringRadius: 0.23, pipeRadius: 0.01)
            rim.materials = [orange]
            let rn = SCNNode(geometry: rim)
            rn.simdPosition = SIMD3(bx - s * 0.38, 3.05, 0)
            root.addChildNode(rn)
            _ = box(1.1, 0.12, 0.12, steel, at: SIMD3(s * (World.halfX - 0.6), 3.45, 0))
            _ = box(0.1, 0.1, 0.1, steel, at: SIMD3(bx - s * 0.1, 3.05, 0))
            // wall pad behind the hoop
            let pad = World.pbr(NSColor(srgbRed: 0.1, green: 0.16, blue: 0.36, alpha: 1), rough: 0.7)
            _ = box(0.06, 1.8, 6, pad, at: SIMD3(s * (World.halfX - 0.03), 1.1, 0), chamfer: 0.02)
        }
    }

    private func buildScoreboard() {
        let frame = World.pbr(NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1), rough: 0.4, metal: 0.5)
        _ = box(4.3, 2.3, 0.3, frame, at: SIMD3(0, 6.3, -World.halfZ + 0.15))
        scoreMat.lightingModel = .constant
        scoreMat.diffuse.contents = NSColor.black
        scoreMat.emission.contents = Tex.scoreboard(seed: nil, step: 0, total: 0, now: nil, peak: 0)
        scoreMat.emission.intensity = 1.6
        let p = SCNPlane(width: 4, height: 2)
        p.materials = [scoreMat]
        let n = SCNNode(geometry: p)
        n.simdPosition = SIMD3(0, 6.3, -World.halfZ + 0.31)
        n.castsShadow = false
        root.addChildNode(n)
    }

    // MARK: The pen

    private func buildPen() {
        // Clear sheet: nearly no diffuse, a faint grazing-angle reflection of the hall.
        let acrylic = SCNMaterial()
        acrylic.lightingModel = .blinn
        acrylic.diffuse.contents = NSColor(srgbRed: 0.5, green: 0.56, blue: 0.6, alpha: 1)
        acrylic.specular.contents = NSColor(white: 0.9, alpha: 1)
        acrylic.shininess = 120
        acrylic.reflective.contents = World.env
        acrylic.reflective.intensity = 0.55
        acrylic.fresnelExponent = 2.2
        acrylic.transparent.contents = World.smudges()
        acrylic.transparencyMode = .aOne
        acrylic.transparency = 1
        acrylic.blendMode = .alpha
        acrylic.isDoubleSided = true
        acrylic.writesToDepthBuffer = false
        let alu = World.pbr(NSColor(srgbRed: 0.78, green: 0.79, blue: 0.8, alpha: 1), rough: 0.28, metal: 1)
        let rubber = World.pbr(NSColor(srgbRed: 0.03, green: 0.03, blue: 0.035, alpha: 1), rough: 0.8)
        let X = World.penX, Z = World.penZ, H = World.penH
        let th: Float = 0.02
        for (alongX, sign) in [(true, -1), (true, 1), (false, -1), (false, 1)] as [(Bool, Float)] {
            let len = alongX ? X * 2 : Z * 2
            let pos = alongX ? SIMD3(0, H / 2, sign * (Z + th / 2)) : SIMD3(sign * (X + th / 2), H / 2, 0)
            let panel = box(alongX ? len : th, H, alongX ? th : len, acrylic, at: pos)
            panel.castsShadow = false
            panel.renderingOrder = 10
            // thicker invisible collider sitting just outside the sheet
            let coll = SCNNode(geometry: SCNBox(width: CGFloat(alongX ? len + 0.4 : 0.2), height: CGFloat(H + 0.1), length: CGFloat(alongX ? 0.2 : len + 0.4), chamferRadius: 0))
            coll.simdPosition = alongX ? SIMD3(0, (H + 0.1) / 2, sign * (Z + 0.1)) : SIMD3(sign * (X + 0.1), (H + 0.1) / 2, 0)
            coll.isHidden = true
            root.addChildNode(coll)
            staticBody(coll, Mask.glass, restitution: 0.75, friction: 0.25)
            // top rail and floor gasket
            _ = box(alongX ? len + 0.08 : 0.05, 0.05, alongX ? 0.05 : len + 0.08, alu, at: SIMD3(pos.x, H + 0.025, pos.z))
            _ = box(alongX ? len : 0.06, 0.04, alongX ? 0.06 : len, rubber, at: SIMD3(pos.x, 0.02, pos.z))
        }
        // posts every 2.5 m
        var posts: [SIMD2<Float>] = []
        var x: Float = -X
        while x <= X + 0.01 { posts.append(SIMD2(x, -Z)); posts.append(SIMD2(x, Z)); x += 2.5 }
        var z: Float = -Z + 3.5
        while z < Z - 0.01 { posts.append(SIMD2(-X, z)); posts.append(SIMD2(X, z)); z += 3.5 }
        for p in posts {
            _ = box(0.06, H + 0.06, 0.06, alu, at: SIMD3(p.x + (p.x < 0 ? -0.02 : 0.02) * (abs(p.x) == X ? 1 : 0), (H + 0.06) / 2, p.y + (p.y < 0 ? -0.02 : 0.02) * (abs(p.y) == Z ? 1 : 0)))
            _ = box(0.3, 0.02, 0.3, alu, at: SIMD3(p.x, 0.01, p.y))
        }
    }

    // MARK: Gantry

    private func buildGantry() {
        let yellow = World.pbr(NSColor(srgbRed: 0.95, green: 0.72, blue: 0.08, alpha: 1), rough: 0.4, metal: 0.2)
        let steel = World.pbr(NSColor(srgbRed: 0.3, green: 0.31, blue: 0.33, alpha: 1), rough: 0.35, metal: 0.9)
        let chrome = World.pbr(NSColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1), rough: 0.08, metal: 1)
        let railY: Float = 4.5
        for s in [-1, 1] as [Float] {
            _ = box(12.6, 0.28, 0.16, steel, at: SIMD3(0, railY, s * (World.penZ + 0.7)))
            for x in [-5.5, 0, 5.5] as [Float] {
                let rod = SCNCylinder(radius: 0.018, height: CGFloat(World.ceiling - 0.9 - railY))
                rod.materials = [steel]
                let n = SCNNode(geometry: rod)
                n.simdPosition = SIMD3(x, (railY + World.ceiling - 0.9) / 2, s * (World.penZ + 0.7))
                root.addChildNode(n)
            }
        }
        root.addChildNode(bridge)
        bridge.simdPosition = SIMD3(0, railY - 0.26, 0)
        let beam = SCNBox(width: 0.3, height: 0.24, length: CGFloat(World.penZ * 2 + 1.7), chamferRadius: 0.01)
        beam.materials = [yellow]
        bridge.addChildNode(SCNNode(geometry: beam))
        for s in [-1, 1] as [Float] {
            let truck = SCNNode(geometry: SCNBox(width: 0.5, height: 0.2, length: 0.3, chamferRadius: 0.02))
            truck.geometry?.materials = [steel]
            truck.simdPosition = SIMD3(0, 0.16, s * (World.penZ + 0.7))
            bridge.addChildNode(truck)
        }
        bridge.addChildNode(carriage)
        carriage.simdPosition = SIMD3(0, -0.24, 0)
        let body = SCNNode(geometry: SCNBox(width: 0.55, height: 0.26, length: 0.55, chamferRadius: 0.03))
        body.geometry?.materials = [yellow]
        carriage.addChildNode(body)
        let motor = SCNNode(geometry: SCNCylinder(radius: 0.1, height: 0.3))
        motor.geometry?.materials = [steel]
        motor.eulerAngles.z = .pi / 2
        motor.simdPosition = SIMD3(0.35, 0.02, 0)
        carriage.addChildNode(motor)
        // dispenser tube down to the nozzle
        let top = railY - 0.26 - 0.24 - 0.13
        let tubeLen = top - World.nozzleY
        let tube = SCNTube(innerRadius: 0.17, outerRadius: 0.2, height: CGFloat(tubeLen))
        tube.materials = [chrome]
        let tn = SCNNode(geometry: tube)
        tn.simdPosition = SIMD3(0, -0.13 - tubeLen / 2, 0)
        carriage.addChildNode(tn)
        let lip = SCNTorus(ringRadius: 0.2, pipeRadius: 0.025)
        lip.materials = [chrome]
        let ln = SCNNode(geometry: lip)
        ln.simdPosition = SIMD3(0, -0.13 - tubeLen, 0)
        carriage.addChildNode(ln)
        let lamp = SCNNode(geometry: SCNSphere(radius: 0.05))
        beacon.emission.contents = NSColor(srgbRed: 1, green: 0.45, blue: 0.02, alpha: 1)
        beacon.emission.intensity = 0
        lamp.geometry?.materials = [beacon]
        lamp.simdPosition = SIMD3(0, 0.16, 0.18)
        carriage.addChildNode(lamp)
    }

    func setGantry(x: Float, z: Float) {
        bridge.simdPosition.x = x
        carriage.simdPosition.z = z
    }

    // MARK: Light

    /// Alpha map for the acrylic: almost clear, with hand smears at leaning height, dusty lower edge,
    /// and the odd ball scuff. Alpha is opacity.
    static func smudges() -> CGImage {
        var rng = RNG(777)
        return makeImage(4096, 1024) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.055))
            ctx.fill(CGRect(x: 0, y: 0, width: 4096, height: 1024))
            ctx.scaleBy(x: 4, y: 4)
            // dust settling toward the bottom
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0.07), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 40), options: [])
            // palm and finger smears around 1–1.4 m (upper half of a 2.2 m sheet)
            for _ in 0..<14 {
                let x = CGFloat(rng.float()) * 1024, y = CGFloat(rng.range(110, 175))
                ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.scaleBy(x: 0.3, y: 0.3); ctx.translateBy(x: -x, y: -y)
                for f in 0..<4 {
                    let fx = x + CGFloat(f) * 7 + CGFloat(rng.range(-2, 2)), l = CGFloat(rng.range(14, 40))
                    ctx.setFillColor(CGColor(gray: 1, alpha: CGFloat(rng.range(0.012, 0.025))))
                    ctx.fillEllipse(in: CGRect(x: fx, y: y - l, width: 5, height: l))
                }
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.02))
                ctx.fillEllipse(in: CGRect(x: x - 4, y: y - 60, width: 34, height: 30))
                ctx.restoreGState()
            }
            // round scuffs where balls hit, low on the sheet
            for _ in 0..<40 {
                let x = CGFloat(rng.float()) * 1024, y = CGFloat(rng.range(5, 90)), r = CGFloat(rng.range(3, 12))
                ctx.setStrokeColor(CGColor(gray: 1, alpha: CGFloat(rng.range(0.02, 0.05))))
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// Overhead high-bay lamps over the pen: each casts its own soft shadow, so balls get the
    /// overlapping multi-shadow look of a real gym.
    private func buildLampSpots() {
        for (i, x) in ([-6, 0, 6] as [Float]).enumerated() {
            let l = SCNLight()
            l.type = .spot
            l.intensity = 150
            l.color = NSColor(srgbRed: 1, green: 0.95, blue: 0.86, alpha: 1)
            l.spotInnerAngle = 60
            l.spotOuterAngle = 120
            l.castsShadow = true
            l.shadowMode = .forward
            l.shadowMapSize = CGSize(width: 2048, height: 2048)
            l.shadowSampleCount = 8
            l.shadowRadius = 6
            l.shadowBias = 1.6
            l.zNear = 3
            l.zFar = 12
            l.shadowColor = NSColor(white: 0, alpha: 0.55)
            let n = SCNNode()
            n.light = l
            n.simdPosition = SIMD3(x, World.ceiling - 1.45, i == 1 ? 0.4 : -0.4)
            n.simdLook(at: SIMD3(x * 0.5, 0, 0), up: SIMD3(0, 0, -1), localFront: SIMD3(0, 0, -1))
            root.addChildNode(n)
        }
    }

    /// Dust motes drifting in the lamp light over the pen.
    private func buildDust() {
        let ps = SCNParticleSystem()
        ps.particleImage = softDotImage(size: 32)
        ps.birthRate = 30
        ps.particleLifeSpan = 16
        ps.particleLifeSpanVariation = 6
        ps.particleSize = 0.004
        ps.particleSizeVariation = 0.003
        ps.particleColor = NSColor(srgbRed: 1, green: 0.95, blue: 0.85, alpha: 0.5)
        ps.particleColorVariation = SCNVector4(0, 0, 0, 0.3)
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.speedFactor = 1
        ps.particleVelocity = 0.03
        ps.particleVelocityVariation = 0.03
        ps.acceleration = SCNVector3(0, -0.004, 0)
        ps.warmupDuration = 16
        ps.emitterShape = SCNBox(width: 12, height: 5, length: 9, chamferRadius: 0)
        ps.birthLocation = .volume
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 180
        let n = SCNNode()
        n.simdPosition = SIMD3(0, 3, 0)
        n.addParticleSystem(ps)
        root.addChildNode(n)
    }

    private func buildLights() {
        buildLampSpots()
        buildDust()
        let k = SCNLight()
        k.type = .directional
        k.intensity = 650
        k.color = NSColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1)
        k.castsShadow = true
        k.shadowMode = .forward
        k.shadowMapSize = CGSize(width: 4096, height: 4096)
        k.shadowSampleCount = 16
        k.shadowRadius = 5
        k.shadowBias = 0.25
        k.orthographicScale = 13
        k.zNear = 1
        k.zFar = 40
        k.shadowColor = NSColor(white: 0, alpha: 0.78)
        k.automaticallyAdjustsShadowProjection = false
        keyLight.light = k
        keyLight.simdPosition = SIMD3(2, 16, 4)
        keyLight.simdLook(at: SIMD3(0, 0, 0), up: SIMD3(0, 0, -1), localFront: SIMD3(0, 0, -1))
        root.addChildNode(keyLight)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 60
        amb.color = NSColor(srgbRed: 1, green: 0.93, blue: 0.85, alpha: 1)
        let an = SCNNode()
        an.light = amb
        root.addChildNode(an)
    }
}
