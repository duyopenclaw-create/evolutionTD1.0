import simd

/// Tracks damage on all 206 bones and turns impacts into injury events.
final class Injuries {
    static let count = Skeleton.bones.count
    private(set) var damage = [Float](repeating: 0, count: Injuries.count)
    private(set) var state = [Injury](repeating: .fine, count: Injuries.count)
    /// Every hit that did real damage: which region, and how hard (for the results map).
    private(set) var hits: [(region: Region, severity: Float)] = []
    var brittle: Float = 1
    /// Damage dealt to bones that were already shattered since last read (pays "overkill" cash).
    var overkill: Float = 0
    private var rng = RNG(99)

    struct Event {
        let bone: Int
        let from: Injury
        let to: Injury
        let baseCash: Float     // before multipliers
        var def: BoneDef { Skeleton.bones[bone] }
    }

    func reset() {
        for i in 0..<damage.count { damage[i] = 0; state[i] = .fine }
        hits.removeAll()
    }

    var brokenCount: Int { state.filter { $0.rawValue >= Injury.broken.rawValue }.count }
    var shatteredCount: Int { state.filter { $0 == .shattered }.count }
    var hurtCount: Int { state.filter { $0 != .fine }.count }
    func count(_ s: Injury) -> Int { state.filter { $0 == s }.count }

    /// Worst damage in a region (drives bruise tint and floppy joints).
    func regionDamage(_ r: Region) -> Float { Skeleton.byRegion[r.rawValue].map { damage[$0] }.max() ?? 0 }
    /// The region's main bone broken? (long bones, spine, neck)
    func regionBroken(_ r: Region) -> Bool {
        let ids = Skeleton.byRegion[r.rawValue]
        switch r {
        case .neck, .spine: return ids.contains { state[$0].rawValue >= Injury.broken.rawValue }
        case .lHand, .rHand, .lFoot, .rFoot, .skull, .ribs:
            return ids.filter { state[$0].rawValue >= Injury.broken.rawValue }.count > ids.count / 2
        default: return state[ids[0]].rawValue >= Injury.broken.rawValue
        }
    }

    /// Damage from an impact at `speed` m/s. Squared above a threshold, like kinetic energy.
    static func dose(_ speed: Float, sharp: Float) -> Float {
        let e = max(0, speed - 3.4)
        return 0.5 * e * e * (1 + sharp * 0.6)
    }

    struct Body {
        var right: V3, up: V3, fwd: V3, chest: V3, pelvis: V3
    }

