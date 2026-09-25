import simd

typealias V3 = SIMD3<Float>

/// Damage bands. Crossing into each one pays out.
enum Injury: Int {
    case fine = 0, bruised, cracked, broken, shattered
    static let thresholds: [Float] = [0, 14, 38, 68, 100]
    static func of(_ d: Float) -> Injury {
        if d >= 100 { return .shattered }
        if d >= 68 { return .broken }
        if d >= 38 { return .cracked }
        if d >= 14 { return .bruised }
        return .fine
    }
    var label: String { ["OK", "BRUISED", "CRACKED", "BROKEN", "SHATTERED"][rawValue] }
    var cash: Float { [0, 1.5, 4, 9, 18][rawValue] }
}

// Particle indices
enum PI {
    static let head = 0, neck = 1, chest = 2, pelvis = 3
    static let lSh = 4, lEl = 5, lHa = 6, rSh = 7, rEl = 8, rHa = 9
    static let lHip = 10, lKn = 11, lAn = 12, lToe = 13, rHip = 14, rKn = 15, rAn = 16, rToe = 17
    static let count = 18
}

// MARK: - Colliders

struct BoxCollider {
    var c: V3
    var ax: V3, ay: V3, az: V3     // unit axes
    var h: V3                       // half extents
    var bound: Float                // bounding radius
    var rock = false
}

/// A capsule (a == b makes it a sphere): rocks, tree trunks, branches, spikes, cacti.
struct Capsule {
    var a: V3
    var b: V3
    var r: Float
    var sharp: Float = 0      // spikes and thorns hurt more
    var hard: Float = 1
    var wood = false          // for the impact sound
}

struct Surface {
    var friction: Float = 0.62
    var bounce: Float = 0.18
    var hardness: Float = 1
    var sharp: Float = 0
}

struct Impact {
    var particle: Int
    var bone: Region?        // set for limb-segment hits
    var t: Float = 0.5       // where along the segment
    var speed: Float
    var normal: V3
    var point: V3
    var rock: Bool
    var sharp: Float = 0
    var wood = false
}

// MARK: - Ragdoll (Verlet)

final class Ragdoll {
    var pos = [V3](repeating: .zero, count: PI.count)
    var prev = [V3](repeating: .zero, count: PI.count)
    var radius: [Float] = [0.12, 0.06, 0.15, 0.14, 0.07, 0.055, 0.06, 0.07, 0.055, 0.06, 0.08, 0.065, 0.055, 0.05, 0.08, 0.065, 0.055, 0.05]
    var invMass: [Float] = [0.7, 0.8, 0.3, 0.3, 0.7, 0.9, 1.1, 0.7, 0.9, 1.1, 0.5, 0.7, 0.9, 1.2, 0.5, 0.7, 0.9, 1.2]
    var accel = [V3](repeating: .zero, count: PI.count)

    struct Link { var a: Int, b: Int, rest: Float, stiff: Float, mode: Int; var tag: Region? = nil; var on = true }  // mode 0 = rod, 1 = min only
    var links: [Link] = []
    struct Seg { var a: Int, b: Int, r: Float, bone: Region }
    let segs: [Seg] = [
        Seg(a: PI.head, b: PI.neck, r: 0.06, bone: .neck), Seg(a: PI.neck, b: PI.chest, r: 0.1, bone: .spine), Seg(a: PI.chest, b: PI.pelvis, r: 0.13, bone: .spine),
        Seg(a: PI.lSh, b: PI.lEl, r: 0.055, bone: .lHum), Seg(a: PI.lEl, b: PI.lHa, r: 0.045, bone: .lFore),
        Seg(a: PI.rSh, b: PI.rEl, r: 0.055, bone: .rHum), Seg(a: PI.rEl, b: PI.rHa, r: 0.045, bone: .rFore),
        Seg(a: PI.lHip, b: PI.lKn, r: 0.075, bone: .lFem), Seg(a: PI.lKn, b: PI.lAn, r: 0.06, bone: .lShin),
        Seg(a: PI.rHip, b: PI.rKn, r: 0.075, bone: .rFem), Seg(a: PI.rKn, b: PI.rAn, r: 0.06, bone: .rShin),
        Seg(a: PI.lSh, b: PI.rSh, r: 0.06, bone: .ribs), Seg(a: PI.lHip, b: PI.rHip, r: 0.08, bone: .pelvis),
    ]
    /// Which bones feel a hit on each particle, and how much.
    static let particleBones: [[(Region, Float)]] = [
        [(.skull, 0.85), (.neck, 0.3)],
        [(.neck, 0.7), (.lClav, 0.25), (.rClav, 0.25)],
        [(.ribs, 0.9), (.spine, 0.35)],
        [(.pelvis, 0.8), (.spine, 0.45)],
        [(.lClav, 0.75), (.lHum, 0.35)], [(.lHum, 0.6), (.lFore, 0.6)], [(.lHand, 0.85), (.lFore, 0.35)],
        [(.rClav, 0.75), (.rHum, 0.35)], [(.rHum, 0.6), (.rFore, 0.6)], [(.rHand, 0.85), (.rFore, 0.35)],
        [(.pelvis, 0.5), (.lFem, 0.6)], [(.lFem, 0.6), (.lShin, 0.6)], [(.lShin, 0.7), (.lFoot, 0.55)], [(.lFoot, 0.9)],
        [(.pelvis, 0.5), (.rFem, 0.6)], [(.rFem, 0.6), (.rShin, 0.6)], [(.rShin, 0.7), (.rFoot, 0.55)], [(.rFoot, 0.9)],
    ]

