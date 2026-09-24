import simd

enum Surface: Int {
    case tile, wood, stone, metal, fabric, plastic, cardboard
}

/// Axis-aligned solid. The kitchen's physical world is a list of these.
struct Solid {
    var lo: SIMD3<Float>
    var hi: SIMD3<Float>
    var climbable = false
    var surface: Surface = .wood
    /// Cats and people can't stand here (thin legs, towel).
    var perch = true
    var name = ""

    init(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, climb: Bool = false, surface: Surface = .wood, perch: Bool = true, name: String = "") {
        self.lo = lo; self.hi = hi; climbable = climb; self.surface = surface; self.perch = perch; self.name = name
    }
    /// Centre/size convenience: x, z centre, footprint, y range.
    init(x: Float, z: Float, w: Float, d: Float, y0: Float, y1: Float, climb: Bool = false, surface: Surface = .wood, perch: Bool = true, name: String = "") {
        self.init(SIMD3(x - w / 2, y0, z - d / 2), SIMD3(x + w / 2, y1, z + d / 2), climb: climb, surface: surface, perch: perch, name: name)
    }
}

struct Contact {
    var index: Int
    var normal: SIMD3<Float>      // horizontal push-out direction
}

final class CollisionWorld {
    var solids: [Solid] = []
    let floorSurface: (Float, Float) -> Surface
    /// Room interior bounds (walls are also solids; this is a last-resort clamp).
    var bounds = (lo: SIMD2<Float>(-2.98, -2.48), hi: SIMD2<Float>(2.98, 2.48))

    init(floor: @escaping (Float, Float) -> Surface) { floorSurface = floor }

    @discardableResult func add(_ s: Solid) -> Int { solids.append(s); return solids.count - 1 }

    /// Highest walkable top under a disc of `r` at (x, z) that is at or below `y + step`.
    func ground(_ x: Float, _ z: Float, y: Float, r: Float, step: Float) -> (Float, Surface, Int?) {
        var best: Float = 0, surf = floorSurface(x, z), idx: Int? = nil
        for (i, s) in solids.enumerated() {
            if s.hi.y > y + step || s.hi.y <= best { continue }
            if x + r < s.lo.x || x - r > s.hi.x || z + r < s.lo.z || z - r > s.hi.z { continue }
            best = s.hi.y; surf = s.surface; idx = i
        }
        return (best, surf, idx)
    }

    /// Lowest solid bottom above `y` covering (x, z): the ceiling over a crawling body.
    func ceiling(_ x: Float, _ z: Float, y: Float, r: Float) -> Float {
        var c: Float = 10
        for s in solids where s.lo.y > y + 0.001 && s.lo.y < c {
            if x + r < s.lo.x || x - r > s.hi.x || z + r < s.lo.z || z - r > s.hi.z { continue }
            c = s.lo.y
        }
        return c
    }

    /// Would a body (feet at p) overlap any solid it can't stand on?
    func blocked(_ p: SIMD3<Float>, r: Float, h: Float) -> Bool {
        for s in solids where s.hi.y > p.y + 0.02 && s.lo.y < p.y + h {
            if p.x + r < s.lo.x || p.x - r > s.hi.x || p.z + r < s.lo.z || p.z - r > s.hi.z { continue }
            return true
        }
        return false
    }

    /// Index of the lowest solid overhead (see `ceiling`).
    func ceilingSolid(_ x: Float, _ z: Float, y: Float, r: Float) -> Int? {
        var c: Float = 10, idx: Int? = nil
        for (i, s) in solids.enumerated() where s.lo.y > y + 0.001 && s.lo.y < c {
            if x + r < s.lo.x || x - r > s.hi.x || z + r < s.lo.z || z - r > s.hi.z { continue }
            c = s.lo.y; idx = i
        }
        return idx
    }

    /// Push a vertical cylinder (feet at p.y, height h, radius r) out of every solid it overlaps
    /// that it can't step onto. Returns contacts.
    func resolve(_ p: inout SIMD3<Float>, r: Float, h: Float, step: Float) -> [Contact] {
        var contacts: [Contact] = []
        for _ in 0..<2 {
            for (i, s) in solids.enumerated() {
                if s.hi.y <= p.y + step || s.lo.y >= p.y + h { continue }
                let cx = clampf(p.x, s.lo.x, s.hi.x), cz = clampf(p.z, s.lo.z, s.hi.z)
                let dx = p.x - cx, dz = p.z - cz
                let d2 = dx * dx + dz * dz
                if d2 >= r * r { continue }
                var n: SIMD3<Float>
                if d2 > 1e-10 {
                    let d = sqrtf(d2)
                    n = SIMD3(dx / d, 0, dz / d)
                    p.x = cx + n.x * r; p.z = cz + n.z * r
                } else {
                    // centre inside: leave by the nearest face
                    let pens = [p.x - s.lo.x, s.hi.x - p.x, p.z - s.lo.z, s.hi.z - p.z]
                    let k = pens.firstIndex(of: pens.min()!)!
                    switch k {
                    case 0: n = SIMD3(-1, 0, 0); p.x = s.lo.x - r
                    case 1: n = SIMD3(1, 0, 0); p.x = s.hi.x + r
                    case 2: n = SIMD3(0, 0, -1); p.z = s.lo.z - r
                    default: n = SIMD3(0, 0, 1); p.z = s.hi.z + r
                    }
                }
                if !contacts.contains(where: { $0.index == i }) { contacts.append(Contact(index: i, normal: n)) }
            }
        }
        p.x = clampf(p.x, bounds.lo.x, bounds.hi.x)
        p.z = clampf(p.z, bounds.lo.y, bounds.hi.y)
        return contacts
    }

    /// Segment test; returns the hit fraction 0...1 or nil.
    func raycast(_ a: SIMD3<Float>, _ b: SIMD3<Float>, skip: (Int) -> Bool = { _ in false }) -> Float? {
        let d = b - a
        var best: Float? = nil
        for (i, s) in solids.enumerated() {
            if skip(i) { continue }
            var t0: Float = 0, t1: Float = best ?? 1
            var hit = true
            for k in 0..<3 {
                if abs(d[k]) < 1e-8 {
                    if a[k] < s.lo[k] || a[k] > s.hi[k] { hit = false; break }
                } else {
                    var ta = (s.lo[k] - a[k]) / d[k], tb = (s.hi[k] - a[k]) / d[k]
                    if ta > tb { swap(&ta, &tb) }
                    t0 = max(t0, ta); t1 = min(t1, tb)
                    if t0 > t1 { hit = false; break }
                }
            }
            if hit { best = t0 }
        }
        // floor
        if d.y < 0 && a.y > 0 {
            let t = a.y / -d.y
            if t < (best ?? 1) { best = t }
        }
        return best
    }

    func visible(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        guard let t = raycast(a, b) else { return true }
        return t > 0.97
    }
}
