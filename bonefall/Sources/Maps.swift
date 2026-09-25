import simd

enum Extra { case none, sea, lava, snow, dust }

struct MapDef {
    let name: String
    let blurb: String
    let cost: Int
    let mult: Float
    let seed: UInt64
    let rock: V3, rock2: V3, top: V3, ground: V3
    let skyTop: V3, skyHorizon: V3, fog: V3, sun: V3
    let sunElev: Float
    let wallW: Float, slopeW: Float, ledgeW: Float
    let wallAngle: ClosedRange<Float>, slopeAngle: ClosedRange<Float>
    let segH: ClosedRange<Float>
    let ledgeLen: ClosedRange<Float>
    let rockDensity: Float
    let rockSize: ClosedRange<Float>
    let sharp: Float
    let friction: Float
    let bounce: Float
    let hardness: Float
    let style: Int          // rock texture: 0 granite, 1 strata, 2 chalk, 3 ice, 4 basalt, 5 jagged
    let groundStyle: Int    // 0 grass, 1 sand, 2 pebbles, 3 snow, 4 ash, 5 dirt
    let extra: Extra
    let jagged: Float       // rock mesh spikiness
    var obstacles: [(ObKind, Float)] = []   // per m² near the fall line
}

enum ObKind { case pine, deadTree, stake, cactus, icicle, crystal, rockSpike }

let heights: [Float] = [1500, 2200, 3200, 4500, 6500, 9000, 12000, 16000, 22000, 30000]
let heightCosts: [Int] = [0, 15000, 45000, 120000, 300000, 700000, 1_500_000, 3_500_000, 7_000_000, 15_000_000]
func heightMult(_ h: Float) -> Float { 1 + sqrtf(h) / 10 }

func c3(_ r: Float, _ g: Float, _ b: Float) -> V3 { V3(r, g, b) }

/// The 10 maps before the forest update, for migrating old saves.
let oldMapOrder = ["Pebble Hill", "Old Quarry", "Red Canyon", "Sea Cliffs", "Boulder Run", "Frozen Crag", "Volcano Rim", "Stairway to Pain", "Spike Gorge", "Mount Agony"]

