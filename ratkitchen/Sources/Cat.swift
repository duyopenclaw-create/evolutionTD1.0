import SceneKit
import simd

/// A grey tabby at real size (~46 cm body, 25 cm at the shoulder).
final class CatModel {
    let node = SCNNode()
    let spine = SCNNode()
    let front = SCNNode(), rear = SCNNode()
    let neck = SCNNode(), head = SCNNode()
    private var upper: [SCNNode] = [], lower: [SCNNode] = []
    private var tail: [SCNNode] = []
    private var earL = SCNNode(), earR = SCNNode()
    private var lids: [SCNNode] = []
    private var t: Float = 0, gait: Float = 0
    let eyeMat: SCNMaterial

    init() {
        let fur = Mat.pbr(Tex.tabby())
        for p in [fur.diffuse, fur.roughness, fur.normal] { p.contentsTransform = SCNMatrix4MakeScale(1, 1, 1) }
        let pale = Mat.plain(color(0.72, 0.68, 0.6), rough: 0.9)
        let pink = Mat.plain(color(0.75, 0.5, 0.5), rough: 0.5)
        eyeMat = Mat.plain(.white, rough: 0.05)
        eyeMat.diffuse.contents = makePixelImage(128, 128) { x, y in
            // sphere UV: iris faces +z at u≈0.75
            let u = Float(x) / 128, v = Float(y) / 128
            let du = (u - 0.75) * 2.2, dv = (v - 0.5) * 1.1
            let r = sqrtf(du * du + dv * dv)
            if abs(du) < 0.035 * (1 - abs(dv) * 2.5) + 0.004 && abs(dv) < 0.3 { return SIMD4(0.01, 0.01, 0.01, 1) }   // slit pupil
            if r < 0.5 { let g = 0.6 + (0.5 - r); return SIMD4(0.55 * g, 0.62 * g, 0.12, 1) }
            return SIMD4(0.9, 0.85, 0.7, 1)
        }
        eyeMat.clearCoat.contents = NSNumber(value: 1)
        eyeMat.emission.contents = color(0.25, 0.35, 0.08)
        eyeMat.emission.intensity = 0.15

        node.addChildNode(spine)
        spine.simdPosition = SIMD3(0, 0.2, 0)
        spine.addChildNode(front)
        spine.addChildNode(rear)
        front.simdPosition = SIMD3(0, 0, 0.06)
        rear.simdPosition = SIMD3(0, 0, -0.06)

        func part(_ rx: Float, _ ry: Float, _ rz: Float, _ at: SIMD3<Float>, _ m: SCNMaterial, parent: SCNNode, fur furry: Bool = true, depth: Float = 0.07) -> SCNNode {
            let (n, g) = ellipsoid(rx, ry, rz, m)
            n.simdPosition = at
            parent.addChildNode(n)
            if furry { Fur.grow(on: n.childNodes[0], geo: g, base: m, depth: depth, repeatUV: 6) }
            return n
        }
        _ = part(0.07, 0.078, 0.14, SIMD3(0, 0.005, 0.02), fur, parent: front)
        _ = part(0.068, 0.08, 0.1, SIMD3(0, 0.005, 0.08), fur, parent: front)
        _ = part(0.05, 0.05, 0.1, SIMD3(0, -0.035, 0.06), pale, parent: front, depth: 0.08)         // chest ruff
        _ = part(0.074, 0.08, 0.12, SIMD3(0, 0.005, -0.04), fur, parent: rear)
        _ = part(0.08, 0.085, 0.08, SIMD3(0, 0.0, -0.1), fur, parent: rear)

        neck.simdPosition = SIMD3(0, 0.05, 0.15)
        front.addChildNode(neck)
        _ = part(0.045, 0.05, 0.06, SIMD3(0, 0.0, 0.02), fur, parent: neck)
        head.simdPosition = SIMD3(0, 0.05, 0.07)
        neck.addChildNode(head)
        _ = part(0.052, 0.046, 0.05, .zero, fur, parent: head)
        _ = part(0.028, 0.02, 0.024, SIMD3(0, -0.018, 0.04), pale, parent: head, depth: 0.1)             // muzzle
        _ = part(0.018, 0.012, 0.02, SIMD3(0, -0.034, 0.03), pale, parent: head, fur: false)            // chin
        let nose = SCNSphere(radius: 0.007)
        nose.materials = [pink]
        let nn = SCNNode(geometry: nose)
        nn.simdScale = SIMD3(1.2, 0.7, 0.8)
        nn.simdPosition = SIMD3(0, -0.006, 0.061)
        head.addChildNode(nn)
        for s in [-1, 1] as [Float] {
            let e = SCNSphere(radius: 0.0115)
            e.segmentCount = 24
            e.materials = [eyeMat]
            let en = SCNNode(geometry: e)
            en.simdPosition = SIMD3(s * 0.022, 0.008, 0.038)
            en.simdEulerAngles = SIMD3(0, s * 0.3, 0)
            head.addChildNode(en)
            // eyelid (closed when asleep)
            let lid = SCNSphere(radius: 0.0125)
            lid.materials = [fur]
            let ln = SCNNode(geometry: lid)
            ln.simdPosition = en.simdPosition
            ln.simdScale = SIMD3(1, 0.05, 1)
            head.addChildNode(ln)
            lids.append(ln)
            let ear = s < 0 ? earL : earR
            let c = SCNCone(topRadius: 0.003, bottomRadius: 0.024, height: 0.05)
            c.radialSegmentCount = 16
            c.materials = [fur]
            let cn = SCNNode(geometry: c)
            cn.simdScale = SIMD3(1, 1, 0.45)
            cn.simdPosition = SIMD3(0, 0.02, 0)
            ear.addChildNode(cn)
            let inner = SCNCone(topRadius: 0.002, bottomRadius: 0.017, height: 0.04)
            inner.materials = [pink]
            let inn = SCNNode(geometry: inner)
            inn.simdScale = SIMD3(1, 1, 0.2)
            inn.simdPosition = SIMD3(0, 0.018, 0.005)
            ear.addChildNode(inn)
            ear.simdPosition = SIMD3(s * 0.03, 0.032, -0.005)
            ear.simdEulerAngles = SIMD3(-0.1, 0, -s * 0.35)
            head.addChildNode(ear)
            // whiskers
            for i in 0..<5 {
                let len: Float = 0.06 + Float(i % 3) * 0.01
                let w = SCNCylinder(radius: 0.0003, height: CGFloat(len))
                w.radialSegmentCount = 3
                w.materials = [Mat.plain(color(0.9, 0.9, 0.88), rough: 0.3)]
                let wn = SCNNode(geometry: w)
                wn.pivot = SCNMatrix4MakeTranslation(0, CGFloat(-len / 2), 0)
                wn.simdPosition = SIMD3(s * 0.018, -0.016, 0.055)
                wn.simdEulerAngles = SIMD3(0.2 + Float(i - 2) * 0.1, 0, s * -1.35)
                wn.castsShadow = false
                head.addChildNode(wn)
            }
        }

        // legs: hip joint → upper → knee → lower → paw
        let hips: [(SCNNode, SIMD3<Float>)] = [(front, SIMD3(-0.04, -0.03, 0.1)), (front, SIMD3(0.04, -0.03, 0.1)),
                                               (rear, SIMD3(-0.045, -0.02, -0.1)), (rear, SIMD3(0.045, -0.02, -0.1))]
        for (i, (p, at)) in hips.enumerated() {
            let hind = i >= 2
            let hip = SCNNode()
            hip.simdPosition = at
            p.addChildNode(hip)
            let ul: Float = hind ? 0.09 : 0.085
            let up = SCNCapsule(capRadius: CGFloat(hind ? 0.03 : 0.022), height: CGFloat(ul + 0.03))
            up.materials = [fur]
            let un = SCNNode(geometry: up)
            un.simdPosition = SIMD3(0, -ul / 2, 0)
            hip.addChildNode(un)
            let knee = SCNNode()
            knee.simdPosition = SIMD3(0, -ul, 0)
            hip.addChildNode(knee)
            let ll: Float = hind ? 0.095 : 0.085
            let lo = SCNCapsule(capRadius: 0.015, height: CGFloat(ll))
            lo.materials = [fur]
            let ln = SCNNode(geometry: lo)
            ln.simdPosition = SIMD3(0, -ll / 2, 0)
            knee.addChildNode(ln)
            let paw = SCNSphere(radius: 1)
            paw.materials = [pale]
            let pn = SCNNode(geometry: paw)
            pn.simdScale = SIMD3(0.019, 0.012, 0.024)
            pn.simdPosition = SIMD3(0, -ll + 0.006, 0.008)
            knee.addChildNode(pn)
            upper.append(hip)
            lower.append(knee)
        }

        // tail
        var parent: SCNNode = rear
        var at = SIMD3<Float>(0, 0.03, -0.17)
        for i in 0..<12 {
            let k = Float(i) / 12
            let r = 0.017 * (1 - k * 0.45)
            let seg = SCNNode()
            seg.simdPosition = at
            parent.addChildNode(seg)
            let (e, g) = ellipsoid(r, r, 0.017, fur, segments: 14)
            e.simdPosition = SIMD3(0, 0, -0.013)
            seg.addChildNode(e)
            if i % 2 == 0 { Fur.grow(on: e.childNodes[0], geo: g, base: fur, depth: 0.25, repeatUV: 2) }
            tail.append(seg)
            parent = seg
            at = SIMD3(0, 0, -0.026)
        }
    }

