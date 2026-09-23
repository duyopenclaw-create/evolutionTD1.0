import SceneKit
import SpriteKit
import GameController
import simd

final class Game: NSObject, SCNSceneRendererDelegate {
    enum Mode { case title, flying, paused }
    enum Cam: Int { case chase, cockpit, flyby, orbit
        var name: String { ["CHASE CAM", "COCKPIT", "FLY-BY", "ORBIT"][rawValue] }
    }

    let view: GameView
    let scene = SCNScene()
    let terrain: Terrain
    let world: World
    let fm = FlightModel()
    let plane = AircraftModel()
    let audio: AudioSystem
    let hud: HUD
    let camNode = SCNNode()
    let camera = SCNCamera()
    let sun = SCNNode()
    private let dot = softDotImage()
    private var smoke: SCNParticleSystem!
    private var vapor: [SCNParticleSystem] = []

    private(set) var mode: Mode = .title
    private var cam: Cam = .chase
    private var lastTime: TimeInterval = 0
    private var accum = 0.0
    private(set) var simTime = 0.0
    private var camQuat = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    private var camInit = false
    private var flybyPos: SIMD3<Float>?
    private var lookYaw: Float = 0, lookPitch: Float = 0
    private var zoom: Float = 1
    private var orbitAngle: Float = 0
    var todIndex = 0
    private var skyCache: [Int: CGImage] = [:]
    private let skyLock = NSLock()
    private var smokeOn = false
    private var invertPitch = false
    private var ringIndex = 0
    private var ringStart: Double?
    private var ringFinish: Double?
    private var bestTime: Double?
    private var prevPos = SIMD3<Float>(0, 0, 0)
    private var calloutsDone = Set<Int>()
    private var lastPullUp = -10.0, lastTail = -10.0, lastStallVoice = -10.0
    private var crashTime: Double?
    private var engineStarting: Double?
    private var firstLiftoff = true
    private var padPrev: [String: Bool] = [:]
    private var summitRunway = "09"
    var ignoreInput = false
    var devPitch = 0.0

    init(view: GameView, muted: Bool = false) {
        self.view = view
        terrain = Terrain()
        world = World(terrain: terrain)
        audio = AudioSystem(muted: muted)
        hud = HUD(mapImage: terrain.mapImage(size: 256),
                  ringsMap: world.rings.map { SIMD2($0.center.x, $0.center.z) },
                  airports: terrain.airports.map { (SIMD2($0.cx, $0.cz), $0.code) })
        let saved = UserDefaults.standard.double(forKey: "bestRingTime")
        bestTime = saved > 0 ? saved : nil
        super.init()
        setupScene()
        let t = terrain
        fm.ground = { x, z in
            var (h, s) = t.ground(x, z)
            if s == .paved { h += 0.3 }
            return (h, s)
        }
        resetToRunway(0, keepEngine: false)
        world.highlightRing(0)

        view.scene = scene
        view.pointOfView = camNode
        view.delegate = self
        view.overlaySKScene = hud.scene
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 120
        view.rendersContinuously = true
        view.isPlaying = true
        view.backgroundColor = .black

        // Pre-render the other skies in the background so time-of-day switches are instant.
        DispatchQueue.global(qos: .utility).async {
            for i in TimeOfDay.presets.indices { _ = self.skyImage(i) }
        }
    }

    // MARK: Scene

    private func setupScene() {
        scene.rootNode.addChildNode(world.root)
        scene.rootNode.addChildNode(plane.node)

        camera.zNear = 0.3
        camera.zFar = 45000
        camera.fieldOfView = 62
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.4
        camera.bloomThreshold = 0.95
        camera.bloomBlurRadius = 12
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 0.8
        camera.saturation = 1.08
        camera.contrast = 0.06
        camera.averageGray = 0.18
        camera.whitePoint = 1.2
        camNode.camera = camera
        scene.rootNode.addChildNode(camNode)

        let l = SCNLight()
        l.type = .directional
        l.castsShadow = true
        l.shadowMapSize = CGSize(width: 2048, height: 2048)
        l.shadowCascadeCount = 3
        l.maximumShadowDistance = 700
        l.shadowCascadeSplittingFactor = 0.25
        l.automaticallyAdjustsShadowProjection = true
        l.shadowSampleCount = 8
        l.shadowRadius = 1.5
        l.shadowColor = NSColor(white: 0, alpha: 0.72)
        l.shadowBias = 1.5
        sun.light = l
        scene.rootNode.addChildNode(sun)

        smoke = trail(life: 9, size: 1.3, grow: 7, alpha: 0.55)
        plane.tail.addParticleSystem(smoke)
        for tip in [plane.tipL, plane.tipR] {
            let v = trail(life: 0.55, size: 0.35, grow: 2.5, alpha: 0.4)
            tip.addParticleSystem(v)
            vapor.append(v)
        }
        applyTime(todIndex)
    }

