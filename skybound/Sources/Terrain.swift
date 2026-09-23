import SceneKit
import simd

enum Surface { case water, grass, paved }

struct Airport {
    let name: String
    let code: String
    let cx: Float, cz: Float
    var elevation: Float = 0
    let alongX: Bool
    let length: Float
    let width: Float

    /// Coordinates relative to the runway: `along` the centreline and `across` it.
    func local(_ x: Float, _ z: Float) -> (along: Float, across: Float) {
        alongX ? (x - cx, z - cz) : (z - cz, x - cx)
    }
    func world(along: Float, across: Float) -> SIMD2<Float> {
        alongX ? SIMD2(cx + along, cz + across) : SIMD2(cx + across, cz + along)
    }
    /// Take-off position and heading (radians, 0 = north, clockwise).
    var start: (pos: SIMD2<Float>, heading: Float) {
        alongX ? (world(along: -length / 2 + 45, across: 0), .pi / 2)
               : (world(along: length / 2 - 45, across: 0), 0)
    }
    /// The heading the start end faces, and the far threshold.
    var farEnd: SIMD2<Float> { alongX ? world(along: length / 2, across: 0) : world(along: -length / 2, across: 0) }
    var nearEnd: SIMD2<Float> { alongX ? world(along: -length / 2, across: 0) : world(along: length / 2, across: 0) }
    /// Apron (hangars, parked planes) is on the +across side.
    var apronAcross: Float { width / 2 + 95 }
}

/// Island heightfield: analytic noise sampled onto a grid; the grid is both the render mesh and the collision surface.
final class Terrain {
    static let size: Float = 16000
    static let res = 512
    let half = Terrain.size / 2
    let cell = Terrain.size / Float(Terrain.res)
    let n = Terrain.res + 1
    private(set) var heights: [Float] = []
    var airports: [Airport]