let maps: [MapDef] = [
    MapDef(name: "Pebble Hill", blurb: "Grassy slopes and friendly rocks. A gentle start.", cost: 0, mult: 1, seed: 11,
           rock: c3(0.52, 0.5, 0.47), rock2: c3(0.38, 0.37, 0.35), top: c3(0.33, 0.5, 0.2), ground: c3(0.36, 0.52, 0.22),
           skyTop: c3(0.28, 0.5, 0.86), skyHorizon: c3(0.75, 0.86, 0.95), fog: c3(0.72, 0.82, 0.92), sun: c3(1, 0.96, 0.88), sunElev: 0.9,
           wallW: 0.8, slopeW: 1.6, ledgeW: 0.7, wallAngle: 62...78, slopeAngle: 36...52, segH: 2.5...6, ledgeLen: 1.5...3,
           rockDensity: 0.05, rockSize: 0.35...0.9, sharp: 0, friction: 0.62, bounce: 0.18, hardness: 1, style: 0, groundStyle: 0, extra: .none, jagged: 0.1, obstacles: [(.pine, 0.004)]),
    MapDef(name: "Old Quarry", blurb: "Cut stone steps, straight drops, hard landings.", cost: 20000, mult: 1.5, seed: 22,
           rock: c3(0.72, 0.66, 0.56), rock2: c3(0.58, 0.52, 0.43), top: c3(0.66, 0.6, 0.5), ground: c3(0.6, 0.55, 0.46),
           skyTop: c3(0.35, 0.55, 0.85), skyHorizon: c3(0.85, 0.87, 0.88), fog: c3(0.8, 0.8, 0.8), sun: c3(1, 0.95, 0.85), sunElev: 0.8,
           wallW: 1.8, slopeW: 0.3, ledgeW: 1.5, wallAngle: 82...88, slopeAngle: 45...55, segH: 2.5...5, ledgeLen: 1.2...2.6,
           rockDensity: 0.04, rockSize: 0.3...0.8, sharp: 0.1, friction: 0.6, bounce: 0.15, hardness: 1.1, style: 1, groundStyle: 5, extra: .dust, jagged: 0.05, obstacles: [(.stake, 0.004)]),
    MapDef(name: "Red Canyon", blurb: "Tall sandstone walls. Long drops, then bang.", cost: 50000, mult: 2, seed: 33,
           rock: c3(0.72, 0.36, 0.2), rock2: c3(0.55, 0.24, 0.14), top: c3(0.78, 0.5, 0.3), ground: c3(0.74, 0.46, 0.28),
           skyTop: c3(0.3, 0.48, 0.8), skyHorizon: c3(0.98, 0.78, 0.55), fog: c3(0.93, 0.72, 0.52), sun: c3(1, 0.85, 0.65), sunElev: 0.45,
           wallW: 2, slopeW: 0.8, ledgeW: 0.6, wallAngle: 78...88, slopeAngle: 42...58, segH: 5...12, ledgeLen: 1.2...2.5,
           rockDensity: 0.05, rockSize: 0.4...1.2, sharp: 0.15, friction: 0.66, bounce: 0.16, hardness: 1.05, style: 1, groundStyle: 1, extra: .dust, jagged: 0.15, obstacles: [(.rockSpike, 0.006)]),
    MapDef(name: "Spiky Forest", blurb: "A pine forest on a cliff. Branches, trunks and sharpened stakes.", cost: 90000, mult: 2.5, seed: 1111,
           rock: c3(0.42, 0.38, 0.33), rock2: c3(0.3, 0.27, 0.23), top: c3(0.24, 0.4, 0.16), ground: c3(0.26, 0.4, 0.17),
           skyTop: c3(0.3, 0.5, 0.78), skyHorizon: c3(0.78, 0.84, 0.86), fog: c3(0.66, 0.74, 0.74), sun: c3(1, 0.93, 0.8), sunElev: 0.6,
           wallW: 1.0, slopeW: 1.8, ledgeW: 0.8, wallAngle: 65...82, slopeAngle: 36...50, segH: 4...10, ledgeLen: 1.5...3,
           rockDensity: 0.08, rockSize: 0.4...1.1, sharp: 0.3, friction: 0.6, bounce: 0.2, hardness: 1.1, style: 0, groundStyle: 0, extra: .none, jagged: 0.2,
           obstacles: [(.pine, 0.05), (.stake, 0.03)]),
    MapDef(name: "Sea Cliffs", blurb: "White chalk down to a beach of black boulders.", cost: 150000, mult: 3, seed: 44,
           rock: c3(0.86, 0.85, 0.8), rock2: c3(0.7, 0.7, 0.66), top: c3(0.38, 0.55, 0.26), ground: c3(0.3, 0.3, 0.32),
           skyTop: c3(0.35, 0.6, 0.9), skyHorizon: c3(0.8, 0.9, 0.96), fog: c3(0.78, 0.86, 0.92), sun: c3(1, 0.97, 0.9), sunElev: 0.75,
           wallW: 1.6, slopeW: 1.1, ledgeW: 0.5, wallAngle: 70...86, slopeAngle: 40...55, segH: 4...10, ledgeLen: 1...2.2,
           rockDensity: 0.08, rockSize: 0.5...1.4, sharp: 0.2, friction: 0.58, bounce: 0.2, hardness: 1.1, style: 2, groundStyle: 2, extra: .sea, jagged: 0.12, obstacles: [(.rockSpike, 0.005)]),
    MapDef(name: "Cactus Canyon", blurb: "Desert drops studded with giant cacti. Prickly.", cost: 250000, mult: 3.5, seed: 1212,
           rock: c3(0.8, 0.55, 0.35), rock2: c3(0.62, 0.38, 0.22), top: c3(0.85, 0.68, 0.45), ground: c3(0.86, 0.7, 0.48),
           skyTop: c3(0.25, 0.48, 0.85), skyHorizon: c3(0.98, 0.85, 0.65), fog: c3(0.95, 0.82, 0.62), sun: c3(1, 0.9, 0.7), sunElev: 0.8,
           wallW: 1.5, slopeW: 1.2, ledgeW: 0.8, wallAngle: 75...88, slopeAngle: 38...55, segH: 4...11, ledgeLen: 1.5...3,
           rockDensity: 0.08, rockSize: 0.4...1.2, sharp: 0.3, friction: 0.62, bounce: 0.18, hardness: 1.1, style: 1, groundStyle: 1, extra: .dust, jagged: 0.2,
           obstacles: [(.cactus, 0.04), (.rockSpike, 0.01)]),
    MapDef(name: "Boulder Run", blurb: "A long steep slope covered in boulders. Pinball.", cost: 400000, mult: 4, seed: 55,
           rock: c3(0.5, 0.48, 0.44), rock2: c3(0.4, 0.37, 0.33), top: c3(0.42, 0.45, 0.28), ground: c3(0.45, 0.43, 0.36),
           skyTop: c3(0.32, 0.52, 0.82), skyHorizon: c3(0.8, 0.84, 0.88), fog: c3(0.76, 0.8, 0.84), sun: c3(1, 0.95, 0.86), sunElev: 0.7,
           wallW: 0.5, slopeW: 2.4, ledgeW: 0.3, wallAngle: 65...75, slopeAngle: 40...52, segH: 5...12, ledgeLen: 1...2,
           rockDensity: 0.22, rockSize: 0.5...1.6, sharp: 0.1, friction: 0.55, bounce: 0.25, hardness: 1.15, style: 0, groundStyle: 5, extra: .none, jagged: 0.2, obstacles: [(.pine, 0.006)]),
    MapDef(name: "Frozen Crag", blurb: "Ice is slippery. You'll slide into everything.", cost: 650000, mult: 5.5, seed: 66,
           rock: c3(0.72, 0.8, 0.88), rock2: c3(0.5, 0.58, 0.68), top: c3(0.94, 0.96, 1), ground: c3(0.9, 0.93, 0.97),
           skyTop: c3(0.42, 0.55, 0.72), skyHorizon: c3(0.85, 0.88, 0.92), fog: c3(0.84, 0.87, 0.91), sun: c3(0.95, 0.97, 1), sunElev: 0.5,
           wallW: 1.2, slopeW: 1.6, ledgeW: 0.6, wallAngle: 70...85, slopeAngle: 30...48, segH: 4...10, ledgeLen: 1.5...3,
           rockDensity: 0.1, rockSize: 0.4...1.3, sharp: 0.3, friction: 0.14, bounce: 0.22, hardness: 1.25, style: 3, groundStyle: 3, extra: .snow, jagged: 0.3, obstacles: [(.icicle, 0.012), (.pine, 0.004)]),
    MapDef(name: "Dead Forest", blurb: "Bare dead trees with snapped, pointed branches. Grim.", cost: 1000000, mult: 5, seed: 1313,
           rock: c3(0.36, 0.34, 0.33), rock2: c3(0.24, 0.23, 0.22), top: c3(0.34, 0.32, 0.26), ground: c3(0.3, 0.28, 0.24),
           skyTop: c3(0.3, 0.32, 0.38), skyHorizon: c3(0.62, 0.6, 0.58), fog: c3(0.5, 0.5, 0.5), sun: c3(0.9, 0.85, 0.8), sunElev: 0.4,
           wallW: 1.2, slopeW: 1.6, ledgeW: 0.7, wallAngle: 68...86, slopeAngle: 36...52, segH: 4...10, ledgeLen: 1.2...2.6,
           rockDensity: 0.1, rockSize: 0.4...1.2, sharp: 0.5, friction: 0.6, bounce: 0.18, hardness: 1.2, style: 0, groundStyle: 5, extra: .dust, jagged: 0.3,
           obstacles: [(.deadTree, 0.05), (.stake, 0.03)]),
    MapDef(name: "Volcano Rim", blurb: "Black glassy basalt. Every edge is sharp.", cost: 1600000, mult: 7, seed: 77,
           rock: c3(0.2, 0.19, 0.19), rock2: c3(0.12, 0.11, 0.11), top: c3(0.25, 0.22, 0.2), ground: c3(0.16, 0.14, 0.13),
           skyTop: c3(0.18, 0.1, 0.12), skyHorizon: c3(0.75, 0.32, 0.15), fog: c3(0.42, 0.22, 0.16), sun: c3(1, 0.6, 0.4), sunElev: 0.35,
           wallW: 1.4, slopeW: 1.4, ledgeW: 0.5, wallAngle: 70...86, slopeAngle: 38...55, segH: 4...11, ledgeLen: 1...2.2,
           rockDensity: 0.12, rockSize: 0.4...1.3, sharp: 0.55, friction: 0.7, bounce: 0.14, hardness: 1.3, style: 4, groundStyle: 4, extra: .lava, jagged: 0.35, obstacles: [(.deadTree, 0.008), (.rockSpike, 0.012)]),
    MapDef(name: "Icicle Abyss", blurb: "Blue ice walls bristling with spears of ice.", cost: 2500000, mult: 8, seed: 1414,
           rock: c3(0.6, 0.75, 0.9), rock2: c3(0.4, 0.55, 0.72), top: c3(0.9, 0.95, 1), ground: c3(0.86, 0.92, 0.98),
           skyTop: c3(0.2, 0.3, 0.55), skyHorizon: c3(0.7, 0.8, 0.9), fog: c3(0.7, 0.8, 0.9), sun: c3(0.9, 0.95, 1), sunElev: 0.45,
           wallW: 1.6, slopeW: 1.2, ledgeW: 0.8, wallAngle: 72...88, slopeAngle: 32...50, segH: 4...11, ledgeLen: 1.5...3,
           rockDensity: 0.08, rockSize: 0.4...1.2, sharp: 0.5, friction: 0.15, bounce: 0.22, hardness: 1.3, style: 3, groundStyle: 3, extra: .snow, jagged: 0.4,
           obstacles: [(.icicle, 0.05)]),
    MapDef(name: "Stairway to Pain", blurb: "Hundreds of stone steps. Bounce on every one.", cost: 3800000, mult: 9, seed: 88,
           rock: c3(0.6, 0.58, 0.55), rock2: c3(0.45, 0.44, 0.42), top: c3(0.5, 0.56, 0.36), ground: c3(0.4, 0.5, 0.3),
           skyTop: c3(0.3, 0.45, 0.78), skyHorizon: c3(0.9, 0.82, 0.75), fog: c3(0.82, 0.8, 0.8), sun: c3(1, 0.9, 0.78), sunElev: 0.55,
           wallW: 3, slopeW: 0, ledgeW: 3, wallAngle: 80...88, slopeAngle: 45...50, segH: 1.2...2.4, ledgeLen: 0.8...1.4,
           rockDensity: 0.05, rockSize: 0.3...0.8, sharp: 0.2, friction: 0.5, bounce: 0.28, hardness: 1.2, style: 1, groundStyle: 0, extra: .none, jagged: 0.1, obstacles: [(.stake, 0.008)]),
    MapDef(name: "Spike Gorge", blurb: "Jagged rocks like broken teeth. Nasty.", cost: 6000000, mult: 12, seed: 99,
           rock: c3(0.42, 0.4, 0.46), rock2: c3(0.28, 0.26, 0.32), top: c3(0.36, 0.38, 0.3), ground: c3(0.34, 0.32, 0.34),
           skyTop: c3(0.22, 0.26, 0.4), skyHorizon: c3(0.6, 0.6, 0.66), fog: c3(0.5, 0.52, 0.58), sun: c3(0.9, 0.9, 1), sunElev: 0.6,
           wallW: 1.6, slopeW: 1.4, ledgeW: 0.4, wallAngle: 72...88, slopeAngle: 42...58, segH: 4...12, ledgeLen: 1...2,
           rockDensity: 0.16, rockSize: 0.4...1.2, sharp: 1, friction: 0.66, bounce: 0.15, hardness: 1.35, style: 5, groundStyle: 5, extra: .none, jagged: 0.75, obstacles: [(.rockSpike, 0.04)]),
    MapDef(name: "Crystal Chasm", blurb: "A dark gorge full of glowing, razor-edged crystals.", cost: 9000000, mult: 14, seed: 1515,
           rock: c3(0.22, 0.2, 0.28), rock2: c3(0.14, 0.12, 0.2), top: c3(0.26, 0.22, 0.32), ground: c3(0.2, 0.18, 0.26),
           skyTop: c3(0.08, 0.06, 0.18), skyHorizon: c3(0.42, 0.28, 0.55), fog: c3(0.3, 0.22, 0.42), sun: c3(0.85, 0.75, 1), sunElev: 0.5,
           wallW: 1.6, slopeW: 1.3, ledgeW: 0.6, wallAngle: 72...88, slopeAngle: 38...55, segH: 4...12, ledgeLen: 1...2.2,
           rockDensity: 0.1, rockSize: 0.4...1.2, sharp: 0.8, friction: 0.6, bounce: 0.18, hardness: 1.4, style: 5, groundStyle: 4, extra: .none, jagged: 0.6,
           obstacles: [(.crystal, 0.05)]),
    MapDef(name: "Mount Agony", blurb: "The big one. Ice, spikes, boulders. Everything.", cost: 14000000, mult: 16, seed: 1010,
           rock: c3(0.46, 0.46, 0.5), rock2: c3(0.3, 0.3, 0.34), top: c3(0.95, 0.96, 1), ground: c3(0.9, 0.92, 0.96),
           skyTop: c3(0.14, 0.24, 0.5), skyHorizon: c3(0.78, 0.72, 0.8), fog: c3(0.7, 0.72, 0.8), sun: c3(1, 0.92, 0.85), sunElev: 0.4,
           wallW: 1.5, slopeW: 1.5, ledgeW: 0.6, wallAngle: 72...88, slopeAngle: 38...55, segH: 4...12, ledgeLen: 1...2.4,
           rockDensity: 0.18, rockSize: 0.5...1.6, sharp: 0.7, friction: 0.45, bounce: 0.2, hardness: 1.45, style: 5, groundStyle: 3, extra: .snow, jagged: 0.5, obstacles: [(.pine, 0.01), (.icicle, 0.012), (.rockSpike, 0.015)]),
]