    /// Standing pose, facing +z, feet at y = 0. Left is +x.
    static let restPose: [V3] = [
        V3(0, 1.66, 0.02), V3(0, 1.48, 0), V3(0, 1.27, 0.01), V3(0, 0.98, 0),
        V3(0.2, 1.43, 0), V3(0.25, 1.14, -0.02), V3(0.27, 0.87, 0.02),
        V3(-0.2, 1.43, 0), V3(-0.25, 1.14, -0.02), V3(-0.27, 0.87, 0.02),
        V3(0.1, 0.93, 0), V3(0.11, 0.51, 0.02), V3(0.11, 0.09, 0), V3(0.11, 0.03, 0.17),
        V3(-0.1, 0.93, 0), V3(-0.11, 0.51, 0.02), V3(-0.11, 0.09, 0), V3(-0.11, 0.03, 0.17),
    ]

    var boxes: [BoxCollider] = []
    var capsules: [Capsule] = []          // world space, supplied by the streaming world
    var surface = Surface()
    var rockSurface = Surface()
    /// Floating origin: particles live in local coordinates near zero so Float stays precise kilometres up.
    /// Always a multiple of 256 m, so re-basing is exact.
    private(set) var origin = V3.zero
    private var nearB: [BoxCollider] = [], nearC: [Capsule] = []
    private(set) var nearestObstacle: Float = 1e9
    var impacts: [Impact] = []
    var gravity = V3(0, -9.81, 0)
    let h: Float = 1.0 / 240
    var drag: Float = 0.0038
    var contacts = 0            // particles touching something last substep
    var groundedCount = 0

