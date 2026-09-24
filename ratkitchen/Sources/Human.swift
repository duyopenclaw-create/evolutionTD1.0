import SceneKit
import simd

/// A person in pyjamas and slippers who comes down for a midnight snack.
final class HumanModel {
    let node = SCNNode()
    let hips = SCNNode()
    let torso = SCNNode()
    let head = SCNNode()
    private(set) var legs: [(hip: SCNNode, knee: SCNNode)] = []
    private(set) var arms: [(sh: SCNNode, el: SCNNode)] = []
    private var t: Float = 0, gait: Float = 0

    init() {
        let pj = Mat.pbr(Tex.pajamas())
        for p in [pj.diffuse, pj.roughness, pj.normal] { p.contentsTransform = SCNMatrix4MakeScale(3, 3, 1) }
        let tee = Mat.pbr(Tex.cloth { _, _ in Tex.lin(0.45, 0.46, 0.48) })
        let skin = Mat.plain(color(0.78, 0.6, 0.5), rough: 0.55)
        let hair = Mat.plain(color(0.12, 0.08, 0.06), rough: 0.6)
        let slipper = Mat.pbr(Tex.plush(Tex.lin(0.35, 0.22, 0.16)))

        node.addChildNode(hips)
        hips.simdPosition = SIMD3(0, 0.92, 0)
        func capsule(_ r: Float, _ h: Float, _ m: SCNMaterial, _ at: SIMD3<Float>, parent: SCNNode) -> SCNNode {
            let c = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(h))
            c.radialSegmentCount = 20
            c.materials = [m]
            let n = SCNNode(geometry: c)
            n.simdPosition = at
            parent.addChildNode(n)
            return n
        }
        let pelvis = capsule(0.15, 0.36, pj, SIMD3(0, 0.02, 0), parent: hips)
        pelvis.simdEulerAngles.z = .pi / 2
        pelvis.simdScale = SIMD3(1, 1, 0.75)
        for s in [-1, 1] as [Float] {
            let hip = SCNNode()
            hip.simdPosition = SIMD3(s * 0.1, 0, 0)
            hips.addChildNode(hip)
            _ = capsule(0.085, 0.46, pj, SIMD3(0, -0.22, 0), parent: hip)
            let knee = SCNNode()
            knee.simdPosition = SIMD3(0, -0.44, 0)
            hip.addChildNode(knee)
            _ = capsule(0.068, 0.46, pj, SIMD3(0, -0.22, 0), parent: knee)
            let ankle = capsule(0.04, 0.1, skin, SIMD3(0, -0.42, 0), parent: knee)
            _ = ankle
            let sl = texturedBox(0.11, 0.07, 0.28, slipper, span: 0.3, chamfer: 0.035)
            sl.simdPosition = SIMD3(0, -0.45, 0.06)
            knee.addChildNode(sl)
            legs.append((hip, knee))
        }
        torso.simdPosition = SIMD3(0, 0.08, 0)
        hips.addChildNode(torso)
        let chest = capsule(0.17, 0.62, tee, SIMD3(0, 0.3, 0), parent: torso)
        chest.simdScale = SIMD3(1.05, 1, 0.68)
        let neck = capsule(0.05, 0.12, skin, SIMD3(0, 0.64, 0), parent: torso)
        _ = neck
        head.simdPosition = SIMD3(0, 0.8, 0.01)
        torso.addChildNode(head)
        let skull = SCNSphere(radius: 0.105)
        skull.materials = [skin]
        let sk = SCNNode(geometry: skull)
        sk.simdScale = SIMD3(0.9, 1.1, 1)
        head.addChildNode(sk)
        let hr = SCNSphere(radius: 0.112)
        hr.materials = [hair]
        let hn = SCNNode(geometry: hr)
        hn.simdScale = SIMD3(0.93, 1.02, 1.03)
        hn.simdPosition = SIMD3(0, 0.03, -0.012)
        head.addChildNode(hn)
        for s in [-1, 1] as [Float] {
            let sh = SCNNode()
            sh.simdPosition = SIMD3(s * 0.2, 0.52, 0)
            torso.addChildNode(sh)
            _ = capsule(0.055, 0.3, tee, SIMD3(0, -0.12, 0), parent: sh)
            let el = SCNNode()
            el.simdPosition = SIMD3(0, -0.28, 0)
            sh.addChildNode(el)
            _ = capsule(0.042, 0.28, skin, SIMD3(0, -0.13, 0), parent: el)
            let hand = SCNSphere(radius: 0.045)
            hand.materials = [skin]
            let hd = SCNNode(geometry: hand)
            hd.simdScale = SIMD3(0.7, 1.1, 0.9)
            hd.simdPosition = SIMD3(0, -0.3, 0)
            el.addChildNode(hd)
            arms.append((sh, el))
        }
        node.isHidden = true
    }

    struct Pose { var speed: Float = 0; var stompLeg = -1; var stomp: Float = 0; var reach: Float = 0; var lookDown: Float = 0 }

    func animate(_ dt: Float, _ p: Pose) {
        t += dt
        gait += dt * (p.speed > 0.05 ? 0.9 + p.speed * 0.6 : 0)
        let ph = gait * 2 * .pi
        let amp = min(0.45, p.speed * 0.4)
        for (i, l) in legs.enumerated() {
            let off: Float = i == 0 ? 0 : .pi
            var a = sinf(ph + off) * amp
            var b = max(0, sinf(ph + off - 1.3)) * amp * 1.5
            if i == p.stompLeg {
                // knee up, then slam
                a = -p.stomp * 1.1
                b = p.stomp * 1.3
            }
            l.hip.simdEulerAngles = SIMD3(a, 0, 0)
            l.knee.simdEulerAngles = SIMD3(b, 0, 0)
        }
        let bob = abs(sinf(ph)) * 0.02 * min(1, p.speed)
        hips.simdPosition = SIMD3(0, 0.92 + bob - (p.stompLeg >= 0 ? 0.0 : 0), 0)
        torso.simdEulerAngles = SIMD3(p.lookDown * 0.35, 0, 0)
        head.simdEulerAngles = SIMD3(p.lookDown * 0.5, 0, 0)
        for (i, a) in arms.enumerated() {
            let off: Float = i == 0 ? .pi : 0
            var s = sinf(ph + off) * amp * 0.8
            var e: Float = -0.15
            if i == 1 && p.reach > 0 { s = mixf(s, -1.3, p.reach); e = mixf(e, -0.3, p.reach) }
            a.sh.simdEulerAngles = SIMD3(s, 0, (i == 0 ? -1 : 1) * 0.06)
            a.el.simdEulerAngles = SIMD3(e, 0, 0)
        }
    }
}