// MARK: - Level generation

struct RockPlacement {
    var c: V3
    var r: Float
    var variant: Int
    var rot: simd_quatf
}

struct Obstacle {
    var kind: ObKind
    var base: V3
    var dir: V3          // growth direction
    var len: Float
    var r: Float
    var yaw: Float
    var seed: UInt64
}

/// What lives on one 40 m piece of one profile segment.
struct Chunk {
    var rocks: [RockPlacement] = []
    var obstacles: [Obstacle] = []
    var capsules: [Capsule] = []
    var grass: [(V3, V3)] = []       // position, tint
}

struct Level {
    var profile: [SIMD2<Float>] = []   // (z, y) polyline, top plateau first, ground last
    var boxes: [BoxCollider] = []
    var edge = SIMD2<Float>(0, 0)
    var baseZ: Float = 0
    var height: Float = 0
    static let piece: Float = 40

    /// Surface height at z (the profile is a function of z).
    func surfaceY(_ z: Float) -> Float {
        if z <= profile[0].x { return profile[0].y }
        var lo = 0, hi = profile.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if profile[m].x <= z { lo = m } else { hi = m } }
        let a = profile[lo], b = profile[hi]
        let t = b.x - a.x < 1e-4 ? 1 : clampf((z - a.x) / (b.x - a.x), 0, 1)
        return a.y + (b.y - a.y) * t
    }

    /// Distance from a point to the cliff surface in the z-y plane.
    func surfaceDistance(_ p: V3) -> Float {
        let q = SIMD2<Float>(p.z, p.y)
        var best: Float = 1e9
        for i in 0..<(profile.count - 1) {
            let a = profile[i], b = profile[i + 1]
            if min(a.y, b.y) > q.y + best || max(a.y, b.y) < q.y - best { continue }
            let ab = b - a
            let t = clampf(simd_dot(q - a, ab) / max(simd_dot(ab, ab), 1e-6), 0, 1)
            best = min(best, simd_length(a + ab * t - q))
        }
        return best
    }

    func pieces(_ i: Int) -> Int { max(1, Int(ceilf(simd_length(profile[i + 1] - profile[i]) / Level.piece))) }
}

