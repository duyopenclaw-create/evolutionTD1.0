import SceneKit
import simd

/// The kitchen at 1:1 metric scale. The room spans x −3…3, z −2.5…2.5 and is 2.6 m high;
/// north (−z) holds the counter run, sink window, stove and fridge.
final class Kitchen {
    let root = SCNNode()
    let world: CollisionWorld

    // Lights
    let moon = SCNNode()
    let ambient = SCNNode()
    let hoodLight = SCNNode()
    let nightLight = SCNNode()
    let ceilingLight = SCNNode()
    let hallLight = SCNNode()
    let fridgeLight = SCNNode()
    let dawnLight = SCNNode()
    private(set) var ceilingBulb: SCNMaterial!
    private(set) var hallBulb: SCNMaterial!
    let moonDir = simd_normalize(SIMD3<Float>(0.3, -0.62, 0.72))
    let window = (lo: SIMD3<Float>(-1.7, 1.05, -2.5), hi: SIMD3<Float>(-0.7, 2.0, -2.5))
    private(set) var skyMat: SCNMaterial!

    // Moving parts
    let fridgeDoor = SCNNode()
    private(set) var ovenClock: SCNMaterial!
    private(set) var microClock: SCNMaterial!
    let dripNode = SCNNode()

    // Gameplay anchors
    let nest = SIMD3<Float>(-1.8, 0, 2.47)
    let catBed = SIMD3<Float>(2.42, 0.1, 1.95)
    let door = SIMD3<Float>(-3.0, 0, 1.05)
    let fridgeFront = SIMD3<Float>(1.65, 0, -1.25)
    let sinkSpout = SIMD3<Float>(-1.2, 1.16, -2.2)
    let wallClock = SIMD3<Float>(0.8, 1.9, 2.48)
    let fridgePos = SIMD3<Float>(1.65, 0.4, -2.15)
    /// Low gaps a rat fits into and a cat doesn't.
    let hideouts: [(lo: SIMD2<Float>, hi: SIMD2<Float>, name: String)] = [
        (SIMD2(-0.1, -2.5), SIMD2(0.66, -1.9), "under the stove"),
        (SIMD2(1.2, -2.5), SIMD2(2.1, -1.8), "under the fridge"),
    ]
    let trapSpots: [(SIMD3<Float>, Float)] = [
        (SIMD3(-2.9, 0, 0.1), .pi / 2), (SIMD3(2.9, 0, -0.6), .pi / 2), (SIMD3(0.3, 0, 2.43), 0),
        (SIMD3(-0.55, 0, -1.84), 0), (SIMD3(2.25, 0, -1.72), 0), (SIMD3(-2.35, 0, 2.43), 0),
        (SIMD3(1.6, 0, 2.43), 0), (SIMD3(-2.92, 0, -0.9), .pi / 2), (SIMD3(2.9, 0, 0.35), .pi / 2),
    ]
    /// Wander targets for the cat (all on the floor, clear of furniture).
    let catWaypoints: [SIMD3<Float>] = [
        SIMD3(2.3, 0, 1.5), SIMD3(1.8, 0, 0.3), SIMD3(-0.6, 0, 0.2), SIMD3(-1.9, 0, 0.8), SIMD3(-2.2, 0, -1.3),
        SIMD3(-0.9, 0, -1.2), SIMD3(0.4, 0, -1.4), SIMD3(1.65, 0, -1.3), SIMD3(2.6, 0, -0.6), SIMD3(-1.0, 0, 1.9),
        SIMD3(0.6, 0, 2.0), SIMD3(2.55, 0, 0.8),
    ]

    // Shared materials
    let tileSet: TexSet
    let mTile, mCab, mQuartz, mWall, mSubway, mSteel, mWalnut, mOak, mTrim, mCeiling: SCNMaterial
    let mChrome, mBlackGlass, mCast, mTowel, mLinen, mRug, mPlush, mBag, mCard, mWhitePlastic: SCNMaterial

    init() {
        tileSet = Tex.floorTiles()
        mTile = Mat.pbr(tileSet)
        mCab = Mat.pbr(Tex.paintedWood(Tex.lin(0.42, 0.5, 0.44)))
        mQuartz = Mat.pbr(Tex.quartz())
        mWall = Mat.pbr(Tex.plaster(Tex.lin(0.78, 0.74, 0.66)), normalScale: 0.2)
        mSubway = Mat.pbr(Tex.subway())
        mSteel = Mat.pbr(Tex.steel(), metal: 1)
        mWalnut = Mat.pbr(Tex.wood(base: Tex.lin(0.36, 0.23, 0.14), dark: Tex.lin(0.18, 0.1, 0.06), seed: 11, rings: 22, gloss: 0.38))
        mOak = Mat.pbr(Tex.wood(base: Tex.lin(0.62, 0.46, 0.3), dark: Tex.lin(0.42, 0.28, 0.16), seed: 17, rings: 14, gloss: 0.5))
        mTrim = Mat.pbr(Tex.paintedWood(Tex.lin(0.88, 0.87, 0.83)))
        mCeiling = Mat.pbr(Tex.plaster(Tex.lin(0.86, 0.85, 0.82)), normalScale: 0.2)
        mChrome = Mat.plain(color(0.9, 0.9, 0.92), rough: 0.08, metal: 1)
        mBlackGlass = Mat.plain(color(0.02, 0.02, 0.025), rough: 0.06, metal: 0)
        mCast = Mat.plain(color(0.05, 0.05, 0.05), rough: 0.55, metal: 0.6)
        mTowel = Mat.pbr(Tex.towelPlaid())
        mLinen = Mat.pbr(Tex.linen())
        mRug = Mat.pbr(Tex.runnerRug())
        mPlush = Mat.pbr(Tex.plush(Tex.lin(0.55, 0.52, 0.48)), normalScale: 0.3)
        for p in [mPlush.diffuse, mPlush.roughness, mPlush.normal] { p.contentsTransform = SCNMatrix4MakeScale(10, 3, 1) }
        mBag = Mat.pbr(Tex.binBag())
        mCard = Mat.pbr(Tex.cardboard())
        mWhitePlastic = Mat.plain(color(0.9, 0.9, 0.88), rough: 0.35)

        // Floor: rug is fabric (quiet); everything else is tile.
        world = CollisionWorld { x, z in
            (x > -2.2 && x < -0.3 && z > -1.85 && z < -1.15) ? .fabric : .tile
        }

        buildRoom()
        buildCounters()
        buildStove()
        buildFridge()
        buildTable()
        buildClutter()
        buildLights()
    }

    // MARK: Helpers

    @discardableResult
    private func box(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, _ m: SCNMaterial, span: Float = 1, chamfer: Float = 0.002, vertical: Bool = false, parent: SCNNode? = nil) -> SCNNode {
        let s = hi - lo
        let n = texturedBox(s.x, s.y, s.z, m, span: span, chamfer: chamfer, grainVertical: vertical)
        n.simdPosition = (lo + hi) / 2
        (parent ?? root).addChildNode(n)
        return n
    }

    @discardableResult
    private func solid(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, _ m: SCNMaterial?, span: Float = 1, chamfer: Float = 0.002,
                       climb: Bool = false, surface: Surface = .wood, perch: Bool = true, name: String = "", vertical: Bool = false) -> SCNNode? {
        world.add(Solid(lo, hi, climb: climb, surface: surface, perch: perch, name: name))
        guard let m = m else { return nil }
        return box(lo, hi, m, span: span, chamfer: chamfer, vertical: vertical)
    }

    private func cyl(_ r: Float, _ h: Float, _ m: SCNMaterial, at p: SIMD3<Float>, seg: Int = 32, parent: SCNNode? = nil) -> SCNNode {
        let c = SCNCylinder(radius: CGFloat(r), height: CGFloat(h))
        c.radialSegmentCount = seg
        c.materials = [m]
        let n = SCNNode(geometry: c)
        n.simdPosition = p
        (parent ?? root).addChildNode(n)
        return n
    }

    // MARK: Room shell

