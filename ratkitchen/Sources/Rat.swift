import SceneKit
import simd

/// A brown rat at life size (~20 cm head and body, 18 cm tail), built from primitives with shell fur.
final class RatModel {
    let node = SCNNode()           // feet position, yaw
    let pitch = SCNNode()          // rear-up / climb pitch about the hips
    let body = SCNNode()
    let head = SCNNode()
    let mouth = SCNNode()
    private var legs: [SCNNode] = []
    private var feet: [SCNNode] = []
    private var tail: [SCNNode] = []
    private let whiskersL = SCNNode(), whiskersR = SCNNode()
    private let earL = SCNNode(), earR = SCNNode()
    private var t: Float = 0
    private var gait: Float = 0
    private var tailYaw: [Float]
    private var sniffT: Float = 0

    init() {
        let fur = Mat.pbr(Tex.ratFur())
        for p in [fur.diffuse, fur.roughness, fur.normal] { p.contentsTransform = SCNMatrix4MakeScale(2, 2, 1) }
        let belly = Mat.plain(color(0.55, 0.5, 0.44), rough: 0.9)
        let pink = Mat.plain(color(0.78, 0.55, 0.52), rough: 0.55)
        let skin = Mat.plain(color(0.42, 0.33, 0.31), rough: 0.6)
        let eye = Mat.plain(color(0.01, 0.005, 0.005), rough: 0.03)
        eye.clearCoat.contents = NSNumber(value: 1)
        let whisker = Mat.plain(color(0.35, 0.33, 0.3), rough: 0.6)

        node.addChildNode(pitch)
        pitch.simdPosition = SIMD3(0, 0, -0.03)
        body.simdPosition = SIMD3(0, 0, 0.03)
        pitch.addChildNode(body)

        func part(_ rx: Float, _ ry: Float, _ rz: Float, _ at: SIMD3<Float>, _ m: SCNMaterial, furry: Bool, parent: SCNNode) -> SCNNode {
            let (n, g) = ellipsoid(rx, ry, rz, m)
            n.simdPosition = at
            parent.addChildNode(n)
            if furry { Fur.grow(on: n.childNodes[0], geo: g, base: m, depth: 0.12, repeatUV: 3) }
            return n
        }
        _ = part(0.031, 0.029, 0.062, SIMD3(0, 0.036, 0.01), fur, furry: true, parent: body)          // torso
        _ = part(0.036, 0.033, 0.042, SIMD3(0, 0.036, -0.035), fur, furry: true, parent: body)        // haunches
        _ = part(0.024, 0.014, 0.05, SIMD3(0, 0.02, 0.0), belly, furry: false, parent: body)          // pale belly

        head.simdPosition = SIMD3(0, 0.044, 0.058)
        body.addChildNode(head)
        _ = part(0.02, 0.019, 0.03, SIMD3(0, 0, 0.012), fur, furry: true, parent: head)
        _ = part(0.011, 0.0105, 0.022, SIMD3(0, -0.004, 0.036), fur, furry: true, parent: head)
        let nose = SCNSphere(radius: 0.0042)
        nose.materials = [pink]
        let nn = SCNNode(geometry: nose)
        nn.simdPosition = SIMD3(0, -0.003, 0.057)
        head.addChildNode(nn)
        for s in [-1, 1] as [Float] {
            let e = SCNSphere(radius: 0.0046)
            e.materials = [eye]
            let en = SCNNode(geometry: e)
            en.simdPosition = SIMD3(s * 0.0145, 0.006, 0.024)
            head.addChildNode(en)
            let ear = s < 0 ? earL : earR
            let eg = SCNSphere(radius: 1)
            eg.materials = [skin]
            let eh = SCNNode(geometry: eg)
            eh.simdScale = SIMD3(0.0078, 0.009, 0.002)
            ear.addChildNode(eh)
            ear.simdPosition = SIMD3(s * 0.014, 0.02, 0.0)
            ear.simdEulerAngles = SIMD3(-0.2, s * 0.5, s * 0.45)
            head.addChildNode(ear)
            // whiskers fan from the muzzle
            let w = s < 0 ? whiskersL : whiskersR
            w.simdPosition = SIMD3(s * 0.008, -0.004, 0.047)
            head.addChildNode(w)
            for i in 0..<7 {
                let len = 0.03 + Float(i % 4) * 0.007
                let c = SCNCylinder(radius: 0.00011, height: CGFloat(len))
                c.radialSegmentCount = 3
                c.materials = [whisker]
                let cn = SCNNode(geometry: c)
                cn.pivot = SCNMatrix4MakeTranslation(0, CGFloat(-len / 2), 0)
                let up = (Float(i) - 3) * 0.12
                cn.simdEulerAngles = SIMD3(up + 0.1, 0, 0)
                cn.simdEulerAngles = SIMD3(0.3 + up, 0, s * -1.25)
                cn.castsShadow = false
                w.addChildNode(cn)
            }
        }
        mouth.simdPosition = SIMD3(0, -0.012, 0.05)
        head.addChildNode(mouth)

        // legs: front pair under the chest, hind pair under the haunches
        let legPos: [SIMD3<Float>] = [SIMD3(-0.017, 0.026, 0.042), SIMD3(0.017, 0.026, 0.042), SIMD3(-0.024, 0.03, -0.04), SIMD3(0.024, 0.03, -0.04)]
        for (i, p) in legPos.enumerated() {
            let hip = SCNNode()
            hip.simdPosition = p
            body.addChildNode(hip)
            let hind = i >= 2
            let len: Float = hind ? 0.03 : 0.026
            let cap = SCNCapsule(capRadius: CGFloat(hind ? 0.0065 : 0.0048), height: CGFloat(len))
            cap.materials = [fur]
            let cn = SCNNode(geometry: cap)
            cn.simdPosition = SIMD3(0, -len / 2 + 0.003, 0)
            hip.addChildNode(cn)
            let f = SCNSphere(radius: 1)
            f.materials = [pink]
            let fnode = SCNNode(geometry: f)
            fnode.simdScale = hind ? SIMD3(0.0055, 0.0025, 0.013) : SIMD3(0.0045, 0.0022, 0.007)
            fnode.simdPosition = SIMD3(0, -len + 0.004, hind ? 0.006 : 0.003)
            hip.addChildNode(fnode)
            legs.append(hip)
            feet.append(fnode)
        }

        // tail: tapering scaly segments
        let scale = Mat.pbr(Tex.make(128, bump: 6) { u, v in
            let ring = sinf(v * 40 * .pi) * 0.5 + 0.5
            let c = Tex.lin(0.62, 0.5, 0.47) * (0.85 + ring * 0.2)
            return (c, 0.5 + ring * 0.1, ring)
        })
        var parent: SCNNode = body
        let segs = 15
        tailYaw = [Float](repeating: 0, count: segs)
        var at = SIMD3<Float>(0, 0.03, -0.072)
        for i in 0..<segs {
            let k = Float(i) / Float(segs)
            let r = 0.0055 * (1 - k * 0.75)
            let len: Float = 0.0125
            let seg = SCNNode()
            seg.simdPosition = at
            parent.addChildNode(seg)
            let c = SCNCylinder(radius: CGFloat(r), height: CGFloat(len + 0.001))
            c.radialSegmentCount = 10
            c.materials = [scale]
            let cn = SCNNode(geometry: c)
            cn.simdEulerAngles.x = .pi / 2
            cn.simdPosition = SIMD3(0, 0, -len / 2)
            seg.addChildNode(cn)
            let jn = SCNSphere(radius: CGFloat(r))
            jn.segmentCount = 10
            jn.materials = [scale]
            seg.addChildNode(SCNNode(geometry: jn))
            tail.append(seg)
            parent = seg
            at = SIMD3(0, 0, -len)
        }
    }

