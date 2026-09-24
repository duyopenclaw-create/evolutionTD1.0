import SceneKit
import SpriteKit
import simd

struct SaveData: Codable {
    var nights = 0            // nights survived
    var night = 1             // next night to play
    var totalStash = 0
    var bestStash = 0
    var streak = 0
    var extraTraps = 0

    static let key = "scurry.save.v1"
    static var disabled = false
    static func load() -> SaveData {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(SaveData.self, from: d) else { return SaveData() }
        return s
    }
    func save() {
        guard !SaveData.disabled, let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(d, forKey: SaveData.key)
    }
}

final class Game: NSObject, SCNSceneRendererDelegate {
    enum Mode { case title, playing, paused, respawning, summary }

    let view: GameView
    let scene = SCNScene()
    let kitchen: Kitchen
    let props: Props
    let rat = Rat()
    let cat: Cat
    let human = Human()
    let audio: AudioSystem
    let hud = HUD()
    let camNode = SCNNode()
    let camera = SCNCamera()

    private(set) var mode: Mode = .title
    var ignoreInput = false
    private var lastTime: TimeInterval = 0
    private(set) var simTime = 0.0
    private var save = SaveData.load()
    private var lastSave = 0.0

    // night state
    private var nightT: Float = 0                 // seconds into the night
    private var minutes: Float = 60               // clock: 60 = 1:00 AM … 330 = 5:30 AM
    private let minutesPerSecond: Float = 270.0 / 480.0
    private var lives = 3
    private var stash = 0
    private var eatenTotal: Float = 0
    private var closeCalls = 0
    private var seenByFamily = false
    private var nextVisit: Float = 150
    private var dawnWarned = false
    private var starveT: Float = 0
    private var respawnT: Float = 0
    private var respawnReason = ""
    private var nightOver = false

    // interaction
    private var eatT: Float = 0
    private var sniffT: Float = 0
    private var noise: Float = 0
    private var squeakCD: Float = 0
    private var lastClockMinute = -1
    private var dripT: Float = 0, dripFall: Float = -1
    private var ratSpeedSmooth: Float = 0
    private var inNest = false
    private var hiddenAt: String?
    private var ratLight: Float = 0

    // camera
    private var camYaw: Float = .pi, camPitch: Float = 0.3, camDist: Float = 0.55
    private var camPos = SIMD3<Float>(-1.8, 0.2, 1.8)
    private var lookIdle: Float = 0
    private var firstPerson = false
    private var titleOrbit: Float = 0
    private let titleRatPos = SIMD3<Float>(-0.55, 0, -0.8)
    private var shake: Float = 0

    // scent glints
    private var glints: [SCNNode] = []
    private let dot = softDotImage(size: 64)

    init(view: GameView, muted: Bool) {
        self.view = view
        kitchen = Kitchen()
        props = Props(kitchen: kitchen)
        cat = Cat(bed: kitchen.catBed)
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
        startNight(fresh: true)
        mode = .title
        hud.setMode(title: true, record: recordLine())
    }

    // MARK: Scene

    private func setupScene() {
        scene.rootNode.addChildNode(kitchen.root)
        scene.rootNode.addChildNode(props.root)
        scene.rootNode.addChildNode(rat.model.node)
        scene.rootNode.addChildNode(cat.model.node)
        scene.rootNode.addChildNode(human.model.node)
        scene.lightingEnvironment.contents = Tex.environment()
        scene.lightingEnvironment.intensity = 0.6

        camera.zNear = 0.005
        camera.zFar = 30
        camera.fieldOfView = 62
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.exposureAdaptationBrighteningSpeedFactor = 0.5
        camera.exposureAdaptationDarkeningSpeedFactor = 1.2
        camera.minimumExposure = -3
        camera.maximumExposure = 3.2
        camera.exposureOffset = 0.6
        camera.averageGray = 0.18
        camera.whitePoint = 1.1
        camera.bloomIntensity = 0.55
        camera.bloomThreshold = 0.9
        camera.bloomBlurRadius = 10
        camera.vignettingIntensity = 0.6
        camera.vignettingPower = 0.9
        camera.saturation = 1.0
        camera.contrast = 0.08
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 0.05
        camera.screenSpaceAmbientOcclusionBias = 0.006
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.08
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        camera.wantsDepthOfField = true
        camera.fStop = 2.2
        camera.focusDistance = 0.55
        camera.apertureBladeCount = 6
        camera.focalBlurSampleCount = 10
        camera.motionBlurIntensity = 0.25
        camera.grainIntensity = 0.12
        camera.grainScale = 1.2
        camera.colorFringeStrength = 0.4
        camera.colorFringeIntensity = 0.6
        camNode.camera = camera
        scene.rootNode.addChildNode(camNode)

        // dust motes drifting in the moonbeam (only visible where light hits them)
        let dust = SCNParticleSystem()
        dust.particleImage = dot
        dust.birthRate = 22
        dust.particleLifeSpan = 14
        dust.particleSize = 0.0012
        dust.particleSizeVariation = 0.0008
        dust.particleColor = NSColor(white: 1, alpha: 0.7)
        dust.emitterShape = SCNBox(width: 1.4, height: 1.6, length: 1.6, chamferRadius: 0)
        dust.particleVelocity = 0.006
        dust.particleVelocityVariation = 0.006
        dust.spreadingAngle = 180
        dust.isAffectedByGravity = false
        dust.acceleration = SCNVector3(0, -0.0006, 0)
        dust.isLightingEnabled = true
        dust.blendMode = .additive
        let dn = SCNNode()
        dn.simdPosition = SIMD3(-1.0, 1.0, -1.6)
        dn.addParticleSystem(dust)
        scene.rootNode.addChildNode(dn)

        for _ in 0..<14 {
            let p = SCNPlane(width: 0.035, height: 0.035)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = dot
            m.emission.contents = color(1, 0.85, 0.45)
            m.emission.intensity = 2
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.readsFromDepthBuffer = true
            p.materials = [m]
            let n = SCNNode(geometry: p)
            n.constraints = [SCNBillboardConstraint()]
            n.isHidden = true
            n.castsShadow = false
            scene.rootNode.addChildNode(n)
            glints.append(n)
        }
    }

    // MARK: Night flow

    private func startNight(fresh: Bool) {
        nightT = 0
        minutes = 60
        lives = 3
        stash = 0
        eatenTotal = 0
        closeCalls = 0
        seenByFamily = false
        dawnWarned = false
        starveT = 0
        nightOver = false
        var r = RNG(UInt64(save.night) &* 7919 &+ 17)
        nextVisit = r.range(95, 160) - Float(min(save.night, 6)) * 6
        props.reset(night: save.night, extraTraps: save.extraTraps, seed: UInt64(save.night) &* 31 &+ 5)
        cat.reset(bed: kitchen.catBed, restless: min(1, 0.2 + Float(save.night) * 0.13))
        human.reset()
        kitchen.hallLight.light?.intensity = 0
        kitchen.hallBulb.emission.intensity = 0
        respawnRat()
        rat.belly = 0.55
        rat.stamina = 1
        camDist = 0.55
        lastClockMinute = -1
    }