    init() {
        let p = Ragdoll.restPose
        func rod(_ a: Int, _ b: Int, _ s: Float = 1, _ tag: Region? = nil) { links.append(Link(a: a, b: b, rest: simd_length(p[a] - p[b]), stiff: s, mode: 0, tag: tag)) }
        func minD(_ a: Int, _ b: Int, _ f: Float, _ tag: Region? = nil) { links.append(Link(a: a, b: b, rest: simd_length(p[a] - p[b]) * f, stiff: 0.8, mode: 1, tag: tag)) }
        // torso: upper and lower clusters, joined by a slightly bendy spine
        let upper = [PI.neck, PI.chest, PI.lSh, PI.rSh]
        for i in 0..<upper.count { for j in (i + 1)..<upper.count { rod(upper[i], upper[j]) } }
        let lower = [PI.pelvis, PI.lHip, PI.rHip]
        for i in 0..<lower.count { for j in (i + 1)..<lower.count { rod(lower[i], lower[j]) } }
        rod(PI.chest, PI.pelvis)
        rod(PI.chest, PI.lHip, 0.6, .spine); rod(PI.chest, PI.rHip, 0.6, .spine)
        rod(PI.lSh, PI.pelvis, 0.35, .spine); rod(PI.rSh, PI.pelvis, 0.35, .spine)
        rod(PI.neck, PI.pelvis, 0.5, .spine)
        // head on a floppy neck
        rod(PI.head, PI.neck)
        rod(PI.head, PI.lSh, 0.25, .neck); rod(PI.head, PI.rSh, 0.25, .neck)
        minD(PI.head, PI.chest, 0.85, .neck)
        // arms
        rod(PI.lSh, PI.lEl); rod(PI.lEl, PI.lHa); minD(PI.lSh, PI.lHa, 0.35, .lFore)
        rod(PI.rSh, PI.rEl); rod(PI.rEl, PI.rHa); minD(PI.rSh, PI.rHa, 0.35, .rFore)
        // legs (foot rigid to shin)
        rod(PI.lHip, PI.lKn); rod(PI.lKn, PI.lAn); rod(PI.lAn, PI.lToe); rod(PI.lKn, PI.lToe, 1, .lShin); minD(PI.lHip, PI.lAn, 0.45, .lFem)
        rod(PI.rHip, PI.rKn); rod(PI.rKn, PI.rAn); rod(PI.rAn, PI.rToe); rod(PI.rKn, PI.rToe, 1, .rShin); minD(PI.rHip, PI.rAn, 0.45, .rFem)
        // keep the legs from swinging through each other too much
        links.append(Link(a: PI.lKn, b: PI.rKn, rest: 0.1, stiff: 0.5, mode: 1))
        links.append(Link(a: PI.lAn, b: PI.rAn, rest: 0.1, stiff: 0.5, mode: 1))
        links.append(Link(a: PI.lHa, b: PI.rHa, rest: 0.08, stiff: 0.5, mode: 1))
        links.append(Link(a: PI.head, b: PI.pelvis, rest: 0.45, stiff: 0.8, mode: 1))
        place(pose: Ragdoll.restPose, at: .zero, yaw: 0)
    }

    /// Positions every particle from a pose, rotated by yaw around y, with zero velocity.
    static func snap(_ p: V3) -> V3 { (p / 256).rounded(.down) * 256 }

