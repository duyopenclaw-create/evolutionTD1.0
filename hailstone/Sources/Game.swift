import SceneKit
import SpriteKit

struct Chain {
    let id: Int
    let seed: Int
    let expected: [Int]
    var values: [Int]
    var done = false
    var peak: Int
}

struct Records: Codable {
    var seed = 27
    var longestSteps = 0, longestSeed = 0
    var highestPeak = 0, highestSeed = 0
    var spawned = 0, finished = 0
    var musicOn = true
    var volume: Float = 0.9
}

enum SaveData {
    static var disabled = false
    static let key = "hailstone.records.v1"
    static func load() -> Records {
        guard let d = UserDefaults.standard.data(forKey: key), let r = try? JSONDecoder().decode(Records.self, from: d) else { return Records() }
        return r
    }
    static func save(_ r: Records) {
        guard !disabled, let d = try? JSONEncoder().encode(r) else { return }
        UserDefaults.standard.set(d, forKey: key)
    }
}

final class Game: NSObject, SCNSceneRendererDelegate, SCNPhysicsContactDelegate {
    let view: GameView
    let scene = SCNScene()
    let world = World()
    let audio: AudioSystem
    let hud = HUD()
    let camNode = SCNNode(), camera = SCNCamera()

    static let maxBalls = 420
    private(set) var balls: [Ball] = []
    private var byNode: [ObjectIdentifier: Ball] = [:]
    private var chains: [Int: Chain] = [:]
    private var nextChain = 1
    private var watched = 0                // chain shown on the graph and scoreboard
    var records = SaveData.load()
    private var typing = ""
    var ignoreInput = false

    private var simTime = 0.0, lastTime = 0.0, lastSave = 0.0
    private struct Contact { let a: SCNNode; let b: SCNNode; let n: SIMD3<Float>; let p: SIMD3<Float> }
    private var contacts: [Contact] = []
    private let contactLock = NSLock()

    // camera
    var yaw: Float = 0.42, pitch: Float = 0.3, dist: Float = 12.5
    private var target = SIMD3<Float>(0, 0.7, 0)
    private var focus: Ball?
    private var focusPinned = false
    private var cinematic = false
    private var camPos = SIMD3<Float>(0, 3, 12)
    private var camRight = SIMD3<Float>(1, 0, 0)

    // gantry
    private var gantry = SIMD2<Float>(0, 0), gantryVel = SIMD2<Float>(0, 0)
    private var dropQueue: [(Int, SIMD2<Float>?)] = []
    private var dropCooldown = 0.0
    private var wasMoving = false

    private var slowmo = false, autoRain = false, autoT = 3.0
    private var scoreDirty = true, scoreT = 0.0
    private var soundsThisFrame = 0
    private var rng = RNG(UInt64(Date().timeIntervalSince1970))

    init(view: GameView, muted: Bool) {
        self.view = view
        audio = AudioSystem(muted: muted)
        super.init()
        setupScene()
        view.scene = scene
        view.pointOfView = camNode
        view.delegate = self
        view.overlaySKScene = hud.scene
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        view.isPlaying = true
        view.backgroundColor = .black
        audio.music.on = records.musicOn ? 1 : 0
        audio.masterVolume = records.volume
        hud.setHelp(true)
        hud.showToast("HAILSTONE", sub: "Press SPACE to drop seed \(records.seed), or click anywhere on the floor", duration: 6, now: 0)
        refreshSeedInfo()
    }

    // MARK: Scene