    struct Pose {
        var speed: Float = 0        // m/s over the ground
        var turn: Float = 0         // yaw rate
        var climbing = false
        var rear: Float = 0         // 0 on all fours → 1 standing on hind legs
        var eating = false
        var crouch: Float = 0       // squeezing under something
        var airborne = false
        var vy: Float = 0
        var sniffing = false
    }
    private var sRear: Float = 0, sClimb: Float = 0, sCrouch: Float = 0, sEat: Float = 0, sAir: Float = 0

    func animate(_ dt: Float, _ p: Pose) {
        t += dt
        let k = min(1, dt * 10)
        sRear += ((p.rear) - sRear) * k
        sClimb += ((p.climbing ? 1 : 0) - sClimb) * min(1, dt * 14)
        sCrouch += (p.crouch - sCrouch) * k
        sEat += ((p.eating ? 1 : 0) - sEat) * k
        sAir += ((p.airborne ? 1 : 0) - sAir) * min(1, dt * 12)

        // stride frequency scales with speed; rats bound when fast
        let freq = 3 + p.speed * 7.5
        gait += dt * freq * (p.speed > 0.02 || p.climbing ? 1 : 0)
        let ph = gait * 2 * .pi
        let amp = min(0.9, p.speed * 1.4) + (p.climbing && p.speed > 0.01 ? 0.5 : 0)
        let bound = smoothstep(1.1, 1.8, p.speed)
        for (i, leg) in legs.enumerated() {
            let front = i < 2, left = i % 2 == 0
            // trot: diagonal pairs; bound: front pair vs hind pair
            let trotOff: Float = (front == left) ? 0 : .pi
            let boundOff: Float = front ? 0 : .pi + (left ? 0 : 0.35)
            let off = mixf(trotOff, boundOff, bound)
            var swing = sinf(ph + off) * amp
            if sAir > 0.5 { swing = front ? -0.7 : 0.8 }
            if front && sEat > 0.1 { swing = mixf(swing, -1.3, sEat) }         // hands up to the mouth
            if front && sRear > 0.1 { swing = mixf(swing, -1.0, sRear) }
            leg.simdEulerAngles = SIMD3(swing, 0, 0)
        }
        // bob and sway
        let bob = abs(sinf(ph)) * 0.003 * min(1, p.speed * 2) + bound * sinf(ph) * 0.004
        body.simdPosition = SIMD3(0, bob - sCrouch * 0.012, 0.03)
        body.simdScale = SIMD3(1, 1 - sCrouch * 0.18, 1 + sCrouch * 0.06)

        // pitch: climb (nose up to vertical), rear up, eat sit, airborne tilt
        var pitchX: Float = -sClimb * (.pi / 2)
        pitchX -= sRear * 1.05 * (1 - sClimb)
        pitchX -= sEat * 0.55 * (1 - sClimb)
        pitchX += sAir * max(-0.4, min(0.4, -p.vy * 0.12)) * (1 - sClimb)
        pitch.simdEulerAngles = SIMD3(pitchX, 0, -p.turn * 0.04)
        pitch.simdPosition = SIMD3(0, sClimb * 0.035, -0.03 * (1 - sClimb))

        // head: sniff twitch, chew nod, look into the turn
        sniffT += dt
        let twitch = sinf(t * 38) * 0.03 + sinf(t * 17) * 0.02
        let idle = p.speed < 0.05 ? 1 : 0.3
        let chew = sEat * sinf(t * 28) * 0.08
        let look = sinf(t * 0.9) * 0.25 * (p.speed < 0.05 && !p.eating ? 1 : 0)
        head.simdEulerAngles = SIMD3(twitch * Float(idle) + chew + sEat * 0.5 + sRear * 0.6 - (p.sniffing ? 0.2 : 0),
                                     p.turn * 0.08 + look, 0)
        // whisking at ~8 Hz when exploring, faster when sniffing
        let whisk = sinf(t * (p.sniffing ? 55 : 48)) * (p.sniffing ? 0.35 : 0.18) * Float(idle)
        whiskersL.simdEulerAngles = SIMD3(0, -whisk, 0)
        whiskersR.simdEulerAngles = SIMD3(0, whisk, 0)
        earL.simdEulerAngles.x = -0.2 + sinf(t * 3.1) * 0.05
        earR.simdEulerAngles.x = -0.2 + sinf(t * 2.7 + 1) * 0.05

        // tail: travelling wave, lags turns, hangs when climbing, lifts for balance when running
        for (i, s) in tail.enumerated() {
            let k2 = Float(i) / Float(tail.count)
            let target = sinf(t * (2 + p.speed * 4) - Float(i) * 0.45) * (0.08 + 0.1 * k2) - p.turn * 0.05 * (1 + k2)
            tailYaw[i] += (target - tailYaw[i]) * min(1, dt * 8)
            let droop: Float = sClimb > 0.5 ? 0.08 * (1 - k2) : (i < 3 ? 0.18 : -0.035 + (p.speed > 1.2 ? 0.02 : 0))
            s.simdEulerAngles = SIMD3(droop, tailYaw[i], 0)
        }
    }
}