    private func respawnRat() {
        if let c = rat.carrying { dropCarried(at: rat.pos, lost: true); _ = c }
        rat.pos = SIMD3(kitchen.nest.x, 0, kitchen.nest.z - 0.1)
        rat.vel = .zero
        rat.yaw = .pi
        rat.climbing = nil
        rat.grounded = true
        camPos = rat.pos + SIMD3(-0.5, 0.2, 0.1)
        camYaw = 1.75
        camPitch = 0.3
    }

    func begin() {
        guard mode == .title || mode == .summary else { return }
        if mode == .summary { startNight(fresh: false) }
        mode = .playing
        hud.setMode(title: false, record: "")
        hud.hideSummary()
        hud.hideHelp()
        audio.play("blip", volume: 0.6)
        hud.showToast("NIGHT \(save.night)", sub: "1:00 AM · the house is asleep", color: color(1, 0.9, 0.7), duration: 3.5, now: simTime)
    }

    private func loseLife(_ why: String) {
        guard mode == .playing else { return }
        lives -= 1
        audio.play("squeal", volume: 0.8)
        audio.play("caught", volume: 0.9)
        shake = 1
        respawnReason = why
        mode = .respawning
        respawnT = 0
        hud.showToast(why, sub: lives > 0 ? "\(lives) \(lives == 1 ? "life" : "lives") left" : "", color: color(1, 0.5, 0.4), duration: 3, now: simTime)
    }

    private func endNight(success: Bool, reason: String) {
        guard !nightOver else { return }
        nightOver = true
        mode = .summary
        let n = save.night
        save.totalStash += stash
        save.bestStash = max(save.bestStash, stash)
        if success { save.nights += 1; save.streak += 1 } else { save.streak = 0 }
        save.extraTraps = seenByFamily ? min(4, save.extraTraps + 2) : max(0, save.extraTraps - 1)
        save.night += 1
        save.save()
        hud.flashSaved(now: simTime)
        if success { audio.play("dawn", volume: 0.8) }
        var lines = [
            reason,
            "Brought home: \(stash)",
            "Belly filled: \(Int(eatenTotal * 100)) %",
            closeCalls > 0 ? "Close calls: \(closeCalls)" : "Not a single close call",
            "Total stash \(save.totalStash)  ·  nights survived \(save.nights)  ·  streak \(save.streak)",
        ]
        if seenByFamily { lines.append("They saw you. Expect more traps tomorrow.") }
        hud.showSummary(title: success ? "Night \(n) — home safe" : "Night \(n) — a hard night", lines: lines)
    }

    private func recordLine() -> String {
        save.nights == 0 && save.totalStash == 0 ? "" : "Night \(save.night)  ·  nights survived \(save.nights)  ·  total stash \(save.totalStash)  ·  best night \(save.bestStash)"
    }