    private func setupScene() {
        scene.rootNode.addChildNode(world.root)
        scene.lightingEnvironment.contents = World.env
        scene.lightingEnvironment.intensity = 1.35
        scene.physicsWorld.gravity = SCNVector3(0, -9.81, 0)
        scene.physicsWorld.timeStep = 1.0 / 180.0
        scene.physicsWorld.contactDelegate = self

        camera.zNear = 0.05
        camera.zFar = 90
        camera.fieldOfView = 48
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0.1
        camera.averageGray = 0.18
        camera.whitePoint = 1.2
        camera.bloomIntensity = 0.35
        camera.bloomThreshold = 1.1
        camera.bloomBlurRadius = 12
        camera.vignettingIntensity = 0.45
        camera.vignettingPower = 0.8
        camera.contrast = 0.06
        camera.saturation = 1.04
        camera.screenSpaceAmbientOcclusionIntensity = CommandLine.arguments.contains("--nossao") ? 0 : 1.0
        camera.screenSpaceAmbientOcclusionRadius = 0.12
        camera.screenSpaceAmbientOcclusionBias = 0.02
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.06
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        camera.wantsDepthOfField = true
        camera.fStop = 5.6
        camera.focalLength = 50
        camera.apertureBladeCount = 7
        camera.focalBlurSampleCount = 8
        camera.motionBlurIntensity = 0
        camera.grainIntensity = 0.06
        camera.grainScale = 1.2
        camNode.camera = camera
        scene.rootNode.addChildNode(camNode)
        updateCamera(0)
    }