    private func buildRoom() {
        // Floor slab
        let floor = texturedBox(6.2, 0.1, 5.2, mTile, span: 0.6, chamfer: 0)
        floor.simdPosition = SIMD3(0, -0.05, 0)
        root.addChildNode(floor)
        // Ceiling
        box(SIMD3(-3.1, 2.6, -2.6), SIMD3(3.1, 2.7, 2.6), mCeiling, span: 2)

        let t: Float = 0.12
        // North wall with the sink window cut out
        solid(SIMD3(-3.1, 0, -2.5 - t), SIMD3(window.lo.x, 2.6, -2.5), mWall, span: 1.5, name: "wall")
        solid(SIMD3(window.hi.x, 0, -2.5 - t), SIMD3(3.1, 2.6, -2.5), mWall, span: 1.5, name: "wall")
        solid(SIMD3(window.lo.x, 0, -2.5 - t), SIMD3(window.hi.x, window.lo.y, -2.5), mWall, span: 1.5, name: "wall")
        solid(SIMD3(window.lo.x, window.hi.y, -2.5 - t), SIMD3(window.hi.x, 2.6, -2.5), mWall, span: 1.5, name: "wall")
        // South wall
        solid(SIMD3(-3.1, 0, 2.5), SIMD3(3.1, 2.6, 2.5 + t), mWall, span: 1.5, name: "wall")
        // East wall
        solid(SIMD3(3.0, 0, -2.6), SIMD3(3.0 + t, 2.6, 2.6), mWall, span: 1.5, name: "wall")
        // West wall with the hallway door
        solid(SIMD3(-3.0 - t, 0, -2.6), SIMD3(-3.0, 2.6, 0.6), mWall, span: 1.5, name: "wall")
        solid(SIMD3(-3.0 - t, 0, 1.5), SIMD3(-3.0, 2.6, 2.6), mWall, span: 1.5, name: "wall")
        box(SIMD3(-3.0 - t, 2.1, 0.6), SIMD3(-3.0, 2.6, 1.5), mWall, span: 1.5)
        // invisible gate: the rat stays in the kitchen
        world.add(Solid(SIMD3(-3.3, 0, 0.6), SIMD3(-3.0, 0.5, 1.5), name: "gate"))

        // Door casing
        box(SIMD3(-3.02, 0, 0.52), SIMD3(-2.98, 2.18, 0.6), mTrim)
        box(SIMD3(-3.02, 0, 1.5), SIMD3(-2.98, 2.18, 1.58), mTrim)
        box(SIMD3(-3.02, 2.1, 0.52), SIMD3(-2.98, 2.18, 1.58), mTrim)
        // Hallway beyond
        let hallWood = Mat.pbr(Tex.wood(base: Tex.lin(0.5, 0.36, 0.24), dark: Tex.lin(0.3, 0.2, 0.12), seed: 23))
        box(SIMD3(-6, -0.1, 0.3), SIMD3(-3, 0, 1.8), hallWood, span: 1.2)
        box(SIMD3(-6, 0, 0.2), SIMD3(-3.12, 2.6, 0.3), mWall, span: 1.5)
        box(SIMD3(-6, 0, 1.8), SIMD3(-3.12, 2.6, 1.9), mWall, span: 1.5)
        box(SIMD3(-6.1, 0, 0.2), SIMD3(-6, 2.6, 1.9), mWall, span: 1.5)
        box(SIMD3(-6, 2.6, 0.2), SIMD3(-3.1, 2.7, 1.9), mCeiling, span: 2)
        // a framed photo in the hall
        box(SIMD3(-5.2, 1.3, 0.3), SIMD3(-4.7, 1.7, 0.32), Mat.plain(color(0.1, 0.08, 0.06), rough: 0.4))

        // Baseboards
        let bh: Float = 0.1, bt: Float = 0.014
        box(SIMD3(-3, 0, -2.5), SIMD3(3, bh, -2.5 + bt), mTrim, span: 1)
        box(SIMD3(-3, 0, 2.5 - bt), SIMD3(nest.x - 0.07, bh, 2.5), mTrim, span: 1)
        box(SIMD3(nest.x + 0.07, 0, 2.5 - bt), SIMD3(3, bh, 2.5), mTrim, span: 1)
        box(SIMD3(3 - bt, 0, -2.5), SIMD3(3, bh, 2.5), mTrim, span: 1)
        box(SIMD3(-3, 0, -2.5), SIMD3(-3 + bt, bh, 0.52), mTrim, span: 1)
        box(SIMD3(-3, 0, 1.58), SIMD3(-3 + bt, bh, 2.5), mTrim, span: 1)
        buildNestHole()

        // Window: frame, sill, mullion, glass, the night outside
        let wf = Mat.pbr(Tex.paintedWood(Tex.lin(0.9, 0.9, 0.87)))
        let wl = window.lo, wh = window.hi
        box(SIMD3(wl.x - 0.06, wl.y - 0.03, -2.52), SIMD3(wh.x + 0.06, wl.y + 0.03, -2.38), mQuartz)        // sill
        world.add(Solid(SIMD3(wl.x - 0.06, wl.y - 0.03, -2.52), SIMD3(wh.x + 0.06, wl.y + 0.03, -2.38), surface: .stone, name: "sill"))
        box(SIMD3(wl.x - 0.06, wh.y, -2.54), SIMD3(wh.x + 0.06, wh.y + 0.06, -2.46), wf)
        box(SIMD3(wl.x - 0.06, wl.y, -2.54), SIMD3(wl.x, wh.y, -2.46), wf)
        box(SIMD3(wh.x, wl.y, -2.54), SIMD3(wh.x + 0.06, wh.y, -2.46), wf)
        box(SIMD3(wl.x, wl.y, -2.56), SIMD3(wh.x, wl.y + 0.04, -2.53), wf)
        box(SIMD3((wl.x + wh.x) / 2 - 0.02, wl.y, -2.56), SIMD3((wl.x + wh.x) / 2 + 0.02, wh.y, -2.53), wf)
        box(SIMD3(wl.x, (wl.y + wh.y) / 2 - 0.02, -2.56), SIMD3(wh.x, (wl.y + wh.y) / 2 + 0.02, -2.53), wf)
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = NSColor(white: 0.02, alpha: 1)
        glass.roughness.contents = 0.03
        glass.metalness.contents = 0
        glass.transparency = 0.12
        glass.blendMode = .alpha
        glass.writesToDepthBuffer = false
        let gl = SCNPlane(width: CGFloat(wh.x - wl.x), height: CGFloat(wh.y - wl.y))
        gl.materials = [glass]
        let gn = SCNNode(geometry: gl)
        gn.simdPosition = SIMD3((wl.x + wh.x) / 2, (wl.y + wh.y) / 2, -2.545)
        gn.castsShadow = false
        root.addChildNode(gn)
        // Curtains, tied back either side
        for side in [-1, 1] as [Float] {
            let cx = side < 0 ? wl.x - 0.14 : wh.x + 0.14
            let c = texturedBox(0.18, 1.2, 0.05, mLinen, span: 0.5, chamfer: 0.02, grainVertical: true)
            c.simdPosition = SIMD3(cx, 1.5, -2.42)
            root.addChildNode(c)
        }
        cyl(0.012, 1.5, mChrome, at: SIMD3((wl.x + wh.x) / 2, 2.12, -2.42)).simdEulerAngles = SIMD3(0, 0, .pi / 2)
        buildOutside()

        // Light switch by the door, wall clock, a framed print on the east wall
        box(SIMD3(-2.995, 1.15, 0.36), SIMD3(-2.985, 1.27, 0.44), mWhitePlastic)
        buildWallClock()
        let print = SCNPlane(width: 0.5, height: 0.65)
        print.materials = [printMaterial()]
        let pn = SCNNode(geometry: print)
        pn.simdPosition = SIMD3(2.985, 1.55, 0.4)
        pn.simdEulerAngles = SIMD3(0, -.pi / 2, 0)
        root.addChildNode(pn)
        box(SIMD3(2.97, 1.2, 0.12), SIMD3(2.995, 1.9, 0.68), Mat.plain(color(0.08, 0.06, 0.05), rough: 0.5), chamfer: 0.004)
        pn.simdPosition.x = 2.965

        // Ceiling fixture
        ceilingBulb = Mat.glow(color(1, 0.97, 0.9), 0)
        let dome = SCNSphere(radius: 0.2)
        dome.materials = [ceilingBulb]
        let dn = SCNNode(geometry: dome)
        dn.simdScale = SIMD3(1, 0.3, 1)
        dn.simdPosition = SIMD3(0.3, 2.6, 0)
        dn.castsShadow = false
        root.addChildNode(dn)
    }

