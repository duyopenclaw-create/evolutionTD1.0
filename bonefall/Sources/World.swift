import SceneKit
import simd

/// Builds the SceneKit scenery for a level: cliff surface, rocks, ground, sky, lights, extras.
final class World {
    let root = SCNNode()
    let sun = SCNNode()
    let ambient = SCNNode()
    private(set) var level = Level()
    private(set) var map = maps[0]
    private var rockMeshes: [SCNGeometry] = []
    private var snow: SCNNode?
    private var rockMat = SCNMaterial(), groundMat = SCNMaterial(), boulderMat = SCNMaterial(), spikeMat = SCNMaterial(), grassMat = SCNMaterial()
    private let chunkRoot = SCNNode()
    private struct Live { var node: SCNNode; var capsules: [Capsule]; var foliage: [Capsule] }
    private var chunks: [Int: Live] = [:]
    private var capsulesDirty = true
    private var capsuleCache: [Capsule] = []
    private lazy var obMats: [String: SCNMaterial] = {
        var d: [String: SCNMaterial] = [:]
        d["bark"] = World.pbr(color(0.3, 0.2, 0.13), rough: 0.95)
        d["dead"] = World.pbr(color(0.36, 0.32, 0.28), rough: 0.95)
        d["needles"] = World.pbr(color(0.12, 0.25, 0.12), rough: 0.9)
        d["snowNeedles"] = World.pbr(color(0.55, 0.62, 0.58), rough: 0.9)
        d["stake"] = World.pbr(color(0.55, 0.4, 0.25), rough: 0.8)
        d["tip"] = World.pbr(color(0.75, 0.62, 0.45), rough: 0.6)
        d["cactus"] = World.pbr(color(0.25, 0.45, 0.2), rough: 0.7)
        let ice = World.pbr(color(0.72, 0.88, 1), rough: 0.08)
        ice.transparency = 0.85; ice.fresnelExponent = 2
        d["ice"] = ice
        let cr = World.pbr(color(0.65, 0.4, 1), rough: 0.12, metal: 0.2)
        cr.emission.contents = color(0.35, 0.15, 0.7); cr.emission.intensity = 1.2
        d["crystal"] = cr
        let cr2 = World.pbr(color(0.3, 0.9, 1), rough: 0.12, metal: 0.2)
        cr2.emission.contents = color(0.1, 0.45, 0.6); cr2.emission.intensity = 1.2
        d["crystal2"] = cr2
        return d
    }()

    init() {
        let l = SCNLight()
        l.type = .directional
        l.castsShadow = true
        l.shadowMode = .deferred
        l.shadowSampleCount = 8
        l.shadowRadius = 2.5
        l.shadowMapSize = CGSize(width: 2048, height: 2048)
        l.orthographicScale = 14
        l.zNear = 1; l.zFar = 120
        l.shadowColor = NSColor(white: 0, alpha: 0.55)
        sun.light = l
        let a = SCNLight()
        a.type = .ambient
        ambient.light = a
    }