    struct Pose {
        var speed: Float = 0
        var turn: Float = 0
        var crouch: Float = 0
        var sit: Float = 0
        var lie: Float = 0
        var leap: Float = 0
        var headYaw: Float = 0
        var headPitch: Float = 0
        var alert: Float = 0
        var eyesClosed: Float = 0
        var wiggle: Float = 0      // pre-pounce butt wiggle
        var reach: Float = 0       // paw swipe into a gap
    }
    private var s = Pose()

    func animate(_ dt: Float, _ p: Pose) {
        t += dt
        let k = min(1, dt * 6)
        s.crouch += (p.crouch - s.crouch) * min(1, dt * 8)
        s.sit += (p.sit - s.sit) * k
        s.lie += (p.lie - s.lie) * min(1, dt * 2.5)
        s.leap += (p.leap - s.leap) * min(1, dt * 16)
        s.headYaw += (p.headYaw - s.headYaw) * min(1, dt * 7)
        s.headPitch += (p.headPitch - s.headPitch) * min(1, dt * 7)
        s.alert += (p.alert - s.alert) * k
        s.eyesClosed += (p.eyesClosed - s.eyesClosed) * min(1, dt * 4)
        s.reach += (p.reach - s.reach) * min(1, dt * 10)

        let freq = 1.2 + p.speed * 1.6
        gait += dt * freq * (p.speed > 0.03 ? 1 : 0)
        let ph = gait * 2 * .pi
        let amp = min(0.55, p.speed * 0.5)
        let gallop = smoothstep(1.4, 2.4, p.speed)

        // spine height and pitch
        let wig = p.wiggle * sinf(t * 22) * 0.05
        let bodyY = 0.2 - s.crouch * 0.085 - s.lie * 0.13 - s.sit * 0.03 + abs(sinf(ph)) * 0.006 * min(1, p.speed)
        spine.simdPosition = SIMD3(0, bodyY, 0)
        spine.simdEulerAngles = SIMD3(-s.sit * 0.55 + s.crouch * 0.06 - s.leap * 0.1 + gallop * sinf(ph) * 0.08, wig * 0.3, p.turn * 0.05 + wig)
        // asleep: curled into a crescent, front and rear halves turned toward each other
        front.simdPosition = SIMD3(s.lie * 0.03, 0, 0.06 - s.lie * 0.01)
        front.simdEulerAngles = SIMD3(0, s.lie * 0.75, s.lie * 0.15)
        rear.simdPosition = SIMD3(s.lie * 0.03, 0, -0.06 + s.lie * 0.01)
        rear.simdEulerAngles = SIMD3(s.sit * 0.3, -s.lie * 0.75, s.lie * 0.15)
        for (i, hip) in upper.enumerated() {
            let fr = i < 2, left = i % 2 == 0
            // walk: lateral sequence; gallop: pairs
            let off: Float = mixf((left ? 0 : .pi) + (fr ? 0 : .pi / 2), (fr ? 0 : .pi) + (left ? 0 : 0.3), gallop)
            var a = sinf(ph + off) * amp * (1 + gallop * 0.6)
            var b = max(0, sinf(ph + off - 1.2)) * amp * 1.6 * (fr ? 1 : -1)
            // crouch: fold legs so paws stay planted
            a += s.crouch * (fr ? -0.7 : 0.9)
            b += s.crouch * (fr ? 1.3 : -1.6)
            // sit: hind legs folded under, front legs straight
            if !fr { a += s.sit * 1.1; b += s.sit * -2.2 }
            else { a += s.sit * 0.55 }
            // lying: tuck everything
            a = mixf(a, fr ? -1.35 : 1.4, s.lie)
            b = mixf(b, fr ? 2.5 : -2.6, s.lie)
            // leap: stretch out
            a = mixf(a, fr ? -1.0 : 0.9, s.leap)
            b = mixf(b, 0.1, s.leap)
            if fr && !left && s.reach > 0.01 { a = mixf(a, -1.4, s.reach); b = mixf(b, 0.2, s.reach) }
            hip.simdEulerAngles = SIMD3(a, 0, 0)
            lower[i].simdEulerAngles = SIMD3(b, 0, 0)
        }
        // head: look target, sniff bob, rest on paws when asleep
        let breathe = sinf(t * (p.lie > 0.5 ? 1.6 : 2.4)) * 0.01
        neck.simdEulerAngles = SIMD3(0.25 - s.headPitch * 0.5 + s.lie * 0.7 + s.crouch * 0.4, s.headYaw * 0.4 + s.lie * 0.9, 0)
        head.simdEulerAngles = SIMD3(-s.headPitch * 0.5 - s.lie * 0.4 + breathe - s.crouch * 0.3, s.headYaw * 0.6, s.lie * 0.4)
        spine.simdScale = SIMD3(1 + breathe * 2 * s.lie, 1 + breathe * 2, 1)
        let earTwitch = (sinf(t * 0.7) > 0.97 ? sinf(t * 40) * 0.3 : 0) as Float
        earL.simdEulerAngles = SIMD3(-0.1 - s.alert * 0.2, s.alert * 0.2 + earTwitch, 0.35 + s.lie * 0.3)
        earR.simdEulerAngles = SIMD3(-0.1 - s.alert * 0.2, -s.alert * 0.2, -0.35 - s.lie * 0.3)
        for l in lids { l.simdScale = SIMD3(1, 0.05 + s.eyesClosed * 0.95, 1) }
        // tail: lazy S-curve, lashing when hunting, wrapped when asleep, up when walking calmly
        for (i, seg) in tail.enumerated() {
            let k2 = Float(i) / Float(tail.count)
            let lash = sinf(t * (2 + s.alert * 5) - Float(i) * 0.5) * (0.06 + s.alert * 0.12)
            let yawT = lash * (1 - s.lie * 0.8) - s.lie * 0.3
            let upT = mixf(i == 0 ? 0.5 : -0.05 * k2, -0.08, s.alert) * (1 - s.lie) + s.lie * (i == 0 ? 0.9 : 0.02)
                + (p.speed > 0.3 && s.alert < 0.3 ? (i < 3 ? -0.35 : 0.05) : 0)
            seg.simdEulerAngles = SIMD3(-upT, yawT, 0)
        }
    }
}