/// Rat physics and state. Units: metres, seconds.
final class Rat {
    let model = RatModel()
    var pos = SIMD3<Float>(0, 0, 0)
    var vel = SIMD3<Float>.zero
    var yaw: Float = 0
    var grounded = true
    var surface: Surface = .tile
    var climbing: (index: Int, normal: SIMD3<Float>)? = nil
    var stamina: Float = 1
    var belly: Float = 0.6
    var carrying: Food?
    var yawRate: Float = 0
    var crouch: Float = 0
    var rear: Float = 0
    var lastLandSpeed: Float = 0
    var stepDist: Float = 0

    let radius: Float = 0.034
    let height: Float = 0.058
    let stepUp: Float = 0.022
    static let jumpSpeed: Float = 3.3            // ≈ 0.55 m hop

    enum Event { case step(Surface, Float), land(Surface, Float), jump, climbStart(Surface), climbStep(Surface), mantle, bump(Int, SIMD3<Float>) }
    var events: [Event] = []

    struct Control {
        var move = SIMD2<Float>.zero      // x right, y forward, camera-relative (already rotated to world xz)
        var raw = SIMD2<Float>.zero       // keys as pressed, for climbing
        var dash = false
        var creep = false
        var jump = false
    }

    func step(_ dt: Float, _ c: Control, world: CollisionWorld, frozen: Bool) {
        if frozen { vel = .zero; return }
        let prevYaw = yaw
        if let cl = climbing {
            climb(dt, c, world: world, cl: cl)
        } else {
            walk(dt, c, world: world)
        }
        var d = yaw - prevYaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        yawRate += (d / max(dt, 1e-4) - yawRate) * min(1, dt * 10)
    }