    static func pbr(_ c: NSColor, rough: CGFloat = 0.85, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    func build(map m: MapDef, height: Float, scene: SCNScene) {
        map = m
        level = generateLevel(m, height: height)
        root.childNodes.forEach { $0.removeFromParentNode() }
        snow = nil

        // sky and fog
        let sky = Tex.skyDome(m, sunDir: sunDir)
        scene.background.contents = sky
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = 0.9
        scene.fogColor = color(mix3(m.fog, m.skyHorizon, 0.6))
        scene.fogStartDistance = 70
        scene.fogEndDistance = CGFloat(900 + height * 0.9)
        scene.fogDensityExponent = 1.3

        // lights
        let sl = sun.light!
        sl.color = color(m.sun)
        sl.intensity = 2100
        ambient.light!.color = color(mix3(m.skyTop, m.fog, 0.5))
        ambient.light!.intensity = 120
        root.addChildNode(sun)
        root.addChildNode(ambient)
        placeSun(at: V3(0, height, 0))

        // materials shared by every chunk
        rockMat = World.triplanar(rock: Tex.rockH(m.style), top: Tex.groundH(m.groundStyle), scale: 0.22, top: 1, bump: 1.4, rough: m.style == 3 ? 0.35 : 0.9)
        groundMat = World.triplanar(rock: Tex.groundH(m.groundStyle), top: Tex.groundH(m.groundStyle), scale: 0.3, top: 1, bump: 0.35, rough: m.groundStyle == 3 ? 0.5 : 0.95)
        if m.extra == .lava {
            groundMat.emission.contents = Tex.lavaGlow()
            groundMat.emission.intensity = 1.6
            groundMat.emission.wrapS = .repeat; groundMat.emission.wrapT = .repeat
        }
        rockMeshes = (0..<6).map { rockMesh(variant: $0, jag: m.jagged) }
        boulderMat = World.triplanar(rock: Tex.rockH(m.style), top: Tex.groundH(m.groundStyle), scale: 0.45, top: m.groundStyle == 3 ? 0.8 : 0.25, bump: 1.6,
                                     rough: m.style == 3 ? 0.3 : (m.style == 4 ? 0.4 : 0.88))
        boulderMat.diffuse.contents = color(mix3(m.rock, m.rock2, 0.6) * 0.95)
        spikeMat = World.triplanar(rock: Tex.rockH(m.style), top: Tex.rockH(m.style), scale: 0.6, top: 0, bump: 1.2, rough: 0.8)
        spikeMat.diffuse.contents = color(mix3(m.rock, m.rock2, 0.4))
        grassMat = SCNMaterial()
        grassMat.lightingModel = .physicallyBased
        grassMat.diffuse.contents = Tex.grassBlades()
        grassMat.roughness.contents = 0.85
        grassMat.isDoubleSided = true
        grassMat.blendMode = .replace
        grassMat.shaderModifiers = [.surface: "#pragma body\nif (_surface.diffuse.a < 0.45) discard_fragment();\n_surface.diffuse.a = 1.0;\n"]

        // the whole cliff at low detail, sunk slightly so streamed detail chunks draw over it
        let p = level.profile
        for i in 0..<(p.count - 1) {
            let isGround = i == p.count - 2
            let g = strip(p[i], p[i + 1], ground: isGround || i == 0, X: max(2500, height * 0.5), fine: false, sink: 1.2)
            g.materials = [isGround ? groundMat : rockMat]
            let n = SCNNode(geometry: g)
            n.castsShadow = false
            root.addChildNode(n)
        }
        root.addChildNode(chunkRoot)
        chunks.removeAll()
        chunkRoot.childNodes.forEach { $0.removeFromParentNode() }
        capsulesDirty = true; blockersDirty = true
        var rng = RNG(m.seed &+ 5)
        addTrees(m, rng: &rng)
        // distant mountains so the horizon isn't empty
        addBackdrop(m, height: height, rng: &rng)

        switch m.extra {
        case .sea:
            let sea = SCNPlane(width: 3000, height: 2000)
            let sm = World.pbr(color(0.1, 0.32, 0.45), rough: 0.12, metal: 0.1)
            sm.transparency = 0.92
            sea.materials = [sm]
            let n = SCNNode(geometry: sea)
            n.eulerAngles.x = -.pi / 2
            n.simdPosition = V3(0, 0.25, level.baseZ + 45 + 1000)
            root.addChildNode(n)
        case .snow, .dust:
            let ps = SCNParticleSystem()
            ps.birthRate = m.extra == .snow ? 500 : 60
            ps.particleLifeSpan = 10
            ps.emitterShape = SCNBox(width: 60, height: 1, length: 60, chamferRadius: 0)
            ps.particleSize = m.extra == .snow ? 0.05 : 0.15
            ps.particleColor = m.extra == .snow ? .white : color(m.ground * 1.2)
            ps.particleColorVariation = SCNVector4(0, 0, 0.1, 0.3)
            ps.particleImage = softDotImage()
            ps.acceleration = SCNVector3(0.4, m.extra == .snow ? -0.9 : -0.05, 0)
            ps.particleVelocity = m.extra == .snow ? 0.4 : 0.8
            ps.particleVelocityVariation = 0.5
            ps.blendMode = .alpha
            ps.isAffectedByGravity = false
            let n = SCNNode()
            n.addParticleSystem(ps)
            root.addChildNode(n)
            snow = n
        case .lava, .none: break
        }
    }

    /// Keeps the shadow frustum and weather centred on the action.
    var sunDir: V3 { let e = map.sunElev; return simd_normalize(V3(0.6, sinf(e) * 1.4, 0.35 + cosf(e) * 0.3)) }

    func placeSun(at focus: V3) {
        let dir = sunDir
        sun.simdPosition = focus + dir * 50
        sun.simdLook(at: focus, up: V3(0, 1, 0), localFront: V3(0, 0, -1))
        snow?.simdPosition = focus + V3(0, 14, 0)
    }

    private func surfaceMaterial(_ tex: CGImage, _ nrm: CGImage, scale: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = tex
        m.normal.contents = nrm
        m.normal.intensity = 0.9
        m.roughness.contents = map.style == 3 ? 0.4 : 0.92
        for p in [m.diffuse, m.normal] { p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear }
        m.isDoubleSided = false
        return m
    }

    /// A grid strip across x over one profile segment, displaced with noise and tinted per vertex.
    private func strip(_ a: SIMD2<Float>, _ b: SIMD2<Float>, ground: Bool, X: Float = 70, fine: Bool = true, sink: Float = 0) -> SCNGeometry {
        let dz = b.x - a.x, dy = b.y - a.y
        let len = max(0.01, sqrtf(dz * dz + dy * dy))
        let d = V3(0, dy, dz) / len
        let n = V3(0, dz, -dy) / len
        let steep = abs(dy) / len
        let alongStep: Float = fine ? 0.8 : max(12, len / 30)
        let nv = max(2, Int(ceilf(len / alongStep)) + 1)
        // denser in the middle where the body lands
        var xs: [Float] = []
        var x = -X
        while x < X { xs.append(x); x += fine ? (abs(x) < 16 ? 0.8 : 3) : (abs(x) < 100 ? 25 : 120) }
        xs.append(X)
        let nu = xs.count
        var verts = [SCNVector3](), norms = [SCNVector3](), uvs = [CGPoint](), cols = [SIMD4<Float>]()
        verts.reserveCapacity(nu * nv)
        let m = map
        var pos = [V3](repeating: .zero, count: nu * nv)
        for j in 0..<nv {
            let s = Float(j) / Float(nv - 1) * len
            let endFade = smoothstep(0, 0.9, min(s, len - s))
            for i in 0..<nu {
                let xx = xs[i]
                let base = V3(xx, a.y, a.x) + d * s
                var amp: Float = ground ? 0.08 : (0.12 + steep * 0.18)
                amp += smoothstep(10, 40, abs(xx)) * (ground ? 0.3 : 2.2)
                let nz = Noise.fbm(xx * 0.18, (base.y + base.z) * 0.18, octaves: 4, seed: 3)
                pos[j * nu + i] = base + n * (nz * amp * endFade - sink)
                verts.append(SCNVector3(pos[j * nu + i]))
                uvs.append(CGPoint(x: CGFloat(xx / (ground ? 5 : 3.5)), y: CGFloat((base.z * 0.3 - base.y) / (ground ? 5 : 3.5))))
                // tint: flat-ish = top colour, steep = rock with bands of rock2
                let mixN = Noise.fbm(xx * 0.07 + 11, (base.y + base.z * 0.5) * 0.09, octaves: 3, seed: 8) * 0.5 + 0.5
                var c = mix3(m.rock, m.rock2, mixN)
                if ground { c = mix3(m.ground, m.ground * 0.8, mixN) } else if n.y > 0.82 {
                    c = mix3(m.top, m.top * 0.82, mixN)
                } else if n.y > 0.55 {
                    c = mix3(c, m.top, smoothstep(0.55, 0.82, n.y) * 0.7)
                }
                cols.append(SIMD4(c.x, c.y, c.z, 1))
            }
        }
        for j in 0..<nv {
            for i in 0..<nu {
                let l = pos[j * nu + max(0, i - 1)], r = pos[j * nu + min(nu - 1, i + 1)]
                let dn = pos[max(0, j - 1) * nu + i], up = pos[min(nv - 1, j + 1) * nu + i]
                var nn = simd_cross(r - l, up - dn)
                if simd_dot(nn, n) < 0 { nn = -nn }
                let ln = simd_length(nn)
                norms.append(SCNVector3(ln > 1e-6 ? nn / ln : n))
            }
        }
        var idx: [Int32] = []
        idx.reserveCapacity((nu - 1) * (nv - 1) * 6)
        for j in 0..<(nv - 1) {
            for i in 0..<(nu - 1) {
                let a0 = Int32(j * nu + i), a1 = a0 + 1, b0 = Int32((j + 1) * nu + i), b1 = b0 + 1
                // winding so the front face points along n
                idx += [a0, b0, a1, a1, b0, b1]
            }
        }
        // make sure winding matches the normal
        let t0 = pos[Int(idx[0])], t1 = pos[Int(idx[1])], t2 = pos[Int(idx[2])]
        if simd_dot(simd_cross(t1 - t0, t2 - t0), n) < 0 {
            for k in stride(from: 0, to: idx.count, by: 3) { idx.swapAt(k + 1, k + 2) }
        }
        let colData = cols.withUnsafeBufferPointer { Data(buffer: $0) }
        let colSrc = SCNGeometrySource(data: colData, semantic: .color, vectorCount: cols.count, usesFloatComponents: true,
                                       componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), SCNGeometrySource(textureCoordinates: uvs), colSrc],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return g
    }

