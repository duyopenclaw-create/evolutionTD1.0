import SceneKit
import simd

struct Ring {
    let node: SCNNode
    let center: SIMD3<Float>
    let normal: SIMD3<Float>
    let radius: Float
}

final class World {
    let root = SCNNode()
    let terrain: Terrain
    var rings: [Ring] = []
    var cloudMaterials: [SCNMaterial] = []
    let ringMat = SCNMaterial(), ringNextMat = SCNMaterial()
    let townCenter = SIMD2<Float>(-2750, 2350)

    init(terrain: Terrain) {
        self.terrain = terrain
        buildTerrain()
        buildSea()
        buildVegetation()
        buildTown()
        for ap in terrain.airports { buildAirport(ap) }
        buildLighthouse()
        buildClouds()
        buildRings()
    }

    // MARK: Terrain & sea

    private func buildTerrain() {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.93
        m.metalness.contents = 0.0
        m.shaderModifiers = [.surface: """
        float hash21(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
        float vnoise(float2 p) {
            float2 i = floor(p); float2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
            float a = hash21(i), b = hash21(i + float2(1.0, 0.0)), c = hash21(i + float2(0.0, 1.0)), d = hash21(i + float2(1.0, 1.0));
            return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
        }
        #pragma body
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float dist = length(_surface.position);
        float near = 1.0 - smoothstep(150.0, 1400.0, dist);
        float n = vnoise(wp.xz * 0.09) * 0.55 + vnoise(wp.xz * 0.37) * 0.3 + vnoise(wp.xz * 1.4) * 0.15;
        float broad = vnoise(wp.xz * 0.011);
        float k = mix(1.0, 0.78 + 0.44 * n, near) * (0.9 + 0.2 * broad);
        _surface.diffuse.rgb *= k;
        """]
        for n in terrain.buildNodes(material: m) {
            n.castsShadow = true
            root.addChildNode(n)
        }
    }

    private func buildSea() {
        let water = SCNMaterial()
        water.lightingModel = .physicallyBased
        water.diffuse.contents = color(0.03, 0.2, 0.3)
        water.roughness.contents = 0.06
        water.metalness.contents = 0.25
        water.transparency = 0.82
        water.blendMode = .alpha
        water.writesToDepthBuffer = true
        water.shaderModifiers = [.surface: """
        #pragma body
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float t = scn_frame.time;
        float dist = length(_surface.position);
        float fade = 1.0 - smoothstep(200.0, 5000.0, dist);
        float2 p = wp.xz;
        float2 g = float2(0.0);
        float2 d1 = normalize(float2(1.0, 0.35));  float ph1 = dot(p, d1) * 0.045 + t * 1.1;  g += d1 * cos(ph1) * 0.045 * 1.0;
        float2 d2 = normalize(float2(-0.6, 1.0));  float ph2 = dot(p, d2) * 0.09 + t * 1.6;   g += d2 * cos(ph2) * 0.09 * 0.45;
        float2 d3 = normalize(float2(0.3, -1.0));  float ph3 = dot(p, d3) * 0.21 + t * 2.3;   g += d3 * cos(ph3) * 0.21 * 0.16;
        float2 d4 = normalize(float2(-1.0, -0.2)); float ph4 = dot(p, d4) * 0.53 + t * 3.1;   g += d4 * cos(ph4) * 0.53 * 0.05;
        float2 d5 = normalize(float2(0.8, 0.9));   float ph5 = dot(p, d5) * 1.31 + t * 4.7;   g += d5 * cos(ph5) * 1.31 * 0.016;
        float3 nw = normalize(float3(-g.x * fade * 3.0, 1.0, -g.y * fade * 3.0));
        _surface.normal = normalize((scn_frame.viewTransform * float4(nw, 0.0)).xyz);
        """]
        let plane = SCNPlane(width: 120_000, height: 120_000)
        plane.widthSegmentCount = 8
        plane.heightSegmentCount = 8
        plane.materials = [water]
        let sea = SCNNode(geometry: plane)
        sea.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        sea.castsShadow = false
        sea.renderingOrder = 5
        root.addChildNode(sea)

        let floorMat = SCNMaterial()
        floorMat.lightingModel = .constant
        floorMat.diffuse.contents = color(0.03, 0.14, 0.22)
        let floorPlane = SCNPlane(width: 120_000, height: 120_000)
        floorPlane.materials = [floorMat]
        let floor = SCNNode(geometry: floorPlane)
        floor.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        floor.simdPosition = SIMD3(0, -70, 0)
        root.addChildNode(floor)
    }