    /// Picks which real bones in a region take a hit, with weights.
    private func targets(_ r: Region, dose d: Float, im: Impact, body b: Body, faceHit: Bool) -> [(Int, Float)] {
        let ids = Skeleton.byRegion[r.rawValue]
        let B = Skeleton.bones
        func pick(_ pool: [Int], _ k: Int) -> [(Int, Float)] {
            guard !pool.isEmpty else { return [] }
            var p = pool, out: [(Int, Float)] = []
            for j in 0..<min(k, p.count) {
                let i = rng.int(p.count)
                out.append((p[i], j == 0 ? 1 : max(0.35, 0.8 - Float(j) * 0.08)))
                p.remove(at: i)
            }
            return out
        }
        func near(_ pool: [Int], center c: Int) -> [(Int, Float)] {
            var out: [(Int, Float)] = []
            for (k, id) in pool.enumerated() {
                let dist = abs(k - c)
                if dist == 0 { out.append((id, 1)) } else if dist == 1 { out.append((id, 0.5)) } else if dist == 2 && d > 40 { out.append((id, 0.25)) }
            }
            return out
        }
        let sideOfHit: Float = simd_dot(im.point - b.chest, b.right) >= 0 ? 1 : -1
        let k = 1 + Int(min(7, d / 14))
        switch r {
        case .skull:
            let pool = ids.filter { faceHit ? B[$0].kind == .facial : B[$0].kind == .cranial }
            var out = pick(pool, k)
            if d > 45 && rng.chance(0.35) { out += pick(ids.filter { B[$0].kind == .ossicle && B[$0].side == sideOfHit }, 1 + rng.int(3)).map { ($0.0, 0.5) } }
            return out
        case .jaw:
            return ids.map { (B[$0].kind == .mandible ? 1 : 0.35) as Float }.enumerated().map { (ids[$0.offset], $0.element) }
        case .neck:
            let c = im.bone == .neck ? Int(im.t * 6.9) : 4 + rng.int(3)
            return near(ids, center: min(6, max(0, c)))
        case .spine:
            var c: Int
            if im.bone == .spine { c = im.particle == PI.neck || im.particle == PI.head ? Int(im.t * 6) : 6 + Int(im.t * 10.9) }
            else if im.particle == PI.pelvis { c = 14 + rng.int(3) } else { c = 3 + rng.int(7) }
            return near(ids, center: min(16, max(0, c)))
        case .ribs:
            let front = simd_dot(-im.normal, b.fwd) > 0.5
            let pool = ids.filter { B[$0].kind == .rib && B[$0].side == sideOfHit }
            let row = min(11, max(0, Int(rng.range(1, 10))))
            var out = near(pool, center: row)
            if k > 3 { out += pick(pool, k - 2).map { ($0.0, 0.5) } }
            if front { out += ids.filter { B[$0].kind == .sternum }.map { ($0, 0.7) } }
            return out
        case .lClav, .rClav:
            let back = simd_dot(-im.normal, b.fwd) < -0.3
            return ids.map { ($0, B[$0].kind == .clavicle ? 1 : (back ? 0.9 : 0.4)) }
        case .pelvis:
            return ids.map { id -> (Int, Float) in
                switch B[id].kind {
                case .hip: return (id, B[id].side == sideOfHit ? 1 : 0.4)
                case .sacrum: return (id, 0.5)
                default: return (id, 0.35)
                }
            }
        case .lHum, .rHum: return [(ids[0], 1)]
        case .lFore, .rFore: return [(ids[0], 1), (ids[1], 0.85)]
        case .lFem, .rFem:
            let knee = im.particle == PI.lKn || im.particle == PI.rKn
            return [(ids[0], 1), (ids[1], knee ? 0.8 : 0.1)]
        case .lShin, .rShin: return [(ids[0], 1), (ids[1], 0.7)]
        case .lHand, .rHand, .lFoot, .rFoot:
            return pick(ids, 1 + Int(min(9, d / 9)))
        }
    }

    /// Applies one impact to the skeleton.
    func apply(_ im: Impact, body b: Body, sharp: Float) -> [Event] {
        let d = Injuries.dose(im.speed, sharp: max(im.sharp, im.rock ? sharp : sharp * 0.3)) * brittle
        guard d > 0.4 else { return [] }
        var shares: [(Region, Float)]
        var faceHit = false
        if let r = im.bone {
            shares = [(r, 1)]
        } else if im.particle == PI.head {
            faceHit = simd_dot(-im.normal, b.fwd) > 0.45
            shares = faceHit ? [(.skull, 0.8), (.jaw, 0.7), (.neck, 0.3)] : Ragdoll.particleBones[PI.head]
        } else {
            shares = Ragdoll.particleBones[im.particle]
        }
        var add = [Float](repeating: 0, count: damage.count)
        var regionHit = [Float](repeating: 0, count: Region.allCases.count)
        for (r, w) in shares {
            for (id, tw) in targets(r, dose: d * w, im: im, body: b, faceHit: faceHit) {
                add[id] += d * w * tw * Skeleton.bones[id].fragility * rng.range(0.75, 1.2)
            }
            regionHit[r.rawValue] += d * w
            // the shock travels up the chain
            for n in r.neighbours where d * w > 12 {
                for (id, tw) in targets(n, dose: d * w * 0.25, im: im, body: b, faceHit: false).prefix(2) {
                    add[id] += d * w * 0.22 * tw * Skeleton.bones[id].fragility
                }
            }
        }
        for (i, v) in regionHit.enumerated() where v > 4 { hits.append((Region(rawValue: i)!, v)) }
        var events: [Event] = []
        for i in 0..<damage.count where add[i] > 0.05 {
            let before = state[i]
            if before == .shattered { overkill += add[i] * Skeleton.bones[i].value; continue }
            damage[i] = min(damage[i] + add[i], 160)
            let after = Injury.of(damage[i])
            if after.rawValue > before.rawValue {
                state[i] = after
                var cash: Float = 0
                for k in (before.rawValue + 1)...after.rawValue { cash += Injury(rawValue: k)!.cash }
                events.append(Event(bone: i, from: before, to: after, baseCash: cash * Skeleton.bones[i].value))
            }
        }
        return events
    }
}