    private func walk(_ dt: Float, _ c: Control, world: CollisionWorld) {
        let slowFromLoad: Float = carrying != nil ? 0.82 : 1
        let dashing = c.dash && stamina > 0.02 && c.move != .zero && !c.creep
        let top: Float = (c.creep ? 0.3 : dashing ? 2.3 : 1.05) * slowFromLoad
        let want = SIMD3<Float>(c.move.x, 0, c.move.y) * top
        let accel: Float = grounded ? (dashing ? 11 : 13) : 3
        var hv = SIMD3<Float>(vel.x, 0, vel.z)
        let dv = want - hv
        let maxDv = accel * dt
        hv += simd_length(dv) > maxDv ? simd_normalize(dv) * maxDv : dv
        vel.x = hv.x; vel.z = hv.z
        if dashing { stamina = max(0, stamina - dt * 0.2) } else { stamina = min(1, stamina + dt * (belly > 0.02 ? 0.14 : 0.03)) }

        let spd = simd_length(hv)
        if spd > 0.05 {
            let target = atan2f(hv.x, hv.z)
            var dy = target - yaw
            while dy > .pi { dy -= 2 * .pi }
            while dy < -.pi { dy += 2 * .pi }
            yaw += dy * min(1, dt * 14)
        }

        if c.jump && grounded {
            vel.y = Rat.jumpSpeed * (c.creep ? 0.7 : 1)
            grounded = false
            events.append(.jump)
        }
        if !grounded { vel.y -= 9.81 * dt }
        pos += vel * dt

        // ceiling (squeezing under the stove, bumping a table from below)
        let ceil = world.ceiling(pos.x, pos.z, y: pos.y + 0.005, r: radius * 0.6)
        crouch = clampf((pos.y + height + 0.02 - ceil) / 0.03, 0, 1)
        if pos.y + height * (1 - 0.3 * crouch) > ceil {
            // leaping up under a lip (counter overhang, table edge): grab it and scramble over
            if !grounded, vel.y > 0, let i = world.ceilingSolid(pos.x, pos.z, y: pos.y + 0.005, r: radius * 0.6), grabLip(world.solids[i], world: world) {
                return
            }
            pos.y = ceil - height * 0.7
            if vel.y > 0 { vel.y = 0 }
        }

        let contacts = world.resolve(&pos, r: radius, h: height * 0.8, step: stepUp)
        for ct in contacts {
            // remove velocity into the wall
            let into = simd_dot(vel, ct.normal)
            if into < 0 { vel -= ct.normal * into }
            events.append(.bump(ct.index, ct.normal))
            let s = world.solids[ct.index]
            let pushing = simd_dot(SIMD3(c.move.x, 0, c.move.y), -ct.normal) > 0.55
            if s.climbable && pushing && pos.y < s.hi.y - 0.04 && (grounded || vel.y < 1.5) {
                climbing = (ct.index, ct.normal)
                yaw = atan2f(-ct.normal.x, -ct.normal.z)
                vel = .zero
                grounded = false
                events.append(.climbStart(s.surface))
                return
            }
        }

        let (g, surf, _) = world.ground(pos.x, pos.z, y: pos.y, r: radius * 0.55, step: stepUp + (grounded ? 0.02 : 0))
        if grounded {
            if g < pos.y - 0.03 {
                grounded = false            // walked off an edge
            } else {
                pos.y = g
                vel.y = 0
                surface = surf
            }
        } else if pos.y <= g && vel.y <= 0 {
            lastLandSpeed = -vel.y
            pos.y = g
            vel.y = 0
            grounded = true
            surface = surf
            events.append(.land(surf, lastLandSpeed))
        }

        if grounded {
            stepDist += spd * dt
            let stride: Float = dashing ? 0.07 : 0.045
            if stepDist > stride {
                stepDist = 0
                events.append(.step(surf, c.creep ? 0.15 : dashing ? 1 : 0.5))
            }
        }
    }