func generateLevel(_ m: MapDef, height H: Float) -> Level {
    var L = Level()
    L.height = H
    var rng = RNG(m.seed &* 7919 &+ UInt64(H))
    var pts: [SIMD2<Float>] = [SIMD2(-60, H), SIMD2(0, H)]
    var y = H, z: Float = 0
    var last = 0
    var first = true
    // Straight drops: near-vertical walls broken by short, steeply tilted ledges that stick out into the fall line.
    while y > 0.01 {
        var kind: Int
        if first { kind = 0; first = false } else if last == 2 { kind = 0 } else {
            kind = rng.chance(m.slopeW == 0 ? 1 : 0.85) ? 2 : 0
        }
        let big = expf(rng.range(logf(1.5), logf(H > 1000 ? 30 : 2)))
        switch kind {
        case 0:
            let ang = rng.range(86, 89.5) * .pi / 180
            var dh = rng.range(m.segH.lowerBound, m.segH.upperBound) * (m.slopeW == 0 ? min(big, 3) : big)
            dh = min(dh, y)
            if y - dh < 1.2 { dh = y }
            z += dh / tanf(ang); y -= dh
        default:
            let len = m.slopeW == 0 ? rng.range(m.ledgeLen.lowerBound, m.ledgeLen.upperBound) : rng.range(2, 5)
            let tilt = rng.range(m.slopeW == 0 ? 10 : 28, m.slopeW == 0 ? 18 : 36) * .pi / 180
            let dh = min(y, len * tanf(tilt))
            z += len; y -= dh
        }
        last = kind
        pts.append(SIMD2(z, max(0, y)))
    }
    pts[pts.count - 1].y = 0
    L.baseZ = z
    pts.append(SIMD2(z + max(400, H * 0.3), 0))
    L.profile = pts
    L.edge = SIMD2(0, H)

    // collision slabs under each segment
    let thick: Float = 8
    for i in 0..<(pts.count - 1) {
        let a = pts[i], b = pts[i + 1]
        let dz = b.x - a.x, dy = b.y - a.y
        let len = sqrtf(dz * dz + dy * dy)
        guard len > 0.01 else { continue }
        let d = V3(0, dy, dz) / len
        let n = V3(0, dz, -dy) / len   // up/outward
        let mid = V3(0, (a.y + b.y) / 2, (a.x + b.x) / 2)
        let half = V3(400, thick / 2, len / 2 + 0.04)
        let c = mid - n * (thick / 2)
        L.boxes.append(BoxCollider(c: c, ax: V3(1, 0, 0), ay: n, az: d, h: half, bound: len / 2 + 450))
    }
    return L
}

