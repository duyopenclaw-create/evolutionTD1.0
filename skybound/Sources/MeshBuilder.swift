import SceneKit
import simd

/// Accumulates vertex-coloured triangles and turns them into one SCNGeometry,
/// so thousands of trees/houses cost a single draw call per chunk.
final class MeshBuilder {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var colors: [SIMD4<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    @discardableResult
    func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ c: SIMD4<Float>) -> UInt32 {
        positions.append(p)
        normals.append(n)
        colors.append(c)
        return UInt32(positions.count - 1)
    }

    @inline(__always) static func xf(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = m * SIMD4(p, 1)
        return SIMD3(r.x, r.y, r.z)
    }

    /// Flat-shaded triangle. If `center` is given the winding is fixed so the face points away from it.
    func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ col: SIMD4<Float>, out center: SIMD3<Float>? = nil) {
        var b = b, c = c
        var n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        if len < 1e-9 { return }
        n /= len
        if let center = center, simd_dot(n, (a + b + c) / 3 - center) < 0 {
            swap(&b, &c)
            n = -n
        }
        let i = vertex(a, n, col)
        vertex(b, n, col)
        vertex(c, n, col)
        indices += [i, i + 1, i + 2]
    }

    func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ col: SIMD4<Float>, out center: SIMD3<Float>? = nil) {
        tri(a, b, c, col, out: center)
        tri(a, c, d, col, out: center)
    }

    /// Cone standing on the XZ plane of `m`, apex at +Y.
    func cone(_ m: simd_float4x4, radius: Float, height: Float, segments: Int, color: SIMD4<Float>, base: Bool = true, rng: inout RNG, jitter: Float = 0) {
        let apex = Self.xf(m, SIMD3(rng.range(-jitter, jitter) * radius, height, rng.range(-jitter, jitter) * radius))
        let center = Self.xf(m, SIMD3(0, height * 0.3, 0))
        let bc = Self.xf(m, .zero)
        var ring: [SIMD3<Float>] = []
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let r = radius * (1 + rng.range(-jitter, jitter))
            ring.append(Self.xf(m, SIMD3(cosf(a) * r, rng.range(-jitter, jitter) * height * 0.2, sinf(a) * r)))
        }
        let dark = SIMD4(color.x * 0.6, color.y * 0.6, color.z * 0.6, 1)
        for i in 0..<segments {
            let p0 = ring[i], p1 = ring[(i + 1) % segments]
            tri(p0, p1, apex, color, out: center)
            if base { tri(p0, p1, bc, dark, out: center) }
        }
    }

    func cylinder(_ m: simd_float4x4, radius: Float, height: Float, segments: Int, color: SIMD4<Float>, topRadius: Float? = nil, cap: Bool = true) {
        let tr = topRadius ?? radius
        let center = Self.xf(m, SIMD3(0, height * 0.5, 0))
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let b0 = Self.xf(m, SIMD3(cosf(a0) * radius, 0, sinf(a0) * radius))
            let b1 = Self.xf(m, SIMD3(cosf(a1) * radius, 0, sinf(a1) * radius))
            let t0 = Self.xf(m, SIMD3(cosf(a0) * tr, height, sinf(a0) * tr))
            let t1 = Self.xf(m, SIMD3(cosf(a1) * tr, height, sinf(a1) * tr))
            quad(b0, b1, t1, t0, color, out: center)
            if cap {
                tri(t0, t1, Self.xf(m, SIMD3(0, height, 0)), color, out: center)
            }
        }
    }

    /// Axis-aligned (in `m`) box centred on the origin.
    func box(_ m: simd_float4x4, size s: SIMD3<Float>, color: SIMD4<Float>, top: SIMD4<Float>? = nil, bottom: Bool = false) {
        let h = s / 2
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { Self.xf(m, SIMD3(x * h.x, y * h.y, z * h.z)) }
        let c = Self.xf(m, .zero)
        let side = color
        quad(p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), side, out: c)
        quad(p(-1, -1, -1), p(1, -1, -1), p(1, 1, -1), p(-1, 1, -1), side * SIMD4(0.85, 0.85, 0.85, 1), out: c)
        quad(p(1, -1, -1), p(1, -1, 1), p(1, 1, 1), p(1, 1, -1), side * SIMD4(0.92, 0.92, 0.92, 1), out: c)
        quad(p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), side * SIMD4(0.8, 0.8, 0.8, 1), out: c)
        quad(p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1), top ?? side, out: c)
        if bottom { quad(p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1), side, out: c) }
    }

    /// Gabled roof sitting on a box footprint (ridge along local X).
    func roof(_ m: simd_float4x4, size s: SIMD3<Float>, color: SIMD4<Float>) {
        let h = s / 2
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { Self.xf(m, SIMD3(x, y, z)) }
        let c = Self.xf(m, SIMD3(0, s.y * 0.3, 0))
        let e: Float = 0.6 // eave overhang
        let a = p(-h.x - e, 0, -h.z - e), b = p(h.x + e, 0, -h.z - e)
        let cc = p(h.x + e, 0, h.z + e), d = p(-h.x - e, 0, h.z + e)
        let r0 = p(-h.x - e, s.y, 0), r1 = p(h.x + e, s.y, 0)
        quad(a, b, r1, r0, color, out: c)
        quad(d, cc, r1, r0, color * SIMD4(0.8, 0.8, 0.8, 1), out: c)
        let wall = SIMD4<Float>(0.85, 0.82, 0.75, 1)
        tri(p(-h.x, 0, -h.z), p(-h.x, 0, h.z), p(-h.x, s.y * 0.92, 0), wall, out: c)
        tri(p(h.x, 0, -h.z), p(h.x, 0, h.z), p(h.x, s.y * 0.92, 0), wall, out: c)
    }

    private static let ico: [SIMD3<Float>] = {
        let t: Float = (1 + sqrtf(5)) / 2
        return [SIMD3(-1, t, 0), SIMD3(1, t, 0), SIMD3(-1, -t, 0), SIMD3(1, -t, 0),
                SIMD3(0, -1, t), SIMD3(0, 1, t), SIMD3(0, -1, -t), SIMD3(0, 1, -t),
                SIMD3(t, 0, -1), SIMD3(t, 0, 1), SIMD3(-t, 0, -1), SIMD3(-t, 0, 1)].map { simd_normalize($0) }
    }()
    private static let icoFaces: [(Int, Int, Int)] = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]

    /// Lumpy low-poly sphere (tree crowns, rocks, bushes).
    func blob(_ m: simd_float4x4, radius: SIMD3<Float>, color: SIMD4<Float>, rng: inout RNG, jitter: Float = 0.18, shadeVar: Float = 0.12) {
        let pts = Self.ico.map { v -> SIMD3<Float> in
            Self.xf(m, v * radius * (1 + rng.range(-jitter, jitter)))
        }
        let c = Self.xf(m, .zero)
        for f in Self.icoFaces {
            let s = 1 + rng.range(-shadeVar, shadeVar)
            tri(pts[f.0], pts[f.1], pts[f.2], SIMD4(color.x * s, color.y * s, color.z * s, 1), out: c)
        }
    }

    /// Smooth surface from a list of rings (each ring a closed loop of points).
    func tube(_ rings: [[SIMD3<Float>]], colors: [[SIMD4<Float>]], capStart: Bool = true, capEnd: Bool = true) {
        let nr = rings.count, np = rings[0].count
        let base = UInt32(positions.count)
        let centroids = rings.map { r in r.reduce(SIMD3<Float>.zero, +) / Float(r.count) }
        for r in 0..<nr {
            for p in 0..<np {
                let prevR = rings[max(r - 1, 0)][p], nextR = rings[min(r + 1, nr - 1)][p]
                let prevP = rings[r][(p - 1 + np) % np], nextP = rings[r][(p + 1) % np]
                var n = simd_cross(nextR - prevR, nextP - prevP)
                let out = rings[r][p] - centroids[r]
                if simd_length(n) < 1e-7 { n = out }
                n = simd_normalize(n)
                if simd_dot(n, out) < 0 { n = -n }
                vertex(rings[r][p], n, colors[r][p])
            }
        }
        for r in 0..<(nr - 1) {
            for p in 0..<np {
                let a = base + UInt32(r * np + p), b = base + UInt32(r * np + (p + 1) % np)
                let c = base + UInt32((r + 1) * np + p), d = base + UInt32((r + 1) * np + (p + 1) % np)
                let fn = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
                if simd_dot(fn, normals[Int(a)] + normals[Int(d)]) >= 0 {
                    indices += [a, b, c, b, d, c]
                } else {
                    indices += [a, c, b, b, c, d]
                }
            }
        }
        func cap(_ r: Int, _ other: Int) {
            let ctr = centroids[r]
            var n = ctr - centroids[other]
            if simd_length(n) < 1e-7 { return }
            n = simd_normalize(n)
            let col = colors[r][0]
            for p in 0..<np {
                let a = rings[r][p], b = rings[r][(p + 1) % np]
                var fn = simd_cross(b - a, ctr - a)
                if simd_length(fn) < 1e-9 { continue }
                fn = simd_normalize(fn)
                let i = vertex(a, n, col)
                if simd_dot(fn, n) >= 0 {
                    vertex(b, n, col); vertex(ctr, n, col)
                } else {
                    vertex(ctr, n, col); vertex(b, n, col)
                }
                indices += [i, i + 1, i + 2]
            }
        }
        if capStart { cap(0, 1) }
        if capEnd { cap(nr - 1, nr - 2) }
    }

    func geometry(_ materials: [SCNMaterial]) -> SCNGeometry {
        let pData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let nData = normals.withUnsafeBufferPointer { Data(buffer: $0) }
        let cData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let stride3 = MemoryLayout<SIMD3<Float>>.stride
        let stride4 = MemoryLayout<SIMD4<Float>>.stride
        let ps = SCNGeometrySource(data: pData, semantic: .vertex, vectorCount: positions.count, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        let ns = SCNGeometrySource(data: nData, semantic: .normal, vectorCount: normals.count, usesFloatComponents: true,
                                   componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride3)
        let cs = SCNGeometrySource(data: cData, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                   componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: stride4)
        let el = SCNGeometryElement(data: iData, primitiveType: .triangles, primitiveCount: indices.count / 3, bytesPerIndex: 4)
        let g = SCNGeometry(sources: [ps, ns, cs], elements: [el])
        g.materials = materials
        return g
    }

    func node(_ materials: [SCNMaterial]) -> SCNNode { SCNNode(geometry: geometry(materials)) }
}

/// Translation + yaw + uniform/non-uniform scale.
func xform(_ p: SIMD3<Float>, yaw: Float = 0, pitch: Float = 0, roll: Float = 0, scale: SIMD3<Float> = SIMD3(1, 1, 1)) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(p, 1)
    let q = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: roll, axis: SIMD3(0, 0, 1))
    let r = simd_float4x4(q)
    let s = simd_float4x4(diagonal: SIMD4(scale, 1))
    return m * r * s
}