/// The midnight-snack visit, as a little state machine the game drives.
final class Human {
    enum Phase { case away, approaching, entering, atFridge, leaving, alarmed, stomping, gone }
    let model = HumanModel()
    private(set) var phase: Phase = .away
    private(set) var phaseT: Float = 0
    var pos = SIMD3<Float>(-4.2, 0, 1.05)
    var yaw: Float = .pi / 2
    var speed: Float = 0
    var spotted: Float = 0
    var lightsOn: Float = 0          // 0…1, driven here
    var fridgeOpen: Float = 0
    var stompCount = 0
    var sawRat = false
    private var path: [SIMD3<Float>] = []
    private var stompLeg = 0, stompT: Float = -1
    private var stompAt = SIMD3<Float>.zero
    private var stepAcc: Float = 0
    private var pose = HumanModel.Pose()

    enum Event { case footstep(SIMD3<Float>, Float), lightSwitch, lightsOn, lightsOff, fridgeOpen, fridgeClose, bottles, yell, stomp(SIMD3<Float>), gone, grumble }
    var events: [Event] = []

    var active: Bool { phase != .away && phase != .gone }
    var inRoom: Bool { [.entering, .atFridge, .leaving, .alarmed, .stomping].contains(phase) }

    func begin() {
        guard phase == .away || phase == .gone else { return }
        phase = .approaching
        phaseT = 0
        pos = SIMD3(-5.4, 0, 1.05)
        yaw = .pi / 2
        spotted = 0
        stompCount = 0
        sawRat = false
        model.node.isHidden = false
    }