/// The cat's brain: sleeps, wanders, hears, stalks, pounces, and waits outside hiding holes.
final class Cat {
    enum State { case sleeping, waking, wander, sit, investigate, stalk, chase, windup, leap, recover, waitHide, hop, groom }
    let model = CatModel()
    var pos: SIMD3<Float>
    var yaw: Float = 0
    var speed: Float = 0
    private(set) var state: State = .sleeping
    private var stateT: Float = 0
    var awareness: Float = 0
    var target = SIMD3<Float>.zero
    var lastSeen: SIMD3<Float>?
    private var seenT: Float = 99
    private var wanderGoal = SIMD3<Float>.zero
    private var awakeFor: Float = 0
    private var stuckT: Float = 0, sidestep: Float = 0
    private var lastPos = SIMD3<Float>.zero
    private var leapFrom = SIMD3<Float>.zero, leapTo = SIMD3<Float>.zero, leapDur: Float = 0.3, leapH: Float = 0.1
    private var rng = RNG(0xCA7)
    private var elevatedT: Float = 0
    var restless: Float = 0.3           // grows each night
    var yawRate: Float = 0
    private var reachT: Float = 0

    let radius: Float = 0.1
    let height: Float = 0.3

    enum Event { case meow, chatter, hiss, pounce, land, caught, wake, swipe, purrStart, mrrp }
    var events: [Event] = []