    // MARK: Loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, time - lastTime)
        lastTime = time
        simTime += dt
        soundsThisFrame = 0
        if !ignoreInput { handleInput() }
        updateGantry(Float(dt))
        updateBalls(Float(dt))
        updateCamera(Float(dt))
        updateHUD()
        if simTime - lastSave > 30 {
            lastSave = simTime
            if !SaveData.disabled { SaveData.save(records); hud.flashSaved(now: simTime) }
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {
        contactLock.lock()
        let cs = contacts
        contacts.removeAll(keepingCapacity: true)
        contactLock.unlock()
        for c in cs { handleContact(c) }
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let n = contact.contactNormal, p = contact.contactPoint
        contactLock.lock()
        contacts.append(Contact(a: contact.nodeA, b: contact.nodeB, n: SIMD3(Float(n.x), Float(n.y), Float(n.z)), p: SIMD3(Float(p.x), Float(p.y), Float(p.z))))
        contactLock.unlock()
    }

    // MARK: Input

    private func handleInput() {
        for d in view.input.drainDigits() {
            if typing.count < 8 && !(typing.isEmpty && d == "0") { typing.append(d); audio.play("tick", volume: 0.4) }
            if let v = Int(typing) { records.seed = v; refreshSeedInfo() }
        }
        for (k, shift) in view.input.drainPresses() {
            switch k {
            case Key.space, Key.ret, Key.enter:
                typing = ""
                if shift { for i in 0..<5 { queueDrop(records.seed + i, at: nil) } } else { queueDrop(records.seed, at: nil) }
            case Key.backspace:
                if !typing.isEmpty { typing.removeLast(); audio.play("tick", volume: 0.3) }
                if let v = Int(typing) { records.seed = v; refreshSeedInfo() }
            case Key.esc: typing = ""; hud.setHelp(false)
            case Key.up: adjustSeed(shift ? 10 : 1)
            case Key.down: adjustSeed(shift ? -10 : -1)
            case Key.left: setSeed(records.seed / 2)
            case Key.right: setSeed(records.seed * 2)
            case Key.r: setSeed(randomSeed())
            case Key.a:
                autoRain.toggle(); autoT = 0.5
                hud.showToast(autoRain ? "Auto-rain on" : "Auto-rain off", sub: autoRain ? "A new random seed every few seconds" : "", duration: 1.6, now: simTime)
            case Key.t:
                slowmo.toggle()
                scene.physicsWorld.speed = slowmo ? 0.3 : 1
            case Key.c: clearAll()
            case Key.m:
                records.musicOn.toggle()
                audio.music.on = records.musicOn ? 1 : 0
                hud.showToast(records.musicOn ? "Music on" : "Music off", duration: 1.2, now: simTime)
            case Key.minus: records.volume = max(0, records.volume - 0.1); audio.masterVolume = records.volume
                hud.showToast("Volume \(Int((records.volume * 100).rounded()))%", duration: 1, now: simTime)
            case Key.equals: records.volume = min(1, records.volume + 0.1); audio.masterVolume = records.volume
                hud.showToast("Volume \(Int((records.volume * 100).rounded()))%", duration: 1, now: simTime)
            case Key.h: hud.toggleHelp()
            case Key.v: cinematic.toggle()
            case Key.tab: hud.visible.toggle()
            case Key.f: focusPinned = false; focus = nil
            default: break
            }
        }
        for c in view.input.drainClicks() {
            switch c {
            case .floor(let p):
                typing = ""
                queueDrop(records.seed, at: SIMD2(p.x, p.z))
            case .ball(let node):
                if let b = byNode[ObjectIdentifier(node)] {
                    focus = b; focusPinned = true
                    let ch = chains[b.chain]
                    hud.showToast("\(b.value.formatted())", sub: "step \(b.step) of seed \(ch?.seed.formatted() ?? "?")  ·  \(b.value % 2 == 0 ? "even: next is \((b.value / 2).formatted())" : (b.value == 1 ? "the end of the line" : "odd: next is \((3 * b.value + 1).formatted())"))  ·  press F to let go", duration: 3, now: simTime)
                    if let ch { watched = ch.id; scoreDirty = true }
                }
            }
        }
        let (mx, my, sc) = view.input.takeMouse()
        if mx != 0 || my != 0 { cinematic = false }
        yaw -= mx * 0.006
        pitch = clampf(pitch + my * 0.005, 0.04, 1.45)
        dist = clampf(dist * expf(-sc * 0.9), 1.5, 26)
    }

    private func adjustSeed(_ d: Int) { setSeed(records.seed + d) }
    private func setSeed(_ v: Int) {
        typing = ""
        records.seed = max(1, min(99_999_999, v))
        audio.play("tick", volume: 0.35)
        refreshSeedInfo()
    }

    private func randomSeed() -> Int {
        let famous = [27, 97, 871, 703, 6171, 77031, 837799, 9663, 230631, 626331]
        let r = rng.float()
        if r < 0.12 { return famous[rng.int(famous.count)] }
        if r < 0.35 { return 200 + rng.int(3000) }
        return 3 + rng.int(200)
    }

    private var seedInfoCache: (Int, String) = (0, "")
    private func refreshSeedInfo() {
        let s = records.seed
        if seedInfoCache.0 == s { return }
        let seq = Collatz.sequence(s)
        let peak = seq.max() ?? s
        seedInfoCache = (s, s == 1 ? "already home: 1 is the end of every chain" : "\(seq.count - 1) steps to 1  ·  peaks at \(peak.formatted())  ·  \(seq.count) balls")
    }

    // MARK: Dropping

    func queueDrop(_ n: Int, at xz: SIMD2<Float>?) {
        guard dropQueue.count < 12 else { return }
        let n = max(1, min(99_999_999, n))
        var p = xz
        if let q = p {
            let m: Float = 0.25 + BallFactory.radius(n)
            p = SIMD2(clampf(q.x, -World.penX + m, World.penX - m), clampf(q.y, -World.penZ + m, World.penZ - m))
        }
        dropQueue.append((n, p))
    }

    private func updateGantry(_ dt: Float) {
        dropCooldown -= Double(dt)
        if autoRain {
            autoT -= Double(dt)
            let running = chains.values.filter { !$0.done }.count
            if autoT <= 0 && running < 4 && dropQueue.isEmpty {
                autoT = Double(rng.range(4, 8))
                queueDrop(randomSeed(), at: SIMD2(rng.range(-4, 4), rng.range(-2.6, 2.6)))
            }
        }
        var goal = gantry
        if let (_, p) = dropQueue.first { goal = p ?? gantry }
        // critically damped approach, speed-limited like a real crane
        let d = goal - gantry
        let desired = simd_length(d) > 0.001 ? simd_normalize(d) * min(3.0, simd_length(d) * 2.2) : SIMD2<Float>(0, 0)
        gantryVel += (desired - gantryVel) * min(1, dt * 5)
        gantry += gantryVel * dt
        world.setGantry(x: gantry.x, z: gantry.y)
        let speed = simd_length(gantryVel)
        audio.ambient.motor = min(1, speed / 2.5)
        let moving = speed > 0.08
        world.beacon.emission.intensity = moving ? (sin(simTime * 12) > 0 ? 4 : 0.2) : 0
        if wasMoving && !moving { audio.play("gantry_stop", volume: 0.5, pan: pan(of: SIMD3(gantry.x, 4, gantry.y))) }
        wasMoving = moving
        if let (n, _) = dropQueue.first, simd_length(d) < 0.03, speed < 0.08, dropCooldown <= 0 {
            dropQueue.removeFirst()
            dropCooldown = 0.45
            release(n)
        }
    }

    private func release(_ n: Int) {
        let id = nextChain
        nextChain += 1
        let seq = Collatz.sequence(n)
        chains[id] = Chain(id: id, seed: n, expected: seq, values: [n], peak: n)
        watched = id
        scoreDirty = true
        let b = Ball(value: n, chain: id, step: 0, born: simTime)
        let pos = SIMD3<Float>(gantry.x, World.nozzleY - b.radius - 0.03, gantry.y)
        add(b, at: pos, velocity: SIMD3(0, -0.6, 0), spin: SIMD3(rng.range(-2, 2), 0, rng.range(-2, 2)))
        records.spawned += 1
        hud.setHelp(false)
        audio.play("drop", volume: 0.8, pan: pan(of: pos))
        if !focusPinned { focus = b }
        hud.pushFeed("SEED \(n.formatted())", color: NSColor(white: 1, alpha: 1))
    }

    private func add(_ b: Ball, at p: SIMD3<Float>, velocity v: SIMD3<Float>, spin: SIMD3<Float>) {
        b.node.simdPosition = p
        b.node.simdOrientation = simd_quatf(angle: rng.range(0, 6.28), axis: simd_normalize(SIMD3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)) + SIMD3(0, 0.01, 0)))
        scene.rootNode.addChildNode(b.node)
        b.node.physicsBody?.velocity = SCNVector3(v.x, v.y, v.z)
        b.node.physicsBody?.angularVelocity = SCNVector4(spin.x, spin.y, spin.z, simd_length(spin))
        b.lastVel = v
        // grow in over a few frames so a birth reads as a birth, not a teleport
        b.node.simdScale = SIMD3(repeating: 0.3)
        b.node.runAction(.customAction(duration: 0.14) { n, t in
            let k = Float(t / 0.14)
            let e = 1 - (1 - k) * (1 - k)
            n.simdScale = SIMD3(repeating: 0.3 + 0.7 * e)
        })
        balls.append(b)
        byNode[ObjectIdentifier(b.node)] = b
    }

    private func remove(_ b: Ball, animated: Bool) {
        byNode[ObjectIdentifier(b.node)] = nil
        if let i = balls.firstIndex(where: { $0 === b }) { balls.remove(at: i) }
        if focus === b { focus = nil; focusPinned = false }
        let node = b.node
        node.physicsBody = nil
        if animated {
            node.runAction(.sequence([.group([.fadeOut(duration: 0.6), .scale(to: 0.01, duration: 0.6)]), .removeFromParentNode()]))
        } else {
            node.removeFromParentNode()
        }
    }

    private func clearAll() {
        for b in balls { remove(b, animated: true) }
        chains.removeAll()
        dropQueue.removeAll()
        watched = 0
        scoreDirty = true
        audio.play("clear", volume: 0.8)
        hud.setGraph(title: "Drop a seed to begin", values: [], total: 1, peak: 1)
    }

    // MARK: Contacts, bounces, births

    private func handleContact(_ c: Contact) {
        let a = byNode[ObjectIdentifier(c.a)], b = byNode[ObjectIdentifier(c.b)]
        if let a, let b {
            let rel = a.lastVel - b.lastVel
            let s = abs(simd_dot(rel, c.n))
            let small = a.radius < b.radius ? a : b
            if s > 0.3 && simTime - max(a.lastSound, b.lastSound) > 0.045 {
                a.lastSound = simTime; b.lastSound = simTime
                let heavy = min(1, (a.radius + b.radius) * 1.5)
                sound("clack_\(AudioSystem.bucket(small.radius))", speed: s, weight: 0.55 + 0.45 * heavy, at: c.p)
            }
            impact(a, s); impact(b, s)
            return
        }
        guard let ball = a ?? b else { return }
        let other = a == nil ? c.a : c.b
        let cat = other.physicsBody?.categoryBitMask ?? 0
        let s = abs(simd_dot(ball.lastVel, c.n))
        if s > 0.25 && simTime - ball.lastSound > 0.045 {
            ball.lastSound = simTime
            let weight = 0.5 + 0.5 * min(1, ball.radius * 2.2)
            if cat == Mask.glass { sound("glass", speed: s, weight: weight, at: c.p) }
            else { sound("bounce_\(AudioSystem.bucket(ball.radius))", speed: s, weight: weight, at: c.p) }
        }
        impact(ball, s)
    }

    private func sound(_ name: String, speed: Float, weight: Float, at p: SIMD3<Float>) {
        guard soundsThisFrame < 7 else { return }
        soundsThisFrame += 1
        let d = simd_length(p - camPos)
        let v = powf(min(1, speed / 6), 1.1) * weight * 1.25 / (1 + 0.07 * d)
        audio.play(name, volume: v, pan: pan(of: p))
    }

    private func pan(of p: SIMD3<Float>) -> Float {
        let d = p - camPos
        let l = simd_length(d)
        guard l > 0.01 else { return 0 }
        return clampf(simd_dot(d / l, camRight) * 0.9, -0.9, 0.9)
    }

    private func impact(_ b: Ball, _ speed: Float) {
        guard !b.spawned, simTime - b.born > 0.22, speed > 0.45 else { return }
        birth(from: b)
    }

    private func birth(from parent: Ball) {
        parent.spawned = true
        guard var ch = chains[parent.chain] else { return }
        let p = parent.position
        if parent.value == 1 {
            ch.done = true
            chains[ch.id] = ch
            parent.flash(NSColor(srgbRed: 1, green: 0.75, blue: 0.25, alpha: 1), peak: 2.4, duration: 2.2)
            audio.play("one", volume: 0.8, pan: pan(of: p))
            let steps = ch.values.count - 1
            records.finished += 1
            var sub = "\(steps) steps  ·  peak \(ch.peak.formatted())"
            if steps > records.longestSteps { records.longestSteps = steps; records.longestSeed = ch.seed; sub += "  ·  NEW LONGEST" }
            if ch.peak > records.highestPeak { records.highestPeak = ch.peak; records.highestSeed = ch.seed; sub += "  ·  NEW HIGHEST" }
            hud.showToast("\(ch.seed.formatted()) reached 1", sub: sub, color: NSColor(srgbRed: 1, green: 0.85, blue: 0.45, alpha: 1), duration: 4, now: simTime)
            hud.pushFeed("1 ✓  seed \(ch.seed.formatted()) home", color: NSColor(srgbRed: 1, green: 0.8, blue: 0.3, alpha: 1))
            audio.music.push(0)
            scoreDirty = true
            return
        }
        let odd = parent.value % 2 == 1
        let nv = Collatz.next(parent.value)
        let child = Ball(value: nv, chain: ch.id, step: parent.step + 1, born: simTime)
        // pop the child out of the top of the parent, drifting back toward the middle of the pen
        let up: Float = odd ? rng.range(3.5, 4.1) : rng.range(2.8, 3.3)
        let ang = rng.range(0, 2 * .pi)
        var h = SIMD2<Float>(cosf(ang), sinf(ang)) * rng.range(0.3, 0.9)
        h -= SIMD2(p.x / World.penX, p.z / World.penZ) * 0.9
        if simd_length(h) > 1.2 { h = simd_normalize(h) * 1.2 }
        let pos = SIMD3<Float>(p.x, p.y + parent.radius + child.radius + 0.03, p.z)
        add(child, at: pos, velocity: SIMD3(h.x, up, h.y), spin: SIMD3(rng.range(-6, 6), rng.range(-3, 3), rng.range(-6, 6)))
        // the parent is shoved down a little by the birth
        if let pb = parent.node.physicsBody {
            let recoil = min(1.0, Double(child.mass / max(parent.mass, 0.01))) * 1.2
            pb.velocity = SCNVector3(pb.velocity.x, pb.velocity.y - CGFloat(recoil), pb.velocity.z)
        }
        parent.flash(odd ? NSColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 1) : NSColor(srgbRed: 0.45, green: 0.7, blue: 1, alpha: 1), peak: 0.3, duration: 0.4)
        audio.play("pop_\(odd ? "odd" : "even")_\(AudioSystem.bucket(child.radius))", volume: 0.55 / (1 + 0.05 * simd_length(pos - camPos)), pan: pan(of: pos))
        audio.music.push(Int(log2(Double(nv)) * 0.75))
        ch.values.append(nv)
        ch.peak = max(ch.peak, nv)
        chains[ch.id] = ch
        records.spawned += 1
        if !focusPinned && ch.id == watched { focus = child }
        if ch.id == watched { scoreDirty = true }
        hud.pushFeed(odd ? "\(parent.value.formatted()) ×3+1 → \(nv.formatted())" : "\(parent.value.formatted()) ÷2 → \(nv.formatted())",
                     color: odd ? NSColor(srgbRed: 1, green: 0.66, blue: 0.35, alpha: 1) : NSColor(srgbRed: 0.6, green: 0.8, blue: 1, alpha: 1))
    }

    // MARK: Per-frame ball upkeep

    private func updateBalls(_ dt: Float) {
        var roll: Float = 0, rollR: Float = 0, rollW: Float = 0
        var stale: [Ball] = []
        for b in balls {
            guard let body = b.node.physicsBody else { continue }
            let v = body.velocity
            b.lastVel = SIMD3(Float(v.x), Float(v.y), Float(v.z))
            let p = b.position
            if p.y < -3 || abs(p.x) > World.halfX + 2 || abs(p.z) > World.halfZ + 2 { stale.append(b); continue }
            // a ball that landed too softly to count still gets its turn
            if !b.spawned && simTime - b.born > 3.5 { birth(from: b) }
            if abs(p.y - b.radius) < 0.03 && abs(b.lastVel.y) < 0.4 {
                let s = simd_length(SIMD2(b.lastVel.x, b.lastVel.z))
                let w = s * b.radius * 2 * 1 / (1 + 0.05 * simd_length(p - camPos))
                roll += w; rollR += b.radius * w; rollW += w
            }
        }
        for b in stale { remove(b, animated: false) }
        // cull the oldest finished balls once the pen is full
        if balls.count > Game.maxBalls {
            var excess = balls.count - Game.maxBalls
            for b in balls where excess > 0 && b.spawned && b !== focus {
                remove(b, animated: true)
                excess -= 1
            }
        }
        audio.ambient.roll = min(1, roll * 0.9)
        audio.ambient.rollPitch = rollW > 0 ? clampf((rollR / rollW - 0.07) / 0.4, 0, 1) : 0
        if let f = focus, f.node.parent == nil { focus = nil }
    }

    // MARK: Camera

    private func updateCamera(_ dt: Float) {
        if cinematic { yaw += dt * 0.08 }
        var want = SIMD3<Float>(0, 0.7, 0)
        if let f = focus {
            let p = f.position
            want = focusPinned ? p : mix3(want, SIMD3(p.x, max(0.5, p.y), p.z), 0.4)
        }
        target += (want - target) * min(1, dt * (focusPinned ? 4 : 1.2))
        var pos = target + dist * SIMD3(cosf(pitch) * sinf(yaw), sinf(pitch), cosf(pitch) * cosf(yaw))
        pos.x = clampf(pos.x, -World.halfX + 0.5, World.halfX - 0.5)
        pos.z = clampf(pos.z, -World.halfZ + 0.5, World.halfZ - 0.5)
        pos.y = clampf(pos.y, 0.25, World.ceiling - 1.5)
        camNode.simdPosition = pos
        camNode.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        camPos = pos
        camRight = camNode.simdWorldRight
        camera.focusDistance = CGFloat(simd_length(target - pos))
    }

    // MARK: HUD + scoreboard

    private func updateHUD() {
        var st = HUDState()
        st.seedText = records.seed.formatted()
        st.typing = !typing.isEmpty
        refreshSeedInfo()
        st.seedInfo = seedInfoCache.1
        st.balls = balls.count
        st.maxBalls = Game.maxBalls
        st.running = chains.values.filter { !$0.done }.count
        st.longest = records.longestSteps > 0 ? "LONGEST  \(records.longestSteps) steps (seed \(records.longestSeed.formatted()))" : "LONGEST  –"
        st.highest = records.highestPeak > 0 ? "HIGHEST  \(records.highestPeak.formatted()) (seed \(records.highestSeed.formatted()))" : "HIGHEST  –"
        st.spawned = records.spawned
        if slowmo { st.flags.append("SLOW-MO") }
        if autoRain { st.flags.append("AUTO-RAIN") }
        if cinematic { st.flags.append("CINEMATIC") }
        if !records.musicOn { st.flags.append("MUSIC OFF") }
        if !dropQueue.isEmpty { st.flags.append("QUEUED \(dropQueue.count)") }
        hud.update(st, now: simTime)

        scoreT -= 1.0 / 60
        if scoreDirty && scoreT <= 0 {
            scoreDirty = false
            scoreT = 0.12
            if let ch = chains[watched] {
                hud.setGraph(title: "SEED \(ch.seed.formatted())\(ch.done ? "  ·  reached 1" : "")", values: ch.values, total: ch.expected.count, peak: ch.expected.max() ?? ch.seed)
                world.scoreMat.emission.contents = Tex.scoreboard(seed: ch.seed, step: ch.values.count - 1, total: ch.expected.count - 1, now: ch.values.last, peak: ch.peak)
            } else {
                world.scoreMat.emission.contents = Tex.scoreboard(seed: nil, step: 0, total: 0, now: nil, peak: 0)
            }
        }
    }

    // MARK: Dev hooks

    /// Instantly lays down a settled-looking pile so screenshots have something to look at.
    func devPile(_ seed: Int) {
        let seq = Collatz.sequence(seed)
        let id = nextChain; nextChain += 1
        chains[id] = Chain(id: id, seed: seed, expected: seq, values: seq, done: false, peak: seq.max() ?? seed)
        watched = id
        for (i, v) in seq.enumerated() {
            let b = Ball(value: v, chain: id, step: i, born: simTime)
            b.spawned = i < seq.count - 1
            let a = Float(i) * 2.4
            let rr = 0.6 + Float(i) * 0.035
            add(b, at: SIMD3(cosf(a) * min(rr, 4.2), b.radius + 0.4 + Float(i % 5) * 0.9, sinf(a) * min(rr * 0.7, 2.9)), velocity: .zero, spin: .zero)
        }
        scoreDirty = true
    }

    func devDrop(_ seed: Int) { queueDrop(seed, at: nil) }
    func devCamera(yaw y: Float?, pitch p: Float?, dist d: Float?) {
        if let y { yaw = y }
        if let p { pitch = p }
        if let d { dist = d }
    }
    func devSlowmo() { slowmo = true; scene.physicsWorld.speed = 0.3 }
    func devHideHelp() { hud.setHelp(false) }

    /// Headless logic checks.
    func autotest() -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool) { print((cond ? "PASS " : "FAIL ") + name); ok = ok && cond }
        let s27 = Collatz.sequence(27)
        check("27 takes 111 steps", s27.count - 1 == 111)
        check("27 peaks at 9232", s27.max() == 9232)
        check("837799 takes 524 steps", Collatz.sequence(837799).count - 1 == 524)
        check("1 is already home", Collatz.sequence(1) == [1])
        check("bands: 1→1, 2→2, 7→3, 8→4", Collatz.band(1) == 1 && Collatz.band(2) == 2 && Collatz.band(7) == 3 && Collatz.band(8) == 4)
        check("halving drops one band", (1...5000).allSatisfy { $0 % 2 == 1 || Collatz.band($0 / 2) == Collatz.band($0) - 1 })
        check("radius grows and caps", BallFactory.radius(1) < BallFactory.radius(9232) && BallFactory.radius(Int(1e12)) <= 0.7)
        check("buckets cover sizes", AudioSystem.bucket(0.07) == 0 && AudioSystem.bucket(0.7) == AudioSystem.buckets - 1)
        let tex = BallFactory.texture(9232, radius: 0.44)
        check("texture 2:1", tex.width == tex.height * 2)
        ok = audio.selfCheck() && ok
        print(ok ? "ALL PASS" : "SOME FAILED")
        return ok
    }

    func saveNow() { SaveData.save(records) }
}