    // MARK: streaming

    /// Things the camera shouldn't sit behind or inside: every capsule plus tree foliage.
    var camBlockers: [Capsule] {
        if blockersDirty { blockerCache = chunks.values.flatMap { $0.capsules.filter { $0.r > 0.2 } + $0.foliage }; blockersDirty = false }
        return blockerCache
    }
    private var blockersDirty = true
    private var blockerCache: [Capsule] = []

    /// Every collision capsule in the loaded chunks.
    var capsules: [Capsule] {
        if capsulesDirty { capsuleCache = chunks.values.flatMap { $0.capsules }; capsulesDirty = false }
        return capsuleCache
    }

    /// Loads detail chunks near `focus` (and `cam`), unloads far ones. `budget` limits new chunks per call.
    func stream(focus: V3, cam: V3, budget: Int = 2) {
        let p = level.profile
        var want: [(Int, Float)] = []
        let R: Float = 170
        for i in 0..<(p.count - 1) {
            let a = p[i], b = p[i + 1]
            let lo = min(a.y, b.y) - R, hi = max(a.y, b.y) + R
            guard (focus.y > lo && focus.y < hi) || (cam.y > lo && cam.y < hi) else { continue }
            let len = simd_length(b - a)
            let np = level.pieces(i)
            for k in 0..<np {
                let t = min(1, (Float(k) + 0.5) * Level.piece / max(len, 0.01))
                let c = a + (b - a) * t
                let cp = V3(0, c.y, c.x)
                let d = min(simd_length(SIMD2(cp.y - focus.y, cp.z - focus.z)), simd_length(SIMD2(cp.y - cam.y, cp.z - cam.z)))
                if d < R { want.append((i * 10000 + k, d)) }
            }
        }
        let wantSet = Set(want.map { $0.0 })
        for (key, live) in chunks where !wantSet.contains(key) {
            // keep a margin so chunks don't flicker at the edge
            let i = key / 10000, k = key % 10000
            let a = p[i], b = p[i + 1]
            let len = simd_length(b - a)
            let t = min(1, (Float(k) + 0.5) * Level.piece / max(len, 0.01))
            let c = a + (b - a) * t
            if simd_length(SIMD2(c.y - focus.y, c.x - focus.z)) > R + 90 && simd_length(SIMD2(c.y - cam.y, c.x - cam.z)) > R + 90 {
                live.node.removeFromParentNode()
                chunks[key] = nil
                capsulesDirty = true; blockersDirty = true
            }
        }
        var built = 0
        for (key, _) in want.sorted(by: { $0.1 < $1.1 }) where chunks[key] == nil {
            if built >= budget { break }
            let i = key / 10000, k = key % 10000
            let ch = buildChunk(level, map, seg: i, piece: k)
            let node = chunkNode(ch, seg: i, piece: k)
            chunkRoot.addChildNode(node)
            let foliage = ch.obstacles.filter { $0.kind == .pine }.map { o in
                Capsule(a: o.base + o.dir * (o.len * 0.3), b: o.base + o.dir * (o.len * 0.95), r: o.len * 0.26)
            }
            chunks[key] = Live(node: node, capsules: ch.capsules, foliage: foliage)
            capsulesDirty = true; blockersDirty = true
            built += 1
        }
    }