    // MARK: Loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        var dt = lastTime == 0 ? 1.0 / 60 : time - lastTime
        lastTime = time
        dt = min(max(dt, 0), 0.05)
        simTime += dt
        let fdt = Float(dt)
        handlePresses()
        let (mdx, mdy, sc) = view.input.takeMouse()
        switch mode {
        case .playing: simulate(fdt)
        case .respawning:
            respawnT += fdt
            hud.setFade(CGFloat(respawnT < 0.8 ? respawnT / 0.8 : max(0, 1 - (respawnT - 1.2) / 0.6)))
            if respawnT > 1.0 && respawnT - fdt <= 1.0 {
                respawnRat()
                human.reset()
                kitchen.hallLight.light?.intensity = 0
                kitchen.hallBulb.emission.intensity = 0
                kitchen.fridgeDoor.simdEulerAngles.y = 0
                kitchen.fridgeLight.light?.intensity = 0
                cat.wakeAlarmed(at: kitchen.catWaypoints[0])
                if lives <= 0 { endNight(success: false, reason: "Too many close shaves. You limp home.") }
            }
            if respawnT > 1.8 { hud.setFade(0); if mode == .respawning { mode = .playing } }
            ambientWorld(fdt)
        case .title:
            titleOrbit += fdt * 0.05
            ambientWorld(fdt)
        case .paused, .summary:
            break
        }
        updateVisuals(fdt)
        updateCamera(fdt, mdx: mdx, mdy: mdy, scroll: sc)
        updateAudio(fdt)
        updateHUD()
        if simTime - lastSave > 30 && mode == .playing {
            lastSave = simTime
            save.save()
            if !SaveData.disabled { hud.flashSaved(now: simTime) }
        }
    }

    private func handlePresses() {
        for k in view.input.drainPresses() {
            if ignoreInput { continue }
            if k == Key.h { hud.toggleHelp(); continue }
            if k == Key.m { audio.music.enabled.toggle(); hud.showToast(audio.music.enabled ? "MUSIC ON" : "MUSIC OFF", duration: 1.2, now: simTime); continue }
            switch mode {
            case .title, .summary:
                if k == Key.space || k == Key.ret { begin() }
            case .playing:
                if k == Key.esc { mode = .paused; hud.setPaused(true) }
                else if k == Key.f { toggleCarry() }
                else if k == Key.q { squeak() }
                else if k == Key.r { sniff() }
                else if k == Key.v { firstPerson.toggle(); hud.showToast(firstPerson ? "RAT'S-EYE VIEW" : "FOLLOW CAM", duration: 1.2, now: simTime) }
            case .paused:
                if k == Key.esc { mode = .playing; hud.setPaused(false) }
                if k == Key.n { hud.setPaused(false); endNight(success: false, reason: "You called it a night early.") }
            case .respawning: break
            }
        }
    }

    // MARK: Simulation

    private func control() -> Rat.Control {
        var c = Rat.Control()
        guard !ignoreInput else { return c }
        let inp = view.input
        var raw = SIMD2<Float>.zero
        if inp.isDown(Key.w) { raw.y += 1 }
        if inp.isDown(Key.s) { raw.y -= 1 }
        if inp.isDown(Key.a) { raw.x -= 1 }
        if inp.isDown(Key.d) { raw.x += 1 }
        if simd_length(raw) > 1 { raw = simd_normalize(raw) }
        c.raw = raw
        let fwd = SIMD2<Float>(sinf(camYaw), cosf(camYaw))
        let right = SIMD2<Float>(-cosf(camYaw), sinf(camYaw))
        let m = fwd * raw.y + right * raw.x
        c.move = firstPerson ? (SIMD2(sinf(rat.yaw), cosf(rat.yaw)) * raw.y + SIMD2(-cosf(rat.yaw), sinf(rat.yaw)) * raw.x * 0.0) : m
        if firstPerson { rat.yaw += -raw.x * 3.2 * (1.0 / 120) }
        c.dash = inp.shift
        c.creep = inp.isDown(Key.c) || inp.ctrl
        c.jump = inp.isDown(Key.space)
        return c
    }

    private var jumpHeld = false

    private func simulate(_ dt: Float) {
        nightT += dt
        minutes += dt * minutesPerSecond
        squeakCD -= dt
        var c = control()
        // jump on press, not hold
        if c.jump { if jumpHeld { c.jump = false } else { jumpHeld = true } } else { jumpHeld = false }
        let eating = view.input.isDown(Key.e) && !ignoreInput && rat.grounded && rat.climbing == nil
        if eating { c.move = .zero; c.jump = false }
        if sniffT > 3.2 { c.move = .zero }

        // rat physics in substeps
        let n = max(1, Int(ceil(dt / (1.0 / 150))))
        let h = dt / Float(n)
        for i in 0..<n {
            var ci = c
            if i > 0 { ci.jump = false }
            rat.step(h, ci, world: kitchen.world, frozen: false)
        }
        let hs = simd_length(SIMD2(rat.vel.x, rat.vel.z))
        ratSpeedSmooth += (hs - ratSpeedSmooth) * min(1, dt * 4)
        handleRatEvents(creep: c.creep)

        inNest = simd_distance(SIMD2(rat.pos.x, rat.pos.z), SIMD2(kitchen.nest.x, kitchen.nest.z)) < 0.13 && rat.pos.y < 0.02
        hiddenAt = kitchen.hideout(at: rat.pos)
        ratLight = (hiddenAt != nil || inNest) ? 0 : kitchen.lightLevel(rat.pos + SIMD3(0, 0.03, 0), lightsOn: human.lightsOn, fridgeOpen: human.fridgeOpen, dawn: dawn)

        // belly
        rat.belly = max(0, rat.belly - dt * (0.0011 + (c.dash ? 0.0012 : 0)))
        if rat.belly <= 0 { starveT += dt } else { starveT = 0 }
        if starveT > 25 { starveT = 0; rat.belly = 0.25; loseLife("Too weak from hunger.") }
        if inNest { rat.stamina = min(1, rat.stamina + dt * 0.25) }

        // eat / carry home
        if eating { eat(dt, creep: c.creep) } else { eatT = 0 }
        if inNest, let f = rat.carrying {
            stash += f.kind.value
            audio.play("stash", volume: 0.7)
            hud.showToast("+\(f.kind.value)", sub: "\(f.kind.name) stashed", color: color(1, 0.85, 0.5), duration: 2, now: simTime)
            rat.carrying = nil
            props.remove(f)
        }
        if sniffT > 0 { sniffT -= dt }

        checkTraps(creep: c.creep)
        updateKnockables(dt)

        // cat
        let groundIdx = kitchen.world.ground(rat.pos.x, rat.pos.z, y: rat.pos.y + 0.005, r: 0.02, step: 0.01).2
        cat.update(dt, world: kitchen.world, kitchen: kitchen,
                   senses: .init(ratPos: rat.pos, ratVel: rat.vel, ratLight: ratLight, ratHidden: hiddenAt, ratInNest: inNest, ratGroundSolid: groundIdx),
                   frozen: false)
        handleCatEvents()

        // person
        if !human.active && nightT > nextVisit && minutes < 318 {
            human.begin()
            var r = RNG(UInt64(nightT * 1000))
            nextVisit = nightT + r.range(120, 200) - Float(min(save.night, 6)) * 8
        }
        let ratVisibleToHuman = human.inRoom && hiddenAt == nil && !inNest && kitchen.world.visible(human.eye, rat.pos + SIMD3(0, 0.04, 0))
        human.update(dt, kitchen: kitchen, rat: rat.pos, ratVisible: ratVisibleToHuman && ratLight > 0.25, ratHidden: hiddenAt != nil || inNest)
        handleHumanEvents()

        // time of night
        if minutes >= 300 && !dawnWarned {
            dawnWarned = true
            hud.showToast("5:00 AM", sub: "Dawn is coming. Get home before the house wakes.", color: color(1, 0.8, 0.55), duration: 4, now: simTime)
            audio.play("blip", volume: 0.5)
        }
        if minutes >= 300 && inNest && rat.carrying == nil { endNight(success: true, reason: "You slipped home as the sky went grey.") }
        if minutes >= 330 && !inNest {
            seenByFamily = true
            endNight(success: false, reason: "Morning. The family found you in the kitchen.")
        }
        noise = max(0, noise - dt * 1.2)
    }

    private var dawn: Float { clampf((minutes - 290) / 40, 0, 1) }

    /// The world keeps living on the title screen and during a respawn fade.
    private func ambientWorld(_ dt: Float) {
        cat.update(dt, world: kitchen.world, kitchen: kitchen,
                   senses: .init(ratPos: SIMD3(99, 0, 99), ratVel: .zero, ratLight: 0, ratHidden: "away", ratInNest: true, ratGroundSolid: nil),
                   frozen: false)
        cat.events.removeAll()
        human.update(dt, kitchen: kitchen, rat: rat.pos, ratVisible: false, ratHidden: true)
        human.events.removeAll()
    }

    private func emitNoise(_ loud: Float, at p: SIMD3<Float>) {
        guard loud > 0.005 else { return }
        noise = max(noise, min(1, loud * 1.6))
        cat.hear(loud, at: p)
        if loud >= 0.85 && !human.active && minutes < 318 {
            nextVisit = min(nextVisit, nightT + 3)
        }
    }

    private func surfaceLoud(_ s: Surface) -> Float {
        switch s {
        case .tile: return 0.22
        case .metal: return 0.3
        case .stone: return 0.18
        case .wood: return 0.12
        case .plastic: return 0.15
        case .cardboard: return 0.35
        case .fabric: return 0.03
        }
    }

    private func stepSound(_ s: Surface) -> String {
        switch s {
        case .tile, .stone, .plastic: return "step_hard"
        case .metal: return "step_metal"
        case .wood: return "step_wood"
        case .fabric: return "step_soft"
        case .cardboard: return "step_card"
        }
    }

    private func handleRatEvents(creep: Bool) {
        let (vol, pan) = spatial(rat.pos, near: 0.6)
        for e in rat.events {
            switch e {
            case .step(let s, let k):
                audio.play(stepSound(s), volume: vol * (0.18 + 0.55 * k), pan: pan)
                emitNoise(surfaceLoud(s) * k * (creep ? 0.1 : 1), at: rat.pos)
            case .land(let s, let v):
                audio.play("land", volume: vol * min(1, 0.2 + v * 0.2), pan: pan)
                audio.play(stepSound(s), volume: vol * 0.8, pan: pan)
                emitNoise(surfaceLoud(s) * min(1.4, 0.4 + v * 0.3), at: rat.pos)
            case .jump:
                audio.play("jump", volume: vol * 0.5, pan: pan)
            case .climbStart, .climbStep:
                audio.play("scratch", volume: vol * 0.45, pan: pan)
                emitNoise(0.04, at: rat.pos)
            case .mantle:
                audio.play("scratch", volume: vol * 0.6, pan: pan)
            case .bump: break
            }
        }
        rat.events.removeAll()
    }

    private func nearestFood(maxDist: Float = 1) -> Food? {
        let m = rat.mouthWorld
        var best: Food? = nil, bd = maxDist
        for f in props.foods where !f.gone && !f.carried {
            let d = simd_distance(SIMD2(m.x, m.z), SIMD2(f.pos.x, f.pos.z))
            let reach = f.kind.reach + 0.03
            if d < reach && d < bd && abs(f.pos.y - rat.pos.y) < 0.06 { best = f; bd = d }
        }
        return best
    }

    private func eat(_ dt: Float, creep: Bool) {
        guard let f = nearestFood() else { eatT = 0; return }
        if rat.belly >= 0.995 {
            if eatT == 0 { hud.showToast("You're stuffed.", sub: "Carry food home instead (F)", duration: 1.5, now: simTime) }
            eatT = 0.001
            return
        }
        eatT += dt
        if eatT < 0.32 { return }
        eatT = 0.001
        if let t = f.trap, t.armed {
            if creep {
                // careful little nibbles; the pedal doesn't feel it
            } else {
                props.spring(t)
                audio.play("snap", volume: 1, pan: spatial(t.pos, near: 0.6).1)
                emitNoise(0.9, at: t.pos)
                loseLife("SNAP! The trap nearly got you.")
                return
            }
        }
        let bite: Float = 0.05
        let have = f.left * f.kind.nutrition
        let take = min(bite, have, 1 - rat.belly + 0.01)
        f.left -= take / f.kind.nutrition
        rat.belly = min(1, rat.belly + take)
        eatenTotal += take
        let hard: Set<FoodKind> = [.crumb, .cheerio, .kibble, .cookie, .peanut, .popcorn, .bone, .crust]
        let (vol, pan) = spatial(rat.pos, near: 0.6)
        audio.play(hard.contains(f.kind) ? "crunch" : "nibble", volume: vol * 0.7, pan: pan)
        emitNoise(hard.contains(f.kind) ? (creep ? 0.03 : 0.1) : 0.03, at: rat.pos)
        if f.left <= 0.02 {
            props.remove(f)
        } else {
            f.node.simdScale = SIMD3(repeating: 0.35 + 0.65 * sqrtf(f.left))
        }
    }

    private func toggleCarry() {
        if rat.carrying != nil {
            dropCarried(at: rat.mouthWorld, lost: false)
            return
        }
        guard rat.climbing == nil, let f = nearestFood() else { return }
        guard f.kind.carriable else {
            hud.showToast("Too big to carry", sub: "Eat it here (hold E)", duration: 1.6, now: simTime)
            return
        }
        f.carried = true
        rat.carrying = f
        f.node.removeFromParentNode()
        f.node.simdPosition = SIMD3(0, -0.004, 0.012)
        f.node.simdEulerAngles = SIMD3(0, [.fry, .bone, .crust].contains(f.kind) ? .pi / 2 : 0, 0)
        f.node.simdScale = SIMD3(repeating: 0.35 + 0.65 * sqrtf(f.left))
        rat.model.mouth.addChildNode(f.node)
        audio.play("pickup", volume: 0.5)
    }

    private func dropCarried(at p: SIMD3<Float>, lost: Bool) {
        guard let f = rat.carrying else { return }
        rat.carrying = nil
        f.node.removeFromParentNode()
        if lost { props.remove(f); return }
        let (g, _, _) = kitchen.world.ground(p.x, p.z, y: rat.pos.y + 0.02, r: 0.01, step: 0.03)
        f.pos = SIMD3(p.x, g, p.z)
        f.carried = false
        f.node.simdPosition = f.pos
        f.node.simdEulerAngles = SIMD3(0, rat.yaw, 0)
        props.root.addChildNode(f.node)
        audio.play("drop", volume: 0.5)
    }

    private func squeak() {
        guard squeakCD <= 0 else { return }
        squeakCD = 0.6
        let (vol, pan) = spatial(rat.pos, near: 0.6)
        audio.play("squeak", volume: vol * 0.9, pan: pan)
        emitNoise(0.5, at: rat.pos)
    }

    private func sniff() {
        guard rat.grounded, rat.climbing == nil else { return }
        sniffT = 4
        var i = 0
        let foods = props.foods.filter { !$0.gone && !$0.carried }.sorted { simd_distance($0.pos, rat.pos) < simd_distance($1.pos, rat.pos) }
        for f in foods where i < glints.count && simd_distance(f.pos, rat.pos) < 2.2 {
            glints[i].simdPosition = f.pos + SIMD3(0, 0.02, 0)
            glints[i].isHidden = false
            glints[i].opacity = 0
            i += 1
        }
        for j in i..<glints.count { glints[j].isHidden = true }
        audio.play("nibble", volume: 0.2)
    }

    private func checkTraps(creep: Bool) {
        guard rat.grounded else { return }
        let paws = rat.pos + rat.forward * 0.045
        for t in props.traps where t.armed {
            if abs(rat.pos.y - t.pos.y) > 0.03 { continue }
            let d = simd_distance(SIMD2(paws.x, paws.z), SIMD2(t.pedal.x, t.pedal.z))
            if d < 0.02 {
                props.spring(t)
                audio.play("snap", volume: 1, pan: spatial(t.pos, near: 0.6).1)
                emitNoise(0.9, at: t.pos)
                loseLife("SNAP! You stepped right on a trap.")
                return
            }
            let near = simd_distance(SIMD2(rat.pos.x, rat.pos.z), SIMD2(t.pos.x, t.pos.z))
            if near < 0.2 && creep == false && ratSpeedSmooth > 0.8 {
                // blundering about next to it can set it off too
                if d < 0.05 {
                    props.spring(t)
                    audio.play("snap", volume: 1, pan: spatial(t.pos, near: 0.6).1)
                    emitNoise(0.9, at: t.pos)
                    closeCalls += 1
                    hud.showToast("SNAP!", sub: "Missed you by a whisker.", color: color(1, 0.7, 0.5), duration: 2, now: simTime)
                }
            }
        }
    }

    private func updateKnockables(_ dt: Float) {
        props.animate(dt)
        for k in props.knockables where !k.broken {
            if !k.falling {
                let d = SIMD2(k.pos.x - rat.pos.x, k.pos.z - rat.pos.z)
                let dist = simd_length(d)
                if dist < k.r + rat.radius && abs(rat.pos.y - k.pos.y) < 0.05 && dist > 1e-4 {
                    let n = d / dist
                    let push = max(0.25, simd_dot(SIMD2(rat.vel.x, rat.vel.z), n))
                    k.vel.x = n.x * push * 0.8; k.vel.z = n.y * push * 0.8
                    k.pos.x = rat.pos.x + n.x * (k.r + rat.radius); k.pos.z = rat.pos.z + n.y * (k.r + rat.radius)
                    if k.resting { audio.play("tip", volume: spatial(k.pos, near: 0.6).0 * 0.6, pan: spatial(k.pos, near: 0.6).1); k.resting = false }
                }
                let sp = simd_length(SIMD2(k.vel.x, k.vel.z))
                if sp > 0 {
                    let dec = min(sp, 2.5 * dt)
                    k.vel.x -= k.vel.x / sp * dec; k.vel.z -= k.vel.z / sp * dec
                    k.pos.x += k.vel.x * dt; k.pos.z += k.vel.z * dt
                }
                let (g, _, _) = kitchen.world.ground(k.pos.x, k.pos.z, y: k.pos.y + 0.005, r: 0.004, step: 0.01)
                if g < k.pos.y - 0.01 { k.falling = true; k.spin = SIMD3(Float.random(in: 4...9), 0, Float.random(in: -6...6)) }
            } else {
                k.vel.y -= 9.81 * dt
                k.pos += k.vel * dt
                k.node.simdEulerAngles += k.spin * dt
                let (g, _, _) = kitchen.world.ground(k.pos.x, k.pos.z, y: k.pos.y, r: 0.004, step: 0.0)
                if k.pos.y <= g {
                    k.pos.y = g
                    k.falling = false
                    let (vol, pan) = spatial(k.pos, near: 2.5)
                    switch k.kind {
                    case .mug: audio.play("shatter", volume: vol, pan: pan); props.shatter(k)
                    case .glass: audio.play("glassbreak", volume: vol, pan: pan); props.shatter(k)
                    case .spoon:
                        audio.play("clatter", volume: vol, pan: pan)
                        k.vel = .zero
                        k.node.simdEulerAngles = SIMD3(0, k.node.simdEulerAngles.y, 0)
                    }
                    emitNoise(k.kind == .spoon ? 0.7 : 1.0, at: k.pos)
                    shake = max(shake, 0.3)
                }
            }
            if !k.broken { k.node.simdPosition = k.pos }
        }
    }

    private func handleCatEvents() {
        let (vol, pan) = spatial(cat.pos + SIMD3(0, 0.25, 0), near: 2)
        for e in cat.events {
            switch e {
            case .meow: audio.play("meow", volume: vol * 0.8, pan: pan)
            case .mrrp: audio.play("mrrp", volume: vol * 0.8, pan: pan)
            case .chatter: audio.play("chatter", volume: vol * 0.7, pan: pan)
            case .hiss: audio.play("hiss", volume: vol * 0.7, pan: pan)
            case .pounce: audio.play("pounce", volume: vol, pan: pan)
            case .land: audio.play("catland", volume: vol * 0.7, pan: pan)
            case .swipe: audio.play("swipe", volume: vol * 0.8, pan: pan)
            case .wake: audio.play("mrrp", volume: vol * 0.5, pan: pan); hud.showToast("The cat stirs…", duration: 2, now: simTime)
            case .purrStart: break
            case .caught: loseLife("The cat got you.")
            }
            if case .land = e, cat.state == .recover { closeCalls += 1 }
        }
        cat.events.removeAll()
    }

    private func handleHumanEvents() {
        for e in human.events {
            switch e {
            case .footstep(let p, let s):
                let (vol, pan) = spatial(p, near: 5)
                audio.play("footfall", volume: vol * (0.5 + 0.5 * s) * (p.x < -3 ? 0.55 : 1), pan: pan)
                emitNoise(0.06, at: p)
            case .lightSwitch: audio.play("switch", volume: spatial(SIMD3(-3, 1.2, 0.4), near: 4).0, pan: spatial(SIMD3(-3, 1.2, 0.4), near: 4).1)
            case .lightsOn: hud.showToast("The lights snap on!", sub: "Find a shadow, or a gap.", color: color(1, 0.9, 0.6), duration: 3, now: simTime)
            case .lightsOff: break
            case .fridgeOpen: audio.play("fridgeOpen", volume: spatial(kitchen.fridgePos, near: 4).0, pan: spatial(kitchen.fridgePos, near: 4).1)
            case .fridgeClose:
                audio.play("fridgeClose", volume: spatial(kitchen.fridgePos, near: 4).0, pan: spatial(kitchen.fridgePos, near: 4).1)
                emitNoise(0.3, at: kitchen.fridgePos)
            case .bottles: audio.play("bottles", volume: spatial(kitchen.fridgePos, near: 4).0, pan: spatial(kitchen.fridgePos, near: 4).1)
            case .yell:
                seenByFamily = true
                audio.say(["Ugh! A rat!", "Oh no. There's a rat in here!", "Get out of here!"].randomElement()!, pitch: 1.1, rate: 0.52)
                cat.wakeAlarmed(at: rat.pos)
                hud.showToast("THEY SAW YOU", sub: "Run!", color: color(1, 0.45, 0.35), duration: 2.5, now: simTime)
            case .stomp(let p):
                let (vol, pan) = spatial(p, near: 5)
                audio.play("stomp", volume: vol * 1.2, pan: pan)
                shake = 1
                emitNoise(0.5, at: p)
                let d = simd_distance(SIMD2(p.x, p.z), SIMD2(rat.pos.x, rat.pos.z))
                if d < 0.12 && rat.pos.y < 0.05 && hiddenAt == nil { loseLife("Stomped!") }
                else if d < 0.3 { closeCalls += 1 }
            case .gone: break
            case .grumble: audio.say("Ugh. I'm getting traps tomorrow.", pitch: 1.0, rate: 0.5)
            }
        }
        human.events.removeAll()
    }

    // MARK: Visuals

    private func updateVisuals(_ dt: Float) {
        // rat
        if mode == .title {
            rat.pos = titleRatPos
            rat.yaw = .pi + 0.6
        }
        rat.model.node.simdPosition = rat.pos
        rat.model.node.simdEulerAngles = SIMD3(0, rat.yaw, 0)
        var pose = RatModel.Pose()
        pose.speed = rat.climbing != nil ? abs(rat.vel.y) : simd_length(SIMD2(rat.vel.x, rat.vel.z))
        pose.turn = rat.yawRate
        pose.climbing = rat.climbing != nil
        pose.airborne = !rat.grounded && rat.climbing == nil
        pose.vy = rat.vel.y
        pose.eating = mode == .playing && view.input.isDown(Key.e) && eatT > 0 && !ignoreInput
        pose.crouch = rat.crouch
        pose.rear = sniffT > 3 ? 1 : (mode == .title ? (sinf(Float(simTime) * 0.4) > 0.6 ? 1 : 0) : 0)
        pose.sniffing = sniffT > 0
        rat.model.animate(dt, pose)
        rat.model.node.isHidden = firstPerson && mode == .playing

        // cat
        cat.model.node.simdPosition = cat.pos
        cat.model.node.simdEulerAngles = SIMD3(0, cat.yaw, 0)
        var cp = cat.pose()
        if cat.hunting || cat.state == .waitHide {
            let to = rat.pos - cat.pos
            var rel = atan2f(to.x, to.z) - cat.yaw
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            cp.headYaw = clampf(rel, -1, 1)
            cp.headPitch = clampf(atan2f(to.y - 0.25, simd_length(SIMD2(to.x, to.z))), -0.8, 0.8)
        }
        cat.model.animate(dt, cp)
        cat.model.eyeMat.emission.intensity = CGFloat(0.1 + (1 - human.lightsOn) * 0.5)

        // lights driven by the visit and by dawn
        let lo = human.lightsOn
        kitchen.ceilingLight.light?.intensity = CGFloat(lo) * 260
        kitchen.ceilingBulb.emission.intensity = CGFloat(lo) * 4
        let d = dawn
        kitchen.dawnLight.light?.intensity = CGFloat(d) * 700
        kitchen.moon.light?.intensity = CGFloat(800 * (1 - d * 0.5))
        kitchen.ambient.light?.intensity = CGFloat(30 + d * 120)
        kitchen.skyMat.emission.intensity = CGFloat(1.2 + d * 5)
        kitchen.skyMat.multiply.contents = NSColor(srgbRed: CGFloat(1), green: CGFloat(1 - d * 0.2), blue: CGFloat(1 - d * 0.45), alpha: 1)

        // clocks
        let m = Int(minutes)
        if m != lastClockMinute {
            lastClockMinute = m
            let img = Game.segmentText(clockString(m, ampm: false))
            kitchen.ovenClock.emission.contents = img
            kitchen.microClock.emission.contents = img
            let hr = Float(m) / 60, mn = Float(m % 60) / 60
            kitchen.root.childNode(withName: "hour", recursively: false)?.simdEulerAngles = SIMD3(0, 0, -hr / 12 * 2 * .pi)
            kitchen.root.childNode(withName: "minute", recursively: false)?.simdEulerAngles = SIMD3(0, 0, -mn * 2 * .pi)
        }

        // tap drip: bead forms, falls, plinks
        if dripFall < 0 {
            dripT += dt
            let grow = min(1, dripT / 2.6)
            kitchen.dripNode.simdScale = SIMD3(repeating: 0.3 + grow)
            kitchen.dripNode.simdPosition = kitchen.sinkSpout
            if dripT > 2.6 { dripFall = 0; dripT = 0 }
        } else {
            dripFall += dt
            let y = kitchen.sinkSpout.y - 4.9 * dripFall * dripFall
            kitchen.dripNode.simdPosition = SIMD3(kitchen.sinkSpout.x, y, kitchen.sinkSpout.z)
            if y <= 0.705 {
                dripFall = -1
                let (vol, pan) = spatial(SIMD3(kitchen.sinkSpout.x, 0.7, kitchen.sinkSpout.z), near: 1.5)
                audio.play("drip", volume: vol * 0.8, pan: pan)
            }
        }

        // sniff glints fade in and out
        for g in glints where !g.isHidden {
            let life = sniffT / 4
            g.opacity = CGFloat(life > 0 ? min(1, (1 - life) * 6) * min(1, life * 3) * (0.7 + 0.3 * sinf(Float(simTime) * 9)) : 0)
            if sniffT <= 0 { g.isHidden = true }
        }
    }

    private func clockString(_ m: Int, ampm: Bool) -> String {
        let h = (m / 60) % 12 == 0 ? 12 : (m / 60) % 12
        return String(format: "%d:%02d", h, m % 60) + (ampm ? " AM" : "")
    }

    /// Blue-green seven-segment-ish digits for the appliance clocks.
    static func segmentText(_ s: String) -> CGImage {
        makeImage(160, 64) { ctx in
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 64))
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            let font = NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.3, green: 0.85, blue: 1, alpha: 1)]
            let a = NSAttributedString(string: s, attributes: attrs)
            let sz = a.size()
            a.draw(at: NSPoint(x: (160 - sz.width) / 2, y: (64 - sz.height) / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: Camera

    private func updateCamera(_ dt: Float, mdx: Float, mdy: Float, scroll: Float) {
        let inp = view.input
        if !ignoreInput {
            camYaw -= mdx * 0.006
            camPitch = clampf(camPitch + mdy * 0.005, -0.35, 1.2)
            if inp.isDown(Key.left) { camYaw += dt * 2 }
            if inp.isDown(Key.right) { camYaw -= dt * 2 }
            if inp.isDown(Key.up) { camPitch = clampf(camPitch + dt * 1.2, -0.35, 1.2) }
            if inp.isDown(Key.down) { camPitch = clampf(camPitch - dt * 1.2, -0.35, 1.2) }
            camDist = clampf(camDist * (1 - scroll * 0.12), 0.22, 1.8)
        }
        if abs(mdx) + abs(mdy) > 0.01 { lookIdle = 0 } else { lookIdle += dt }

        if mode == .title {
            // slow drift at rat height near the hole
            // low across the floor: the rat sitting in the moonbeam, the counter looming behind
            let a = titleOrbit
            let look = titleRatPos + SIMD3(0, 0.05, 0)
            let pos = look + SIMD3(0.35 + sinf(a) * 0.12, 0.05 + sinf(a * 0.7) * 0.02, 0.55)
            camNode.simdPosition = pos
            camNode.simdLook(at: look + SIMD3(-0.05, 0.1, 0), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            camera.focusDistance = CGFloat(simd_distance(pos, look))
            camera.fieldOfView = 55
            return
        }

        if firstPerson {
            let eye = rat.pos + rat.forward * 0.085 + SIMD3(0, rat.climbing != nil ? 0.11 : 0.05, 0)
            camNode.simdPosition = eye
            let pitch = camPitch - 0.3
            let look = SIMD3<Float>(sinf(rat.yaw) * cosf(pitch), -sinf(pitch), cosf(rat.yaw) * cosf(pitch))
            camNode.simdLook(at: eye + look, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
            camYaw = rat.yaw
            camera.fieldOfView = 78
            camera.focusDistance = 0.8
            camera.fStop = 5.6
            return
        }
        camera.fieldOfView = 62
        camera.fStop = 2.2

        // gently swing behind the rat when it runs and the player isn't steering the camera
        let spd = simd_length(SIMD2(rat.vel.x, rat.vel.z))
        if lookIdle > 1.2 && spd > 0.4 && rat.climbing == nil {
            var dy = rat.yaw - camYaw
            while dy > .pi { dy -= 2 * .pi }
            while dy < -.pi { dy += 2 * .pi }
            if abs(dy) < 2.4 { camYaw += dy * min(1, dt * 0.8) }
        }
        var target = rat.pos + SIMD3(0, 0.05, 0)
        var yaw = camYaw, pitch = camPitch
        if let cl = rat.climbing {
            // on a wall: look at it from behind and below
            target = rat.pos + SIMD3(0, 0.09, 0)
            yaw = atan2f(-cl.normal.x, -cl.normal.z)
            pitch = 0.15
        }
        // if a wall is right behind, rise up and look down over the rat instead
        let skip: (Int) -> Bool = { let n = self.kitchen.world.solids[$0].name; return n == "gate" || n == "chair leg" || n == "table leg" }
        var want = target
        for (k, p) in [pitch, max(pitch, 0.75), max(pitch, 1.1)].enumerated() {
            let dir = SIMD3<Float>(sinf(yaw) * cosf(p), -sinf(p), cosf(yaw) * cosf(p))
            want = target - dir * camDist
            guard let t = kitchen.world.raycast(target, want, skip: skip) else { break }
            if t > 0.55 || k == 2 {
                want = target + (want - target) * max(0.08, t - 0.03 / camDist)
                break
            }
        }
        want.y = max(want.y, 0.012)
        camPos += (want - camPos) * min(1, dt * 10)
        var p = camPos
        if shake > 0 {
            shake = max(0, shake - dt * 2.5)
            p += SIMD3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * shake * 0.01
        }
        camNode.simdPosition = p
        camNode.simdLook(at: target, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        camera.focusDistance = CGFloat(max(0.1, simd_distance(p, target)))
    }

    // MARK: Audio

    /// Volume and pan for a world-space source heard from the camera.
    private func spatial(_ p: SIMD3<Float>, near: Float) -> (Float, Float) {
        let lp = camNode.simdPosition
        let right = camNode.simdWorldRight
        let d = p - lp
        let dist = simd_length(d)
        let pan = dist > 0.01 ? simd_dot(d / dist, right) * 0.8 : 0
        let vol = 1 / (1 + (dist / near) * (dist / near))
        return (vol, pan)
    }

    private func updateAudio(_ dt: Float) {
        let a = audio.ambient
        let (fv, fp) = spatial(kitchen.fridgePos, near: 1.8)
        a.fridgeGain = fv * 0.9; a.fridgePan = fp
        let (cv, cpn) = spatial(kitchen.wallClock, near: 2.2)
        a.clockGain = cv; a.clockPan = cpn
        let (wv, wp) = spatial(SIMD3(-1.2, 1.5, -2.5), near: 2.5)
        a.windGain = wv * 0.35; a.windPan = wp
        let (pv, pp) = spatial(cat.pos + SIMD3(0, 0.1, 0), near: 0.8)
        a.purrGain = cat.state == .sleeping ? pv : 0; a.purrPan = pp
        a.buzz = human.lightsOn
        a.underStove = hiddenAt != nil ? 0.8 : 0
        a.master = mode == .paused ? 0.3 : 1
        var danger: Float = 0
        if mode == .playing || mode == .respawning {
            let catD = simd_distance(cat.pos, rat.pos)
            danger = cat.danger * clampf(1.6 - catD * 0.4, 0, 1)
            if human.phase == .stomping || human.phase == .alarmed { danger = 1 }
            if human.inRoom { danger = max(danger, 0.4 + human.spotted * 0.6) }
        }
        a.heart = danger * 0.9
        a.heartRate = 72 + danger * 90
        let mu = audio.music
        mu.explore = mode == .playing && ratSpeedSmooth > 0.15 ? 1 : 0
        mu.tension = mode == .title ? 0 : max(cat.hunting ? 1 : cat.danger * 0.6, human.inRoom ? (human.phase == .stomping ? 1 : 0.55) : 0)
        mu.home = mode == .title ? 0.6 : (inNest ? 1 : 0)
        mu.volume = mode == .summary ? 0.5 : 0.75
    }

    // MARK: HUD

    private func updateHUD() {
        var st = HUDState()
        let m = Int(minutes)
        st.clock = clockString(m, ampm: true)
        st.night = save.night
        st.stash = stash
        st.carrying = rat.carrying?.kind.name
        st.belly = rat.belly
        st.stamina = rat.stamina
        st.lives = lives
        st.visibility = ratLight
        st.noise = noise
        st.hidden = inNest ? "home" : hiddenAt
        st.spotted = human.inRoom && !human.sawRat ? human.spotted : 0
        switch human.phase {
        case .approaching:
            st.threat = "FOOTSTEPS IN THE HALL"; st.threatColor = color(1, 0.8, 0.5)
        case .entering, .atFridge, .leaving:
            st.threat = "SOMEONE'S IN THE KITCHEN"; st.threatColor = color(1, 0.7, 0.4)
        case .alarmed, .stomping:
            st.threat = "THEY'VE SEEN YOU!"; st.threatColor = color(1, 0.35, 0.3)
        default:
            st.threat = "CAT · \(cat.stateName)"
            st.threatColor = cat.danger >= 1 ? color(1, 0.35, 0.3) : cat.danger > 0.3 ? color(1, 0.8, 0.4) : NSColor(white: 1, alpha: 0.55)
        }
        // context prompt
        if mode == .playing {
            if inNest {
                st.prompt = minutes >= 300 ? "HOME — the night is done" : "HOME — safe. Bring food back here."
            } else if rat.climbing != nil {
                st.prompt = "W / S  climb    ·    SPACE  kick off"
            } else if let c = rat.carrying {
                st.prompt = "F  drop \(c.kind.name)    ·    take it home to stash it"
            } else if let f = nearestFood() {
                if let t = f.trap, t.armed {
                    st.prompt = "E  nibble the bait — only while creeping (C), or it snaps"
                } else {
                    st.prompt = "E  eat \(f.kind.name)" + (f.kind.carriable ? "    ·    F  carry" : "")
                }
            } else if minutes >= 300 {
                st.prompt = "Get home!"
            }
        }
        hud.update(st, viewSize: view.bounds.size, now: simTime)
    }

    // MARK: Dev hooks

    func devStart(pos: SIMD3<Float>?, yaw: Float?) {
        begin()
        if let p = pos {
            rat.pos = p
            let (g, _, _) = kitchen.world.ground(p.x, p.z, y: p.y + 0.01, r: 0.02, step: 0.02)
            rat.pos.y = g
            camPos = rat.pos + SIMD3(0, 0.2, 0.4)
        }
        if let y = yaw { rat.yaw = y; camYaw = y }
    }
    func devCamera(yaw: Float?, pitch: Float?, dist: Float?) {
        if let y = yaw { camYaw = y }
        if let p = pitch { camPitch = p }
        if let d = dist { camDist = d }
        lookIdle = -1000
    }
    func devHuman() { human.begin() }
    func devTime(_ m: Float) { minutes = m }
    func devCatChase() { cat.wakeAlarmed(at: rat.pos); cat.awareness = 1.5 }
    func devFirstPerson() { firstPerson = true }
    func devSummary() { begin(); endNight(success: true, reason: "You slipped home as the sky went grey.") }
    func devSniff() { sniff() }
    func devCatPos(_ p: SIMD3<Float>, yaw: Float) { cat.pos = p; cat.yaw = yaw; cat.wakeAlarmed(at: p) }
}

// MARK: - Automated physics checks (--autotest)

extension Game {
    func autotest() {
        audio.selfCheck()
        let w = kitchen.world
        func run(_ name: String, from p: SIMD3<Float>, move: SIMD2<Float>, secs: Float, jumpAt: [Float] = [], dash: Bool = false, until: Float? = nil, expect: (Rat) -> Bool) {
            let r = Rat()
            r.pos = p
            let (g, _, _) = w.ground(p.x, p.z, y: p.y + 0.01, r: 0.02, step: 0.02)
            r.pos.y = g
            var t: Float = 0
            let h: Float = 1.0 / 150
            var jumps = jumpAt
            var maxY: Float = 0
            var climbed = false
            while t < secs {
                var c = Rat.Control()
                let arrived = until.map { r.grounded && r.pos.y >= $0 - 0.01 } ?? false
                c.move = arrived ? .zero : move
                c.raw = SIMD2(0, simd_length(c.move) > 0 ? 1 : 0)
                c.dash = dash
                if let j = jumps.first, t >= j { c.jump = !arrived; jumps.removeFirst() }
                r.step(h, c, world: w, frozen: false)
                r.events.removeAll()
                maxY = max(maxY, r.pos.y)
                if r.climbing != nil { climbed = true }
                t += h
            }
            let ok = expect(r)
            print(String(format: "%@ %@  pos (%.2f, %.3f, %.2f) maxY %.2f climbed %@ hidden %@", ok ? "PASS" : "FAIL", name,
                         r.pos.x, r.pos.y, r.pos.z, maxY, climbed ? "yes" : "no", kitchen.hideout(at: r.pos) ?? "-"))
        }
        run("walk 1 s", from: SIMD3(0.5, 0, 1.8), move: SIMD2(0, -1), secs: 1) { $0.pos.z < 0.9 && $0.pos.z > 0.6 }
        run("stool → counter", from: SIMD3(-1.2, 0, -1.25), move: SIMD2(0, -1), secs: 3, jumpAt: [0.05, 0.8, 1.6].filter { _ in true }, until: 0.9) { abs($0.pos.y - 0.9) < 0.01 }
        run("climb chair leg", from: SIMD3(0.0675, 0, -0.3), move: SIMD2(0, -1), secs: 2.5, until: 0.46) { abs($0.pos.y - 0.46) < 0.01 }
        run("climb table leg", from: SIMD3(-0.015, 0, 0.25), move: SIMD2(0, -1), secs: 3.5, until: 0.76) { abs($0.pos.y - 0.76) < 0.02 }
        run("towel → stove top", from: SIMD3(0.23, 0, -1.55), move: SIMD2(0, -1), secs: 3.5, jumpAt: [0.1]) { $0.pos.y > 0.8 }
        run("under the stove", from: SIMD3(0.28, 0, -1.6), move: SIMD2(0, -1), secs: 1.5) { self.kitchen.hideout(at: $0.pos) != nil }
        run("under the fridge", from: SIMD3(1.65, 0, -1.4), move: SIMD2(0, -1), secs: 1.5) { self.kitchen.hideout(at: $0.pos) != nil }
        run("hop onto chair", from: SIMD3(0.25, 0, 0.25), move: SIMD2(0, -1), secs: 1.2, jumpAt: [0.05], until: 0.46) { abs($0.pos.y - 0.46) < 0.01 }
        run("wall stops rat", from: SIMD3(0, 0, 2.2), move: SIMD2(0, 1), secs: 1.5, dash: true) { $0.pos.z < 2.5 }
        run("table from chair", from: SIMD3(0.25, 0.46, -0.3), move: SIMD2(0, 1), secs: 1.5, jumpAt: [0.08], until: 0.76) { abs($0.pos.y - 0.76) < 0.01 }
        run("recycling crate", from: SIMD3(2.45, 0, -1.8), move: SIMD2(0, -1), secs: 1.2, jumpAt: [0.05], until: 0.46) { abs($0.pos.y - 0.46) < 0.01 }
        run("bin bag climb", from: SIMD3(-2.62, 0, -0.85), move: SIMD2(0, -1), secs: 2, until: 0.2) { $0.pos.y > 0.15 }
        func catRun(_ name: String, rat rp: SIMD3<Float>, cat cp: SIMD3<Float>, secs: Float, lit: Float, wake: Bool, expect: (Bool, Cat) -> Bool) {
            let c = Cat(bed: kitchen.catBed)
            c.reset(bed: cp, restless: 0.5)
            if wake { c.wakeAlarmed(at: rp) }
            var t: Float = 0, caught = false
            var states: [String] = []
            while t < secs {
                let hid = kitchen.hideout(at: rp)
                c.update(1.0 / 60, world: w, kitchen: kitchen, senses: .init(ratPos: rp, ratVel: .zero, ratLight: lit, ratHidden: hid, ratInNest: false, ratGroundSolid: w.ground(rp.x, rp.z, y: rp.y + 0.005, r: 0.02, step: 0.01).2), frozen: false)
                if c.events.contains(where: { if case .caught = $0 { return true }; return false }) { caught = true; break }
                c.events.removeAll()
                if states.last != c.stateName { states.append(c.stateName) }
                t += 1.0 / 60
            }
            let ok = expect(caught, c)
            print(String(format: "%@ %@  caught %@ after %.1fs  cat (%.2f, %.2f, %.2f)  %@", ok ? "PASS" : "FAIL", name, caught ? "yes" : "no", t, c.pos.x, c.pos.y, c.pos.z, states.joined(separator: ">")))
        }
        catRun("cat catches rat in the open", rat: SIMD3(-0.8, 0, 1.2), cat: SIMD3(0.8, 0, 1.9), secs: 15, lit: 0.6, wake: true) { caught, _ in caught }
        catRun("sleeping cat ignores dark rat", rat: SIMD3(0.5, 0, 1.6), cat: kitchen.catBed, secs: 10, lit: 0.1, wake: false) { caught, _ in !caught }
        catRun("rat safe under stove", rat: SIMD3(0.28, 0, -2.3), cat: SIMD3(0.3, 0, -0.9), secs: 15, lit: 0.5, wake: true) { caught, _ in !caught }
        catRun("cat hops onto table", rat: SIMD3(0.6, 0.76, 0.6), cat: SIMD3(1.8, 0, 0.6), secs: 15, lit: 0.6, wake: true) { caught, c in c.pos.y > 0.7 || caught }
        run("into sink", from: SIMD3(-1.2, 0.9, -1.93), move: SIMD2(0, -1), secs: 0.8, until: 2) { abs($0.pos.y - 0.7) < 0.01 }
    }
}