/// Obstacle collision shapes (deterministic from the obstacle's seed; the visuals use the same numbers).
func obstacleCapsules(_ o: Obstacle, sharpBase: Float) -> [Capsule] {
    var r = RNG(o.seed)
    let up = o.dir
    let side = simd_normalize(simd_cross(up, abs(up.y) > 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)))
    let fwd = simd_cross(side, up)
    func around(_ a: Float) -> V3 { side * cosf(a) + fwd * sinf(a) }
    var out: [Capsule] = []
    switch o.kind {
    case .pine:
        let top = o.base + up * o.len
        out.append(Capsule(a: o.base, b: top, r: o.r, sharp: 0, hard: 0.9, wood: true))
        let n = 5 + r.int(4)
        for k in 0..<n {
            let h = 0.3 + 0.6 * Float(k) / Float(n)
            let a = r.range(0, 6.28)
            let reach = (1 - h) * o.len * 0.32 + 0.3
            let s = o.base + up * (o.len * h)
            out.append(Capsule(a: s, b: s + around(a) * reach - up * reach * 0.25, r: 0.07, sharp: 0.2, hard: 0.8, wood: true))
        }
    case .deadTree:
        let top = o.base + up * o.len
        out.append(Capsule(a: o.base, b: top, r: o.r, sharp: 0, hard: 0.95, wood: true))
        let n = 4 + r.int(4)
        for _ in 0..<n {
            let h = r.range(0.35, 0.95)
            let a = r.range(0, 6.28)
            let reach = r.range(0.8, 2.2)
            let s = o.base + up * (o.len * h)
            out.append(Capsule(a: s, b: s + (around(a) * 0.8 + up * 0.6) * reach, r: 0.06, sharp: 0.9, hard: 0.9, wood: true))
        }
    case .stake:
        out.append(Capsule(a: o.base, b: o.base + up * o.len, r: o.r, sharp: 1.6, hard: 1, wood: true))
    case .cactus:
        let top = o.base + up * o.len
        out.append(Capsule(a: o.base, b: top, r: o.r, sharp: 0.9, hard: 0.7))
        for k in 0..<(1 + r.int(2)) {
            let a = r.range(0, 6.28) + Float(k) * 3
            let h = r.range(0.35, 0.65) * o.len
            let s = o.base + up * h
            let e = s + around(a) * (o.r * 2.2)
            out.append(Capsule(a: s, b: e, r: o.r * 0.7, sharp: 0.9, hard: 0.7))
            out.append(Capsule(a: e, b: e + up * r.range(0.8, 1.6), r: o.r * 0.7, sharp: 0.9, hard: 0.7))
        }
    case .icicle, .rockSpike:
        // a cone approximated by three capsules getting thinner
        for k in 0..<3 {
            let t0 = Float(k) / 3, t1 = Float(k + 1) / 3
            out.append(Capsule(a: o.base + up * (o.len * t0), b: o.base + up * (o.len * t1), r: o.r * (1 - t0) * 0.85 + 0.03,
                               sharp: k == 2 ? 1.5 : 0.6, hard: o.kind == .icicle ? 1.3 : 1.2))
        }
    case .crystal:
        let n = 3 + r.int(3)
        for k in 0..<n {
            let d = simd_normalize(up + around(r.range(0, 6.28)) * (k == 0 ? 0.1 : r.range(0.3, 0.8)))
            let len = o.len * (k == 0 ? 1 : r.range(0.4, 0.8))
            let rr = o.r * (k == 0 ? 1 : r.range(0.5, 0.8))
            out.append(Capsule(a: o.base, b: o.base + d * len * 0.8, r: rr, sharp: 0.8, hard: 1.4))
            out.append(Capsule(a: o.base + d * len * 0.8, b: o.base + d * len, r: rr * 0.4, sharp: 1.6, hard: 1.4))
        }
    }
    for i in 0..<out.count { out[i].sharp = max(out[i].sharp, 0) + sharpBase * 0 }
    return out
}