    private func chunkNode(_ ch: Chunk, seg i: Int, piece k: Int) -> SCNNode {
        let node = SCNNode()
        let p = level.profile
        let a = p[i], b = p[i + 1]
        let len = simd_length(b - a)
        let t0 = Float(k) * Level.piece / len, t1 = min(1, Float(k + 1) * Level.piece / len)
        let isGround = i == p.count - 2
        let g = strip(a + (b - a) * t0, a + (b - a) * t1, ground: isGround || i == 0, X: 70, fine: true)
        g.materials = [isGround ? groundMat : rockMat]
        node.addChildNode(SCNNode(geometry: g))
        let props = SCNNode()
        for r in ch.rocks {
            let n = SCNNode(geometry: rockMeshes[r.variant])
            n.geometry!.firstMaterial = boulderMat
            n.simdPosition = r.c
            n.simdOrientation = r.rot
            n.simdScale = V3(repeating: r.r)
            props.addChildNode(n)
        }
        for o in ch.obstacles { props.addChildNode(obstacleNode(o)) }
        if !props.childNodes.isEmpty {
            let flat = props.flattenedClone()
            flat.castsShadow = true
            node.addChildNode(flat)
        }
        if !ch.grass.isEmpty { node.addChildNode(grassNode(ch.grass, seed: UInt64(i * 10000 + k))) }
        return node
    }