    private func go(_ p: Phase) { phase = p; phaseT = 0 }

    /// - Returns: foot position for the current stomp when it lands (for the hit test).
    func update(_ dt: Float, kitchen: Kitchen, rat: SIMD3<Float>, ratVisible: Bool, ratHidden: Bool) {
        phaseT += dt
        pose = HumanModel.Pose()
        switch phase {
        case .away, .gone:
            lightsOn = max(0, lightsOn - dt * 2)
            return
        case .approaching:
            walk(toward: SIMD3(-3.4, 0, 1.05), speed: 0.9, dt)
            kitchen.hallLight.light?.intensity = CGFloat(min(1, phaseT / 0.3)) * 380
            kitchen.hallBulb.emission.intensity = CGFloat(min(1, phaseT / 0.3)) * 3
            if simd_distance(pos, SIMD3(-3.4, 0, 1.05)) < 0.1 {
                events.append(.lightSwitch)
                go(.entering)
                path = [SIMD3(-2.2, 0, 0.6), SIMD3(-0.9, 0, -0.55), kitchen.fridgeFront + SIMD3(-0.25, 0, 0.1)]
            }
        case .entering:
            // lights flicker on
            let f: Float = phaseT < 0.08 ? 1 : phaseT < 0.16 ? 0.1 : phaseT < 0.22 ? 1 : phaseT < 0.3 ? 0.3 : 1
            lightsOn = f
            if phaseT > 0.3 && phaseT - dt <= 0.3 { events.append(.lightsOn) }
            if phaseT > 0.6 {
                if followPath(dt, speed: 1.0) { go(.atFridge); yaw = .pi; events.append(.fridgeOpen) }
            }
        case .atFridge:
            speed = 0
            yaw += (.pi * 1.0 - yaw) * min(1, dt * 4)
            fridgeOpen = min(1, phaseT / 0.8)
            if phaseT > 4.2 { fridgeOpen = max(0, 1 - (phaseT - 4.2) / 0.6) }
            if phaseT > 1.2 && phaseT - dt <= 1.2 { events.append(.bottles) }
            pose.reach = phaseT > 0.8 && phaseT < 4 ? 1 : 0
            if phaseT > 4.8 {
                fridgeOpen = 0
                events.append(.fridgeClose)
                go(.leaving)
                path = [SIMD3(-0.9, 0, -0.55), SIMD3(-2.2, 0, 0.6), SIMD3(-3.4, 0, 1.05), SIMD3(-5.4, 0, 1.05)]
            }
        case .leaving:
            if pos.x < -3.2 && lightsOn > 0 {
                if lightsOn >= 1 { events.append(.lightSwitch); events.append(.lightsOff) }
                lightsOn = 0
            }
            if followPath(dt, speed: 1.0) {
                model.node.isHidden = true
                kitchen.hallLight.light?.intensity = 0
                kitchen.hallBulb.emission.intensity = 0
                go(.gone)
                events.append(.gone)
            }
        case .alarmed:
            speed = 0
            face(rat, dt)
            pose.lookDown = 1
            if phaseT > 0.9 { go(.stomping); stompT = -1 }
        case .stomping:
            pose.lookDown = 1
            let elevated = rat.y > 0.3
            if ratHidden || elevated || stompCount >= 3 || phaseT > 12 {
                if phaseT > 1 {
                    events.append(.grumble)
                    fridgeOpen = 0
                    go(.leaving)
                    path = [SIMD3(-2.2, 0, 0.6), SIMD3(-3.4, 0, 1.05), SIMD3(-5.4, 0, 1.05)]
                }
                break
            }
            if stompT < 0 {
                let d = simd_distance(SIMD2(pos.x, pos.z), SIMD2(rat.x, rat.z))
                if d > 0.32 { walk(toward: rat, speed: 1.3, dt) }
                else { speed = 0; stompT = 0; stompLeg = stompCount % 2; face(rat, dt) }
            } else {
                stompT += dt
                speed = 0
                // lift 0.5 s, aim, slam in 0.1 s
                if stompT < 0.5 {
                    pose.stomp = stompT / 0.5
                    stompAt = rat
                    // step so the raised slipper hangs over the target
                    let f = SIMD3<Float>(sinf(yaw), 0, cosf(yaw)), side = SIMD3<Float>(cosf(yaw), 0, -sinf(yaw))
                    let want = stompAt - f * 0.06 - side * (stompLeg == 0 ? -0.1 : 0.1)
                    pos += (SIMD3(want.x, 0, want.z) - pos) * min(1, dt * 6)
                }
                else if stompT < 0.6 { pose.stomp = 1 - (stompT - 0.5) / 0.1 }
                else {
                    pose.stomp = 0
                    if stompT - dt < 0.6 { events.append(.stomp(stompAt)); stompCount += 1 }
                    if stompT > 1.1 { stompT = -1 }
                }
                pose.stompLeg = stompLeg
            }
        }

        // spotting: in the room, lights on, rat visible
        if inRoom && phase != .alarmed && phase != .stomping {
            if ratVisible && !ratHidden {
                let d = simd_distance(pos, rat)
                spotted += dt * (0.9 / (0.6 + d * 0.6)) * lightsOn
            } else {
                spotted = max(0, spotted - dt * 0.3)
            }
            if spotted >= 1 && !sawRat {
                sawRat = true
                events.append(.yell)
                go(.alarmed)
            }
        }
        pose.speed = speed
        model.node.simdPosition = pos
        model.node.simdEulerAngles = SIMD3(0, yaw, 0)
        model.animate(dt, pose)
        kitchen.fridgeDoor.simdEulerAngles.y = -fridgeOpen * 1.75
        kitchen.fridgeLight.light?.intensity = CGFloat(fridgeOpen) * 90
    }