    func place(pose: [V3], at o: V3, yaw: Float, velocity: V3 = .zero) {
        let c = cosf(yaw), s = sinf(yaw)
        origin = Ragdoll.snap(o)
        let lo = o - origin
        for i in 0..<PI.count {
            let q = pose[i]
            pos[i] = lo + V3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c)
            prev[i] = pos[i] - velocity * h
        }
    }

    var localCom: V3 {
        var s = V3.zero, m: Float = 0
        for i in 0..<PI.count { let w = 1 / invMass[i]; s += pos[i] * w; m += w }
        return s / m
    }
    /// Centre of mass in world space.
    var com: V3 { origin + localCom }
    func wpos(_ i: Int) -> V3 { origin + pos[i] }
    var worldPos: [V3] { pos.map { origin + $0 } }
    func vel(_ i: Int) -> V3 { (pos[i] - prev[i]) / h }
    var maxSpeed: Float { (0..<PI.count).map { simd_length(vel($0)) }.max() ?? 0 }
    var comVel: V3 {
        var s = V3.zero, m: Float = 0
        for i in 0..<PI.count { let w = 1 / invMass[i]; s += vel(i) * w; m += w }
        return s / m
    }

    /// Torso frame: right (+x in rest = body's left), up, forward (+z = where the chest faces).
    var frame: (right: V3, up: V3, fwd: V3) {
        let r = simd_normalize(pos[PI.lSh] - pos[PI.rSh] + (pos[PI.lHip] - pos[PI.rHip]) * 0.5 + V3(0, 0, 1e-5))
        let upRaw = pos[PI.neck] - pos[PI.pelvis]
        let u = simd_normalize(upRaw - r * simd_dot(upRaw, r) + V3(0, 1e-5, 0))
        let f = simd_cross(r, u)
        return (r, u, f)
    }

    /// Spins the body about a world axis through its centre of mass (air control).
    func applySpin(axis: V3, alpha: Float, maxRate: Float) {
        let c = localCom, cv = comVel
        var L: Float = 0, I: Float = 0
        for i in 0..<PI.count {
            let r = pos[i] - c
            let rp = r - axis * simd_dot(r, axis)
            let w = 1 / invMass[i]
            L += simd_dot(simd_cross(rp, vel(i) - cv), axis) * w
            I += simd_length_squared(rp) * w
        }
        let rate = I > 1e-4 ? L / I : 0
        if (alpha > 0 && rate > maxRate) || (alpha < 0 && rate < -maxRate) { return }
        for i in 0..<PI.count {
            let r = pos[i] - c
            accel[i] += simd_cross(axis, r - axis * simd_dot(r, axis)) * alpha
        }
    }

    /// Muscles: pulls hands, elbows, knees and feet toward pose targets given in the torso frame.
    /// The reaction goes into the torso so the body can't swim through the air.
    func applyPose(_ targets: [(Int, V3)], strength k: Float) {
        let f = frame
        let o = pos[PI.chest]
        var reaction = V3.zero
        for (i, t) in targets {
            let w = o + f.right * t.x + f.up * t.y + f.fwd * t.z
            let rv = vel(i) - vel(PI.chest)
            var a = (w - pos[i]) * k - rv * sqrtf(k) * 0.9
            let m = simd_length(a)
            if m > 120 { a *= 120 / m }
            accel[i] += a
            reaction -= a / invMass[i]
        }
        for i in [PI.chest, PI.pelvis, PI.neck] { accel[i] += reaction / 3 * invMass[i] }
    }

    // MARK: Step

    /// Collects colliders near the body for this frame's substeps, in local coordinates. Re-bases the origin when needed.
    func gatherNear(frameDt: Float) {
        var lc = localCom
        if simd_length(lc) > 160 {
            let shift = Ragdoll.snap(origin + lc) - origin
            origin += shift
            for i in 0..<PI.count { pos[i] -= shift; prev[i] -= shift }
            lc = localCom
        }
        var rad: Float = 0
        for i in 0..<PI.count { rad = max(rad, simd_length(pos[i] - lc)) }
        rad += maxSpeed * frameDt * 1.5 + 1
        nearB.removeAll(keepingCapacity: true)
        nearC.removeAll(keepingCapacity: true)
        let wc = origin + lc
        for b in boxes where simd_length(b.c - wc) < b.bound + rad {
            var l = b; l.c = b.c - origin; nearB.append(l)
        }
        var nearest: Float = 1e9
        for c in capsules {
            let ab = c.b - c.a
            let L2 = simd_length_squared(ab)
            let t = L2 > 1e-6 ? clampf(simd_dot(wc - c.a, ab) / L2, 0, 1) : 0
            let d = simd_length(c.a + ab * t - wc) - c.r
            nearest = min(nearest, d)
            if d < rad {
                var l = c; l.a = c.a - origin; l.b = c.b - origin; nearC.append(l)
            }
        }
        // distance to the terrain surface counts too (the world passes it in through surfaceGap)
        nearestObstacle = min(nearest, surfaceGap)
    }
    /// Height of the body above the cliff surface, set by the game each frame.
    var surfaceGap: Float = 1e9

    func substep() {
        // integrate
        for i in 0..<PI.count {
            var v = pos[i] - prev[i]
            let vm = simd_length(v) / h
            let dragA = -v / h * vm * drag
            v *= contacts > 6 && vm < 1.2 ? 0.985 : 0.9998    // a body at rest settles instead of jittering
            prev[i] = pos[i]
            pos[i] += v + (gravity + accel[i] + dragA) * h * h
        }
        // collisions with velocity response and impact recording
        contacts = 0
        groundedCount = 0
        for i in 0..<PI.count { collideParticle(i, respond: true) }
        for s in segs { collideSegment(s, respond: true) }
        // constraints
        for it in 0..<10 {
            for l in links where l.on {
                let d = pos[l.b] - pos[l.a]
                let len = simd_length(d)
                guard len > 1e-6 else { continue }
                if l.mode == 1 && len >= l.rest { continue }
                let wa = invMass[l.a], wb = invMass[l.b]
                let corr = d * ((len - l.rest) / (len * (wa + wb))) * l.stiff
                pos[l.a] += corr * wa
                pos[l.b] -= corr * wb
            }
            if it % 2 == 1 { hinges() }
            if it % 3 == 2 || it == 9 {
                for i in 0..<PI.count { collideParticle(i, respond: false) }
            }
        }
        for s in segs { collideSegment(s, respond: false) }
    }

    /// Hinges that only bend one way (knees fold back, elbows fold forward), unless that bone is broken.
    var hingeOn: [Region: Bool] = [.lFem: true, .rFem: true, .lHum: true, .rHum: true, .lShin: true, .rShin: true, .lFore: true, .rFore: true]

    /// A broken bone stops holding its shape: the joints around it go floppy.
    func fracture(_ r: Region) {
        for i in 0..<links.count where links[i].tag == r {
            if links[i].mode == 1 { links[i].on = false } else { links[i].stiff = min(links[i].stiff, r == .spine ? 0.06 : 0.12) }
        }
        hingeOn[r] = false
    }

    func resetFractures() {
        let fresh = Ragdoll()
        links = fresh.links
        for k in hingeOn.keys { hingeOn[k] = true }
    }

    private func hinges() {
        let f = frame
        // knees: the knee must stay in front of the hip-ankle line
        for (hip, kn, an, r1, r2) in [(PI.lHip, PI.lKn, PI.lAn, Region.lFem, Region.lShin), (PI.rHip, PI.rKn, PI.rAn, Region.rFem, Region.rShin)] where hingeOn[r1] == true && hingeOn[r2] == true {
            let mid = (pos[hip] + pos[an]) * 0.5
            let d = simd_dot(pos[kn] - mid, f.fwd)
            if d < -0.01 {
                let c = f.fwd * (-0.01 - d)
                pos[kn] += c * 0.6; pos[hip] -= c * 0.2; pos[an] -= c * 0.2
            }
        }
        // elbows: the elbow must stay behind the shoulder-hand line
        for (sh, el, ha, r1, r2) in [(PI.lSh, PI.lEl, PI.lHa, Region.lHum, Region.lFore), (PI.rSh, PI.rEl, PI.rHa, Region.rHum, Region.rFore)] where hingeOn[r1] == true && hingeOn[r2] == true {
            let mid = (pos[sh] + pos[ha]) * 0.5
            let d = simd_dot(pos[el] - mid, f.fwd)
            if d > 0.01 {
                let c = f.fwd * (d - 0.01)
                pos[el] -= c * 0.6; pos[sh] += c * 0.15; pos[ha] += c * 0.25
            }
        }
    }

    func clearForces() { for i in 0..<PI.count { accel[i] = .zero } }

    @inline(__always) private func boxQuery(_ b: BoxCollider, _ p: V3, _ r: Float) -> (V3, Float)? {
        let d = p - b.c
        let lx = simd_dot(d, b.ax), ly = simd_dot(d, b.ay), lz = simd_dot(d, b.az)
        let px = b.h.x + r - abs(lx), py = b.h.y + r - abs(ly), pz = b.h.z + r - abs(lz)
        if px <= 0 || py <= 0 || pz <= 0 { return nil }
        if py <= px && py <= pz { return (b.ay * (ly < 0 ? -1 : 1), py) }
        if pz <= px { return (b.az * (lz < 0 ? -1 : 1), pz) }
        return (b.ax * (lx < 0 ? -1 : 1), px)
    }

    private func respondVelocity(_ i: Int, n: V3, s: Surface, isRock: Bool, boneHit: Region?, sharp: Float, wood: Bool) {
        let v = (pos[i] - prev[i]) / h
        let vn = simd_dot(v, n)
        guard vn < 0 else { return }
        let impact = -vn
        if impact > 2.5 {
            impacts.append(Impact(particle: i, bone: boneHit, speed: impact * s.hardness, normal: n, point: origin + pos[i] - n * radius[i], rock: isRock, sharp: sharp, wood: wood))
        }
        var vt = v - n * vn
        let vtm = simd_length(vt)
        if vtm > 1e-6 { vt *= max(0, 1 - s.friction * impact / vtm) }
        vt *= 0.995
        let vnNew = impact > 1.5 ? impact * s.bounce : 0
        let nv = vt + n * vnNew
        prev[i] = pos[i] - nv * h
    }

    private func capSurface(_ c: Capsule) -> Surface {
        var s = rockSurface
        s.hardness *= c.hard
        s.sharp = max(s.sharp, c.sharp)
        return s
    }

    private func collideParticle(_ i: Int, respond: Bool) {
        let r = radius[i]
        for b in nearB {
            guard let (n, pen) = boxQuery(b, pos[i], r) else { continue }
            pos[i] += n * pen
            if respond {
                contacts += 1
                if n.y > 0.5 { groundedCount += 1 }
                respondVelocity(i, n: n, s: b.rock ? rockSurface : surface, isRock: b.rock, boneHit: nil, sharp: 0, wood: false)
            } else {
                prev[i] += n * pen
            }
        }
        for c in nearC {
            let ab = c.b - c.a
            let L2 = simd_length_squared(ab)
            let t = L2 > 1e-6 ? clampf(simd_dot(pos[i] - c.a, ab) / L2, 0, 1) : 0
            let d = pos[i] - (c.a + ab * t)
            let dist = simd_length(d)
            let pen = c.r + r - dist
            guard pen > 0, dist > 1e-5 else { continue }
            let n = d / dist
            pos[i] += n * pen
            if respond {
                contacts += 1
                if n.y > 0.5 { groundedCount += 1 }
                respondVelocity(i, n: n, s: capSurface(c), isRock: true, boneHit: nil, sharp: c.sharp, wood: c.wood)
            } else {
                prev[i] += n * pen
            }
        }
    }

    /// Closest points between segments p1-q1 and p2-q2 (Ericson). Returns (s, t).
    @inline(__always) private func closest(_ p1: V3, _ q1: V3, _ p2: V3, _ q2: V3) -> (Float, Float) {
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = simd_dot(d1, d1), e = simd_dot(d2, d2), f = simd_dot(d2, r)
        if a <= 1e-8 && e <= 1e-8 { return (0, 0) }
        var s: Float = 0, t: Float = 0
        if a <= 1e-8 { t = clampf(f / e, 0, 1) } else {
            let c = simd_dot(d1, r)
            if e <= 1e-8 { s = clampf(-c / a, 0, 1) } else {
                let b = simd_dot(d1, d2)
                let den = a * e - b * b
                s = den > 1e-8 ? clampf((b * f - c * e) / den, 0, 1) : 0
                t = (b * s + f) / e
                if t < 0 { t = 0; s = clampf(-c / a, 0, 1) } else if t > 1 { t = 1; s = clampf((b - c) / a, 0, 1) }
            }
        }
        return (s, t)
    }

    /// Limb segments against capsules, so a shin can wrap around a boulder or a branch even when neither end touches it.
    private func collideSegment(_ sg: Seg, respond: Bool) {
        for c in nearC {
            let a = pos[sg.a], b = pos[sg.b]
            let (t, u) = closest(a, b, c.a, c.b)
            if t < 0.08 || t > 0.92 { continue }   // ends are handled as particles
            let q = a + (b - a) * t
            let cp = c.a + (c.b - c.a) * u
            let d = q - cp
            let dist = simd_length(d)
            let pen = c.r + sg.r - dist
            guard pen > 0, dist > 1e-5 else { continue }
            let n = d / dist
            let wa = 1 - t, wb = t
            let den = wa * wa + wb * wb
            pos[sg.a] += n * pen * wa / den
            pos[sg.b] += n * pen * wb / den
            if respond {
                let sf = capSurface(c)
                let va = (pos[sg.a] - prev[sg.a]) / h, vb = (pos[sg.b] - prev[sg.b]) / h
                let vq = va * wa + vb * wb
                let vn = simd_dot(vq, n)
                guard vn < 0 else { continue }
                let impact = -vn
                if impact > 2.5 {
                    impacts.append(Impact(particle: t < 0.5 ? sg.a : sg.b, bone: sg.bone, t: t, speed: impact * sf.hardness, normal: n,
                                          point: origin + q - n * sg.r, rock: true, sharp: c.sharp, wood: c.wood))
                }
                var vt = vq - n * vn
                let vtm = simd_length(vt)
                if vtm > 1e-6 { vt = vt * min(1, sf.friction * impact / vtm) } else { vt = .zero }
                let dv = n * (impact * (1 + sf.bounce * 0.5)) - vt
                prev[sg.a] -= dv * (wa / den) * h
                prev[sg.b] -= dv * (wb / den) * h
            } else {
                prev[sg.a] += n * pen * wa / den
                prev[sg.b] += n * pen * wb / den
            }
        }
    }
}