    /// A cylinder (or cone) between two points.
    private func rod(_ a: V3, _ b: V3, r0: Float, r1: Float, _ m: SCNMaterial, sides: Int = 10) -> SCNNode {
        let g = SCNCone(topRadius: CGFloat(r1), bottomRadius: CGFloat(r0), height: 1)
        g.radialSegmentCount = sides
        g.materials = [m]
        let n = SCNNode(geometry: g)
        let d = b - a, L = max(0.01, simd_length(d))
        n.simdPosition = (a + b) / 2
        n.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: d / L)
        n.simdScale = V3(1, L, 1)
        return n
    }

    private func obstacleNode(_ o: Obstacle) -> SCNNode {
        let node = SCNNode()
        let caps = obstacleCapsules(o, sharpBase: 0)
        let M = obMats
        switch o.kind {
        case .pine:
            let snowy = map.groundStyle == 3
            node.addChildNode(rod(caps[0].a, caps[0].b, r0: o.r, r1: o.r * 0.4, M["bark"]!))
            for c in caps.dropFirst() { node.addChildNode(rod(c.a, c.b, r0: 0.07, r1: 0.03, M["bark"]!, sides: 5)) }
            for k in 0..<4 {
                let h = o.len * (0.3 + Float(k) * 0.17)
                let rr = (1 - Float(k) * 0.2) * o.len * 0.3 + 0.4
                let base = o.base + o.dir * h
                let cone = rod(base, base + o.dir * (o.len * 0.34), r0: rr, r1: 0, snowy && k == 3 ? World.pbr(color(0.92, 0.94, 0.97)) : M[snowy ? "snowNeedles" : "needles"]!, sides: 9)
                node.addChildNode(cone)
            }
        case .deadTree:
            node.addChildNode(rod(caps[0].a, caps[0].b, r0: o.r, r1: o.r * 0.3, M["dead"]!, sides: 7))
            for c in caps.dropFirst() { node.addChildNode(rod(c.a, c.b, r0: 0.08, r1: 0.005, M["dead"]!, sides: 5)) }
        case .stake:
            let c = caps[0]
            let mid = c.a + (c.b - c.a) * 0.8
            node.addChildNode(rod(c.a, mid, r0: o.r, r1: o.r, M["stake"]!, sides: 7))
            node.addChildNode(rod(mid, c.b, r0: o.r, r1: 0.003, M["tip"]!, sides: 7))
        case .cactus:
            for c in caps {
                let g = SCNCapsule(capRadius: CGFloat(c.r), height: CGFloat(simd_length(c.b - c.a) + c.r * 2))
                g.radialSegmentCount = 12
                g.materials = [M["cactus"]!]
                let n = SCNNode(geometry: g)
                let d = c.b - c.a, L = max(0.01, simd_length(d))
                n.simdPosition = (c.a + c.b) / 2
                n.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: d / L)
                node.addChildNode(n)
            }
        case .icicle:
            node.addChildNode(rod(o.base, o.base + o.dir * o.len, r0: o.r, r1: 0.005, M["ice"]!, sides: 8))
        case .rockSpike:
            node.addChildNode(rod(o.base, o.base + o.dir * o.len, r0: o.r, r1: 0.01, spikeMat, sides: 7))
        case .crystal:
            var i = 0
            while i + 1 < caps.count {
                let body = caps[i], tip = caps[i + 1]
                let m = M[(o.seed + UInt64(i)) % 3 == 0 ? "crystal2" : "crystal"]!
                node.addChildNode(rod(body.a, body.b, r0: body.r, r1: body.r, m, sides: 6))
                node.addChildNode(rod(tip.a, tip.b, r0: body.r, r1: 0.005, m, sides: 6))
                i += 2
            }
        }
        return node
    }

    private func grassNode(_ tufts: [(V3, V3)], seed: UInt64) -> SCNNode {
        var rng = RNG(seed &+ 77)
        var v = [SCNVector3](), n = [SCNVector3](), uv = [CGPoint](), col = [SIMD4<Float>](), idx = [Int32]()
        for (p, tint) in tufts {
            let h = rng.range(0.25, 0.6), w = rng.range(0.35, 0.65)
            let th = rng.range(0, .pi)
            let lean = V3(rng.range(-0.1, 0.1), 0, rng.range(-0.1, 0.1))
            let c = tint * rng.range(0.75, 1.2) + V3(rng.range(0, 0.06), rng.range(0, 0.05), 0)
            for k in 0..<3 {
                let a = th + Float(k) * .pi / 3
                let d = V3(cosf(a), 0, sinf(a)) * (w / 2)
                let base = Int32(v.count)
                let pts = [p - d, p + d, p + d + V3(0, h, 0) + lean, p - d + V3(0, h, 0) + lean]
                for (i, q) in pts.enumerated() {
                    v.append(SCNVector3(q)); n.append(SCNVector3(0, 1, 0))
                    uv.append(CGPoint(x: i == 0 || i == 3 ? 0 : 1, y: i < 2 ? 1 : 0))
                    let shade: Float = i < 2 ? 0.78 : 1.05
                    col.append(SIMD4(c.x * shade, c.y * shade, c.z * shade, 1))
                }
                idx += [base, base + 1, base + 2, base, base + 2, base + 3]
            }
        }
        let colSrc = SCNGeometrySource(data: col.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: col.count, usesFloatComponents: true,
                                       componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n), SCNGeometrySource(textureCoordinates: uv), colSrc],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [grassMat]
        let node = SCNNode(geometry: g)
        node.castsShadow = false
        return node
    }

    /// A unit boulder: subdivided icosahedron pushed around with noise and ridges, smooth-shaded.
    private func rockMesh(variant: Int, jag: Float) -> SCNGeometry {
        var (v, f) = icosphere(4)
        let sx = 1 + Float(variant % 3) * 0.14, sz = 1 - Float(variant % 2) * 0.12
        for i in 0..<v.count {
            let p = v[i]
            let n1 = Noise.fbm(p.x * 1.4 + Float(variant) * 3.1 + p.z * 0.7, p.y * 1.4 - p.z * 1.1, octaves: 5, seed: Int32(variant + 1))
            let ridge = Noise.ridged(p.x * 2.4 + p.z, p.y * 2.4 - p.z * 0.6 + Float(variant), octaves: 4, seed: Int32(variant + 9))
            // flat-ish facets: quantise a low-frequency field a little
            let facet = Noise.perlin(p.x * 2 + p.z * 1.3, p.y * 2 - p.z * 0.7, seed: Int32(variant + 20))
            var r: Float = 0.9 + n1 * 0.16 + (ridge - 0.3) * 0.22 * (0.4 + jag) - abs(facet) * 0.06
            r = clampf(r, 0.72, 1.2 + jag * 0.12)
            var q = p * r
            q.x *= sx; q.z *= sz
            if q.y < -0.3 { q.y = -0.3 + (q.y + 0.3) * 0.55 }
            v[i] = q
        }
        var nrm = [V3](repeating: .zero, count: v.count)
        var idx: [Int32] = []
        for t in f {
            let n = simd_cross(v[t.1] - v[t.0], v[t.2] - v[t.0])
            nrm[t.0] += n; nrm[t.1] += n; nrm[t.2] += n
            idx += [Int32(t.0), Int32(t.1), Int32(t.2)]
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: v.map { SCNVector3($0) }), SCNGeometrySource(normals: nrm.map { SCNVector3(simd_normalize($0)) }),
                                     SCNGeometrySource(textureCoordinates: v.map { CGPoint(x: CGFloat($0.x + $0.z * 0.5), y: CGFloat($0.y)) })],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// World-space triplanar detail + bump, so rock never stretches, and flat tops blend to the ground texture.
    static func triplanar(rock: CGImage, top: CGImage, scale: Float, top topAmount: Float, bump: Float, rough: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = rough
        m.metalness.contents = 0.0
        let rp = SCNMaterialProperty(contents: rock); rp.mipFilter = .linear; rp.wrapS = .repeat; rp.wrapT = .repeat
        let tp = SCNMaterialProperty(contents: top); tp.mipFilter = .linear; tp.wrapS = .repeat; tp.wrapT = .repeat
        m.setValue(rp, forKey: "rockTex")
        m.setValue(tp, forKey: "topTex")
        m.setValue(NSNumber(value: scale), forKey: "texScale")
        m.setValue(NSNumber(value: topAmount), forKey: "topAmount")
        m.setValue(NSNumber(value: bump), forKey: "bumpK")
        m.shaderModifiers = [.surface: """
        #pragma arguments
        texture2d<float> rockTex;
        texture2d<float> topTex;
        float texScale;
        float topAmount;
        float bumpK;
        #pragma body
        constexpr sampler smp(filter::linear, mip_filter::linear, address::repeat);
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
        float3 bw = pow(abs(wn), float3(6.0)); bw /= (bw.x + bw.y + bw.z + 0.0001);
        float s = texScale;
        float r = rockTex.sample(smp, wp.zy * s).r * bw.x + rockTex.sample(smp, wp.xz * s).r * bw.y + rockTex.sample(smp, wp.xy * s).r * bw.z;
        float s2 = s * 0.12;
        float macro = rockTex.sample(smp, wp.zy * s2 + 0.31).r * bw.x + rockTex.sample(smp, wp.xz * s2 + 0.31).r * bw.y + rockTex.sample(smp, wp.xy * s2 + 0.31).r * bw.z;
        float s3 = s * 3.1;
        float fine = rockTex.sample(smp, wp.zy * s3 + 0.7).r * bw.x + rockTex.sample(smp, wp.xz * s3 + 0.7).r * bw.y + rockTex.sample(smp, wp.xy * s3 + 0.7).r * bw.z;
        float t = topTex.sample(smp, wp.xz * s * 1.7).r * 0.6 + topTex.sample(smp, wp.xz * s * 0.37 + 0.5).r * 0.4;
        float up = smoothstep(0.6, 0.85, wn.y) * topAmount;
        float h = mix(r * 0.75 + fine * 0.25, t * 0.5, up);
        float dist = length(_surface.position);
        float near = 1.0 - smoothstep(40.0, 160.0, dist);
        float tone = mix(0.6 + 0.6 * (r * 0.8 + fine * 0.2), 0.86 + 0.22 * t, up);
        tone = mix(0.85, tone, 0.35 + 0.65 * near);
        _surface.diffuse.rgb *= tone * (0.72 + 0.56 * macro);
        _surface.roughness = clamp(_surface.roughness - (1.0 - r) * 0.15, 0.05, 1.0);
        float3 dpdx = dfdx(_surface.position), dpdy = dfdy(_surface.position);
        float dhx = dfdx(h), dhy = dfdy(h);
        float3 N = _surface.normal;
        float3 r1 = cross(dpdy, N), r2 = cross(N, dpdx);
        float det = dot(dpdx, r1);
        float3 grad = sign(det) * (dhx * r1 + dhy * r2);
        _surface.normal = normalize(abs(det) * N - grad * bumpK * near * (1.0 - up * 0.85));
        """]
        return m
    }

    // MARK: grass and trees

    private var grassy: Bool { map.top.y > map.top.x * 1.12 && map.top.y > map.top.z * 1.2 }
    private var groundGrassy: Bool { map.ground.y > map.ground.x * 1.12 && map.ground.y > map.ground.z * 1.2 }

    private func addTrees(_ m: MapDef, rng: inout RNG) {
        let snowy = m.groundStyle == 3
        guard grassy || groundGrassy || snowy else { return }
        let bark = World.pbr(color(0.3, 0.2, 0.13), rough: 0.95)
        let needles = World.pbr(color(snowy ? V3(0.55, 0.62, 0.58) : V3(0.13, 0.26, 0.13)), rough: 0.9)
        let snowM = World.pbr(color(0.92, 0.94, 0.97), rough: 0.8)
        let forest = SCNNode()
        func tree(_ p: V3, _ s: Float) {
            let t = SCNNode()
            let trunk = SCNCylinder(radius: CGFloat(0.16 * s), height: CGFloat(2 * s))
            trunk.materials = [bark]
            let tn = SCNNode(geometry: trunk); tn.simdPosition = V3(0, s, 0)
            t.addChildNode(tn)
            for k in 0..<4 {
                let r = (1.6 - Float(k) * 0.33) * s, h = (2.2 - Float(k) * 0.3) * s
                let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(r), height: CGFloat(h))
                cone.radialSegmentCount = 9
                cone.materials = [snowy && k == 3 ? snowM : needles]
                let cn = SCNNode(geometry: cone)
                cn.simdPosition = V3(0, (1.5 + Float(k) * 1.05) * s + h / 2, 0)
                cn.eulerAngles.y = CGFloat(Float(k) * 0.7)
                t.addChildNode(cn)
            }
            t.simdPosition = p
            t.eulerAngles.y = CGFloat(rng.range(0, 6))
            forest.addChildNode(t)
        }
        let H = level.height
        for _ in 0..<70 {
            let side: Float = rng.chance(0.5) ? 1 : -1
            let x = side * rng.range(6, 70), z = rng.range(-60, -5)
            tree(V3(x, H - 0.1, z), rng.range(0.8, 1.5))
        }
        for _ in 0..<140 {
            let side: Float = rng.chance(0.5) ? 1 : -1
            let x = side * rng.range(14, 150), z = level.baseZ + rng.range(20, 300)
            tree(V3(x, -0.1, z), rng.range(0.9, 1.8))
        }
        let flat = forest.flattenedClone()
        flat.castsShadow = true
        root.addChildNode(flat)
    }

    /// A ring of ridged mountains around the valley, and a second, paler one behind it.
    private func addBackdrop(_ m: MapDef, height: Float, rng: inout RNG) {
        let center = V3(0, 0, level.baseZ * 0.5)
        let sc = max(1, height / 1500)
        for (ring, R, hMin, hMax, tint) in [(0, Float(2200) * sc, Float(300) * sc, Float(900) * sc, Float(0.35)), (1, 3800 * sc, 600 * sc, 1600 * sc, 0.6)] {
            let seg = 220
            var v = [SCNVector3](), n = [SCNVector3](), idx = [Int32](), col = [SIMD4<Float>]()
            let snowLine: Float = m.groundStyle == 3 || m.style == 3 ? 0.35 : 0.8
            for i in 0...seg {
                let a = Float(i) / Float(seg) * 2 * .pi
                let dir = V3(sinf(a), 0, cosf(a))
                let rid = Noise.ridged(cosf(a) * 3 + Float(ring) * 7, sinf(a) * 3, octaves: 5, seed: Int32(truncatingIfNeeded: m.seed) &+ Int32(ring))
                let hgt = hMin + (hMax - hMin) * rid + height * 0.7
                let base = center + dir * R
                let top = center + dir * (R + hgt * 0.6) + V3(0, hgt, 0)
                v.append(SCNVector3(base - V3(0, 10, 0))); v.append(SCNVector3(top))
                let nn = simd_normalize(-dir + V3(0, 0.6, 0))
                n.append(SCNVector3(nn)); n.append(SCNVector3(nn))
                let rc = mix3(mix3(m.rock2, m.rock, 0.4), m.fog, tint)
                let sc = mix3(V3(0.92, 0.94, 0.97), m.fog, tint * 0.6)
                col.append(SIMD4(rc.x * 0.8, rc.y * 0.8, rc.z * 0.8, 1))
                let t = rid > snowLine ? sc : rc
                col.append(SIMD4(t.x, t.y, t.z, 1))
            }
            for i in 0..<seg {
                let a = Int32(i * 2)
                idx += [a, a + 1, a + 2, a + 2, a + 1, a + 3]
            }
            let colSrc = SCNGeometrySource(data: col.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: col.count, usesFloatComponents: true,
                                           componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n), colSrc],
                                elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            let mat = World.pbr(.white, rough: 1)
            mat.isDoubleSided = true
            g.materials = [mat]
            let node = SCNNode(geometry: g)
            node.castsShadow = false
            root.addChildNode(node)
        }
    }
}

func icosphere(_ subdivisions: Int) -> ([V3], [(Int, Int, Int)]) {
    let t: Float = (1 + sqrtf(5)) / 2
    var v: [V3] = [V3(-1, t, 0), V3(1, t, 0), V3(-1, -t, 0), V3(1, -t, 0), V3(0, -1, t), V3(0, 1, t),
                   V3(0, -1, -t), V3(0, 1, -t), V3(t, 0, -1), V3(t, 0, 1), V3(-t, 0, -1), V3(-t, 0, 1)].map { simd_normalize($0) }
    var f: [(Int, Int, Int)] = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
                                (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in 0..<subdivisions {
        var cache: [Int: Int] = [:]
        func mid(_ a: Int, _ b: Int) -> Int {
            let key = min(a, b) << 16 | max(a, b)
            if let m = cache[key] { return m }
            v.append(simd_normalize((v[a] + v[b]) / 2))
            cache[key] = v.count - 1
            return v.count - 1
        }
        var nf: [(Int, Int, Int)] = []
        for (a, b, c) in f {
            let ab = mid(a, b), bc = mid(b, c), ca = mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        }
        f = nf
    }
    return (v, f)
}