    init(bed: SIMD3<Float>) {
        pos = bed
        yaw = 2.4
    }

    var stateName: String {
        switch state {
        case .sleeping: return "ASLEEP"
        case .waking, .groom, .sit: return "AWAKE"
        case .wander: return "PROWLING"
        case .investigate: return "CURIOUS"
        case .stalk: return "STALKING"
        case .chase, .windup, .leap, .recover, .hop: return "HUNTING"
        case .waitHide: return "WAITING"
        }
    }
    var hunting: Bool { [.chase, .windup, .leap, .hop, .stalk].contains(state) }
    var danger: Float {
        switch state {
        case .chase, .windup, .leap, .hop: return 1
        case .stalk, .waitHide: return 0.65
        case .investigate: return 0.35
        default: return 0
        }
    }

    func reset(bed: SIMD3<Float>, restless r: Float) {
        pos = bed; yaw = 2.4; state = .sleeping; stateT = 0; awareness = 0; lastSeen = nil; speed = 0
        restless = r
        awakeFor = 0
    }

    private func go(_ s: State) {
        state = s
        stateT = 0
    }

    /// Hearing: loudness at source (0...1).
    func hear(_ loud: Float, at p: SIMD3<Float>) {
        let d = simd_distance(p, pos)
        let perceived = loud / (1 + d * d * 0.35)
        switch state {
        case .sleeping:
            if perceived > 0.2 - restless * 0.06 { go(.waking); events.append(.wake); target = p }
        case .wander, .sit, .groom, .waking, .investigate:
            if perceived > 0.045 { target = p; if state != .waking { go(.investigate) } }
            if perceived > 0.3 && d < 2.5 { awareness += 0.35 }
        case .waitHide, .stalk:
            if perceived > 0.1 { target = p }
        default: break
        }
    }