/// Rocks, obstacles and grass on one piece of one segment. Deterministic, so chunks can be rebuilt any time.
func buildChunk(_ L: Level, _ m: MapDef, seg i: Int, piece k: Int) -> Chunk {
    var c = Chunk()
    let p = L.profile
    guard i >= 0 && i < p.count - 1 else { return c }
    var rng = RNG(m.seed &* 31 &+ UInt64(i) &* 1_000_003 &+ UInt64(k) &* 7919 &+ UInt64(L.height))
    let a = p[i], b = p[i + 1]
    let dz = b.x - a.x, dy = b.y - a.y
    let len = sqrtf(dz * dz + dy * dy)
    guard len > 0.01 else { return c }
    let n = V3(0, dz, -dy) / len
    let t0 = Float(k) * Level.piece / len, t1 = min(1, Float(k + 1) * Level.piece / len)
    let pl = (t1 - t0) * len
    let isTop = i == 0, isGround = i == p.count - 2
    let steep = abs(dy) / len
    func at(_ t: Float, _ x: Float) -> V3 { V3(x, a.y + dy * t, a.x + dz * t) }
    func rock(_ pp: V3, _ r: Float, embed: Float) {
        let q = simd_quatf(angle: rng.range(0, 6.28), axis: simd_normalize(V3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)) + V3(0, 0.01, 0)))
        let rp = RockPlacement(c: pp + n * (r * embed), r: r, variant: rng.int(6), rot: q)
        c.rocks.append(rp)
        c.capsules.append(Capsule(a: rp.c, b: rp.c, r: r * 0.9, sharp: m.sharp, hard: 1))
    }
    // the run-up stays clear: no rocks on the plateau near the start line
    if !isTop {
        // rocks everywhere: dense along the fall line, thinner out to the sides
        let dens = m.rockDensity * (isGround ? 1.2 : 1) * (steep > 0.95 ? 0.5 : 1)
        let nIn = Int(pl * 20 * dens * 1.6 + rng.float())
        let nOut = Int(pl * 60 * dens * 0.5 + rng.float())
        for j in 0..<(nIn + nOut) {
            let x = j < nIn ? rng.range(-10, 10) : (rng.chance(0.5) ? 1 : -1) * rng.range(10, 40)
            let r = rng.range(m.rockSize.lowerBound, m.rockSize.upperBound) * (steep > 0.95 ? 0.8 : 1) * (j < nIn ? 1 : 1.3)
            rock(at(rng.range(t0, t1), x), r, embed: steep > 0.6 ? rng.range(-0.05, 0.25) : rng.range(0.1, 0.45))
        }
        // big outcrops half-buried in steep faces
        if steep > 0.8 {
            for _ in 0..<Int(pl * (0.4 + m.rockDensity * 3) + rng.float()) {
                let r = rng.range(0.8, 2.4)
                rock(at(rng.range(t0, t1), rng.range(-18, 18)), r, embed: -rng.range(0.45, 0.7))
            }
        }
        // trees, spikes, cacti, ice and crystals
        for (kind, d) in m.obstacles {
            if steep > 0.85 && kind == .cactus { continue }
            let onWall = steep > 0.85
            let cnt = Int(pl * 30 * d * (onWall ? 0.8 : 1) + rng.float())
            for _ in 0..<cnt {
                let x = rng.chance(0.75) ? rng.range(-9, 9) : rng.range(-25, 25)
                let base = at(rng.range(t0, t1), x)
                var dir: V3, len: Float, r: Float
                switch kind {
                case .pine: dir = simd_normalize(V3(0, 1, 0) + n * (onWall ? 1.3 : 0.15)); len = rng.range(onWall ? 4 : 6, onWall ? 9 : 13); r = rng.range(0.18, 0.32)
                case .deadTree: dir = simd_normalize(V3(0, 1, 0) + n * (onWall ? 1.3 : 0.25) + V3(rng.range(-0.2, 0.2), 0, 0)); len = rng.range(4, 9); r = rng.range(0.14, 0.26)
                case .stake: dir = simd_normalize(n * 0.8 + V3(0, 0.6, 0) + V3(rng.range(-0.3, 0.3), 0, rng.range(-0.2, 0.2))); len = rng.range(1.2, 2.4); r = rng.range(0.06, 0.1)
                case .cactus: dir = V3(0, 1, 0); len = rng.range(2.5, 5); r = rng.range(0.25, 0.4)
                case .icicle: dir = simd_normalize(n + V3(0, 0.5, 0) + V3(rng.range(-0.3, 0.3), 0, 0)); len = rng.range(2, 6); r = rng.range(0.3, 0.8)
                case .rockSpike: dir = simd_normalize(n + V3(0, 0.4, 0) + V3(rng.range(-0.3, 0.3), 0, 0)); len = rng.range(1.5, 4.5); r = rng.range(0.3, 0.8)
                case .crystal: dir = simd_normalize(n + V3(0, 0.3, 0)); len = rng.range(1.5, 4.5); r = rng.range(0.2, 0.5)
                }
                let o = Obstacle(kind: kind, base: base - dir * 0.2, dir: dir, len: len, r: r, yaw: rng.range(0, 6.28), seed: rng.next())
                c.obstacles.append(o)
                c.capsules += obstacleCapsules(o, sharpBase: m.sharp)
            }
        }
    }
    // grass on anything flat enough, if the map has grass
    let grassy = m.top.y > m.top.x * 1.12 && m.top.y > m.top.z * 1.2
    let groundGrassy = m.ground.y > m.ground.x * 1.12 && m.ground.y > m.ground.z * 1.2
    if steep < 0.72 && ((isGround && groundGrassy) || (!isGround && grassy)) {
        let tint = isGround ? m.ground : m.top
        let cnt = Int(pl * 60 * (isTop ? 0.9 : 0.8))
        for _ in 0..<cnt {
            let x = rng.chance(0.7) ? rng.range(-14, 14) : rng.range(-30, 30)
            c.grass.append((at(rng.range(t0, t1), x) - n * 0.02, tint))
        }
    }
    return c
}