    private func buildNestHole() {
        // A gnawed arch through the baseboard into the dark wall cavity.
        let p = NSBezierPath()
        let w: CGFloat = 0.1, h: CGFloat = 0.06
        p.move(to: CGPoint(x: -w / 2, y: 0))
        p.line(to: CGPoint(x: -w / 2, y: h))
        p.appendArc(withCenter: CGPoint(x: 0, y: h), radius: w / 2, startAngle: 180, endAngle: 0, clockwise: true)
        p.line(to: CGPoint(x: w / 2, y: 0))
        p.close()
        p.flatness = 0.002
        let hole = SCNShape(path: p, extrusionDepth: 0.004)
        hole.materials = [Mat.glow(NSColor(white: 0.0, alpha: 1), 0)]
        let hn = SCNNode(geometry: hole)
        hn.simdPosition = SIMD3(nest.x, 0.0, 2.497)
        hn.simdEulerAngles = SIMD3(0, .pi, 0)
        root.addChildNode(hn)
        // chewed rim
        let rim = NSBezierPath()
        rim.move(to: CGPoint(x: -w / 2 - 0.012, y: 0))
        rim.line(to: CGPoint(x: -w / 2 - 0.012, y: h))
        rim.appendArc(withCenter: CGPoint(x: 0, y: h), radius: w / 2 + 0.012, startAngle: 180, endAngle: 0, clockwise: true)
        rim.line(to: CGPoint(x: w / 2 + 0.012, y: 0))
        rim.close()
        let rs = SCNShape(path: rim, extrusionDepth: 0.003)
        rs.materials = [Mat.plain(color(0.28, 0.2, 0.13), rough: 0.9)]
        let rn = SCNNode(geometry: rs)
        rn.simdPosition = SIMD3(nest.x, 0.0, 2.4985)
        rn.simdEulerAngles = SIMD3(0, .pi, 0)
        root.addChildNode(rn)
        // shredded paper just inside
        var rng = RNG(404)
        for _ in 0..<14 {
            let b = SCNBox(width: CGFloat(rng.range(0.01, 0.03)), height: 0.002, length: CGFloat(rng.range(0.004, 0.01)), chamferRadius: 0)
            b.materials = [Mat.plain(color(CGFloat(rng.range(0.7, 0.9)), CGFloat(rng.range(0.65, 0.85)), CGFloat(rng.range(0.55, 0.75))), rough: 0.9)]
            let n = SCNNode(geometry: b)
            n.simdPosition = SIMD3(nest.x + rng.range(-0.05, 0.05), 0.002, 2.49 - rng.range(0, 0.03))
            n.simdEulerAngles = SIMD3(0, rng.range(0, 3), 0)
            root.addChildNode(n)
        }
    }

    private func buildOutside() {
        let img = makePixelImage(1024, 640) { x, y in
            let u = Float(x) / 1024, v = Float(y) / 640         // v = 0 top
            var c = mix3(SIMD3(0.004, 0.007, 0.02), SIMD3(0.03, 0.04, 0.08), v)
            // stars
            if Noise.cell(x, y, 3) > 0.9985 && v < 0.6 { c += SIMD3(0.5, 0.5, 0.55) * Noise.cell(x, y, 4) }
            // moon, upper left, with a soft halo
            let md = sqrtf((u - 0.22) * (u - 0.22) * 2.56 + (v - 0.2) * (v - 0.2))
            c += SIMD3(0.35, 0.38, 0.45) * max(0, 1 - md * 4) * 0.25
            if md < 0.045 {
                let maria = Noise.fbm(u * 60, v * 60, octaves: 3, seed: 5)
                c = SIMD3(0.95, 0.95, 0.88) * (0.85 + maria * 0.2)
            }
            // rooftops and a few lit windows
            let roof = 0.62 + Noise.fbm(u * 6, 0.5, octaves: 2, seed: 9) * 0.05 + (fmodf(u * 7, 1) < 0.5 ? 0.02 : -0.03)
            if v > roof {
                c = SIMD3(0.006, 0.006, 0.01)
                let wx = Int(u * 90), wy = Int(v * 60)
                if Noise.cell(wx, wy, 13) > 0.93 && fmodf(u * 90, 1) < 0.6 && fmodf(v * 60, 1) < 0.55 && v > roof + 0.03 {
                    c = SIMD3(0.6, 0.42, 0.18) * (0.5 + Noise.cell(wx, wy, 14))
                }
            }
            // a tree silhouette on the right
            let tx = u - 0.8, ty = v - 0.35
            let canopy = sqrtf(tx * tx * 3 + ty * ty) < 0.22 + Noise.fbm(u * 30, v * 30, octaves: 3, seed: 17) * 0.06
            let trunk = abs(tx + (v - 0.6) * 0.1) < 0.012 && v > 0.45
            if canopy || trunk { c = SIMD3(0.002, 0.003, 0.004) }
            return SIMD4(c.x, c.y, c.z, 1)
        }
        skyMat = Mat.glow(NSColor.white, 1.2)
        skyMat.emission.contents = img
        let plane = SCNPlane(width: 6, height: 3.75)
        plane.materials = [skyMat]
        let n = SCNNode(geometry: plane)
        n.simdPosition = SIMD3(-1.2, 1.6, -4.4)
        n.castsShadow = false
        root.addChildNode(n)
    }