    func wakeAlarmed(at p: SIMD3<Float>) {
        if state == .sleeping { events.append(.wake) }
        target = p
        go(.investigate)
        awakeFor = 0
    }

    var eye: SIMD3<Float> {
        let f = SIMD3<Float>(sinf(yaw), 0, cosf(yaw))
        return pos + f * 0.3 + SIMD3(0, state == .sleeping ? 0.1 : 0.3, 0)
    }
    var forward: SIMD3<Float> { SIMD3(sinf(yaw), 0, cosf(yaw)) }

    struct Senses {
        var ratPos: SIMD3<Float>
        var ratVel: SIMD3<Float>
        var ratLight: Float
        var ratHidden: String?
        var ratInNest: Bool
        var ratGroundSolid: Int?
    }

    func update(_ dt: Float, world: CollisionWorld, kitchen: Kitchen, senses r: Senses, frozen: Bool) {
        stateT += dt
        if frozen { speed = 0; return }
        let toRat = r.ratPos - pos
        let dRat = simd_length(SIMD2(toRat.x, toRat.z))

        // --- sight
        var sees = false
        if state != .sleeping && r.ratHidden == nil && !r.ratInNest && dRat < 6.5 {
            let dir = simd_normalize(r.ratPos + SIMD3(0, 0.03, 0) - eye)
            let fov = simd_dot(SIMD3(dir.x, 0, dir.z) / max(0.001, simd_length(SIMD2(dir.x, dir.z))), forward)
            if fov > 0.3 || dRat < 0.45 {
                if world.visible(eye, r.ratPos + SIMD3(0, 0.035, 0)) {
                    let motion = min(1, simd_length(r.ratVel) / 0.8)
                    let vis = r.ratLight * (0.3 + 0.7 * motion) + (dRat < 0.6 ? 0.4 : 0)
                    awareness += dt * vis * 2.4 / (0.35 + dRat * 0.55)
                    if awareness > 0.3 { sees = true }
                }
            }
        }
        if sees { lastSeen = r.ratPos; seenT = 0 } else { seenT += dt; awareness = max(0, awareness - dt * 0.18) }
        awareness = min(awareness, 1.6)

        // --- decisions
        switch state {
        case .sleeping:
            speed = 0
        case .waking:
            speed = 0
            if stateT > 1.8 { go(target == .zero ? .wander : .investigate) }
        case .wander, .sit, .groom:
            awakeFor += dt
            if awareness > 1 { go(.chase); events.append(.mrrp) }
            else if awareness > 0.4 { go(.stalk); events.append(.chatter) }
            else if state == .wander {
                if simd_distance(SIMD2(pos.x, pos.z), SIMD2(wanderGoal.x, wanderGoal.z)) < 0.25 || stateT > 14 || wanderGoal == .zero {
                    if rng.chance(0.35) { go(rng.chance(0.5) ? .sit : .groom) }
                    else { wanderGoal = kitchen.catWaypoints[rng.int(kitchen.catWaypoints.count)]; stateT = 0 }
                    if rng.chance(0.12) { events.append(.meow) }
                }
                move(toward: wanderGoal, speed: 0.45, dt, world)
            } else {
                speed = 0
                if stateT > rng.range(4, 9) { go(.wander) }
                // bored and sleepy: back to bed
                if awakeFor > 70 + restless * 120 && rng.chance(dt * 0.1) { wanderGoal = kitchen.catBed; go(.wander); awakeFor = -1000 }
            }
            if awakeFor < -900 && simd_distance(SIMD2(pos.x, pos.z), SIMD2(kitchen.catBed.x, kitchen.catBed.z)) < 0.2 {
                go(.sleeping); awakeFor = 0; events.append(.purrStart)
            }
        case .investigate:
            if awareness > 1 { go(.chase); events.append(.mrrp); break }
            if awareness > 0.4 { go(.stalk); events.append(.chatter); break }
            let d = simd_distance(SIMD2(pos.x, pos.z), SIMD2(target.x, target.z))
            // a sound from up on the table or counter: jump up for a look
            if target.y > pos.y + 0.12 && d < 0.9, let si = world.ground(target.x, target.z, y: target.y + 0.01, r: 0.02, step: 0.02).2,
               canPerch(world.solids[si], from: pos) {
                beginHop(onto: world.solids[si], near: target, world: world)
                break
            }
            if d > 0.3 { move(toward: target, speed: 0.8, dt, world) } else { speed = 0 }
            if stateT > 9 || (d <= 0.3 && stateT > 3) { go(.sit) }
        case .stalk:
            // low and slow toward the rat; commits when close or sure
            let goal = lastSeen ?? target
            move(toward: goal, speed: 0.35, dt, world)
            if awareness > 1 || (sees && dRat < 0.9) { go(.chase); events.append(.mrrp) }
            if seenT > 3 { go(.investigate); target = goal }
        case .chase:
            let goal = sees ? r.ratPos : (lastSeen ?? target)
            let elevated = goal.y > pos.y + 0.12
            if elevated { elevatedT += dt } else { elevatedT = 0 }
            if elevated, elevatedT > 1.2, let si = r.ratGroundSolid, sees, dRat < 0.9, canPerch(world.solids[si], from: pos) {
                beginHop(onto: world.solids[si], near: r.ratPos, world: world)
                break
            }
            if !elevated && goal.y < pos.y - 0.2 && pos.y > 0.1 {
                // rat went back down: hop to the floor near it
                beginHop(down: goal, world: world)
                break
            }
            move(toward: goal, speed: 2.7, dt, world)
            if sees && dRat < 0.5 && abs(r.ratPos.y - pos.y) < 0.12 { go(.windup) }
            if r.ratHidden != nil, let ls = lastSeen, simd_distance(ls, pos) < 1.0 { go(.waitHide); target = ls }
            if seenT > 4 { go(.investigate); target = lastSeen ?? target; awareness = 0.3 }
        case .windup:
            speed = 0
            face(r.ratPos, dt, rate: 8)
            if stateT > 0.45 {
                leapFrom = pos
                let lead = r.ratPos + SIMD3(r.ratVel.x, 0, r.ratVel.z) * 0.22
                var dir = lead - pos; dir.y = 0
                // land so the forepaws (≈22 cm ahead of the hips) come down on the target
                let full = simd_length(dir)
                let len = min(max(0, full - 0.2), 0.7)
                if full > 0.001 { yaw = atan2f(dir.x, dir.z) }
                leapTo = pos + (full > 0.001 ? dir / full * len : .zero)
                leapTo.y = pos.y
                leapDur = 0.28; leapH = 0.1
                go(.leap)
                events.append(.pounce)
            }
        case .leap:
            let k = min(1, stateT / leapDur)
            var p = mix3(leapFrom, leapTo, k)
            p.y += sinf(k * .pi) * leapH
            pos = p
            _ = world.resolve(&pos, r: radius * 0.7, h: height * 0.6, step: 0.05)
            if k >= 1 {
                events.append(.land)
                let paws = pos + forward * 0.22
                let d = simd_distance(SIMD2(paws.x, paws.z), SIMD2(r.ratPos.x, r.ratPos.z))
                if d < 0.12 && abs(r.ratPos.y - pos.y) < 0.1 && r.ratHidden == nil && !r.ratInNest { events.append(.caught) }
                go(.recover)
            }
        case .recover:
            speed = 0
            if stateT > 0.9 { go(awareness > 0.5 ? .chase : .investigate) }
        case .hop:
            let k = min(1, stateT / leapDur)
            var p = mix3(leapFrom, leapTo, k)
            p.y = mixf(leapFrom.y, leapTo.y, k) + sinf(k * .pi) * leapH
            pos = p
            if k >= 1 { pos = leapTo; events.append(.land); go(awareness > 0.5 ? .chase : .investigate) }
        case .waitHide:
            // sit at the gap, stare in, swipe now and then, lose interest eventually
            face(target, dt, rate: 4)
            let d = simd_distance(SIMD2(pos.x, pos.z), SIMD2(target.x, target.z))
            if d > 0.35 { move(toward: target, speed: 0.6, dt, world) } else { speed = 0 }
            reachT -= dt
            if reachT < 0 && d < 0.5 { reachT = rng.range(2.5, 5); events.append(.swipe) }
            if stateT > 6 && rng.chance(dt * 0.1) { events.append(.hiss) }
            if r.ratHidden == nil && sees { go(.chase) }
            if stateT > 9 + restless * 6 { go(.wander); awareness = 0.2; wanderGoal = kitchen.catWaypoints[rng.int(kitchen.catWaypoints.count)] }
        }

        // stay on whatever we're standing on (cats don't walk off counters by accident)
        if state != .leap && state != .hop {
            let (g, _, _) = world.ground(pos.x, pos.z, y: pos.y, r: 0.06, step: 0.08)
            if g >= pos.y - 0.08 { pos.y = g }
        }
        lastPos = pos
    }