    private func climb(_ dt: Float, _ c: Control, world: CollisionWorld, cl: (index: Int, normal: SIMD3<Float>)) {
        let s = world.solids[cl.index]
        let n = cl.normal
        let side = SIMD3<Float>(n.z, 0, -n.x)         // right along the face when looking at it
        let tired = stamina < 0.02
        let speed: Float = (c.dash && !tired ? 0.75 : 0.42) * (tired ? 0.4 : 1)
        var up = c.raw.y * speed
        if tired && c.raw.y <= 0 { up = -0.15 }
        let lateral = c.raw.x * speed * 0.6
        stamina = max(0, stamina - dt * (c.dash ? 0.14 : 0.05))

        pos.y += up * dt
        pos += side * lateral * dt
        // stay on the face
        let faceLo = s.lo, faceHi = s.hi
        if abs(n.x) > 0.5 {
            pos.x = n.x > 0 ? faceHi.x + 0.012 : faceLo.x - 0.012
            pos.z = clampf(pos.z, faceLo.z + 0.004, faceHi.z - 0.004)
        } else {
            pos.z = n.z > 0 ? faceHi.z + 0.012 : faceLo.z - 0.012
            pos.x = clampf(pos.x, faceLo.x + 0.004, faceHi.x - 0.004)
        }
        yaw = atan2f(-n.x, -n.z)
        vel = SIMD3(0, up, 0)
        if abs(up) > 0.05 || abs(lateral) > 0.05 {
            stepDist += dt * max(abs(up), abs(lateral))
            if stepDist > 0.04 { stepDist = 0; events.append(.climbStep(s.surface)) }
        }

        // top: mantle onto whatever surface is above and just inside
        if pos.y >= s.hi.y - 0.015 {
            var best: SIMD3<Float>? = nil
            for off in [0.03, 0.05, 0.07, 0.09, 0.11, 0.13, 0.15] as [Float] {
                let q = pos - n * (off + 0.012)
                let (g, _, _) = world.ground(q.x, q.z, y: s.hi.y + 0.01, r: 0.015, step: 0.16)
                if g >= s.hi.y - 0.02 && !world.blocked(SIMD3(q.x, g, q.z), r: radius * 0.8, h: height * 0.8) && (best == nil || g > best!.y + 0.01) { best = SIMD3(q.x, g, q.z) }
            }
            if best == nil {
                for side2 in [0.05, -0.05, 0.09, -0.09] as [Float] {
                    let sideDir = SIMD3<Float>(n.z, 0, -n.x)
                    for off in [0.05, 0.09] as [Float] {
                        let q = pos - n * (off + 0.012) + sideDir * side2
                        let (g, _, _) = world.ground(q.x, q.z, y: s.hi.y + 0.01, r: 0.015, step: 0.16)
                        if g >= s.hi.y - 0.02 && !world.blocked(SIMD3(q.x, g, q.z), r: radius * 0.8, h: height * 0.8) { best = SIMD3(q.x, g, q.z); break }
                    }
                    if best != nil { break }
                }
            }
            if let b = best {
                pos = b
                climbing = nil
                grounded = true
                vel = .zero
                events.append(.mantle)
                return
            }
            pos.y = s.hi.y - 0.015
        }
        // bottom: step off onto the floor
        let (g, surf, _) = world.ground(pos.x + n.x * 0.03, pos.z + n.z * 0.03, y: pos.y, r: radius * 0.5, step: 0.01)
        if pos.y <= g + 0.002 && up <= 0 {
            pos += n * 0.03
            pos.y = g
            climbing = nil
            grounded = true
            surface = surf
            return
        }
        if c.jump {
            // kick off backwards
            climbing = nil
            vel = n * 1.3 + SIMD3(0, 1.6, 0)
            pos += n * 0.02
            yaw = atan2f(n.x, n.z)
            grounded = false
            events.append(.jump)
        }
    }