    /// Where the stomping foot is, relative to the target it was aimed at.
    var stompFoot: SIMD3<Float> { stompAt }

    var eye: SIMD3<Float> { pos + SIMD3(0, 1.62, 0) + SIMD3(sinf(yaw), 0, cosf(yaw)) * 0.1 }

    private func face(_ p: SIMD3<Float>, _ dt: Float) {
        let d = p - pos
        let target = atan2f(d.x, d.z)
        var dy = target - yaw
        while dy > .pi { dy -= 2 * .pi }
        while dy < -.pi { dy += 2 * .pi }
        yaw += dy * min(1, dt * 5)
    }

    private func walk(toward p: SIMD3<Float>, speed want: Float, _ dt: Float) {
        var d = p - pos; d.y = 0
        let len = simd_length(d)
        guard len > 0.02 else { speed = 0; return }
        face(p, dt)
        speed += (want - speed) * min(1, dt * 4)
        pos += d / len * min(len, speed * dt)
        stepAcc += speed * dt
        if stepAcc > 0.62 { stepAcc = 0; events.append(.footstep(pos, min(1, speed))) }
    }

    private func followPath(_ dt: Float, speed: Float) -> Bool {
        guard let next = path.first else { return true }
        walk(toward: next, speed: speed, dt)
        if simd_distance(SIMD2(pos.x, pos.z), SIMD2(next.x, next.z)) < 0.12 { path.removeFirst() }
        return path.isEmpty
    }

    func startAlarm() {
        if inRoom && phase != .stomping && phase != .alarmed { sawRat = true; events.append(.yell); go(.alarmed) }
    }

    func reset() {
        phase = .away
        model.node.isHidden = true
        lightsOn = 0
        fridgeOpen = 0
        spotted = 0
    }
}