    private func canPerch(_ s: Solid, from p: SIMD3<Float>) -> Bool {
        guard s.perch, s.hi.y < 1.0, s.hi.y > p.y + 0.1 else { return false }
        return (s.hi.x - s.lo.x) > 0.25 && (s.hi.z - s.lo.z) > 0.25
    }

    private func beginHop(onto s: Solid, near: SIMD3<Float>, world: CollisionWorld) {
        leapFrom = pos
        var to = near
        to.x = clampf(to.x, s.lo.x + 0.12, s.hi.x - 0.12)
        to.z = clampf(to.z, s.lo.z + 0.12, s.hi.z - 0.12)
        // land a little short of the rat
        var d = to - pos; d.y = 0
        if simd_length(d) > 0.3 { to -= simd_normalize(d) * 0.18 }
        to.y = s.hi.y
        leapTo = to
        leapDur = 0.45; leapH = 0.2
        yaw = atan2f(d.x, d.z)
        go(.hop)
        events.append(.mrrp)
    }

    private func beginHop(down goal: SIMD3<Float>, world: CollisionWorld) {
        leapFrom = pos
        var d = goal - pos; d.y = 0
        let len = simd_length(d)
        var to = pos + (len > 0.01 ? simd_normalize(d) * min(len, 0.6) : forward * 0.5)
        to.y = 0
        var q = to
        _ = world.resolve(&q, r: radius, h: height, step: 0.06)
        to = SIMD3(q.x, 0, q.z)
        leapTo = to
        leapDur = 0.4; leapH = 0.08
        yaw = atan2f(d.x, d.z)
        go(.hop)
    }