    init() {
        airports = [
            Airport(name: "HARBOR FIELD", code: "HBR", cx: -1500, cz: 2700, alongX: false, length: 1500, width: 36),
            Airport(name: "SUMMIT STRIP", code: "SMT", cx: 2350, cz: -2350, alongX: true, length: 1050, width: 26),
        ]
        for i in airports.indices {
            var sum: Float = 0, cnt: Float = 0
            let ap = airports[i]
            for a in stride(from: Float(-0.5), through: 0.5, by: 0.05) {
                for b: Float in [-60, 0, 60] {
                    let w = ap.world(along: a * ap.length, across: b)
                    sum += baseHeight(w.x, w.y)
                    cnt += 1
                }
            }
            airports[i].elevation = max((sum / cnt).rounded(), 14)
        }
        heights = [Float](repeating: 0, count: n * n)
        let nn = n, h0 = half, c = cell
        heights.withUnsafeMutableBufferPointer { buf in
            let ptr = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: nn) { j in
                let z = -h0 + Float(j) * c
                for i in 0..<nn { ptr[j * nn + i] = self.rawHeight(-h0 + Float(i) * c, z) }
            }
        }
    }

    // MARK: Height functions

    func baseHeight(_ x: Float, _ z: Float) -> Float {
        let wx = x + 900 * Noise.fbm(x * 0.00025 + 3.1, z * 0.00025 + 7.7, octaves: 3, seed: 11)
        let wz = z + 900 * Noise.fbm(x * 0.00025 + 1.9, z * 0.00025 + 4.2, octaves: 3, seed: 23)
        let d = sqrtf(wx * wx + wz * wz) / 6600
        let island = smoothstep(1.0, 0.42, d)
        let hills = 55 + 120 * Noise.fbm(x * 0.0007, z * 0.0007, octaves: 5, seed: 5)
        let mdx = (wx - 1900) / 3300, mdz = (wz + 1500) / 2700
        let mMask = smoothstep(1.0, 0.12, sqrtf(mdx * mdx + mdz * mdz))
        let ridge = Noise.ridged(x * 0.00042, z * 0.00042, octaves: 6, seed: 77)
        let mountain = mMask * (ridge * 1350 + 120 * mMask)
        let detail = 7 * Noise.fbm(x * 0.004, z * 0.004, octaves: 3, seed: 91)
        let land = hills + mountain + detail
        return -75 + (land + 75) * island
    }

    func flattenWeight(_ x: Float, _ z: Float, _ ap: Airport) -> Float {
        let (al, ac) = ap.local(x, z)
        let dx = max(abs(al) - (ap.length / 2 + 130), 0)
        let dz = max(abs(ac) - (ap.width / 2 + 190), 0)
        return smoothstep(430, 0, sqrtf(dx * dx + dz * dz))
    }

    func airportWeight(_ x: Float, _ z: Float) -> Float {
        airports.reduce(0) { max($0, flattenWeight(x, z, $1)) }
    }

    func rawHeight(_ x: Float, _ z: Float) -> Float {
        var h = baseHeight(x, z)
        for ap in airports {
            let w = flattenWeight(x, z, ap)
            if w > 0 { h = mixf(h, ap.elevation, w) }
        }
        return h
    }

    @inline(__always) func grid(_ i: Int, _ j: Int) -> Float {
        heights[min(max(j, 0), n - 1) * n + min(max(i, 0), n - 1)]
    }

    /// Height of the rendered triangle mesh at (x, z).
    func height(_ x: Float, _ z: Float) -> Float {
        let gx = (x + half) / cell, gz = (z + half) / cell
        if gx < 0 || gz < 0 || gx >= Float(Terrain.res) || gz >= Float(Terrain.res) { return -75 }
        let i = Int(gx), j = Int(gz)
        let fx = gx - Float(i), fz = gz - Float(j)
        let h00 = heights[j * n + i], h10 = heights[j * n + i + 1]
        let h01 = heights[(j + 1) * n + i], h11 = heights[(j + 1) * n + i + 1]
        if fx + fz <= 1 {
            return h00 + (h10 - h00) * fx + (h01 - h00) * fz
        }
        return h11 + (h01 - h11) * (1 - fx) + (h10 - h11) * (1 - fz)
    }

    func gridNormal(_ i: Int, _ j: Int) -> SIMD3<Float> {
        let hl = grid(i - 1, j), hr = grid(i + 1, j), hd = grid(i, j - 1), hu = grid(i, j + 1)
        return simd_normalize(SIMD3(hl - hr, 2 * cell, hd - hu))
    }

    func normal(_ x: Float, _ z: Float) -> SIMD3<Float> {
        let e: Float = 6
        return simd_normalize(SIMD3(height(x - e, z) - height(x + e, z), 2 * e, height(x, z - e) - height(x, z + e)))
    }

    func surface(_ x: Float, _ z: Float) -> Surface {
        for ap in airports {
            let (al, ac) = ap.local(x, z)
            if abs(al) <= ap.length / 2 + 5 && abs(ac) <= ap.width / 2 + 4 { return .paved }
            // taxiway + apron strip
            if abs(al) <= ap.length / 2 - 40 && ac > ap.width / 2 && ac < ap.apronAcross + 45 { return .paved }
        }
        return height(x, z) < 0 ? .water : .grass
    }

    /// Ground height used by the flight model: water surface counts as 0.
    func ground(_ x: Double, _ z: Double) -> (Double, Surface) {
        let fx = Float(x), fz = Float(z)
        let s = surface(fx, fz)
        if s == .water { return (0, .water) }
        return (Double(max(height(fx, fz), 0)), s)
    }

    func forest(_ x: Float, _ z: Float) -> Float {
        Noise.fbm(x * 0.0011 + 40, z * 0.0011 - 12, octaves: 3, seed: 300) + 0.12
    }

    // MARK: Colouring

    func color(_ x: Float, _ z: Float, _ h: Float, _ ny: Float) -> SIMD3<Float> {
        let slope = 1 - ny
        let n1 = Noise.fbm(x * 0.0025, z * 0.0025, octaves: 3, seed: 201)
        let n2 = Noise.perlin(x * 0.021, z * 0.021, seed: 202)
        var c: SIMD3<Float>
        if h < 0 {
            let shallow = SIMD3<Float>(0.72, 0.78, 0.62), deep = SIMD3<Float>(0.06, 0.18, 0.26)
            c = mix3(shallow, deep, smoothstep(0, 38, -h))
        } else {
            let sand = SIMD3<Float>(0.86, 0.78, 0.58)
            let grassA = SIMD3<Float>(0.23, 0.40, 0.12), grassB = SIMD3<Float>(0.38, 0.50, 0.18)
            let dry = SIMD3<Float>(0.56, 0.52, 0.30)
            var g = mix3(grassA, grassB, clampf(n1 * 0.9 + 0.5, 0, 1))
            g = mix3(g, dry, smoothstep(220, 520, h + n2 * 40) * 0.55)
            g = mix3(g, SIMD3(0.13, 0.26, 0.08), smoothstep(0.0, 0.35, forest(x, z)) * 0.6 * (1 - smoothstep(500, 700, h)))
            // mowed grass around airports
            g = mix3(g, SIMD3(0.36, 0.52, 0.2), smoothstep(0.6, 1.0, airportWeight(x, z)) * 0.7)
            c = mix3(sand, g, smoothstep(2.0, 6.5, h + n2 * 2.5))
            let rock = mix3(SIMD3(0.42, 0.39, 0.35), SIMD3(0.58, 0.55, 0.50), n2 * 0.5 + 0.5)
            c = mix3(c, rock, smoothstep(0.2, 0.34, slope + n2 * 0.06))
            c = mix3(c, rock, smoothstep(640, 860, h + n1 * 60))
            let snow = SIMD3<Float>(0.95, 0.96, 0.99)
            c = mix3(c, snow, smoothstep(900, 1010, h + n1 * 90) * (1 - smoothstep(0.42, 0.62, slope)))
        }
        return c * (0.93 + 0.14 * n2)
    }

    // MARK: Mesh

    func buildNodes(material: SCNMaterial, chunks: Int = 8) -> [SCNNode] {
        let per = Terrain.res / chunks
        var nodes: [SCNNode] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: chunks * chunks) { idx in
            let ci = idx % chunks, cj = idx / chunks
            let mb = MeshBuilder()
            let vn = per + 1
            mb.positions.reserveCapacity(vn * vn)
            for j in 0...per {
                for i in 0...per {
                    let gi = ci * per + i, gj = cj * per + j
                    let x = -half + Float(gi) * cell, z = -half + Float(gj) * cell
                    let h = grid(gi, gj)
                    let nrm = gridNormal(gi, gj)
                    let col = self.color(x, z, h, nrm.y)
                    mb.vertex(SIMD3(x, h, z), nrm, SIMD4(col, 1))
                }
            }
            for j in 0..<per {
                for i in 0..<per {
                    let v00 = UInt32(j * vn + i), v10 = v00 + 1
                    let v01 = UInt32((j + 1) * vn + i), v11 = v01 + 1
                    mb.indices += [v00, v01, v10, v10, v01, v11]
                }
            }
            let node = mb.node([material])
            node.name = "terrain"
            lock.lock(); nodes.append(node); lock.unlock()
        }
        return nodes
    }

    /// Top-down colour map for the HUD minimap (north up).
    func mapImage(size: Int) -> CGImage {
        makePixelImage(size, size) { px, py in
            let x = -self.half + (Float(px) + 0.5) / Float(size) * Terrain.size
            let z = -self.half + (Float(py) + 0.5) / Float(size) * Terrain.size
            let h = self.height(x, z)
            if h < 0 {
                let t = smoothstep(0, 40, -h)
                return SIMD4(mix3(SIMD3(0.35, 0.65, 0.75), SIMD3(0.06, 0.2, 0.35), t), 0.85)
            }
            let nrm = self.normal(x, z)
            var c = self.color(x, z, h, nrm.y)
            let light = clampf(simd_dot(nrm, simd_normalize(SIMD3(-0.6, 0.7, -0.4))) * 1.2, 0.35, 1.25)
            c *= light
            if self.surface(x, z) == .paved { c = SIMD3(0.15, 0.15, 0.17) }
            return SIMD4(c, 0.92)
        }
    }
}