    private func trail(life: CGFloat, size: CGFloat, grow: CGFloat, alpha: CGFloat) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = dot
        ps.birthRate = 0
        ps.particleLifeSpan = life
        ps.particleLifeSpanVariation = life * 0.2
        ps.particleSize = size
        ps.particleSizeVariation = size * 0.3
        ps.particleColor = NSColor(white: 1, alpha: alpha)
        ps.blendMode = .alpha
        ps.particleVelocity = 0.6
        ps.spreadingAngle = 180
        ps.isLightingEnabled = false
        let sz = CAKeyframeAnimation()
        sz.values = [1, grow]
        let op = CAKeyframeAnimation()
        op.values = [1, 0.7, 0]
        ps.propertyControllers = [.size: SCNParticlePropertyController(animation: sz), .opacity: SCNParticlePropertyController(animation: op)]
        return ps
    }

    func skyImage(_ i: Int) -> CGImage {
        skyLock.lock()
        if let img = skyCache[i] { skyLock.unlock(); return img }
        skyLock.unlock()
        let img = Sky.image(TimeOfDay.presets[i])
        skyLock.lock(); skyCache[i] = img; skyLock.unlock()
        return img
    }

    func applyTime(_ i: Int) {
        let t = TimeOfDay.presets[i]
        let img = skyImage(i)
        scene.background.contents = img
        scene.lightingEnvironment.contents = img
        scene.lightingEnvironment.intensity = t.ambient
        if let l = sun.light {
            l.color = color(t.sunColor)
            l.intensity = t.sunIntensity
        }
        let d = t.sunDirection
        sun.simdPosition = d * 1000
        sun.simdLook(at: .zero, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        scene.fogColor = Sky.fogColor(t)
        scene.fogStartDistance = 1800
        scene.fogEndDistance = t.fogDistance
        scene.fogDensityExponent = 1.25
        camera.exposureOffset = t.exposure
        world.tintClouds(t.cloudTint)
    }

    // MARK: Resets

    func resetToRunway(_ idx: Int, keepEngine: Bool = true) {
        let ap = terrain.airports[idx]
        let st = ap.start
        let wasOn = fm.engineOn
        fm.reset(position: SIMD3(Double(st.pos.x), Double(ap.elevation) + 0.3 + fm.gearHeight, Double(st.pos.y)),
                 heading: Double(st.heading), speed: 0, onRunway: true)
        fm.engineOn = keepEngine && wasOn
        fm.rpm = fm.engineOn ? 0.08 : 0
        afterReset()
    }

    func airStart(course: Bool) {
        if course {
            let r = world.rings[max(ringIndex, 0) < world.rings.count ? ringIndex : 0]
            let p = r.center - r.normal * 650
            let hdg = atan2(Double(r.normal.x), Double(-r.normal.z))
            fm.reset(position: SIMD3<Double>(p), heading: hdg, speed: 62, onRunway: false)
        } else {
            // Choose the runway end whose final approach is clearest of the ridges.
            let ap = terrain.airports[1]
            let dist: Float = 3400
            let slope = tanf(3.5 * .pi / 180)
            var best: (start: SIMD2<Float>, heading: Double, worst: Float)?
            for dirSign: Float in [-1, 1] {
                let thr = ap.world(along: dirSign * ap.length / 2, across: 0)
                let start = ap.world(along: dirSign * (ap.length / 2 + dist), across: 0)
                var worst: Float = 0
                for k in 0...40 {
                    let t = Float(k) / 40
                    let p = start + (thr - start) * t
                    worst = max(worst, terrain.height(p.x, p.y) + 60 - (ap.elevation + dist * (1 - t) * slope))
                }
                let hdg = atan2(Double(thr.x - start.x), Double(-(thr.y - start.y)))
                if best == nil || worst < best!.worst { best = (start, hdg, worst) }
            }
            let p = best!.start
            summitRunway = best!.heading > 0 ? "09" : "27"
            let y = ap.elevation + dist * slope + best!.worst + 40
            fm.reset(position: SIMD3(Double(p.x), Double(y), Double(p.y)), heading: best!.heading, speed: 42, onRunway: false)
            fm.gearDown = true; fm.gearPos = 1
            fm.flapSetting = 2; fm.flap = 2.0 / 3
            fm.throttle = 0.5
        }
        fm.engineOn = true
        afterReset()
    }

    private func afterReset() {
        plane.node.isHidden = false
        crashTime = nil
        engineStarting = nil
        camInit = false
        flybyPos = nil
        calloutsDone.removeAll()
        prevPos = SIMD3<Float>(fm.pos)
        audio.synth.alive = 1
    }

    func resetRings() {
        ringIndex = 0
        ringStart = nil
        ringFinish = nil
        world.highlightRing(0)
    }

    func startFlying() {
        mode = .flying
        hud.title.isHidden = true
        if !fm.engineOn {
            audio.play("starter", volume: 0.9)
            engineStarting = simTime
        }
        hud.showToast("CLEARED FOR TAKE-OFF", sub: "Hold SHIFT for full power · pull back (S) at 60 kt · G raises the gear", color: color(1, 0.85, 0.35), duration: 6, now: simTime)
    }

    // MARK: Loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        var dt = lastTime == 0 ? 1.0 / 60 : time - lastTime
        lastTime = time
        dt = min(max(dt, 0), 0.05)
        handlePresses()
        let (mdx, mdy, sc) = view.input.takeMouse()
        if mode != .paused {
            simTime += dt
            simulate(dt)
        }
        updateVisuals(Float(dt))
        updateCamera(Float(dt), mdx: mdx, mdy: mdy, scroll: sc)
        updateAudio()
        updateHUD()
    }

    private func handlePresses() {
        for k in view.input.drainPresses() {
            if mode == .title {
                if k == Key.space || k == Key.ret { startFlying() }
                else if k == Key.m { toggleMusic() }
                else if k == Key.t { cycleTime() }
                else if k == Key.h { hud.help.isHidden.toggle() }
                continue
            }
            switch k {
            case Key.p, Key.esc:
                mode = mode == .paused ? .flying : .paused
                hud.pause.isHidden = mode != .paused
                audio.play("blip", volume: 0.5)
            case Key.h: hud.help.isHidden.toggle()
            case Key.c:
                cam = Cam(rawValue: (cam.rawValue + 1) % 4)!
                lookYaw = 0; lookPitch = 0; flybyPos = nil
                hud.showToast(cam.name, now: simTime)
            case Key.m: toggleMusic()
            case Key.t: cycleTime()
            case Key.x:
                smokeOn.toggle()
                audio.play("click")
                hud.showToast(smokeOn ? "SMOKE ON" : "SMOKE OFF", now: simTime)
            case Key.f:
                if fm.flapSetting < 3 { fm.flapSetting += 1; audio.play("flaps", volume: 0.8) }
                hud.showToast("FLAPS \(fm.flapSetting * 10)°", now: simTime)
            case Key.v:
                if fm.flapSetting > 0 { fm.flapSetting -= 1; audio.play("flaps", volume: 0.8) }
                hud.showToast("FLAPS \(fm.flapSetting * 10)°", now: simTime)
            case Key.g:
                if fm.onGround {
                    hud.showToast("GEAR LOCKED", sub: "The gear can't retract on the ground", now: simTime)
                } else if !fm.crashed {
                    fm.gearDown.toggle()
                    audio.play("gear", volume: 0.9)
                    hud.showToast(fm.gearDown ? "GEAR DOWN" : "GEAR UP", now: simTime)
                }
            case Key.r:
                resetToRunway(0)
                if !fm.engineOn { audio.play("starter", volume: 0.9); engineStarting = simTime }
                hud.showToast("HARBOR FIELD · RUNWAY 36", sub: "Hold SHIFT for power", now: simTime)
            case Key.two:
                airStart(course: true)
                hud.showToast("AIR START", sub: "Next ring dead ahead", now: simTime)
            case Key.three:
                airStart(course: false)
                hud.showToast("SUMMIT STRIP APPROACH", sub: "Runway \(summitRunway) · elevation \(Int(terrain.airports[1].elevation * 3.28)) ft · flaps 20, gear down", now: simTime)
            case Key.n:
                resetRings()
                hud.showToast("RING COURSE RESET", now: simTime)
            case Key.l:
                fm.assist.toggle()
                hud.showToast(fm.assist ? "WING LEVELLER ON" : "WING LEVELLER OFF", sub: fm.assist ? "" : "Full manual — the plane holds whatever bank you give it", now: simTime)
            case Key.i:
                invertPitch.toggle()
                hud.showToast(invertPitch ? "PITCH INVERTED" : "PITCH NORMAL", sub: invertPitch ? "W = nose up" : "W = nose down", now: simTime)
            default: break
            }
        }
    }

    private func toggleMusic() {
        audio.music.enabled.toggle()
        hud.showToast(audio.music.enabled ? "MUSIC ON" : "MUSIC OFF", now: simTime)
    }

    private func cycleTime() {
        todIndex = (todIndex + 1) % TimeOfDay.presets.count
        applyTime(todIndex)
        hud.showToast(TimeOfDay.presets[todIndex].name, now: simTime)
    }

    private func pad(_ name: String, _ pressed: Bool) -> Bool {
        let was = padPrev[name] ?? false
        padPrev[name] = pressed
        return pressed && !was
    }

    private func simulate(_ dt: Double) {
        var pitch = 0.0, roll = 0.0, yaw = 0.0
        let I = view.input
        if mode == .flying && !fm.crashed && !ignoreInput {
            if I.isDown(Key.s) || I.isDown(Key.down) { pitch += 1 }
            if I.isDown(Key.w) || I.isDown(Key.up) { pitch -= 1 }
            if I.isDown(Key.d) || I.isDown(Key.right) { roll += 1 }
            if I.isDown(Key.a) || I.isDown(Key.left) { roll -= 1 }
            if I.isDown(Key.e) { yaw += 1 }
            if I.isDown(Key.q) { yaw -= 1 }
            if invertPitch { pitch = -pitch }
            var thr = 0.0
            if I.shift || I.isDown(Key.equals) { thr += 1 }
            if I.ctrl || I.isDown(Key.minus) { thr -= 1 }
            fm.brake = I.isDown(Key.space) || I.isDown(Key.b)

            if let g = GCController.controllers().first?.extendedGamepad {
                roll += Double(g.leftThumbstick.xAxis.value)
                pitch += Double(-g.leftThumbstick.yAxis.value) * (invertPitch ? -1 : 1)
                yaw += Double(g.rightShoulder.value - g.leftShoulder.value)
                thr += Double(g.rightTrigger.value - g.leftTrigger.value)
                if g.buttonA.isPressed { fm.brake = true }
                lookYaw -= g.rightThumbstick.xAxis.value * Float(dt) * 2
                lookPitch += g.rightThumbstick.yAxis.value * Float(dt) * 1.5
                if pad("x", g.buttonX.isPressed) && !fm.onGround { fm.gearDown.toggle(); audio.play("gear", volume: 0.9) }
                if pad("y", g.buttonY.isPressed) { cam = Cam(rawValue: (cam.rawValue + 1) % 4)!; flybyPos = nil }
                if pad("b", g.buttonB.isPressed) { fm.flapSetting = (fm.flapSetting + 1) % 4; audio.play("flaps", volume: 0.8) }
            }
            fm.throttle = clampd(fm.throttle + thr * dt * 0.55, 0, 1)
            if (pitch != 0 || roll != 0 || yaw != 0) && CommandLine.arguments.contains("--log") { print("input", pitch, roll, yaw, GCController.controllers().map { $0.vendorName ?? "?" }) }
            pitch = clampd(pitch, -1, 1); roll = clampd(roll, -1, 1); yaw = clampd(yaw, -1, 1)
        } else {
            fm.brake = mode == .title
            pitch = devPitch
        }
        if let es = engineStarting, simTime - es > 1.05 {
            fm.engineOn = true
            fm.rpm = max(fm.rpm, 0.2)
            engineStarting = nil
        }

        let h = 1.0 / 240
        accum += dt
        var steps = 0
        while accum >= h && steps < 20 {
            fm.step(h, pitch: pitch, roll: roll, yaw: yaw)
            accum -= h
            steps += 1
        }
        for e in fm.events { handle(e) }
        fm.events.removeAll()

        checkRings()
        callouts()
    }

    private func nearestAirport() -> Airport? {
        let p = SIMD2<Float>(Float(fm.pos.x), Float(fm.pos.z))
        return terrain.airports.first { ap in
            let (al, ac) = ap.local(p.x, p.y)
            return abs(al) < ap.length / 2 + 200 && abs(ac) < 300
        }
    }

    private func handle(_ e: FlightEvent) {
        switch e {
        case .touchdown(let fpm, let surf):
            audio.play("touch", volume: Float(clampd(0.35 + fpm / 600, 0.35, 1.2)))
            if fpm > 500 { audio.play("thud", volume: 0.8) }
            let rating: String
            let c: NSColor
            switch fpm {
            case ..<160: rating = "BUTTER!"; c = color(0.4, 1, 0.6)
            case ..<380: rating = "SMOOTH LANDING"; c = color(0.5, 0.95, 1)
            case ..<650: rating = "FIRM LANDING"; c = color(1, 0.9, 0.4)
            default: rating = "HARD LANDING"; c = color(1, 0.55, 0.3)
            }
            var sub = String(format: "%.0f ft/min", fpm)
            if let ap = nearestAirport(), surf == .paved { sub = "Welcome to \(ap.name.capitalized) · " + sub }
            else if surf == .grass { sub = "Off-field landing · " + sub }
            if simTime > 3 { hud.showToast(rating, sub: sub, color: c, duration: 4, now: simTime) }
            calloutsDone.removeAll()
        case .liftoff:
            if firstLiftoff && simTime > 3 {
                firstLiftoff = false
                hud.showToast("POSITIVE RATE", sub: "Gear up with G · follow the cyan marker to the first ring", color: color(0.5, 0.95, 1), duration: 5, now: simTime)
            }
        case .tailStrike:
            if simTime - lastTail > 2 {
                lastTail = simTime
                audio.play("scrape", volume: 0.8)
                hud.showToast("TAIL STRIKE", sub: "Ease off the back pressure", color: color(1, 0.6, 0.3), now: simTime)
            }
        case .crash(let water, let reason):
            crashTime = simTime
            audio.play(water ? "splash" : "crash", volume: 1)
            audio.synth.alive = 0
            spawnExplosion(at: SIMD3<Float>(fm.pos), water: water)
            plane.node.isHidden = true
            hud.showToast(water ? "SPLASH DOWN" : "CRASHED", sub: reason + " · press R to restart, 2 for an air start", color: color(1, 0.35, 0.3), duration: 9, now: simTime)
        }
    }

    private func checkRings() {
        let pos = SIMD3<Float>(fm.pos)
        defer { prevPos = pos }
        guard ringIndex < world.rings.count, !fm.crashed else { return }
        let r = world.rings[ringIndex]
        let d0 = simd_dot(prevPos - r.center, r.normal), d1 = simd_dot(pos - r.center, r.normal)
        guard d0 < 0 && d1 >= 0 else { return }
        let t = d0 / (d0 - d1)
        let hit = prevPos + (pos - prevPos) * t
        guard simd_distance(hit, r.center) < r.radius + 1 else { return }
        if ringIndex == 0 { ringStart = simTime }
        ringIndex += 1
        world.highlightRing(ringIndex)
        if ringIndex == world.rings.count {
            let total = simTime - (ringStart ?? simTime)
            ringFinish = total
            audio.play("fanfare", volume: 1)
            var sub = "Time " + HUD.fmt(total)
            if bestTime == nil || total < bestTime! {
                bestTime = total
                UserDefaults.standard.set(total, forKey: "bestRingTime")
                sub += " · NEW BEST!"
            }
            hud.showToast("COURSE COMPLETE", sub: sub + " · now land at Harbor Field", color: color(0.4, 1, 0.6), duration: 7, now: simTime)
        } else {
            audio.play("chime", volume: 0.9)
            hud.showToast("RING \(ringIndex) / \(world.rings.count)", color: color(0.4, 1, 0.95), duration: 1.2, now: simTime)
        }
    }

    private func callouts() {
        guard mode == .flying, !fm.crashed else { return }
        let aglFt = fm.agl * 3.281
        if fm.onGround || aglFt > 650 { if aglFt > 650 { calloutsDone.removeAll() }; return }
        if fm.gearDown && fm.vel.y < -0.3 {
            for th in [500, 100, 50, 40, 30, 20, 10] where aglFt < Double(th) && !calloutsDone.contains(th) {
                calloutsDone.insert(th)
                audio.say(th == 500 ? "five hundred" : th == 100 ? "one hundred" : "\(th)")
                break
            }
        }
        let vs = fm.vel.y
        if fm.agl < 160 && vs < -9 && fm.agl / -vs < 5.5 && simTime - lastPullUp > 3.5 && !(fm.gearDown && vs > -6) {
            lastPullUp = simTime
            audio.play("warn", volume: 0.7)
            audio.say("Terrain. Pull up!")
        }
        if fm.stalled && simTime - lastStallVoice > 5 {
            lastStallVoice = simTime
            audio.say("Stall. Stall.")
        }
    }

    // MARK: Effects

    private func spawnExplosion(at p: SIMD3<Float>, water: Bool) {
        let holder = SCNNode()
        holder.simdPosition = p
        scene.rootNode.addChildNode(holder)
        func ps(_ setup: (SCNParticleSystem) -> Void) {
            let s = SCNParticleSystem()
            s.particleImage = dot
            s.isLightingEnabled = false
            setup(s)
            holder.addParticleSystem(s)
        }
        func keyframes(_ v: [Any]) -> SCNParticlePropertyController {
            let a = CAKeyframeAnimation(); a.values = v
            return SCNParticlePropertyController(animation: a)
        }
        if water {
            ps { s in
                s.birthRate = 6000; s.emissionDuration = 0.12; s.loops = false
                s.particleLifeSpan = 2.4; s.particleLifeSpanVariation = 0.8
                s.particleVelocity = 26; s.particleVelocityVariation = 14
                s.emittingDirection = SCNVector3(0, 1, 0); s.spreadingAngle = 35
                s.isAffectedByGravity = true
                s.particleSize = 1.6; s.particleSizeVariation = 0.8
                s.particleColor = NSColor(white: 1, alpha: 0.75)
                s.blendMode = .alpha
                s.propertyControllers = [.size: keyframes([1, 3.5]), .opacity: keyframes([1, 0.8, 0])]
            }
            ps { s in
                s.birthRate = 30; s.emissionDuration = 8; s.loops = false
                s.particleLifeSpan = 4; s.particleVelocity = 2; s.spreadingAngle = 90
                s.emittingDirection = SCNVector3(0, 1, 0)
                s.particleSize = 5; s.particleColor = NSColor(white: 0.95, alpha: 0.35)
                s.propertyControllers = [.size: keyframes([1, 4]), .opacity: keyframes([0.8, 0])]
            }
        } else {
            ps { s in
                s.birthRate = 5000; s.emissionDuration = 0.1; s.loops = false
                s.particleLifeSpan = 1.1; s.particleLifeSpanVariation = 0.5
                s.particleVelocity = 34; s.particleVelocityVariation = 22; s.spreadingAngle = 180
                s.particleSize = 3.5; s.particleSizeVariation = 2
                s.dampingFactor = 2.5
                s.blendMode = .additive
                s.particleColor = color(1, 0.7, 0.25)
                s.propertyControllers = [.size: keyframes([1, 3.2]),
                                         .color: keyframes([color(1, 0.95, 0.6), color(1, 0.5, 0.1), color(0.5, 0.1, 0.02), color(0, 0, 0)])]
            }
            ps { s in
                s.birthRate = 45; s.emissionDuration = 25; s.loops = false
                s.particleLifeSpan = 7; s.particleLifeSpanVariation = 2
                s.particleVelocity = 7; s.particleVelocityVariation = 3
                s.emittingDirection = SCNVector3(0, 1, 0); s.spreadingAngle = 25
                s.acceleration = SCNVector3(1.5, 1.5, 0)
                s.particleSize = 5; s.particleSizeVariation = 2
                s.blendMode = .alpha
                s.particleColor = NSColor(white: 0.12, alpha: 0.7)
                s.propertyControllers = [.size: keyframes([1, 7]), .opacity: keyframes([0.9, 0.5, 0])]
            }
            ps { s in
                s.birthRate = 90; s.emissionDuration = 16; s.loops = false
                s.particleLifeSpan = 0.8; s.particleVelocity = 4; s.spreadingAngle = 30
                s.emittingDirection = SCNVector3(0, 1, 0)
                s.particleSize = 2.8; s.particleSizeVariation = 1
                s.blendMode = .additive
                s.particleColor = color(1, 0.55, 0.15)
                s.propertyControllers = [.opacity: keyframes([1, 0])]
            }
            // tumbling debris
            let mat = AircraftModel.pbr(color(0.15, 0.13, 0.12), rough: 0.8)
            var rng = RNG(UInt64(simTime * 1000))
            for _ in 0..<10 {
                let b = SCNNode(geometry: SCNBox(width: CGFloat(rng.range(0.3, 1.4)), height: 0.1, length: CGFloat(rng.range(0.3, 1.2)), chamferRadius: 0))
                b.geometry?.materials = [mat]
                holder.addChildNode(b)
                let dir = SIMD3<Float>(rng.range(-1, 1), rng.range(0.6, 1.6), rng.range(-1, 1)) * rng.range(8, 20)
                let dur = Double(rng.range(1.2, 2.2))
                let apex = dir * Float(dur / 2)
                let up = SCNAction.move(by: SCNVector3(apex.x, apex.y, apex.z), duration: dur / 2)
                up.timingMode = .easeOut
                let down = SCNAction.move(by: SCNVector3(apex.x, -apex.y - 1, apex.z), duration: dur / 2)
                down.timingMode = .easeIn
                b.runAction(.group([.sequence([up, down]), .rotateBy(x: CGFloat(rng.range(-8, 8)), y: CGFloat(rng.range(-8, 8)), z: 3, duration: dur)]))
            }
        }
        holder.runAction(.sequence([.wait(duration: 40), .removeFromParentNode()]))
    }

    // MARK: Visuals & camera

    private func updateVisuals(_ dt: Float) {
        let pos = SIMD3<Float>(fm.pos)
        var shakeOff = SIMD3<Float>.zero
        if fm.onGround && fm.airspeed > 1 {
            let b = Float(fm.groundBump)
            shakeOff.y = sinf(Float(simTime) * 31) * 0.012 * b + sinf(Float(simTime) * 17.3) * 0.01 * b
        }
        plane.node.simdPosition = pos + shakeOff
        plane.node.simdOrientation = simd_quatf(fm.q)
        plane.update(dt: dt, rpm: Float(fm.rpm), pitch: Float(fm.inPitch), roll: Float(fm.inRoll), yaw: Float(fm.inYaw),
                     flap: Float(fm.flap), gear: Float(fm.gearPos), time: simTime)
        let inCockpit = cam == .cockpit && mode != .title && !fm.crashed
        plane.pilot.isHidden = inCockpit
        plane.canopy.isHidden = inCockpit
        let alive = !fm.crashed
        smoke.birthRate = smokeOn && alive && mode == .flying ? 240 : 0
        let v = alive && fm.gLoad > 2.6 && fm.airspeed > 40 ? CGFloat((fm.gLoad - 2.6) * 110) : 0
        for s in vapor { s.birthRate = v }
        if ringIndex < world.rings.count {
            let n = world.rings[ringIndex].node
            let s = 1 + 0.06 * sinf(Float(simTime) * 4)
            n.simdScale = SIMD3(s, s, s)
        }
    }

    private func updateCamera(_ dt: Float, mdx: Float, mdy: Float, scroll: Float) {
        let pPos = SIMD3<Float>(fm.pos)
        let pq = simd_quatf(fm.q)
        if !camInit { camQuat = pq; camInit = true }
        zoom = clampf(zoom * (1 - scroll * 0.08), 0.35, 4)
        let dragging = view.input.dragging
        if mdx != 0 || mdy != 0 {
            lookYaw -= mdx * 0.006
            lookPitch = clampf(lookPitch + mdy * 0.005, -1.2, 1.3)
        } else if !dragging && cam != .orbit {
            lookYaw *= max(0, 1 - dt * 1.6)
            lookPitch *= max(0, 1 - dt * 1.6)
        }
        var fov: Float = 62
        let crashed = fm.crashed

        if mode == .title || crashed || cam == .orbit {
            orbitAngle += dt * (mode == .title ? 0.12 : 0.2)
            let dist: Float = crashed ? 70 : 17 * zoom
            let target = crashed ? pPos : pPos + SIMD3(0, 0.5, 0)
            let yaw = orbitAngle + lookYaw
            let el: Float = (crashed ? 0.35 : 0.12) + lookPitch * 0.5
            var p = target + SIMD3(sinf(yaw) * cosf(el), sinf(el), cosf(yaw) * cosf(el)) * dist
            p.y = max(p.y, max(terrain.height(p.x, p.z), 0) + 1.5)
            camNode.simdPosition = p
            camNode.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            camera.zNear = 0.3
            fov = mode == .title ? 55 : 62
        } else {
            switch cam {
            case .chase:
                let k = 1 - expf(-dt * 4.5)
                camQuat = simd_slerp(camQuat, pq, k)
                let look = simd_quatf(angle: lookYaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -lookPitch, axis: SIMD3(1, 0, 0))
                let q = camQuat * look
                var p = pPos + q.act(SIMD3(0, 3.0, 15.5) * zoom)
                p.y = max(p.y, max(terrain.height(p.x, p.z), 0) + 1.2)
                camNode.simdPosition = p
                camNode.simdLook(at: pPos + q.act(SIMD3(0, 1.3, -8)), up: q.act(SIMD3(0, 1, 0)), localFront: SIMD3(0, 0, -1))
                camera.zNear = 0.3
                fov = 60 + Float(min(fm.airspeed, 100)) * 0.1
            case .cockpit:
                let eye = SIMD3<Float>(0, 1.08, -0.85)
                var jitter = SIMD3<Float>.zero
                if fm.onGround { jitter.y = sinf(Float(simTime) * 37) * 0.006 * Float(fm.groundBump) }
                if fm.stallWarning > 0.3 { jitter.x = sinf(Float(simTime) * 43) * 0.004 }
                camNode.simdPosition = pPos + pq.act(eye + jitter)
                camNode.simdOrientation = pq * simd_quatf(angle: lookYaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: lookPitch * 0.8 - 0.05, axis: SIMD3(1, 0, 0))
                camera.zNear = 0.05
                fov = 70
            case .flyby:
                let vdir = fm.airspeed > 5 ? simd_normalize(SIMD3<Float>(fm.vel)) : SIMD3<Float>(fm.forward)
                if flybyPos == nil || simd_distance(flybyPos!, pPos) > 650 || simd_dot(pPos - flybyPos!, vdir) > 220 {
                    let side = simd_normalize(simd_cross(vdir, SIMD3(0, 1, 0)))
                    var p = pPos + vdir * min(max(Float(fm.airspeed) * 5, 60), 380) + side * 30 + SIMD3(0, 6, 0)
                    p.y = max(p.y, max(terrain.height(p.x, p.z), 0) + 2)
                    flybyPos = p
                }
                camNode.simdPosition = flybyPos!
                camNode.simdLook(at: pPos, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
                let d = simd_distance(flybyPos!, pPos)
                fov = clampf(2 * atanf(14 / max(d, 1)) * 180 / .pi, 6, 60)
                camera.zNear = 0.5
            case .orbit: break
            }
        }
        camera.fieldOfView = CGFloat(fov)
    }

    private func updateAudio() {
        let s = audio.synth
        s.rpm = Float(fm.rpm)
        s.airspeed = Float(fm.airspeed)
        s.groundRoll = fm.onGround ? Float(min(fm.airspeed / 30, 1) * (0.4 + fm.groundBump)) : 0
        s.stall = Float(fm.stallWarning)
        s.cockpit = cam == .cockpit && mode != .title ? 1 : 0
        s.volume = mode == .paused ? 0.15 : 1
        if fm.crashed { s.alive = 0 }
    }

    private func updateHUD() {
        let e = fm.euler
        var st = HUDState()
        st.speedKts = fm.airspeed * 1.944
        st.altFt = fm.pos.y * 3.281
        st.aglFt = fm.agl * 3.281
        st.vsFpm = fm.vel.y * 196.85
        var hdg = e.heading * 180 / .pi
        if hdg < 0 { hdg += 360 }
        st.heading = hdg
        st.pitchDeg = e.pitch * 180 / .pi
        st.rollDeg = e.roll * 180 / .pi
        st.throttle = fm.throttle
        st.rpm = fm.rpm
        st.flaps = fm.flapSetting
        st.gearDown = fm.gearDown
        st.gearPos = fm.gearPos
        st.brake = fm.brake && fm.onGround
        st.gLoad = fm.gLoad
        st.stall = fm.stallWarning
        st.onGround = fm.onGround
        st.engineOn = fm.engineOn
        st.ringIndex = ringIndex
        st.ringCount = world.rings.count
        if let f = ringFinish { st.ringTime = f } else if let s = ringStart { st.ringTime = simTime - s }
        st.bestTime = bestTime
        st.mapPos = SIMD2(Float(fm.pos.x), Float(fm.pos.z))
        st.camName = cam.name
        st.timeName = TimeOfDay.presets[todIndex].name
        st.musicOn = audio.music.enabled
        st.assist = fm.assist
        let size = hud.scene.size
        if ringIndex < world.rings.count && !fm.crashed {
            let rc = world.rings[ringIndex].center
            st.nextRingMap = SIMD2(rc.x, rc.z)
            st.markerDist = Double(simd_distance(rc, SIMD3<Float>(fm.pos)))
            let local = camNode.simdConvertPosition(rc, from: nil)
            if local.z < 0 {
                let p = view.projectPoint(SCNVector3(rc.x, rc.y, rc.z))
                let pt = CGPoint(x: p.x, y: p.y)
                if pt.x > 40 && pt.x < size.width - 40 && pt.y > 40 && pt.y < size.height - 40 {
                    st.marker = pt
                } else {
                    st.markerAngle = atan2(pt.y - size.height / 2, pt.x - size.width / 2)
                }
            } else {
                st.markerAngle = CGFloat(atan2(local.y, local.x))
                if abs(local.x) < 0.001 && abs(local.y) < 0.001 { st.markerAngle = -.pi / 2 }
            }
        }
        hud.update(st, viewSize: size, now: simTime, flying: mode != .title)
    }
}