    private func face(_ p: SIMD3<Float>, _ dt: Float, rate: Float) {
        let d = p - pos
        let target = atan2f(d.x, d.z)
        var dy = target - yaw
        while dy > .pi { dy -= 2 * .pi }
        while dy < -.pi { dy += 2 * .pi }
        let step = dy * min(1, dt * rate)
        yaw += step
        yawRate = step / max(dt, 1e-4)
    }

    private func move(toward goal: SIMD3<Float>, speed want: Float, _ dt: Float, _ world: CollisionWorld) {
        var d = goal - pos; d.y = 0
        let dist = simd_length(d)
        if dist < 0.05 { speed *= 0.8; return }
        var dir = d / dist
        if sidestep > 0 {
            sidestep -= dt
            dir = simd_normalize(dir + SIMD3(-dir.z, 0, dir.x) * 1.6)
        }
        let target = atan2f(dir.x, dir.z)
        var dy = target - yaw
        while dy > .pi { dy -= 2 * .pi }
        while dy < -.pi { dy += 2 * .pi }
        let turnRate: Float = want > 1.5 ? 7 : 4
        let step = dy * min(1, dt * turnRate)
        yaw += step
        yawRate = step / max(dt, 1e-4)
        let align = max(0.2, cosf(dy))
        speed += (want * align - speed) * min(1, dt * (want > 1.5 ? 5 : 3))
        let before = pos
        var p = pos + forward * speed * dt
        // don't walk off an elevated surface
        if pos.y > 0.1 {
            let (g, _, _) = world.ground(p.x, p.z, y: pos.y, r: 0.05, step: 0.05)
            if g < pos.y - 0.1 { speed = 0; return }
        }
        _ = world.resolve(&p, r: radius, h: height, step: 0.07)
        pos = p
        // stuck: moved much less than intended
        let moved = simd_length(SIMD2(pos.x - before.x, pos.z - before.z))
        if speed > 0.2 && moved < speed * dt * 0.3 { stuckT += dt } else { stuckT = max(0, stuckT - dt) }
        if stuckT > 0.5 { sidestep = 0.8; stuckT = 0 }
    }

    func pose() -> CatModel.Pose {
        var p = CatModel.Pose()
        p.speed = speed
        p.turn = yawRate
        switch state {
        case .sleeping: p.lie = 1; p.eyesClosed = 1
        case .waking: p.lie = max(0, 1 - stateT); p.eyesClosed = 0.5; p.alert = 0.3
        case .sit, .groom: p.sit = 1; p.headPitch = state == .groom ? -0.8 : 0.1
        case .stalk: p.crouch = 0.75; p.alert = 1
        case .windup: p.crouch = 1; p.alert = 1; p.wiggle = 1
        case .leap, .hop: p.leap = 1; p.alert = 1
        case .chase: p.alert = 1; p.crouch = 0.15
        case .waitHide: p.crouch = 0.8; p.alert = 0.8; p.reach = reachT > 0 && reachT > 2.1 ? 1 : 0
        case .investigate: p.alert = 0.5
        default: break
        }
        return p
    }
}