    // MARK: Vegetation

    private func vegetationMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.9
        m.metalness.contents = 0.0
        return m
    }

    private func buildVegetation() {
        let chunks = 8
        let chunkSize = Terrain.size / Float(chunks)
        var builders = (0..<(chunks * chunks)).map { _ in MeshBuilder() }
        var rng = RNG(4242)
        let mat = vegetationMaterial()
        for _ in 0..<90_000 {
            let x = rng.range(-7400, 7400), z = rng.range(-7400, 7400)
            let h = terrain.height(x, z)
            if h < 4.5 || h > 760 { continue }
            let nrm = terrain.normal(x, z)
            if nrm.y < 0.85 { continue }
            let f = terrain.forest(x, z)
            let density = max(smoothstep(-0.02, 0.32, f) * 0.9, 0.035)
            if rng.float() > density * (1 - smoothstep(560, 760, h)) { continue }
            if terrain.airportWeight(x, z) > 0.02 { continue }
            if simd_distance(SIMD2(x, z), townCenter) < 820 { continue }
            let ci = min(Int((x + terrain.half) / chunkSize), chunks - 1)
            let cj = min(Int((z + terrain.half) / chunkSize), chunks - 1)
            let mb = builders[cj * chunks + ci]
            let s = rng.range(0.75, 1.45)
            let yaw = rng.range(0, 6.28)
            let base = SIMD3(x, h - 0.5, z)
            let conifer = h > 280 || rng.chance(0.3)
            let trunk = SIMD4<Float>(0.3, 0.2, 0.12, 1)
            if conifer {
                let g = rng.range(0.75, 1.15)
                let col = SIMD4<Float>(0.07 * g, 0.2 * g, 0.09 * g, 1)
                mb.cylinder(xform(base, yaw: yaw, scale: SIMD3(s, s, s)), radius: 0.35, height: 3, segments: 5, color: trunk, cap: false)
                mb.cone(xform(base + SIMD3(0, 2 * s, 0), yaw: yaw, scale: SIMD3(s, s, s)), radius: 3.3, height: 6.5, segments: 7, color: col, rng: &rng, jitter: 0.1)
                mb.cone(xform(base + SIMD3(0, 5 * s, 0), yaw: yaw + 0.4, scale: SIMD3(s, s, s)), radius: 2.5, height: 5.5, segments: 7, color: col * SIMD4(1.1, 1.1, 1.1, 1), rng: &rng, jitter: 0.1)
                mb.cone(xform(base + SIMD3(0, 8 * s, 0), yaw: yaw + 0.8, scale: SIMD3(s, s, s)), radius: 1.6, height: 4.2, segments: 6, color: col * SIMD4(1.2, 1.2, 1.2, 1), rng: &rng, jitter: 0.1)
            } else {
                var col = SIMD4<Float>(0.16, 0.33, 0.1, 1) * SIMD4(rng.range(0.8, 1.2), rng.range(0.85, 1.15), 1, 1)
                if rng.chance(0.06) { col = SIMD4(0.62, 0.42, 0.1, 1) }
                if rng.chance(0.04) { col = SIMD4(0.5, 0.18, 0.1, 1) }
                mb.cylinder(xform(base, yaw: yaw, scale: SIMD3(s, s, s)), radius: 0.4, height: 4.5, segments: 5, color: trunk, cap: false)
                mb.blob(xform(base + SIMD3(0, 6.5 * s, 0), yaw: yaw, scale: SIMD3(s, s, s)), radius: SIMD3(4.2, 3.6, 4.2), color: col, rng: &rng)
                if rng.chance(0.5) {
                    mb.blob(xform(base + SIMD3(1.8 * s, 8.4 * s, 0.8 * s), yaw: yaw, scale: SIMD3(s, s, s)), radius: SIMD3(2.8, 2.4, 2.8), color: col * SIMD4(1.12, 1.12, 1.1, 1), rng: &rng)
                }
            }
        }
        // Boulders on the high slopes
        for _ in 0..<2600 {
            let x = rng.range(-2500, 6000), z = rng.range(-5500, 2000)
            let h = terrain.height(x, z)
            if h < 250 { continue }
            let nrm = terrain.normal(x, z)
            if nrm.y > 0.97 || nrm.y < 0.6 { continue }
            if terrain.airportWeight(x, z) > 0.1 { continue }
            let ci = min(Int((x + terrain.half) / chunkSize), chunks - 1)
            let cj = min(Int((z + terrain.half) / chunkSize), chunks - 1)
            let s = rng.range(2, 9)
            let g = rng.range(0.4, 0.58)
            builders[cj * chunks + ci].blob(xform(SIMD3(x, h, z), yaw: rng.range(0, 6)), radius: SIMD3(s, s * 0.6, s * 0.9),
                                           color: SIMD4(g, g * 0.96, g * 0.9, 1), rng: &rng, jitter: 0.3, shadeVar: 0.2)
        }
        for mb in builders where !mb.isEmpty {
            let n = mb.node([mat])
            n.castsShadow = true
            root.addChildNode(n)
        }
        builders.removeAll()
    }

    // MARK: Town

    private func buildTown() {
        let mb = MeshBuilder()
        var rng = RNG(99)
        let walls: [SIMD4<Float>] = [SIMD4(0.93, 0.9, 0.82, 1), SIMD4(0.95, 0.85, 0.7, 1), SIMD4(0.85, 0.9, 0.95, 1),
                                     SIMD4(0.98, 0.95, 0.9, 1), SIMD4(0.9, 0.75, 0.6, 1), SIMD4(0.75, 0.85, 0.8, 1)]
        let roofs: [SIMD4<Float>] = [SIMD4(0.65, 0.22, 0.12, 1), SIMD4(0.55, 0.18, 0.12, 1), SIMD4(0.3, 0.3, 0.34, 1), SIMD4(0.72, 0.35, 0.18, 1)]
        let spacing: Float = 38
        for gx in -18...18 {
            for gz in -18...18 {
                if gx % 4 == 0 || gz % 5 == 0 { continue } // streets
                let off = SIMD2(Float(gx) * spacing, Float(gz) * spacing)
                let d = simd_length(off)
                let p = townCenter + off + SIMD2(rng.range(-5, 5), rng.range(-5, 5))
                if rng.float() > 1 - smoothstep(250, 760, d) + 0.05 { continue }
                let h = terrain.height(p.x, p.y)
                if h < 3 || terrain.normal(p.x, p.y).y < 0.93 { continue }
                let yaw: Float = rng.chance(0.5) ? 0 : .pi / 2
                if d < 200 && rng.chance(0.55) {
                    // taller blocks downtown
                    let hh = rng.range(12, 34)
                    let w = rng.range(14, 22)
                    let c = walls[rng.int(walls.count)] * SIMD4(0.9, 0.9, 0.95, 1)
                    mb.box(xform(SIMD3(p.x, h - 2 + hh / 2, p.y), yaw: yaw), size: SIMD3(w, hh + 4, w * 0.8), color: c, top: SIMD4(0.4, 0.4, 0.42, 1))
                    // window bands
                    var y: Float = 3
                    while y < hh - 1 {
                        mb.box(xform(SIMD3(p.x, h + y, p.y), yaw: yaw), size: SIMD3(w + 0.2, 1.1, w * 0.8 + 0.2), color: SIMD4(0.2, 0.3, 0.4, 1))
                        y += 3.4
                    }
                } else {
                    let w = rng.range(8, 13), dd = rng.range(7, 10), hh = rng.range(4.5, 6.5)
                    let c = walls[rng.int(walls.count)]
                    mb.box(xform(SIMD3(p.x, h - 1.5 + hh / 2, p.y), yaw: yaw), size: SIMD3(w, hh + 3, dd), color: c)
                    mb.roof(xform(SIMD3(p.x, h - 1.5 + hh + 1.5, p.y), yaw: yaw), size: SIMD3(w, rng.range(2.5, 4), dd), color: roofs[rng.int(roofs.count)])
                    if rng.chance(0.4) {
                        mb.blob(xform(SIMD3(p.x + w * 0.8, h + 3, p.y + dd * 0.4)), radius: SIMD3(2.4, 2.8, 2.4), color: SIMD4(0.18, 0.36, 0.12, 1), rng: &rng)
                    }
                }
            }
        }
        // Church tower in the square
        let ch = terrain.height(townCenter.x + 20, townCenter.y + 60)
        mb.box(xform(SIMD3(townCenter.x + 20, ch + 12, townCenter.y + 60)), size: SIMD3(7, 26, 7), color: SIMD4(0.92, 0.9, 0.85, 1))
        var r = RNG(1)
        mb.cone(xform(SIMD3(townCenter.x + 20, ch + 25, townCenter.y + 60), yaw: .pi / 4), radius: 5.2, height: 11, segments: 4, color: SIMD4(0.3, 0.32, 0.38, 1), rng: &r)
        let n = mb.node([vegetationMaterial()])
        n.castsShadow = true
        root.addChildNode(n)
    }

    private func buildLighthouse() {
        // on the southern headland
        var best = SIMD2<Float>(0, 3600), bestH: Float = -100
        for i in 0..<60 {
            let p = SIMD2<Float>(-600 + Float(i) * 40, 3900)
            for k in 0..<30 {
                let q = p + SIMD2(0, Float(-k) * 30)
                let h = terrain.height(q.x, q.y)
                if h > 8 && h < 30 && h > bestH && terrain.normal(q.x, q.y).y > 0.95 { best = q; bestH = h; break }
            }
        }
        if bestH < 0 { return }
        let mb = MeshBuilder()
        for i in 0..<6 {
            let c: SIMD4<Float> = i % 2 == 0 ? SIMD4(0.95, 0.95, 0.95, 1) : SIMD4(0.8, 0.1, 0.08, 1)
            mb.cylinder(xform(SIMD3(best.x, bestH - 1 + Float(i) * 4.5, best.y)), radius: 3.2 - Float(i) * 0.2, height: 4.5, segments: 14, color: c, topRadius: 3.0 - Float(i) * 0.2)
        }
        mb.cylinder(xform(SIMD3(best.x, bestH + 26, best.y)), radius: 2.1, height: 2.6, segments: 12, color: SIMD4(0.9, 0.95, 0.7, 1))
        var r = RNG(3)
        mb.cone(xform(SIMD3(best.x, bestH + 28.6, best.y)), radius: 2.6, height: 2.2, segments: 12, color: SIMD4(0.15, 0.15, 0.15, 1), rng: &r)
        let n = mb.node([vegetationMaterial()])
        n.castsShadow = true
        root.addChildNode(n)
    }

    // MARK: Airports

    private func runwayTexture(end: Bool, number: String) -> CGImage {
        let w = 128, h = end ? 512 : 256
        return makeImage(w, h) { ctx in
            // asphalt with grain
            ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.21, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            var rng = RNG(UInt64(h))
            for _ in 0..<(w * h / 6) {
                let g = CGFloat(rng.range(0.13, 0.3))
                ctx.setFillColor(CGColor(srgbRed: g, green: g, blue: g * 1.03, alpha: 0.5))
                ctx.fill(CGRect(x: Int(rng.range(0, Float(w))), y: Int(rng.range(0, Float(h))), width: 1, height: 1))
            }
            // tyre marks
            for _ in 0..<(end ? 40 : 6) {
                ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 0.25))
                let x = CGFloat(rng.range(40, 88))
                ctx.fill(CGRect(x: x, y: CGFloat(rng.range(0, Float(h))), width: 3, height: CGFloat(rng.range(20, 120))))
            }
            let white = CGColor(srgbRed: 0.93, green: 0.93, blue: 0.9, alpha: 0.95)
            ctx.setFillColor(white)
            // edge lines
            ctx.fill(CGRect(x: 3, y: 0, width: 3, height: h))
            ctx.fill(CGRect(x: w - 6, y: 0, width: 3, height: h))
            // In CG coords y=0 is the image bottom (the threshold end).
            let pxPerM = CGFloat(h) / (end ? 150 : 60)
            if end {
                for i in 0..<8 {
                    let x = 10 + CGFloat(i) * 14 + (i >= 4 ? 4 : 0)
                    ctx.fill(CGRect(x: x, y: 6 * pxPerM, width: 8, height: 30 * pxPerM))
                }
                let para = NSMutableParagraphStyle(); para.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 56, weight: .heavy),
                                                            .foregroundColor: NSColor(cgColor: white)!, .paragraphStyle: para]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: 42 * pxPerM)
                ctx.scaleBy(x: 1, y: 2.2)
                (number as NSString).draw(in: CGRect(x: 0, y: 0, width: w, height: 70), withAttributes: attrs)
                ctx.restoreGState()
                NSGraphicsContext.restoreGraphicsState()
                ctx.fill(CGRect(x: 26, y: 110 * pxPerM, width: 14, height: 30 * pxPerM))
                ctx.fill(CGRect(x: CGFloat(w - 40), y: 110 * pxPerM, width: 14, height: 30 * pxPerM))
            } else {
                ctx.fill(CGRect(x: CGFloat(w / 2 - 2), y: 0, width: 4, height: 36 * pxPerM))
            }
        }
    }

    private func asphalt(_ img: CGImage, repeatV: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.roughness.contents = 0.82
        m.metalness.contents = 0
        m.diffuse.wrapT = .repeat
        m.diffuse.wrapS = .clamp
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(1, repeatV, 1)
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 16
        return m
    }

    private func flat(_ w: CGFloat, _ l: CGFloat, _ m: SCNMaterial) -> SCNNode {
        let p = SCNPlane(width: w, height: l)
        p.materials = [m]
        let inner = SCNNode(geometry: p)
        inner.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        inner.castsShadow = false
        let n = SCNNode()
        n.addChildNode(inner)
        return n
    }

    private func buildAirport(_ ap: Airport) {
        let base = SCNNode()
        base.simdPosition = SIMD3(ap.cx, ap.elevation, ap.cz)
        // local -Z = take-off direction; +X = apron side.
        base.simdEulerAngles = SIMD3(0, ap.alongX ? -.pi / 2 : 0, 0)
        root.addChildNode(base)
        let L = CGFloat(ap.length), W = CGFloat(ap.width)
        let hdgStart = ap.alongX ? "09" : "36"
        let hdgFar = ap.alongX ? "27" : "18"

        let endLen: CGFloat = 150
        let startEnd = flat(W, endLen, asphalt(runwayTexture(end: true, number: hdgStart)))
        startEnd.simdPosition = SIMD3(0, 0.3, Float(L / 2 - endLen / 2))
        base.addChildNode(startEnd)
        let farEnd = flat(W, endLen, asphalt(runwayTexture(end: true, number: hdgFar)))
        farEnd.simdPosition = SIMD3(0, 0.3, Float(-L / 2 + endLen / 2))
        farEnd.simdEulerAngles = SIMD3(0, .pi, 0)
        base.addChildNode(farEnd)
        let midLen = L - endLen * 2
        let mid = flat(W, midLen, asphalt(runwayTexture(end: false, number: ""), repeatV: midLen / 60))
        mid.simdPosition = SIMD3(0, 0.3, 0)
        base.addChildNode(mid)

        // Taxiway, connectors and apron
        let tarmac = SCNMaterial()
        tarmac.lightingModel = .physicallyBased
        tarmac.diffuse.contents = color(0.27, 0.27, 0.28)
        tarmac.roughness.contents = 0.9
        let concrete = SCNMaterial()
        concrete.lightingModel = .physicallyBased
        concrete.diffuse.contents = color(0.55, 0.55, 0.53)
        concrete.roughness.contents = 0.85
        let taxiX = Float(W / 2 + 55)
        let taxi = flat(16, L - 120, tarmac)
        taxi.simdPosition = SIMD3(taxiX, 0.22, 0)
        base.addChildNode(taxi)
        for zc in [Float(L / 2 - 70), Float(-L / 2 + 70), 0] {
            let c = flat(CGFloat(taxiX - Float(W / 2)) + 8, 16, tarmac)
            c.simdPosition = SIMD3(Float(W / 2) + (taxiX - Float(W / 2)) / 2, 0.21, zc)
            base.addChildNode(c)
        }
        let apronW: CGFloat = 110, apronL: CGFloat = min(360, L * 0.4)
        let apronX = taxiX + 8 + Float(apronW / 2)
        let apron = flat(apronW, apronL, concrete)
        apron.simdPosition = SIMD3(apronX, 0.2, 0)
        base.addChildNode(apron)

        // Buildings
        let shed = AircraftModel.pbr(color(0.72, 0.74, 0.76), rough: 0.45, metal: 0.6)
        let wall = AircraftModel.pbr(color(0.9, 0.9, 0.88), rough: 0.7)
        let dark = AircraftModel.pbr(color(0.12, 0.13, 0.15), rough: 0.6)
        let glassM = AircraftModel.pbr(color(0.1, 0.2, 0.28), rough: 0.08, metal: 0.8)
        let hangarX = apronX + Float(apronW / 2) + 16
        let count = ap.length > 1200 ? 3 : 2
        for i in 0..<count {
            let z = Float(i - (count - 1) / 2) * 42 - (count == 2 ? 21 : 0)
            let box = SCNNode(geometry: SCNBox(width: 24, height: 8, length: 32, chamferRadius: 0))
            box.geometry?.materials = [shed]
            box.simdPosition = SIMD3(hangarX, 4, z)
            base.addChildNode(box)
            let arch = SCNNode(geometry: SCNCylinder(radius: 12, height: 32))
            arch.geometry?.materials = [shed]
            arch.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            arch.simdPosition = SIMD3(hangarX, 8, z)
            arch.simdScale = SIMD3(1, 1, 0.55)
            base.addChildNode(arch)
            let door = SCNNode(geometry: SCNBox(width: 0.3, height: 7, length: 26, chamferRadius: 0))
            door.geometry?.materials = [dark]
            door.simdPosition = SIMD3(hangarX - 12.05, 3.6, z)
            base.addChildNode(door)
        }
        // Control tower
        let tz = Float(apronL / 2) + 30
        let shaft = SCNNode(geometry: SCNCylinder(radius: 2.6, height: 20))
        shaft.geometry?.materials = [wall]
        shaft.simdPosition = SIMD3(apronX, 10, tz)
        base.addChildNode(shaft)
        let cab = SCNNode(geometry: SCNCylinder(radius: 5, height: 4))
        cab.geometry?.materials = [glassM]
        cab.simdPosition = SIMD3(apronX, 22, tz)
        base.addChildNode(cab)
        let cap = SCNNode(geometry: SCNCone(topRadius: 1, bottomRadius: 5.8, height: 1.6))
        cap.geometry?.materials = [dark]
        cap.simdPosition = SIMD3(apronX, 24.8, tz)
        base.addChildNode(cap)
        let beacon = SCNNode(geometry: SCNSphere(radius: 0.5))
        beacon.geometry?.materials = [AircraftModel.emissive(color(1, 0.3, 0.1))]
        beacon.simdPosition = SIMD3(apronX, 26, tz)
        base.addChildNode(beacon)
        // Terminal
        let term = SCNNode(geometry: SCNBox(width: 18, height: 9, length: 60, chamferRadius: 0.5))
        term.geometry?.materials = [wall]
        term.simdPosition = SIMD3(apronX + Float(apronW / 2) + 14, 4.5, -Float(apronL / 2) + 10)
        base.addChildNode(term)
        let band = SCNNode(geometry: SCNBox(width: 18.3, height: 2.6, length: 60.3, chamferRadius: 0.2))
        band.geometry?.materials = [glassM]
        band.simdPosition = term.simdPosition + SIMD3(0, 0.8, 0)
        base.addChildNode(band)
        // Windsock
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 7))
        pole.geometry?.materials = [shed]
        pole.simdPosition = SIMD3(-Float(W / 2) - 30, 3.5, Float(L / 2) - 260)
        base.addChildNode(pole)
        let sock = SCNNode(geometry: SCNCone(topRadius: 0.35, bottomRadius: 0.7, height: 4))
        let sockMat = AircraftModel.pbr(color(1, 0.45, 0.05), rough: 0.8)
        sock.geometry?.materials = [sockMat]
        sock.simdEulerAngles = SIMD3(0, 0.6, .pi / 2 - 0.15)
        sock.simdPosition = pole.simdPosition + SIMD3(1.8, 3.2, 0)
        base.addChildNode(sock)
        // Fuel tanks
        for i in 0..<2 {
            let tank = SCNNode(geometry: SCNCylinder(radius: 3, height: 6))
            tank.geometry?.materials = [wall]
            tank.simdPosition = SIMD3(hangarX + 4, 3, -Float(apronL / 2) - 18 - Float(i) * 8)
            base.addChildNode(tank)
        }
        // Parked aircraft on the apron
        let tints: [NSColor] = [color(0.55, 0.8, 1.0), color(1.0, 0.92, 0.5), color(0.7, 1.0, 0.7)]
        for i in 0..<(ap.length > 1200 ? 3 : 1) {
            let pm = AircraftModel(primary: SIMD4(0.1, 0.25, 0.7, 1), tint: tints[i % tints.count])
            pm.node.simdPosition = SIMD3(apronX + 20, 1.7, Float(i) * 22 - 30)
            pm.node.simdEulerAngles = SIMD3(0, .pi / 2 + 0.2, 0)
            pm.propDisc.isHidden = true
            base.addChildNode(pm.node)
        }

        // Runway edge + threshold lights
        let lights = MeshBuilder()
        var z = -Float(L / 2)
        while z <= Float(L / 2) {
            for sx: Float in [-1, 1] {
                lights.box(xform(SIMD3(sx * (Float(W / 2) + 1.5), 0.55, z)), size: SIMD3(0.45, 0.45, 0.45), color: SIMD4(1, 0.95, 0.8, 1))
            }
            z += 60
        }
        for i in 0..<10 {
            let x = -Float(W / 2) + Float(i) * Float(W) / 9
            lights.box(xform(SIMD3(x, 0.55, Float(L / 2) + 2)), size: SIMD3(0.5, 0.5, 0.5), color: SIMD4(0.2, 1, 0.3, 1))
            lights.box(xform(SIMD3(x, 0.55, -Float(L / 2) - 2)), size: SIMD3(0.5, 0.5, 0.5), color: SIMD4(1, 0.15, 0.1, 1))
        }
        // approach light bar
        for k in 1...8 {
            for i in -2...2 {
                lights.box(xform(SIMD3(Float(i) * 3, 1.0, Float(L / 2) + Float(k) * 30)), size: SIMD3(0.5, 0.5, 0.5), color: SIMD4(1, 1, 0.9, 1))
            }
        }
        let lm = SCNMaterial()
        lm.lightingModel = .constant
        lm.diffuse.contents = NSColor.white
        lm.diffuse.intensity = 2.5
        let ln = lights.node([lm])
        ln.castsShadow = false
        base.addChildNode(ln)

    }

    // MARK: Clouds

    private func cloudTexture(seed: UInt64) -> CGImage {
        var rng = RNG(seed)
        var blobs: [(Float, Float, Float)] = []
        for _ in 0..<26 {
            let a = rng.range(0, 6.28), r = rng.range(0, 0.28)
            blobs.append((0.5 + cosf(a) * r * 1.1, 0.55 + sinf(a) * r * 0.55 - 0.05, rng.range(0.12, 0.24)))
        }
        return makePixelImage(256, 256) { x, y in
            let u = Float(x) / 256, v = Float(y) / 256
            var dens: Float = 0
            for b in blobs {
                let dx = (u - b.0) / b.2, dy = (v - b.1) / b.2
                dens += max(0, 1 - (dx * dx + dy * dy))
            }
            let n = Noise.fbm(u * 6 + Float(seed), v * 6, octaves: 4, seed: 5) * 0.35
            let a = smoothstep(0.15, 0.95, dens + n)
            let shade = mixf(1.0, 0.72, smoothstep(0.35, 0.8, v))  // flat, darker undersides
            return SIMD4(shade, shade, shade * 1.02, a * 0.92)
        }
    }

    private func buildClouds() {
        let textures = (0..<4).map { cloudTexture(seed: UInt64(10 + $0)) }
        cloudMaterials = textures.map { tex in
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = tex
            m.multiply.contents = NSColor.white
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            m.blendMode = .alpha
            return m
        }
        var rng = RNG(777)
        let bb = SCNBillboardConstraint()
        bb.freeAxes = .all
        let cloudRoot = SCNNode()
        for _ in 0..<70 {
            let a = rng.range(0, 6.28), r = sqrtf(rng.float()) * 11000
            let c = SIMD3(cosf(a) * r, rng.range(1000, 1700), sinf(a) * r)
            let puffs = 5 + rng.int(7)
            let spread = rng.range(160, 380)
            for _ in 0..<puffs {
                let s = CGFloat(rng.range(220, 460))
                let p = SCNPlane(width: s * 1.5, height: s)
                p.materials = [cloudMaterials[rng.int(cloudMaterials.count)]]
                let n = SCNNode(geometry: p)
                n.simdPosition = c + SIMD3(rng.range(-spread, spread), rng.range(-40, 60), rng.range(-spread, spread))
                n.constraints = [bb]
                n.castsShadow = false
                n.renderingOrder = 10
                cloudRoot.addChildNode(n)
            }
        }
        root.addChildNode(cloudRoot)
    }

    func tintClouds(_ c: SIMD3<Float>) {
        for m in cloudMaterials { m.multiply.contents = color(c) }
    }

    // MARK: Ring course

    private func buildRings() {
        ringMat.lightingModel = .constant
        ringMat.diffuse.contents = color(1.0, 0.62, 0.12)
        ringMat.diffuse.intensity = 1.3
        ringNextMat.lightingModel = .constant
        ringNextMat.diffuse.contents = color(0.2, 1.0, 0.95)
        ringNextMat.diffuse.intensity = 2.2

        let hbr = terrain.airports[0]
        var pts: [SIMD3<Float>] = []
        let first = hbr.farEnd + SIMD2(0, -1100)
        pts.append(SIMD3(first.x, 0, first.y))
        let angles: [Float] = [-112, -88, -64, -40, -16, 8, 32, 56, 80, 104, 128, 152, 176, 198]
        for (i, deg) in angles.enumerated() {
            let a = deg * .pi / 180
            let r = 3800 + 700 * sinf(a * 3 + 1) + (i % 2 == 0 ? 150 : -150)
            pts.append(SIMD3(sinf(a) * r, 0, -cosf(a) * r))
        }
        // altitude: clear the terrain around each ring and along each leg
        var alts = pts.map { p -> Float in
            var m: Float = 0
            for k in 0..<12 {
                let a = Float(k) / 12 * 6.28
                m = max(m, terrain.height(p.x + cosf(a) * 250, p.z + sinf(a) * 250))
            }
            return max(m, terrain.height(p.x, p.z), 0) + 110
        }
        alts[0] = max(alts[0], hbr.elevation + 140)
        for i in 1..<pts.count {
            var m: Float = 0
            for k in 0...20 {
                let t = Float(k) / 20
                let p = mix3(pts[i - 1], pts[i], t)
                m = max(m, terrain.height(p.x, p.z))
            }
            alts[i] = max(alts[i], m + 70)
            alts[i - 1] = max(alts[i - 1], m + 50)
        }
        for i in pts.indices { pts[i].y = max(alts[i], 160) }

        let torus = SCNTorus(ringRadius: 17, pipeRadius: 1.2)
        torus.ringSegmentCount = 64
        torus.pipeSegmentCount = 12
        for i in pts.indices {
            let prev = pts[max(i - 1, 0)], next = pts[min(i + 1, pts.count - 1)]
            var dir = i == 0 ? pts[1] - pts[0] : next - prev
            dir.y *= 0.4
            dir = simd_normalize(dir)
            let g = torus.copy() as! SCNTorus
            g.materials = [ringMat]
            let n = SCNNode(geometry: g)
            n.simdPosition = pts[i]
            n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: dir)
            n.castsShadow = false
            root.addChildNode(n)
            rings.append(Ring(node: n, center: pts[i], normal: dir, radius: 17))
        }
    }

    func highlightRing(_ index: Int) {
        for (i, r) in rings.enumerated() {
            r.node.isHidden = i < index
            r.node.geometry?.materials = [i == index ? ringNextMat : ringMat]
            r.node.opacity = i == index ? 1 : (i == index + 1 ? 0.85 : 0.45)
        }
    }
}