    /// If the rat is within a whisker of an edge of `s` and its top is in reach, pop onto the top.
    private func grabLip(_ s: Solid, world: CollisionWorld) -> Bool {
        guard s.perch, s.hi.y - pos.y < 0.2 else { return false }
        let inset: [(Float, SIMD3<Float>)] = [
            (pos.x - s.lo.x, SIMD3(1, 0, 0)), (s.hi.x - pos.x, SIMD3(-1, 0, 0)),
            (pos.z - s.lo.z, SIMD3(0, 0, 1)), (s.hi.z - pos.z, SIMD3(0, 0, -1)),
        ]
        guard let (d, inward) = inset.min(by: { $0.0 < $1.0 }), d < 0.07 else { return false }
        var q = pos + inward * (0.05 - d + 0.02)
        let (g, surf, _) = world.ground(q.x, q.z, y: s.hi.y + 0.01, r: 0.015, step: 0.05)
        guard g >= s.hi.y - 0.01 else { return false }
        q.y = g
        pos = q
        vel = .zero
        grounded = true
        surface = surf
        events.append(.mantle)
        return true
    }

    var mouthWorld: SIMD3<Float> {
        let f = SIMD3<Float>(sinf(yaw), 0, cosf(yaw))
        if climbing != nil { return pos + SIMD3(0, 0.12, 0) }
        return pos + f * 0.11 + SIMD3(0, 0.02, 0)
    }

    var forward: SIMD3<Float> { SIMD3(sinf(yaw), 0, cosf(yaw)) }
}