// MARK: - Upgrades (Roblox-style)

struct UpgradeDef {
    let name: String
    let desc: String
    let costs: [Int]
    var max: Int { costs.count }
}

enum Up { static let jump = 0, run = 1, brittle = 2, cash = 3, air = 4 }

let upgrades: [UpgradeDef] = [
    UpgradeDef(name: "Jump Power", desc: "Leap higher and further off the edge", costs: [8000, 40000, 160000, 600000, 2_000_000]),
    UpgradeDef(name: "Run Speed", desc: "Faster run-up, faster launch", costs: [6000, 30000, 120000, 450000, 1_500_000]),
    UpgradeDef(name: "Brittle Bones", desc: "+18% bone damage per level", costs: [12000, 60000, 250000, 900000, 3_000_000]),
    UpgradeDef(name: "Cash Boost", desc: "+25% cash per level", costs: [15000, 80000, 350000, 1_300_000, 4_500_000]),
    UpgradeDef(name: "Air Control", desc: "Flip and roll harder in the air", costs: [10000, 80000, 500000]),
]

// MARK: - Abilities (bought with cash, used mid-fall with keys 1-6)

struct AbilityDef {
    let name: String
    let desc: String
    let cost: Int
    let uses: Int
}

let abilities: [AbilityDef] = [
    AbilityDef(name: "Rocket Slam", desc: "Blast yourself down into the rocks", cost: 25000, uses: 2),
    AbilityDef(name: "Air Jump", desc: "Jump again in mid-air", cost: 15000, uses: 3),
    AbilityDef(name: "Rock Magnet", desc: "Get yanked into the nearest obstacle", cost: 60000, uses: 2),
    AbilityDef(name: "Mega Mass", desc: "Heavy as lead for 6 s: double damage", cost: 150000, uses: 1),
    AbilityDef(name: "Explosion", desc: "Blow yourself up. Every bone takes a hit", cost: 400000, uses: 1),
    AbilityDef(name: "Bullet Time", desc: "Slow motion for 4 s and double cash", cost: 1_000_000, uses: 1),
    AbilityDef(name: "Jetpack", desc: "Hold 7 to fly, steer with W A S D. 8 s of fuel", cost: 750_000, uses: 1),
]