    private func buildWallClock() {
        let face = makeImage(256, 256) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.93, blue: 0.88, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 256, height: 256))
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            for i in 0..<12 {
                let a = CGFloat(i) / 12 * 2 * .pi
                let r1: CGFloat = i % 3 == 0 ? 96 : 104
                ctx.saveGState()
                ctx.translateBy(x: 128, y: 128)
                ctx.rotate(by: a)
                ctx.fill(CGRect(x: -3, y: r1, width: 6, height: 116 - r1))
                ctx.restoreGState()
            }
        }
        let c = SCNCylinder(radius: 0.15, height: 0.03)
        let faceMat = Mat.plain(.white, rough: 0.3)
        faceMat.diffuse.contents = face
        c.materials = [Mat.plain(color(0.1, 0.1, 0.1), rough: 0.3), faceMat, faceMat]
        let n = SCNNode(geometry: c)
        n.simdPosition = wallClock
        n.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        root.addChildNode(n)
        // hands, parented so the game can turn them
        for (i, len) in [(0, Float(0.08)), (1, Float(0.12))] {
            let h = SCNBox(width: 0.008, height: CGFloat(len), length: 0.003, chamferRadius: 0)
            h.materials = [Mat.plain(color(0.05, 0.05, 0.05), rough: 0.4)]
            let hn = SCNNode(geometry: h)
            hn.pivot = SCNMatrix4MakeTranslation(0, CGFloat(-len / 2), 0)
            hn.simdPosition = wallClock + SIMD3(0, 0, -0.02 - Float(i) * 0.003)
            hn.name = i == 0 ? "hour" : "minute"
            root.addChildNode(hn)
        }
    }

    private func printMaterial() -> SCNMaterial {
        let img = makePixelImage(256, 332) { x, y in
            let u = Float(x) / 256, v = Float(y) / 332
            if u < 0.08 || u > 0.92 || v < 0.06 || v > 0.94 { return SIMD4(0.92, 0.9, 0.85, 1) }
            // a botanical-ish watercolour: lemons on a branch
            var c = SIMD3<Float>(0.86, 0.83, 0.74)
            let leaf = Noise.fbm(u * 5, v * 5, octaves: 4, seed: 51)
            if leaf > 0.12 { c = mix3(c, SIMD3(0.35, 0.48, 0.3), 0.7) }
            for (cx, cy) in [(0.4, 0.45), (0.62, 0.58), (0.45, 0.7)] as [(Float, Float)] {
                let d = sqrtf((u - cx) * (u - cx) * 1.6 + (v - cy) * (v - cy))
                if d < 0.09 { c = SIMD3(0.92, 0.78, 0.25) * (0.9 + (0.09 - d) * 1.5) }
            }
            return SIMD4(c.x, c.y, c.z, 1)
        }
        let m = Mat.plain(.white, rough: 0.85)
        m.diffuse.contents = img
        return m
    }

    // MARK: Counter run

    private func buildCounters() {
        let front: Float = -1.92, top: Float = 0.86, slab: Float = 0.9, over: Float = -1.88
        // Carcasses (collision) split around the sink so the basin can be entered.
        solid(SIMD3(-3, 0, -2.5), SIMD3(-1.55, top, front), nil, name: "cabinet")
        solid(SIMD3(-1.55, 0, -2.5), SIMD3(-0.85, 0.7, front), nil, surface: .metal, name: "sink")
        solid(SIMD3(-0.85, 0, -2.5), SIMD3(-0.1, top, front), nil, name: "cabinet")
        solid(SIMD3(0.66, 0, -2.5), SIMD3(1.1, top, front), nil, name: "cabinet")
        // Visual carcass, toe kick, doors and drawers
        let kick = Mat.plain(color(0.06, 0.06, 0.06), rough: 0.8)
        for (x0, x1) in [(Float(-3), Float(-0.1)), (Float(0.66), Float(1.1))] {
            box(SIMD3(x0, 0, -2.5), SIMD3(x1, 0.1, front - 0.0 + 0.04 - 0.07), kick, chamfer: 0)
            box(SIMD3(x0, 0.1, -2.5), SIMD3(x1, top, front - 0.02), mCab, span: 1)
            // fronts
            var x = x0 + 0.003
            let width = x1 - x0
            let n = max(1, Int((width / 0.5).rounded()))
            let dw = width / Float(n)
            for _ in 0..<n {
                box(SIMD3(x, 0.11, front - 0.02), SIMD3(x + dw - 0.006, top - 0.17, front), mCab, span: 1, chamfer: 0.004, vertical: true)
                box(SIMD3(x, top - 0.165, front - 0.02), SIMD3(x + dw - 0.006, top - 0.005, front), mCab, span: 1, chamfer: 0.004)
                // bar pulls
                let pull = cyl(0.006, 0.14, mSteel, at: SIMD3(x + dw / 2, top - 0.085, front + 0.022), seg: 12)
                pull.simdEulerAngles = SIMD3(0, 0, .pi / 2)
                for s in [-0.06, 0.06] as [Float] { _ = cyl(0.004, 0.022, mSteel, at: SIMD3(x + dw / 2 + s, top - 0.085, front + 0.011), seg: 8).simdEulerAngles = SIMD3(.pi / 2, 0, 0) }
                let pull2 = cyl(0.006, 0.14, mSteel, at: SIMD3(x + dw / 2, top - 0.23, front + 0.022), seg: 12)
                pull2.simdEulerAngles = SIMD3(0, 0, .pi / 2)
                x += dw
            }
        }
        // Countertop slabs around the sink
        let slabs: [(Float, Float, Float, Float)] = [
            (-3, -1.55, -2.5, over), (-0.85, -0.1, -2.5, over), (-1.55, -0.85, -2.5, -2.38), (-1.55, -0.85, -1.98, over), (0.66, 1.14, -2.5, over),
        ]
        for (x0, x1, z0, z1) in slabs {
            solid(SIMD3(x0, top, z0), SIMD3(x1, slab, z1), mQuartz, span: 1.2, chamfer: 0.003, surface: .stone, name: "counter")
        }
        // Sink basin (brushed steel), faucet, drain
        let bl = SIMD3<Float>(-1.55, 0.7, -2.38), bh = SIMD3<Float>(-0.85, slab, -1.98)
        box(SIMD3(bl.x, bl.y - 0.01, bl.z), SIMD3(bh.x, bl.y, bh.z), mSteel, span: 0.5, chamfer: 0)
        box(SIMD3(bl.x, bl.y, bl.z), SIMD3(bl.x + 0.01, slab - 0.005, bh.z), mSteel, span: 0.5, chamfer: 0)
        box(SIMD3(bh.x - 0.01, bl.y, bl.z), SIMD3(bh.x, slab - 0.005, bh.z), mSteel, span: 0.5, chamfer: 0)
        box(SIMD3(bl.x, bl.y, bl.z), SIMD3(bh.x, slab - 0.005, bl.z + 0.01), mSteel, span: 0.5, chamfer: 0)
        box(SIMD3(bl.x, bl.y, bh.z - 0.01), SIMD3(bh.x, slab - 0.005, bh.z), mSteel, span: 0.5, chamfer: 0)
        _ = cyl(0.03, 0.002, mCast, at: SIMD3(-1.2, 0.701, -2.18))
        // faucet: base, riser, gooseneck, spout
        _ = cyl(0.025, 0.04, mChrome, at: SIMD3(-1.2, 0.92, -2.44))
        _ = cyl(0.013, 0.3, mChrome, at: SIMD3(-1.2, 1.07, -2.44))
        let arm = cyl(0.012, 0.25, mChrome, at: SIMD3(-1.2, 1.21, -2.315))
        arm.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        _ = cyl(0.014, 0.06, mChrome, at: SIMD3(-1.2, 1.19, -2.2))
        for s in [-1, 1] as [Float] {
            let lever = cyl(0.006, 0.07, mChrome, at: SIMD3(-1.2 + s * 0.07, 0.95, -2.44))
            lever.simdEulerAngles = SIMD3(0, 0, s * 1.2)
        }
        // water droplet (animated by the game)
        let drop = SCNSphere(radius: 0.0035)
        drop.materials = [Mat.plain(color(0.8, 0.85, 0.9), rough: 0.02, metal: 0)]
        dripNode.geometry = drop
        dripNode.simdPosition = sinkSpout
        dripNode.castsShadow = false
        root.addChildNode(dripNode)

        // Backsplash and upper cabinets
        box(SIMD3(-3, slab, -2.5), SIMD3(window.lo.x - 0.06, 1.45, -2.49), mSubway, span: 0.6, chamfer: 0)
        box(SIMD3(window.hi.x + 0.06, slab, -2.5), SIMD3(1.14, 1.45, -2.49), mSubway, span: 0.6, chamfer: 0)
        box(SIMD3(window.lo.x - 0.06, slab, -2.5), SIMD3(window.hi.x + 0.06, window.lo.y - 0.03, -2.49), mSubway, span: 0.6, chamfer: 0)
        for (x0, x1) in [(Float(-3), Float(-1.84)), (Float(-0.56), Float(-0.14)), (Float(0.7), Float(1.14))] {
            solid(SIMD3(x0, 1.45, -2.5), SIMD3(x1, 2.2, -2.16), mCab, span: 1, name: "upper")
            let n = max(1, Int(((x1 - x0) / 0.45).rounded()))
            let dw = (x1 - x0) / Float(n)
            for i in 0..<n {
                let dx = x0 + Float(i) * dw
                box(SIMD3(dx + 0.003, 1.455, -2.16), SIMD3(dx + dw - 0.003, 2.195, -2.145), mCab, span: 1, chamfer: 0.003, vertical: true)
                _ = cyl(0.005, 0.12, mSteel, at: SIMD3(dx + (i % 2 == 0 ? dw - 0.04 : 0.04), 1.52, -2.125), seg: 10)
            }
        }
        // Range hood over the stove, with its little night light underneath
        solid(SIMD3(-0.14, 1.55, -2.5), SIMD3(0.7, 1.72, -1.98), mSteel, span: 0.6, chamfer: 0.004, surface: .metal, name: "hood")
        box(SIMD3(0.06, 1.72, -2.5), SIMD3(0.5, 2.6, -2.2), mSteel, span: 0.6)
        let lamp = SCNBox(width: 0.08, height: 0.004, length: 0.05, chamferRadius: 0.001)
        lamp.materials = [Mat.glow(color(1, 0.8, 0.55), 2.5)]
        let ln = SCNNode(geometry: lamp)
        ln.simdPosition = SIMD3(0.28, 1.548, -2.1)
        ln.castsShadow = false
        root.addChildNode(ln)
    }

    private func buildStove() {
        let x0: Float = -0.1, x1: Float = 0.66, z0: Float = -2.5, z1: Float = -1.9
        // body is raised: a rat-sized gap underneath
        solid(SIMD3(x0, 0.075, z0), SIMD3(x1, 0.92, z1), nil, surface: .metal, name: "stove")
        box(SIMD3(x0 + 0.005, 0.075, z0), SIMD3(x1 - 0.005, 0.9, z1), mSteel, span: 0.8)
        // feet
        for fx in [x0 + 0.04, x1 - 0.04] { for fz in [z0 + 0.05, z1 - 0.05] { _ = cyl(0.012, 0.075, mCast, at: SIMD3(fx, 0.0375, fz), seg: 10) } }
        // oven door: steel frame, black glass window, handle
        box(SIMD3(x0 + 0.01, 0.1, z1), SIMD3(x1 - 0.01, 0.74, z1 + 0.025), mSteel, span: 0.8, chamfer: 0.006)
        box(SIMD3(x0 + 0.08, 0.3, z1 + 0.025), SIMD3(x1 - 0.08, 0.62, z1 + 0.027), mBlackGlass, chamfer: 0)
        let handle = cyl(0.012, 0.64, mSteel, at: SIMD3((x0 + x1) / 2, 0.8, z1 + 0.06), seg: 16)
        handle.simdEulerAngles = SIMD3(0, 0, .pi / 2)
        for s in [-0.29, 0.29] as [Float] { _ = cyl(0.007, 0.06, mSteel, at: SIMD3((x0 + x1) / 2 + s, 0.8, z1 + 0.03), seg: 8).simdEulerAngles = SIMD3(.pi / 2, 0, 0) }
        // control strip with knobs
        box(SIMD3(x0 + 0.005, 0.76, z1), SIMD3(x1 - 0.005, 0.9, z1 + 0.012), mCast, chamfer: 0.002)
        for i in 0..<4 {
            let k = cyl(0.018, 0.022, mCast, at: SIMD3(x0 + 0.12 + Float(i) * 0.14 + (i >= 2 ? 0.08 : 0), 0.83, z1 + 0.022), seg: 20)
            k.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        }
        // oven clock (texture is redrawn by the game)
        ovenClock = Mat.glow(.black, 1.6)
        let cl = SCNPlane(width: 0.07, height: 0.028)
        cl.materials = [ovenClock]
        let cn = SCNNode(geometry: cl)
        cn.simdPosition = SIMD3((x0 + x1) / 2 + 0.04, 0.83, z1 + 0.0135)
        cn.castsShadow = false
        root.addChildNode(cn)
        // cooktop: black glass top with cast-iron grates
        box(SIMD3(x0, 0.9, z0), SIMD3(x1, 0.915, z1), mCast, chamfer: 0.002)
        for gx in [x0 + 0.19, x1 - 0.19] {
            for gz in [z0 + 0.16, z1 - 0.15] {
                let r: Float = gz > -2.2 ? 0.08 : 0.065
                let ring = SCNTorus(ringRadius: CGFloat(r), pipeRadius: 0.005)
                ring.materials = [mCast]
                let rn = SCNNode(geometry: ring)
                rn.simdPosition = SIMD3(gx, 0.925, gz)
                root.addChildNode(rn)
                for a in 0..<4 {
                    let bar = SCNBox(width: CGFloat(r * 2.3), height: 0.008, length: 0.008, chamferRadius: 0.002)
                    bar.materials = [mCast]
                    let bn = SCNNode(geometry: bar)
                    bn.simdPosition = SIMD3(gx, 0.925, gz)
                    bn.simdEulerAngles = SIMD3(0, Float(a) * .pi / 4, 0)
                    root.addChildNode(bn)
                }
                _ = cyl(0.03, 0.012, mCast, at: SIMD3(gx, 0.92, gz), seg: 20)
            }
        }
        // back panel
        solid(SIMD3(x0, 0.915, z0), SIMD3(x1, 1.06, z0 + 0.06), mSteel, span: 0.6, surface: .metal, name: "stove back")

        // Dish towel folded over the oven handle: climbable from the floor with a jump
        let tx0: Float = 0.1, tx1: Float = 0.36
        solid(SIMD3(tx0, 0.42, z1 + 0.066), SIMD3(tx1, 0.815, z1 + 0.084), mTowel, span: 0.3, chamfer: 0.004,
              climb: true, surface: .fabric, perch: false, name: "dish towel", vertical: true)
        box(SIMD3(tx0, 0.52, z1 + 0.038), SIMD3(tx1, 0.815, z1 + 0.05), mTowel, span: 0.3, chamfer: 0.004, vertical: true)
        let fold = cyl(0.022, tx1 - tx0, mTowel, at: SIMD3((tx0 + tx1) / 2, 0.81, z1 + 0.06), seg: 16)
        fold.simdEulerAngles = SIMD3(0, 0, .pi / 2)
    }

    private func buildFridge() {
        let x0: Float = 1.2, x1: Float = 2.1, z0: Float = -2.5, z1: Float = -1.8
        solid(SIMD3(x0, 0.08, z0), SIMD3(x1, 1.85, z1), nil, surface: .metal, name: "fridge")
        // Cabinet shell (sides, top, back) and a lit interior revealed when the door opens
        box(SIMD3(x0, 0.08, z0), SIMD3(x0 + 0.03, 1.85, z1 - 0.02), mSteel, span: 1)
        box(SIMD3(x1 - 0.03, 0.08, z0), SIMD3(x1, 1.85, z1 - 0.02), mSteel, span: 1)
        box(SIMD3(x0, 1.82, z0), SIMD3(x1, 1.85, z1 - 0.02), mSteel, span: 1)
        box(SIMD3(x0, 0.08, z0), SIMD3(x1, 0.14, z1 - 0.02), mSteel, span: 1)
        box(SIMD3(x0, 1.28, z0), SIMD3(x1, 1.32, z1 - 0.02), mSteel, span: 1)
        let inner = Mat.plain(color(0.92, 0.93, 0.95), rough: 0.3)
        box(SIMD3(x0 + 0.03, 0.14, z0), SIMD3(x1 - 0.03, 1.28, z0 + 0.03), inner)
        for sy in [0.45, 0.75, 1.02] as [Float] {
            let shelf = Mat.plain(color(0.85, 0.9, 0.92), rough: 0.05)
            shelf.transparency = 0.6
            box(SIMD3(x0 + 0.03, sy, z0 + 0.03), SIMD3(x1 - 0.03, sy + 0.006, z1 - 0.06), shelf, chamfer: 0)
        }
        // groceries inside
        let milk = texturedBox(0.09, 0.24, 0.09, Mat.plain(color(0.95, 0.95, 0.97), rough: 0.5), span: 1)
        milk.simdPosition = SIMD3(1.35, 0.45 + 0.12, -2.2)
        root.addChildNode(milk)
        let oj = texturedBox(0.09, 0.22, 0.09, Mat.plain(color(0.95, 0.62, 0.15), rough: 0.5), span: 1)
        oj.simdPosition = SIMD3(1.5, 0.45 + 0.11, -2.25)
        root.addChildNode(oj)
        for i in 0..<3 {
            let jar = cyl(0.035, 0.1, Mat.plain(color(0.6, 0.15 + CGFloat(i) * 0.15, 0.1), rough: 0.1), at: SIMD3(1.7 + Float(i) * 0.1, 0.81, -2.25))
            jar.geometry?.materials.first?.transparency = 0.9
        }
        let tub = cyl(0.07, 0.07, Mat.plain(color(0.92, 0.9, 0.8), rough: 0.4), at: SIMD3(1.8, 1.06, -2.2))
        _ = tub
        let fl = SCNLight()
        fl.type = .omni
        fl.color = color(1, 0.97, 0.9)
        fl.intensity = 0
        fl.attenuationStartDistance = 0.2
        fl.attenuationEndDistance = 2.4
        fl.castsShadow = false
        fridgeLight.light = fl
        fridgeLight.simdPosition = SIMD3(1.65, 1.2, -2.1)
        root.addChildNode(fridgeLight)

        // Freezer door (fixed) and main door (hinged on the right)
        let doorW = x1 - x0
        let fz = texturedBox(doorW, 0.52, 0.06, mSteel, span: 1, chamfer: 0.012)
        fz.simdPosition = SIMD3((x0 + x1) / 2, 1.585, z1 + 0.01)
        root.addChildNode(fz)
        fridgeDoor.simdPosition = SIMD3(x1, 0, z1 - 0.02)
        root.addChildNode(fridgeDoor)
        let md = texturedBox(doorW, 1.16, 0.06, mSteel, span: 1, chamfer: 0.012)
        md.simdPosition = SIMD3(-doorW / 2, 0.72, 0.03)
        fridgeDoor.addChildNode(md)
        // door bins on the inside face
        for by in [0.4, 0.8] as [Float] {
            let bin = texturedBox(doorW - 0.1, 0.08, 0.06, Mat.plain(color(0.9, 0.92, 0.95), rough: 0.1), span: 1)
            bin.simdPosition = SIMD3(-doorW / 2, by, -0.03)
            fridgeDoor.addChildNode(bin)
        }
        // handles
        for (hy, hl) in [(Float(0.95), Float(0.5)), (Float(1.5), Float(0.25))] {
            let h = cyl(0.012, CGFloat(hl) == 0 ? 0.1 : hl, mSteel, at: SIMD3(0, 0, 0), seg: 14)
            h.removeFromParentNode()
            if hy < 1.3 { h.simdPosition = SIMD3(-doorW + 0.07, hy, 0.1); fridgeDoor.addChildNode(h) }
            else { h.simdPosition = SIMD3(x0 + 0.07, hy, z1 + 0.08); root.addChildNode(h) }
        }
        // magnets and a child's drawing on the door
        var rng = RNG(77)
        let drawing = makePixelImage(128, 160) { x, y in
            let u = Float(x) / 128, v = Float(y) / 160
            var c = SIMD3<Float>(0.97, 0.96, 0.92)
            if abs(v - 0.75 - sinf(u * 9) * 0.02) < 0.012 { c = SIMD3(0.2, 0.6, 0.2) }
            let sd = sqrtf((u - 0.75) * (u - 0.75) + (v - 0.2) * (v - 0.2))
            if sd < 0.1 { c = SIMD3(1, 0.8, 0.1) }
            if abs(u - 0.35) < 0.1 && v > 0.45 && v < 0.72 { c = SIMD3(0.8, 0.2, 0.15) }
            if abs(v - 0.45 + abs(u - 0.35) * 0.9) < 0.015 && abs(u - 0.35) < 0.14 { c = SIMD3(0.3, 0.2, 0.6) }
            return SIMD4(c.x, c.y, c.z, 1)
        }
        let dm = Mat.plain(.white, rough: 0.9)
        dm.diffuse.contents = drawing
        let dp = SCNPlane(width: 0.21, height: 0.27)
        dp.materials = [dm]
        let dn = SCNNode(geometry: dp)
        dn.simdPosition = SIMD3(-doorW / 2 + 0.05, 0.95, 0.062)
        dn.simdEulerAngles = SIMD3(0, 0, 0.05)
        fridgeDoor.addChildNode(dn)
        for _ in 0..<6 {
            let mg = SCNCylinder(radius: 0.012, height: 0.008)
            mg.materials = [Mat.plain(NSColor(hue: CGFloat(rng.float()), saturation: 0.7, brightness: 0.8, alpha: 1), rough: 0.3)]
            let mn = SCNNode(geometry: mg)
            mn.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            mn.simdPosition = SIMD3(-doorW / 2 + rng.range(-0.3, 0.3), rng.range(0.6, 1.2), 0.064)
            fridgeDoor.addChildNode(mn)
        }
        // cereal boxes on top of the fridge
        for (i, c) in [color(0.85, 0.2, 0.15), color(0.95, 0.75, 0.2)].enumerated() {
            let cb = texturedBox(0.2, 0.3, 0.07, Mat.plain(c, rough: 0.6), span: 1)
            cb.simdPosition = SIMD3(1.4 + Float(i) * 0.25, 2.0, -2.3)
            root.addChildNode(cb)
        }
        // kick grille (dark) leaving the gap open at the sides
        box(SIMD3(x0 + 0.25, 0.02, z1 - 0.03), SIMD3(x1 - 0.25, 0.075, z1 - 0.02), Mat.plain(color(0.03, 0.03, 0.03), rough: 0.7), chamfer: 0)
    }

    // MARK: Table and chairs

    private func buildTable() {
        let tl = SIMD3<Float>(-0.1, 0.72, 0.05), th = SIMD3<Float>(1.3, 0.76, 1.05)
        solid(tl, th, mWalnut, span: 1.4, chamfer: 0.006, surface: .wood, name: "table")
        // aprons (visual) and legs (climbable)
        box(SIMD3(tl.x + 0.06, 0.64, tl.z + 0.06), SIMD3(th.x - 0.06, 0.72, tl.z + 0.08), mWalnut, span: 1.4)
        box(SIMD3(tl.x + 0.06, 0.64, th.z - 0.08), SIMD3(th.x - 0.06, 0.72, th.z - 0.06), mWalnut, span: 1.4)
        box(SIMD3(tl.x + 0.06, 0.64, tl.z + 0.06), SIMD3(tl.x + 0.08, 0.72, th.z - 0.06), mWalnut, span: 1.4)
        box(SIMD3(th.x - 0.08, 0.64, tl.z + 0.06), SIMD3(th.x - 0.06, 0.72, th.z - 0.06), mWalnut, span: 1.4)
        for lx in [tl.x + 0.06, th.x - 0.11] {
            for lz in [tl.z + 0.06, th.z - 0.11] {
                solid(SIMD3(lx, 0, lz), SIMD3(lx + 0.05, 0.72, lz + 0.05), mWalnut, span: 0.8, chamfer: 0.004, climb: true, perch: false, name: "table leg", vertical: true)
            }
        }
        // placemat and a plate with leftovers are added by Props
        chair(x: 0.25, z: -0.22, backNorth: true)
        chair(x: 0.95, z: -0.2, backNorth: true)
        chair(x: 0.25, z: 1.32, backNorth: false)
        chair(x: 1.02, z: 1.36, backNorth: false)
    }

    private func chair(x: Float, z: Float, backNorth: Bool) {
        let s: Float = 0.42, seatY: Float = 0.46
        solid(SIMD3(x - s / 2, seatY - 0.03, z - s / 2), SIMD3(x + s / 2, seatY, z + s / 2), mOak, span: 0.8, chamfer: 0.006, name: "chair seat")
        for lx in [x - s / 2 + 0.01, x + s / 2 - 0.045] {
            for lz in [z - s / 2 + 0.01, z + s / 2 - 0.045] {
                solid(SIMD3(lx, 0, lz), SIMD3(lx + 0.035, seatY - 0.03, lz + 0.035), mOak, span: 0.8, chamfer: 0.004, climb: true, perch: false, name: "chair leg", vertical: true)
            }
        }
        // stretchers
        box(SIMD3(x - s / 2 + 0.02, 0.15, z - 0.01), SIMD3(x + s / 2 - 0.02, 0.17, z + 0.01), mOak, span: 0.8)
        // back: two posts and three slats on the far side
        let bz = backNorth ? z - s / 2 + 0.01 : z + s / 2 - 0.04
        for px in [x - s / 2 + 0.01, x + s / 2 - 0.045] {
            solid(SIMD3(px, seatY, bz), SIMD3(px + 0.035, 0.95, bz + 0.03), mOak, span: 0.8, chamfer: 0.004, climb: true, perch: false, name: "chair back", vertical: true)
        }
        for sy in [0.62, 0.74, 0.88] as [Float] {
            box(SIMD3(x - s / 2 + 0.04, sy, bz + 0.005), SIMD3(x + s / 2 - 0.04, sy + 0.05, bz + 0.025), mOak, span: 0.8, chamfer: 0.003)
        }
    }

    // MARK: Everything else on the floor and counter

    private func buildClutter() {
        // Runner rug in front of the sink
        let rug = texturedBox(1.9, 0.008, 0.7, mRug, span: 1, chamfer: 0.002)
        rug.simdPosition = SIMD3(-1.25, 0.004, -1.5)
        rug.geometry?.materials = rug.geometry!.materials.map { m in
            let c = m.copy() as! SCNMaterial
            for p in [c.diffuse, c.roughness, c.normal] { p.contentsTransform = SCNMatrix4Identity; p.wrapS = .clamp; p.wrapT = .clamp }
            return c
        }
        root.addChildNode(rug)

        // Two-step stool against the counter under the sink (the easy way up)
        let stoolM = Mat.plain(color(0.93, 0.93, 0.9), rough: 0.4)
        solid(SIMD3(-1.4, 0, -1.62), SIMD3(-1.0, 0.25, -1.42), nil, surface: .plastic, name: "stool step")
        solid(SIMD3(-1.4, 0, -1.88), SIMD3(-1.0, 0.5, -1.62), nil, surface: .plastic, name: "stool top")
        box(SIMD3(-1.4, 0.22, -1.62), SIMD3(-1.0, 0.25, -1.42), stoolM, chamfer: 0.008)
        box(SIMD3(-1.4, 0.47, -1.88), SIMD3(-1.0, 0.5, -1.62), stoolM, chamfer: 0.008)
        let grip = Mat.plain(color(0.3, 0.3, 0.32), rough: 0.9)
        for gz in [-1.58, -1.5] as [Float] { box(SIMD3(-1.36, 0.25, gz), SIMD3(-1.04, 0.252, gz + 0.03), grip, chamfer: 0) }
        for sx in [-1.39, -1.03] as [Float] {
            box(SIMD3(sx, 0, -1.62), SIMD3(sx + 0.02, 0.22, -1.44), stoolM, chamfer: 0.003)
            box(SIMD3(sx, 0, -1.87), SIMD3(sx + 0.02, 0.47, -1.63), stoolM, chamfer: 0.003)
        }

        // Pedal bin and a split bin bag (food spills from it; see Props)
        let bin = cyl(0.16, 0.55, mSteel, at: SIMD3(-2.72, 0.275, -1.62), seg: 40)
        _ = bin
        world.add(Solid(x: -2.72, z: -1.62, w: 0.3, d: 0.3, y0: 0, y1: 0.55, surface: .metal, name: "bin"))
        let lid = cyl(0.162, 0.02, mSteel, at: SIMD3(-2.72, 0.56, -1.62), seg: 40)
        _ = lid
        let bag = SCNSphere(radius: 0.2)
        bag.segmentCount = 32
        bag.materials = [mBag]
        let bn = SCNNode(geometry: bag)
        bn.simdScale = SIMD3(1.1, 0.55, 0.85)
        bn.simdPosition = SIMD3(-2.62, 0.1, -1.1)
        bn.simdEulerAngles = SIMD3(0, 0.4, 0.1)
        root.addChildNode(bn)
        world.add(Solid(x: -2.62, z: -1.1, w: 0.36, d: 0.26, y0: 0, y1: 0.2, climb: true, surface: .plastic, name: "bin bag"))
        let tie = SCNCone(topRadius: 0.0, bottomRadius: 0.05, height: 0.1)
        tie.materials = [mBag]
        let tn = SCNNode(geometry: tie)
        tn.simdPosition = SIMD3(-2.84, 0.14, -1.2)
        tn.simdEulerAngles = SIMD3(0, 0, 1.2)
        root.addChildNode(tn)

        // Recycling crate by the fridge, flattened pizza box on top
        let crate = Mat.plain(color(0.1, 0.3, 0.62), rough: 0.5)
        solid(SIMD3(2.25, 0, -2.45), SIMD3(2.7, 0.42, -2.05), crate, chamfer: 0.01, surface: .plastic, name: "recycling")
        solid(SIMD3(2.22, 0.42, -2.47), SIMD3(2.74, 0.46, -2.0), mCard, span: 0.6, chamfer: 0.003, surface: .cardboard, name: "pizza box")
        // broom leaning in the corner
        let handle = cyl(0.012, 1.3, mOak, at: SIMD3(2.88, 0.72, -2.38), seg: 10)
        handle.simdEulerAngles = SIMD3(0.12, 0, -0.08)
        let brush = texturedBox(0.28, 0.14, 0.06, Mat.plain(color(0.7, 0.55, 0.3), rough: 0.95), span: 1)
        brush.simdPosition = SIMD3(2.83, 0.07, -2.43)
        root.addChildNode(brush)

        // Cat corner: bed, bowls on a mat
        let bed = SCNTorus(ringRadius: 0.24, pipeRadius: 0.07)
        bed.materials = [mPlush]
        let bedN = SCNNode(geometry: bed)
        bedN.simdPosition = SIMD3(catBed.x, 0.07, catBed.z)
        bedN.simdScale = SIMD3(1, 0.9, 1)
        root.addChildNode(bedN)
        _ = cyl(0.25, 0.05, mPlush, at: SIMD3(catBed.x, 0.025, catBed.z), seg: 36)
        world.add(Solid(x: catBed.x, z: catBed.z, w: 0.6, d: 0.6, y0: 0, y1: 0.06, surface: .fabric, name: "cat bed"))
        let mat = texturedBox(0.34, 0.004, 0.52, Mat.plain(color(0.2, 0.22, 0.25), rough: 0.9), span: 1, chamfer: 0.002)
        mat.simdPosition = SIMD3(2.72, 0.002, 0.78)
        root.addChildNode(mat)
        for (bz, water) in [(Float(0.9), false), (Float(0.64), true)] {
            let tube = SCNTube(innerRadius: 0.075, outerRadius: 0.085, height: 0.05)
            tube.radialSegmentCount = 36
            tube.materials = [mSteel]
            let t = SCNNode(geometry: tube)
            t.simdPosition = SIMD3(2.72, 0.025, bz)
            root.addChildNode(t)
            _ = cyl(0.077, 0.004, mSteel, at: SIMD3(2.72, 0.004, bz), seg: 36)
            if water {
                let w = Mat.plain(color(0.1, 0.12, 0.13), rough: 0.02)
                w.transparency = 0.7
                _ = cyl(0.075, 0.002, w, at: SIMD3(2.72, 0.035, bz), seg: 36)
            }
            world.add(Solid(x: 2.72, z: bz, w: 0.17, d: 0.17, y0: 0, y1: water ? 0.05 : 0.02, surface: .metal, name: water ? "water bowl" : "food bowl"))
        }

        // Counter clutter: toaster, kettle, knife block, cutting board, fruit bowl, microwave
        let red = Mat.plain(color(0.6, 0.08, 0.06), rough: 0.25, metal: 0.3)
        solid(SIMD3(-2.85, 0.9, -2.42), SIMD3(-2.55, 1.08, -2.26), red, chamfer: 0.03, surface: .metal, name: "toaster")
        box(SIMD3(-2.8, 1.075, -2.37), SIMD3(-2.6, 1.082, -2.35), mCast, chamfer: 0)
        box(SIMD3(-2.8, 1.075, -2.33), SIMD3(-2.6, 1.082, -2.31), mCast, chamfer: 0)
        let kettle = cyl(0.08, 0.2, mChrome, at: SIMD3(-2.3, 1.0, -2.36))
        _ = kettle
        world.add(Solid(x: -2.3, z: -2.36, w: 0.16, d: 0.16, y0: 0.9, y1: 1.1, surface: .metal, name: "kettle"))
        solid(SIMD3(-2.25, 0.9, -2.2), SIMD3(-1.8, 0.92, -1.95), mOak, span: 0.5, chamfer: 0.004, surface: .wood, name: "cutting board")
        solid(SIMD3(-0.62, 0.9, -2.45), SIMD3(-0.5, 1.12, -2.3), mWalnut, span: 0.5, chamfer: 0.01, name: "knife block")
        for i in 0..<4 {
            let k = SCNBox(width: 0.02, height: 0.06, length: 0.006, chamferRadius: 0.002)
            k.materials = [mCast]
            let kn = SCNNode(geometry: k)
            kn.simdPosition = SIMD3(-0.6 + Float(i) * 0.025, 1.14, -2.38)
            kn.simdEulerAngles = SIMD3(-0.3, 0, 0)
            root.addChildNode(kn)
        }
        let bowl = SCNSphere(radius: 0.13)
        bowl.materials = [Mat.plain(color(0.85, 0.82, 0.75), rough: 0.3)]
        let bw = SCNNode(geometry: bowl)
        bw.simdScale = SIMD3(1, 0.35, 1)
        bw.simdPosition = SIMD3(-0.35, 0.93, -2.3)
        root.addChildNode(bw)
        world.add(Solid(x: -0.35, z: -2.3, w: 0.22, d: 0.22, y0: 0.9, y1: 0.95, surface: .stone, name: "fruit bowl"))
        for (i, c) in [color(0.85, 0.1, 0.08), color(0.95, 0.55, 0.1), color(0.4, 0.6, 0.15)].enumerated() {
            let f = SCNSphere(radius: 0.038)
            f.materials = [Mat.plain(c, rough: 0.3)]
            let fnode = SCNNode(geometry: f)
            fnode.simdPosition = SIMD3(-0.4 + Float(i) * 0.05, 0.99, -2.3 + (i == 1 ? 0.04 : -0.02))
            root.addChildNode(fnode)
        }
        // microwave with a clock
        solid(SIMD3(0.72, 0.9, -2.46), SIMD3(1.1, 1.13, -2.14), Mat.plain(color(0.1, 0.1, 0.1), rough: 0.3), chamfer: 0.01, surface: .metal, name: "microwave")
        box(SIMD3(0.74, 0.93, -2.14), SIMD3(0.98, 1.1, -2.135), mBlackGlass, chamfer: 0)
        microClock = Mat.glow(.black, 1.2)
        let mp = SCNPlane(width: 0.05, height: 0.02)
        mp.materials = [microClock]
        let mn = SCNNode(geometry: mp)
        mn.simdPosition = SIMD3(1.04, 1.08, -2.134)
        mn.castsShadow = false
        root.addChildNode(mn)
        // paper towel roll
        let roll = cyl(0.055, 0.26, Mat.plain(color(0.96, 0.96, 0.94), rough: 0.9), at: SIMD3(-1.95, 1.03, -2.42))
        _ = roll
        world.add(Solid(x: -1.95, z: -2.42, w: 0.11, d: 0.11, y0: 0.9, y1: 1.16, surface: .fabric, name: "paper towel"))
        // a pan on the front-left burner
        let pan = SCNTube(innerRadius: 0.115, outerRadius: 0.12, height: 0.04)
        pan.materials = [mCast]
        let pn = SCNNode(geometry: pan)
        pn.simdPosition = SIMD3(0.09, 0.95, -2.05)
        root.addChildNode(pn)
        _ = cyl(0.118, 0.006, mCast, at: SIMD3(0.09, 0.933, -2.05))
        let ph = cyl(0.012, 0.2, mCast, at: SIMD3(0.09, 0.955, -1.85), seg: 10)
        ph.simdEulerAngles = SIMD3(.pi / 2 - 0.1, 0, 0)
        world.add(Solid(x: 0.09, z: -2.05, w: 0.22, d: 0.22, y0: 0.92, y1: 0.936, surface: .metal, name: "pan"))
    }

    // MARK: Lights

    private func buildLights() {
        let m = SCNLight()
        m.type = .directional
        m.color = color(0.62, 0.72, 1.0)
        m.intensity = 800
        m.castsShadow = true
        m.shadowMapSize = CGSize(width: 4096, height: 4096)
        m.shadowMode = .forward
        m.shadowSampleCount = 16
        m.shadowRadius = 2.5
        m.shadowBias = 0.2
        m.orthographicScale = 4.2
        m.zNear = 0.1
        m.zFar = 12
        m.automaticallyAdjustsShadowProjection = false
        m.shadowColor = NSColor(white: 0, alpha: 1)
        moon.light = m
        // aim through the window at the middle of the floor patch
        let target = SIMD3<Float>(-0.7, 0.4, -0.9)
        moon.simdPosition = target - moonDir * 6
        moon.simdLook(at: target)
        root.addChildNode(moon)

        let a = SCNLight()
        a.type = .ambient
        a.color = color(0.35, 0.4, 0.55)
        a.intensity = 30
        ambient.light = a
        root.addChildNode(ambient)

        let h = SCNLight()
        h.type = .spot
        h.color = color(1, 0.76, 0.5)
        h.intensity = 90
        h.spotInnerAngle = 40
        h.spotOuterAngle = 115
        h.attenuationStartDistance = 0.1
        h.attenuationEndDistance = 3.2
        h.attenuationFalloffExponent = 2
        h.castsShadow = true
        h.shadowMapSize = CGSize(width: 1024, height: 1024)
        h.shadowSampleCount = 8
        h.shadowRadius = 3
        h.shadowMode = .forward
        h.zNear = 0.02
        hoodLight.light = h
        hoodLight.simdPosition = SIMD3(0.28, 1.54, -2.1)
        hoodLight.simdEulerAngles = SIMD3(-.pi / 2 + 0.25, 0, 0)
        root.addChildNode(hoodLight)

        // Plug-in night light on the south wall
        let nl = SCNLight()
        nl.type = .omni
        nl.color = color(1, 0.62, 0.32)
        nl.intensity = 22
        nl.attenuationStartDistance = 0.05
        nl.attenuationEndDistance = 1.8
        nl.attenuationFalloffExponent = 2
        nl.castsShadow = false
        nl.shadowMapSize = CGSize(width: 1024, height: 1024)
        nl.shadowMode = .forward
        nl.shadowSampleCount = 8
        nl.zNear = 0.01
        nightLight.light = nl
        nightLight.simdPosition = SIMD3(-0.7, 0.3, 2.44)
        root.addChildNode(nightLight)
        box(SIMD3(-0.73, 0.26, 2.485), SIMD3(-0.67, 0.34, 2.5), mWhitePlastic, chamfer: 0.005)
        let nlGlow = SCNBox(width: 0.045, height: 0.06, length: 0.012, chamferRadius: 0.006)
        nlGlow.materials = [Mat.glow(color(1, 0.65, 0.35), 3)]
        let ng = SCNNode(geometry: nlGlow)
        ng.simdPosition = SIMD3(-0.7, 0.3, 2.476)
        ng.castsShadow = false
        root.addChildNode(ng)

        let c = SCNLight()
        c.type = .omni
        c.color = color(1, 0.95, 0.86)
        c.intensity = 0
        c.attenuationStartDistance = 0.5
        c.attenuationEndDistance = 7
        c.attenuationFalloffExponent = 2
        c.castsShadow = false
        c.shadowMapSize = CGSize(width: 2048, height: 2048)
        c.shadowMode = .forward
        c.shadowSampleCount = 8
        c.shadowRadius = 4
        ceilingLight.light = c
        ceilingLight.simdPosition = SIMD3(0.3, 2.45, 0)
        root.addChildNode(ceilingLight)

        let hl = SCNLight()
        hl.type = .omni
        hl.color = color(1, 0.85, 0.65)
        hl.intensity = 0
        hl.attenuationStartDistance = 0.3
        hl.attenuationEndDistance = 5
        hallLight.light = hl
        hallLight.simdPosition = SIMD3(-4.5, 2.3, 1.05)
        root.addChildNode(hallLight)
        hallBulb = Mat.glow(color(1, 0.9, 0.7), 0)
        let hb = SCNSphere(radius: 0.08)
        hb.materials = [hallBulb]
        let hbn = SCNNode(geometry: hb)
        hbn.simdPosition = SIMD3(-4.5, 2.55, 1.05)
        root.addChildNode(hbn)

        // First light of morning through the window (off until dawn)
        let d = SCNLight()
        d.type = .directional
        d.color = color(1, 0.72, 0.5)
        d.intensity = 0
        d.castsShadow = false
        dawnLight.light = d
        dawnLight.simdPosition = moon.simdPosition
        dawnLight.simdLook(at: target)
        root.addChildNode(dawnLight)
    }

    // MARK: Queries

    func hideout(at p: SIMD3<Float>) -> String? {
        guard p.y < 0.04 else { return nil }
        for h in hideouts where p.x > h.lo.x + 0.02 && p.x < h.hi.x - 0.02 && p.z > h.lo.y && p.z < h.hi.y - 0.03 {
            return h.name
        }
        return nil
    }

    /// Is point p in the moonbeam? Traces toward the moon through the window opening.
    func moonlit(_ p: SIMD3<Float>) -> Bool {
        let back = -moonDir
        guard back.z < 0 else { return false }
        let t = (window.lo.z - p.z) / back.z
        guard t > 0 else { return false }
        let hit = p + back * t
        guard hit.x > window.lo.x + 0.03, hit.x < window.hi.x - 0.03, hit.y > window.lo.y + 0.03, hit.y < window.hi.y - 0.03 else { return false }
        return world.visible(p + SIMD3(0, 0.02, 0), hit + moonDir * 0.05)
    }

    /// Rough light level (0 = pitch dark, 1 = bright) used for how visible the rat is.
    func lightLevel(_ p: SIMD3<Float>, lightsOn: Float, fridgeOpen: Float, dawn: Float) -> Float {
        var l: Float = 0.06
        if moonlit(p) { l += 0.5 }
        // hood lamp pool over the stove and in front of it
        let hp = SIMD3<Float>(0.28, 1.54, -2.1)
        let dh = simd_distance(p, hp)
        if p.z < -1.6 || p.y > 0.8 { l += 0.5 * max(0, 1 - dh / 1.6) }
        // night light
        let dn = simd_distance(p, nightLight.simdPosition)
        l += 0.45 * max(0, 1 - dn / 1.6)
        l += fridgeOpen * 0.7 * max(0, 1 - simd_distance(p, fridgeFront) / 2.2)
        l += lightsOn * 0.9
        l += dawn * 0.35
        return min(l, 1)
    }
}
