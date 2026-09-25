import SceneKit
import SpriteKit
import simd

struct SaveData: Codable {
    var money = 0
    var ownedMaps = [Bool](repeating: false, count: maps.count)
    var ownedHeights = [Bool](repeating: false, count: 10)
    var upLevels = [Int](repeating: 0, count: 5)
    var ownedAbilities = [Bool](repeating: false, count: 7)
    var map = 0, heightIdx = 0
    var falls = 0, totalEarned = 0, bestFall = 0, totalBones = 0
    var musicOn = true

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        money = (try? c.decode(Int.self, forKey: .money)) ?? 0
        ownedMaps = (try? c.decode([Bool].self, forKey: .ownedMaps)) ?? ownedMaps
        ownedHeights = (try? c.decode([Bool].self, forKey: .ownedHeights)) ?? ownedHeights
        upLevels = (try? c.decode([Int].self, forKey: .upLevels)) ?? upLevels
        ownedAbilities = (try? c.decode([Bool].self, forKey: .ownedAbilities)) ?? ownedAbilities
        while ownedAbilities.count < abilities.count { ownedAbilities.append(false) }
        map = (try? c.decode(Int.self, forKey: .map)) ?? 0
        heightIdx = (try? c.decode(Int.self, forKey: .heightIdx)) ?? 0
        falls = (try? c.decode(Int.self, forKey: .falls)) ?? 0
        totalEarned = (try? c.decode(Int.self, forKey: .totalEarned)) ?? 0
        bestFall = (try? c.decode(Int.self, forKey: .bestFall)) ?? 0
        totalBones = (try? c.decode(Int.self, forKey: .totalBones)) ?? 0
        musicOn = (try? c.decode(Bool.self, forKey: .musicOn)) ?? true
        while upLevels.count < upgrades.count { upLevels.append(0) }
        // saves from before the forest update had 10 maps in a different order
        if ownedMaps.count < maps.count {
            var owned = [Bool](repeating: false, count: maps.count)
            for (i, o) in ownedMaps.enumerated() where o && i < oldMapOrder.count {
                if let j = maps.firstIndex(where: { $0.name == oldMapOrder[i] }) { owned[j] = true }
            }
            if map < oldMapOrder.count, let j = maps.firstIndex(where: { $0.name == oldMapOrder[map] }) { map = j } else { map = 0 }
            ownedMaps = owned
        }
    }

    static var disabled = false
    static let key = "bonefall.save.v1"
    static func load() -> SaveData {
        var s = SaveData()
        if !disabled, let d = UserDefaults.standard.data(forKey: key), let l = try? JSONDecoder().decode(SaveData.self, from: d) { s = l }
        s.ownedMaps[0] = true; s.ownedHeights[0] = true
        return s
    }
    static func save(_ s: SaveData) {
        guard !disabled, let d = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(d, forKey: key)
    }
}

enum Phase { case title, shop, ready, falling, stuck, resting, results }

final class Game: NSObject, SCNSceneRendererDelegate {
    let view: GameView
    let scene = SCNScene()
    let world = World()
    let audio: AudioSystem
    let hud = HUD()
    let camNode = SCNNode(), camera = SCNCamera()
    let rd = Ragdoll()
    let inj = Injuries()
    let body = BodyView()
    var save = SaveData.load()
    var ignoreInput = false
    var autoplay = false
    var backing: CGFloat = 2
    var devFreezeCam: (V3, V3)?
    var headless = false
    var devJet = false
    private weak var renderer: SCNSceneRenderer?

    private(set) var phase: Phase = .title
    private var phaseT: Float = 0
    private var cursorCol = 3, cursorRow = 0
    private var hover: String?

    // run-up
    private var heading: Float = 0
    private var runPos = V3.zero, runSpeed: Float = 0, runPhase: Float = 0
    private static let startZ: Float = -14
    private var edge = V3.zero

    // fall
    private var acc: Float = 0
    private var fallCash: Float = 0
    private var combo = 0, comboT: Float = 0, bestCombo = 0
    private var topSpeed: Float = 0, fallTime: Float = 0, restT: Float = 0
    private var wriggles = 3
    private var timeScale: Float = 1, slowT: Float = 0, slowCooldown: Float = 0, shake: Float = 0
    private var voiceCD: Float = 0, thudCD: Float = 0, scrapeCD: Float = 0, coinCD: Float = 0, toastCD: Float = 0, bloodCD: Float = 0
    private var screaming = false
    private var camMode = 0
    private(set) var warp: Float = 1
    private var usesLeft = [Int](repeating: 0, count: 7)
    private var fuel: Float = 0, jetCD: Float = 0, jetting = false
    private var massT: Float = 0, magnetT: Float = 0, bulletT: Float = 0, flameT: Float = 0
    private var calmT: Float = 0
    private var pushes = 0
    private var floaters: [(node: SKNode, wp: V3, born: Double)] = []
    private var pushY: Float = 0
    private var airT: Float = 0
    private var camYaw: Float = 0.9, camPitch: Float = 0.28, camDist: Float = 7, camVel = V3.zero, lookVel = V3.zero
    private var fractured = Set<Region>()
    private var dust: SCNParticleSystem!, blood: SCNParticleSystem!

    // camera
    private var camPos = V3(30, 20, 30), camLook = V3(0, 10, 0)
    private var orbit: Float = 0
    private var lastTime = 0.0, lastSave = 0.0, simTime = 0.0
    private var rng = RNG(UInt64(Date().timeIntervalSince1970))

    init(view: GameView, muted: Bool) {
        self.view = view
        audio = AudioSystem(muted: muted)
        super.init()
        setupScene()
        view.scene = scene
        view.delegate = self
        view.pointOfView = camNode
        view.overlaySKScene = hud.scene
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.backgroundColor = .black
        audio.music.on = save.musicOn ? 1 : 0
        buildWorld()
        enter(.title)
    }

    private func setupScene() {
        camera.zNear = 0.08
        camera.zFar = 3000
        camera.fieldOfView = 60
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.25
        camera.bloomIntensity = 0.35
        camera.bloomThreshold = 1.1
        camera.bloomBlurRadius = 10
        camera.vignettingIntensity = 0.45
        camera.vignettingPower = 0.7
        camera.saturation = 1.08
        camera.contrast = 0.12
        camera.screenSpaceAmbientOcclusionIntensity = 0.55
        camera.screenSpaceAmbientOcclusionRadius = 0.35
        camera.screenSpaceAmbientOcclusionBias = 0.03
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.25
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        camNode.camera = camera
        scene.rootNode.addChildNode(camNode)
        scene.rootNode.addChildNode(world.root)
        scene.rootNode.addChildNode(body.root)
        dust = SCNParticleSystem()
        dust.birthRate = 0
        dust.particleLifeSpan = 1.2
        dust.particleLifeSpanVariation = 0.4
        dust.particleSize = 0.25
        dust.particleSizeVariation = 0.15
        dust.particleImage = softDotImage()
        dust.particleVelocity = 1.4
        dust.particleVelocityVariation = 1
        dust.spreadingAngle = 180
        dust.acceleration = SCNVector3(0, -1.5, 0)
        dust.blendMode = .alpha
        dust.particleColor = NSColor(white: 0.8, alpha: 0.5)
        dust.propertyControllers = [.opacity: SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation(); a.values = [0.6, 0.35, 0]; a.keyTimes = [0, 0.4, 1]; return a }())]
        blood = SCNParticleSystem()
        blood.particleLifeSpan = 0.9
        blood.particleSize = 0.035
        blood.particleSizeVariation = 0.02
        blood.particleImage = softDotImage(size: 32, hardness: 0.8)
        blood.particleColor = color(0.45, 0.02, 0.03)
        blood.particleVelocity = 2.4
        blood.particleVelocityVariation = 1.5
        blood.spreadingAngle = 70
        blood.acceleration = SCNVector3(0, -9.8, 0)
        blood.blendMode = .alpha
        blood.loops = false
        blood.emissionDuration = 0.05
    }

    // MARK: world

    private var H: Float { heights[save.heightIdx] }
    private var map: MapDef { maps[save.map] }
    private func lvl(_ u: Int) -> Int { save.upLevels[u] }
    private var runMax: Float { 5.5 + 1.3 * Float(lvl(Up.run)) }

    private func buildWorld() {
        world.build(map: map, height: H, scene: scene)
        rd.boxes = world.level.boxes
        world.stream(focus: V3(0, H, -5), cam: V3(0, H, -5), budget: 999)
        rd.capsules = world.capsules
        camera.zFar = Double(max(4000, H * 3))
        rd.surface = Surface(friction: map.friction, bounce: map.bounce, hardness: map.hardness * 0.9, sharp: 0)
        rd.rockSurface = Surface(friction: max(map.friction, 0.35), bounce: map.bounce + 0.05, hardness: map.hardness * 1.15, sharp: map.sharp)
        edge = V3(0, H, 0)
        audio.ambient.gulls = map.extra == .sea
        audio.ambient.rumble = map.extra == .lava
        dust.particleColor = color(mix3(map.ground, V3(0.85, 0.85, 0.85), 0.5)).withAlphaComponent(0.6)
        resetRunner()
    }

    private func resetRunner() {
        body.jetpack.isHidden = !save.ownedAbilities[6]
        heading = 0
        runPos = V3(0, H, Game.startZ)
        runSpeed = 0; runPhase = 0
        rd.resetFractures()
        fractured.removeAll()
        rd.place(pose: Ragdoll.restPose, at: runPos, yaw: heading)
        body.update(rd)
        inj.reset()
        body.tint(inj)
        hud.mini.set(inj.state, flash: false)
    }

    // MARK: loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        self.renderer = renderer
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, time - lastTime)
        lastTime = time
        let f = ignoreInput ? InputState.Frame() : view.input.frame()
        step(Float(dt), input: f)
    }

    func step(_ dt: Float, input f: InputState.Frame) {
        simTime += Double(dt)
        phaseT += dt
        if f.pressed(Key.m) {
            save.musicOn.toggle()
            audio.music.on = save.musicOn ? 1 : 0
            persist()
        }
        if f.pressed(Key.c) { camMode = (camMode + 1) % 3 }
        if !headless { hover = hud.hit(f.mouse) }
        switch phase {
        case .title:
            orbit += dt * 0.05
            if f.pressed(Key.space, Key.ret, Key.enter) || !f.clicks.isEmpty { audio.play("select"); enter(.shop) }
        case .shop: shopInput(f)
        case .ready: runStep(dt, f)
        case .falling, .stuck, .resting: fallStep(dt, f)
        case .results:
            orbit += dt * 0.15
            if f.pressed(Key.space) || (!f.clicks.isEmpty && phaseT > 0.5) { audio.play("select"); enter(.ready) }
            else if f.pressed(Key.ret, Key.enter, Key.esc) { audio.play("select"); enter(.shop) }
        }
        if simTime - lastSave > 30 { persist() }
        updateCamera(dt)
        world.placeSun(at: phase == .shop || phase == .title ? V3(0, H * 0.5, world.level.baseZ * 0.5) : rd.com)
        if !headless { updateHUD(Double(dt)) }
    }

    private func persist() {
        lastSave = simTime
        SaveData.save(save)
        if !SaveData.disabled && !headless { hud.flashSaved() }
    }
    func saveNow() { SaveData.save(save) }

    func enter(_ p: Phase) {
        phase = p
        phaseT = 0
        switch p {
        case .title:
            hud.setMode(.title)
            audio.music.mood = .menu
        case .shop:
            hud.setMode(.shop)
            audio.music.mood = .menu
            resetRunner()
            audio.ambient.rush = 0
        case .ready:
            hud.setMode(.ready)
            audio.music.mood = .ready
            resetRunner()
            audio.ambient.rush = 0
            camPos = runPos + V3(0, 3, -6)
        case .falling:
            hud.setMode(.fall)
            audio.music.mood = .fall
        case .stuck, .resting:
            break
        case .results:
            hud.setMode(.results)
            audio.music.mood = .results
        }
    }

    // MARK: shop

    private func colCount(_ c: Int) -> Int { [maps.count, heights.count, upgrades.count + abilities.count, 1][c] }

    private func shopInput(_ f: InputState.Frame) {
        if f.pressed(Key.esc) { enter(.title); return }
        if f.pressed(Key.up, Key.w) {
            if cursorCol == 3 { cursorCol = 0; cursorRow = maps.count - 1 } else { cursorRow = max(0, cursorRow - 1) }
            audio.play("click")
        }
        if f.pressed(Key.down, Key.s) {
            if cursorCol < 3 { if cursorRow >= colCount(cursorCol) - 1 { cursorCol = 3 } else { cursorRow += 1 } }
            audio.play("click")
        }
        if f.pressed(Key.left, Key.a) {
            if cursorCol == 3 { cursorCol = 0; cursorRow = save.map } else if cursorCol > 0 { cursorCol -= 1; cursorRow = min(cursorRow, colCount(cursorCol) - 1) }
            audio.play("click")
        }
        if f.pressed(Key.right, Key.d) {
            if cursorCol == 3 { cursorCol = 2; cursorRow = 0 } else if cursorCol < 2 { cursorCol += 1; cursorRow = min(cursorRow, colCount(cursorCol) - 1) }
            audio.play("click")
        }
        if f.pressed(Key.space) { startRun(); return }
        if f.pressed(Key.ret, Key.enter) {
            if cursorCol == 3 { startRun(); return }
            if cursorCol == 2 && cursorRow >= upgrades.count { activate("ab:\(cursorRow - upgrades.count)") }
            else { activate(["map", "h", "up"][cursorCol] + ":\(cursorRow)") }
        }
        for c in f.clicks {
            guard let name = hud.hit(c) else { continue }
            if name == "jump" { startRun(); return }
            activate(name)
        }
    }

    private func startRun() {
        audio.play("select")
        enter(.ready)
    }

    private func buy(_ cost: Int, what: String) -> Bool {
        guard save.money >= cost else {
            audio.play("nope")
            hud.showToast("NOT ENOUGH CASH", "\(what) costs \(money(cost))", color: color(1, 0.5, 0.4))
            return false
        }
        save.money -= cost
        audio.play("buy"); audio.play("cash", volume: 0.6)
        return true
    }

    private func activate(_ name: String) {
        let parts = name.split(separator: ":")
        guard parts.count == 2, let i = Int(parts[1]) else { return }
        switch parts[0] {
        case "map":
            cursorCol = 0; cursorRow = i
            if !save.ownedMaps[i] {
                guard buy(maps[i].cost, what: maps[i].name) else { return }
                save.ownedMaps[i] = true
                hud.showToast("UNLOCKED!", maps[i].name, color: color(1, 0.85, 0.3))
            } else { audio.play("select") }
            if save.map != i { save.map = i; buildWorld() }
        case "h":
            cursorCol = 1; cursorRow = i
            if !save.ownedHeights[i] {
                guard buy(heightCosts[i], what: "\(Int(heights[i])) m") else { return }
                save.ownedHeights[i] = true
                hud.showToast("HIGHER!", "\(Int(heights[i])) m unlocked", color: color(1, 0.85, 0.3))
            } else { audio.play("select") }
            if save.heightIdx != i { save.heightIdx = i; buildWorld() }
        case "up":
            cursorCol = 2; cursorRow = i
            let u = upgrades[i], l = save.upLevels[i]
            guard l < u.max else { audio.play("nope"); return }
            guard buy(u.costs[l], what: u.name) else { return }
            save.upLevels[i] += 1
            hud.showToast("UPGRADED!", "\(u.name) level \(l + 1)", color: color(0.55, 1, 0.45))
        case "ab":
            cursorCol = 2; cursorRow = upgrades.count + i
            guard !save.ownedAbilities[i] else { audio.play("select"); return }
            guard buy(abilities[i].cost, what: abilities[i].name) else { return }
            save.ownedAbilities[i] = true
            body.jetpack.isHidden = !save.ownedAbilities[6]
            hud.showToast("NEW ABILITY!", "\(abilities[i].name) — press \(i + 1) while falling", color: color(0.5, 0.85, 1))
        default: return
        }
        persist()
    }

    // MARK: run-up

    /// Procedural running pose in body space (facing +z). `ph` is the stride phase, `a` how hard we run (0 = standing).
    static func runPose(_ ph: Float, _ a: Float) -> [V3] {
        var p = Ragdoll.restPose
        func rot(_ v: V3, _ ang: Float) -> V3 { V3(v.x, v.y * cosf(ang) - v.z * sinf(ang), v.y * sinf(ang) + v.z * cosf(ang)) }
        let bob = abs(sinf(ph)) * 0.05 * a - 0.04 * a
        for (hip, kn, an, toe, off) in [(PI.lHip, PI.lKn, PI.lAn, PI.lToe, Float(0)), (PI.rHip, PI.rKn, PI.rAn, PI.rToe, .pi)] {
            let s = ph + off
            let th = sinf(s) * 0.75 * a
            let bend = (0.15 + 1.1 * max(0, sinf(s + 1.7))) * a
            let h = p[hip] + V3(0, bob, 0)
            let k = h + rot(V3(0, -0.42, 0), th)
            let an2 = k + rot(V3(0, -0.42, 0), th - bend)
            let footAng = (th - bend) * 0.6
            p[hip] = h; p[kn] = k; p[an] = an2
            p[toe] = an2 + rot(V3(0, -0.06, 0.17), footAng)
        }
        for (sh, el, ha, off) in [(PI.lSh, PI.lEl, PI.lHa, Float.pi), (PI.rSh, PI.rEl, PI.rHa, 0)] {
            let s = ph + off
            let phi = sinf(s) * 0.7 * a
            let e = p[sh] + rot(V3(0, -0.3, 0), phi)
            p[el] = e
            p[ha] = e + rot(V3(0, -0.28, 0), phi + 1.2 * a)
        }
        let lean = 0.25 * a
        let pel = p[PI.pelvis]
        for i in [PI.head, PI.neck, PI.chest, PI.lSh, PI.rSh, PI.lEl, PI.rEl, PI.lHa, PI.rHa] { p[i] = pel + rot(p[i] - pel, lean) }
        for i in [PI.head, PI.neck, PI.chest, PI.pelvis, PI.lSh, PI.rSh, PI.lEl, PI.rEl, PI.lHa, PI.rHa] { p[i].y += bob }
        return p
    }

    private func runStep(_ dt: Float, _ f: InputState.Frame) {
        if f.pressed(Key.esc) { enter(.shop); return }
        camera.fieldOfView += (60 - camera.fieldOfView) * CGFloat(min(1, dt * 3))
        let auto = autoplay
        let go = f.down(Key.w, Key.up) || f.mouseHeld || auto
        if go { runSpeed = min(runMax, runSpeed + 7 * dt) } else { runSpeed = max(0, runSpeed - 9 * dt) }
        if f.down(Key.s, Key.down) { runSpeed = max(0, runSpeed - 12 * dt) }
        if f.down(Key.a, Key.left) { heading = min(0.6, heading + dt * 1.3) }
        if f.down(Key.d, Key.right) { heading = max(-0.6, heading - dt * 1.3) }
        let fwd = V3(sinf(heading), 0, cosf(heading))
        runPos += fwd * runSpeed * dt
        runPos.x = clampf(runPos.x, -10, 10)
        let oldPhase = runPhase
        runPhase += runSpeed * dt * 2.3
        let toEdge = -runPos.z
        let jumpPressed = f.pressed(Key.space) || (auto && toEdge < 1.2)
        if jumpPressed && toEdge < 4 { launch(jumped: true); return }
        if toEdge < -0.15 { launch(jumped: false); return }
        let a = min(1, runSpeed / 5)
        var pose = Game.runPose(runPhase, a)
        if a < 0.05 {
            let sway = sinf(Float(simTime) * 1.6) * 0.03
            for i in [PI.lHa, PI.rHa, PI.lEl, PI.rEl] { pose[i].z += sway }
        }
        if Int(runPhase / .pi) != Int(oldPhase / .pi) && runSpeed > 1 { audio.play("thud", volume: 0.12, rate: 1.8) }
        rd.place(pose: pose, at: runPos, yaw: heading, velocity: fwd * runSpeed)
        body.update(rd)
    }

    private func launch(jumped: Bool) {
        let fwd = V3(sinf(heading), 0, cosf(heading))
        let jl = Float(lvl(Up.jump))
        var v = fwd * runSpeed
        if jumped { v = fwd * (runSpeed * (1 + 0.06 * jl) + 1) + V3(0, 3.2 + 1.1 * jl, 0) }
        let pose = Game.runPose(runPhase, min(1, runSpeed / 5))
        rd.place(pose: pose, at: runPos, yaw: heading, velocity: v)
        for i in [PI.head, PI.neck, PI.lSh, PI.rSh, PI.lHa, PI.rHa] { rd.prev[i] -= fwd * (0.8 + runSpeed * 0.15) * rd.h }
        for i in [PI.lAn, PI.rAn, PI.lToe, PI.rToe] { rd.prev[i] += fwd * 0.5 * rd.h }
        inj.reset()
        inj.brittle = 1 + 0.18 * Float(lvl(Up.brittle))
        body.tint(inj)
        hud.mini.set(inj.state, flash: false)
        fallCash = 0; combo = 0; comboT = 0; bestCombo = 0; topSpeed = 0; fallTime = 0; restT = 0; wriggles = 3 + Int(H / 2500)
        timeScale = 1; slowT = 0; acc = 0; warp = 1; airT = 0; calmT = 0; pushes = 0
        usesLeft = abilities.indices.map { save.ownedAbilities[$0] && $0 != 6 ? abilities[$0].uses : 0 }
        massT = 0; magnetT = 0; bulletT = 0; flameT = 0
        fuel = save.ownedAbilities[6] ? 8 : 0
        rd.gravity = V3(0, -9.81, 0); rd.drag = 0.0038
        audio.play("whoosh", volume: 0.8)
        if jumped { audio.play("hup", volume: 0.7) }
        screaming = true
        audio.scream()
        camYaw = 0.9; camPitch = 0.28; camVel = .zero; lookVel = .zero
        enter(.falling)
    }

    // MARK: fall

    private static let starfish: [(Int, V3)] = [(PI.lHa, V3(0.8, 0.3, 0)), (PI.rHa, V3(-0.8, 0.3, 0)), (PI.lEl, V3(0.5, 0.18, 0)), (PI.rEl, V3(-0.5, 0.18, 0)),
                                                (PI.lAn, V3(0.45, -1.15, 0)), (PI.rAn, V3(-0.45, -1.15, 0)), (PI.lKn, V3(0.25, -0.72, 0)), (PI.rKn, V3(-0.25, -0.72, 0))]
    private static let tuck: [(Int, V3)] = [(PI.lKn, V3(0.12, -0.2, 0.32)), (PI.rKn, V3(-0.12, -0.2, 0.32)), (PI.lAn, V3(0.12, -0.55, 0.15)), (PI.rAn, V3(-0.12, -0.55, 0.15)),
                                            (PI.lHa, V3(0.12, -0.18, 0.36)), (PI.rHa, V3(-0.12, -0.18, 0.36)), (PI.lEl, V3(0.2, -0.05, 0.22)), (PI.rEl, V3(-0.2, -0.05, 0.22))]

    private func orbitInput(_ f: InputState.Frame) {
        camYaw -= Float(f.drag.x) * 0.006
        camPitch = clampf(camPitch + Float(f.drag.y) * 0.005, -0.2, 1.45)
        camDist = clampf(camDist * (1 - Float(f.scroll) * 0.04), 2.5, 40)
    }

    private func fallStep(_ realDt: Float, _ f: InputState.Frame) {
        orbitInput(f)
        slowCooldown -= realDt
        calmT += realDt
        if slowT > 0 { slowT -= realDt; timeScale += (0.28 - timeScale) * min(1, realDt * 20) }
        else if bulletT > 0 { timeScale += (0.35 - timeScale) * min(1, realDt * 8) }
        else { timeScale += (1 - timeScale) * min(1, realDt * 6) }
        let dt = realDt * timeScale
        comboT -= dt
        if comboT <= 0 { combo = 0 }
        voiceCD -= realDt; thudCD -= realDt; scrapeCD -= realDt; coinCD -= realDt; toastCD -= realDt; bloodCD -= realDt

        if phase == .stuck {
            let high = rd.com.y > 40
            if f.pressed(Key.space) || !f.clicks.isEmpty || (autoplay && phaseT > 0.8) || (high && phaseT > 0.8) { wriggle() }
            else if f.pressed(Key.ret, Key.enter) || phaseT > 6 { finishFall(); return }
        }
        if phase == .resting && phaseT > 1.3 { finishFall(); return }
        if f.pressed(Key.esc) && phase != .resting { finishFall(); return }

        rd.clearForces()
        jetting = save.ownedAbilities[6] && (f.down(Key.nums[6]) || (devJet && fallTime > 1 && fallTime < 5)) && fuel > 0 && (phase == .falling || phase == .stuck)
        if jetting && phase == .stuck { phase = .falling; phaseT = 0; restT = 0 }
        if phase == .falling && !jetting {
            let airborne = rd.contacts == 0
            let k: Float = (airborne ? 1 : 0.35) * (1 + 0.5 * Float(lvl(Up.air)))
            let flipAxis = V3(cosf(heading), 0, -sinf(heading))
            let rollAxis = V3(sinf(heading), 0, cosf(heading))
            var fl: Float = 0, ro: Float = 0
            if f.down(Key.w, Key.up) { fl += 1 }
            if f.down(Key.s, Key.down) { fl -= 1 }
            if f.down(Key.a, Key.left) { ro -= 1 }
            if f.down(Key.d, Key.right) { ro += 1 }
            if autoplay { fl = 1 }
            if fl != 0 { rd.applySpin(axis: flipAxis, alpha: fl * 20 * k, maxRate: 7) }
            if ro != 0 { rd.applySpin(axis: rollAxis, alpha: ro * 20 * k, maxRate: 7) }
            if f.down(Key.space) { rd.applyPose(Game.starfish, strength: 140) }
            else if f.down(Key.shift) { rd.applyPose(Game.tuck, strength: 140) }
        }
        if phase == .falling || phase == .stuck { useAbilities(f, realDt) }
        // fast-forward through open air (automatic), or on demand with F
        airT = rd.contacts == 0 ? airT + realDt : 0
        var targetWarp: Float = 1
        if phase == .falling {
            if f.down(Key.f) { targetWarp = 10 } else if airT > 0.8 && rd.nearestObstacle > 35 && slowT <= 0 && bulletT <= 0 { targetWarp = 6 }
            else if calmT > 2 && bulletT <= 0 && slowT <= 0 { targetWarp = 4 }
            if autoplay || headless { targetWarp = max(targetWarp, airT > 0.5 && rd.nearestObstacle > 25 ? 8 : 1) }
        }
        if jetting || magnetT > 0 { targetWarp = min(targetWarp, f.down(Key.f) ? 10 : 1) }
        warp += (targetWarp - warp) * min(1, realDt * (targetWarp > warp ? 3 : 10))
        let wdt = dt * warp
        world.stream(focus: rd.com + rd.comVel * 0.6, cam: camPos, budget: warp > 2 ? 4 : 2)
        rd.capsules = world.capsules
        rd.surfaceGap = world.level.surfaceDistance(rd.com)
        rd.gatherNear(frameDt: wdt)
        acc += wdt
        var n = 0
        let cap = Int(24 * max(1, warp))
        while acc >= rd.h && n < cap { rd.substep(); acc -= rd.h; n += 1 }
        if n == cap { acc = 0 }
        fallTime += wdt
        processImpacts()

        let spd = simd_length(rd.comVel)
        topSpeed = max(topSpeed, spd)
        audio.ambient.rush = clampf((spd - 4) / 30, 0, 1) * (rd.contacts == 0 ? 1 : 0.5)
        if rd.contacts > 0 && spd > 2.5 && scrapeCD <= 0 {
            audio.play("scrape", volume: min(0.5, (spd - 2) * 0.05), rate: 0.8 + spd * 0.02)
            scrapeCD = 0.22
        }
        body.update(rd)

        if phase == .falling {
            let still = simd_length(rd.comVel) < 0.35 && rd.maxSpeed < 2.5
            restT = still && fallTime > 1 ? restT + dt : 0
            let c = rd.com
            if pushes > 0 && c.y < pushY - 15 { pushes = 0 }
            let offWorld = c.y < -10 || abs(c.x) > 350 || c.z > (world.level.profile.last?.x ?? 1e9) - 5
            if offWorld { phase = .resting; phaseT = 0 }
            else if restT > 1.0 || fallTime > maxFall {
                let above = c.y - world.level.surfaceY(c.z) < 2 && c.y > 2.5
                if (above || c.y - world.level.surfaceY(c.z) > 3) && (wriggles > 0 || c.y > 40) && pushes < 6 && fallTime < maxFall {
                    phase = .stuck; phaseT = 0
                } else {
                    phase = .resting; phaseT = 0
                    audio.ambient.rush = 0
                    if screaming { audio.stopScream(); screaming = false }
                    if inj.state[0] != .shattered { audio.play("groan", volume: 0.6) }
                }
            }
        }
    }

    private var maxFall: Float { 150 + H / 5 }

    /// Keys 1-6 fire the abilities bought in the shop.
    private func useAbilities(_ f: InputState.Frame, _ dt: Float) {
        massT -= dt; magnetT -= dt; bulletT -= dt; flameT -= dt
        if massT <= 0 { rd.gravity = V3(0, -9.81, 0); rd.drag = 0.0038; inj.brittle = 1 + 0.18 * Float(lvl(Up.brittle)) }
        if jetting { jetpack(f, dt) }
        for (i, key) in Key.nums.enumerated() where i < abilities.count && i != 6 && f.pressed(key) {
            guard usesLeft[i] > 0 else { if save.ownedAbilities[i] { audio.play("nope", volume: 0.4) }; continue }
            usesLeft[i] -= 1
            fire(i)
        }
        if autoplay && usesLeft.contains(where: { $0 > 0 }) && fallTime > 2, let i = usesLeft.firstIndex(where: { $0 > 0 }), rng.chance(0.01) {
            usesLeft[i] -= 1; fire(i)
        }
        let fwd = V3(sinf(heading), 0, cosf(heading))
        if magnetT > 0 {
            // pull toward the nearest obstacle or boulder; otherwise back into the cliff
            let c = rd.com
            var best: V3? = nil, bd: Float = 80
            for cap in world.capsules {
                let ab = cap.b - cap.a
                let L2 = simd_length_squared(ab)
                let t = L2 > 1e-6 ? clampf(simd_dot(c - cap.a, ab) / L2, 0, 1) : 0
                let q = cap.a + ab * t
                let d = simd_length(q - c)
                if d < bd && d > 0.5 { bd = d; best = q }
            }
            let dir = best.map { simd_normalize($0 - c) } ?? simd_normalize(V3(0, -0.5, -1))
            for i in 0..<PI.count { rd.accel[i] += dir * 38 }
        }
        if flameT > 0 && !headless {
            let s = dust.copy() as! SCNParticleSystem
            s.particleColor = color(1, 0.55, 0.15, 0.9)
            s.birthRate = 300; s.loops = false; s.emissionDuration = 0.03
            s.particleSize = 0.35
            let c = rd.com + fwd * -0.3 + V3(0, 0.6, 0)
            scene.addParticleSystem(s, transform: SCNMatrix4MakeTranslation(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)))
        }
    }

    /// Jetpack: thrust up along the body, steer with WASD relative to the camera, keep the head up.
    private func jetpack(_ f: InputState.Frame, _ dt: Float) {
        fuel = max(0, fuel - dt)
        let yaw = heading + camYaw + .pi
        let fwd = V3(sinf(yaw), 0, cosf(yaw)), side = V3(fwd.z, 0, -fwd.x)
        var steer = V3.zero
        if f.down(Key.w, Key.up) { steer += fwd }
        if f.down(Key.s, Key.down) { steer -= fwd }
        if f.down(Key.a, Key.left) { steer += side }
        if f.down(Key.d, Key.right) { steer -= side }
        let lift = V3(0, 21, 0) + steer * 13
        for i in 0..<PI.count { rd.accel[i] += lift }
        // stay upright: head pulled up, feet down
        rd.accel[PI.head] += V3(0, 10, 0); rd.accel[PI.neck] += V3(0, 6, 0)
        for i in [PI.lAn, PI.rAn, PI.lToe, PI.rToe] { rd.accel[i] += V3(0, -8, 0) }
        // air brake so you can hover
        let v = rd.comVel
        for i in 0..<PI.count { rd.accel[i] -= V3(v.x * 0.6, min(0, v.y) * 0.8, v.z * 0.6) }
        jetCD -= dt
        if jetCD <= 0 { audio.play("jet", volume: 0.55, jitter: 0.03); jetCD = 0.16 }
        if !headless {
            let back = rd.frame.fwd * -0.22
            for p in [PI.lSh, PI.rSh] {
                let s = dust.copy() as! SCNParticleSystem
                s.particleColor = color(1, 0.6, 0.2, 0.95)
                s.birthRate = 500; s.loops = false; s.emissionDuration = 0.02
                s.particleSize = 0.18; s.particleVelocity = 6; s.particleLifeSpan = 0.35; s.spreadingAngle = 12
                s.emittingDirection = SCNVector3(-rd.frame.up)
                let c = rd.wpos(p) + back - rd.frame.up * 0.35
                scene.addParticleSystem(s, transform: SCNMatrix4MakeTranslation(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)))
            }
        }
    }

    private func addVelocity(_ v: V3) { for i in 0..<PI.count { rd.prev[i] -= v * rd.h } }

    private func fire(_ i: Int) {
        let fwd = V3(sinf(heading), 0, cosf(heading))
        let name = abilities[i].name
        switch i {
        case 0: // Rocket Slam: down and back into the cliff
            addVelocity(simd_normalize(V3(0, -1, -0.45)) * 38)
            flameT = 0.6
            audio.play("whoosh", volume: 1, rate: 0.7); audio.play("boom", volume: 0.5)
        case 1: // Air Jump
            let v = rd.comVel
            addVelocity(V3(-v.x * 0.5, 12 - min(0, v.y) * 0.6, -v.z * 0.5) + fwd * 3)
            audio.play("hup", volume: 0.8); audio.play("whoosh", volume: 0.7, rate: 1.3)
        case 2: // Rock Magnet
            magnetT = 3
            audio.play("select", volume: 0.8, rate: 0.6)
        case 3: // Mega Mass
            massT = 6
            rd.gravity = V3(0, -16, 0); rd.drag = 0.0015
            inj.brittle = (1 + 0.18 * Float(lvl(Up.brittle))) * 2
            audio.play("boom", volume: 0.5, rate: 0.6)
        case 4: // Explosion: blast every limb outward, and every bone takes a hit
            let c = rd.com
            for k in 0..<PI.count {
                let out = simd_normalize(rd.wpos(k) - c + V3(rng.range(-0.3, 0.3), rng.range(0, 0.4), rng.range(-0.3, 0.3)))
                rd.prev[k] -= out * rng.range(14, 26) * rd.h
                rd.impacts.append(Impact(particle: k, bone: nil, speed: rng.range(16, 26), normal: -out, point: rd.wpos(k), rock: false, sharp: 0.4))
            }
            audio.play("explode", volume: 1.2)
            shake = 1
            if !headless {
                let s = dust.copy() as! SCNParticleSystem
                s.particleColor = color(1, 0.6, 0.2, 1)
                s.birthRate = 3000; s.loops = false; s.emissionDuration = 0.05
                s.particleSize = 0.8; s.particleVelocity = 12
                scene.addParticleSystem(s, transform: SCNMatrix4MakeTranslation(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)))
                let smoke = dust.copy() as! SCNParticleSystem
                smoke.particleColor = NSColor(white: 0.2, alpha: 0.7)
                smoke.birthRate = 1200; smoke.loops = false; smoke.emissionDuration = 0.1
                smoke.particleSize = 1.4; smoke.particleVelocity = 5; smoke.particleLifeSpan = 2.5
                scene.addParticleSystem(smoke, transform: SCNMatrix4MakeTranslation(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z)))
            }
        case 5: // Bullet Time
            bulletT = 4
            audio.play("boom", volume: 0.4, rate: 0.5)
        default: return
        }
        if !headless { hud.showToast(name.uppercased() + "!", "", color: color(0.5, 0.85, 1), dur: 0.6) }
    }

    private func wriggle() {
        guard (wriggles > 0 || rd.com.y > 40) && pushes < 6 else { return }
        pushY = rd.com.y
        wriggles = max(0, wriggles - 1)
        phase = .falling; phaseT = 0; restT = 0
        let out = V3(sinf(heading), 0, cosf(heading))
        pushes += 1
        let v = out * (4.5 + 2 * Float(min(pushes, 4))) + V3(0, 4, 0)
        for i in 0..<PI.count { rd.prev[i] = rd.pos[i] - (v + V3(rng.range(-0.5, 0.5), rng.range(-0.3, 0.3), rng.range(-0.5, 0.5))) * rd.h }
        audio.play("hup", volume: 0.6)
        audio.play("whoosh", volume: 0.5)
    }

    private func screenPoint(_ p: V3) -> CGPoint? {
        guard let r = renderer else { return nil }
        let q = r.projectPoint(SCNVector3(p))
        guard q.z > 0 && q.z < 1 else { return nil }
        return CGPoint(x: CGFloat(q.x), y: CGFloat(q.y))
    }

    private func processImpacts() {
        guard !rd.impacts.isEmpty else { return }
        var best: [Int: Impact] = [:]
        for im in rd.impacts {
            let key = im.particle * 32 + (im.bone.map { $0.rawValue + 1 } ?? 0)
            if let b = best[key], b.speed >= im.speed { continue }
            best[key] = im
        }
        rd.impacts.removeAll(keepingCapacity: true)
        let fr = rd.frame
        let bodyInfo = Injuries.Body(right: fr.right, up: fr.up, fwd: fr.fwd, chest: rd.wpos(PI.chest), pelvis: rd.wpos(PI.pelvis))
        var maxHit: Impact?
        var events: [Injuries.Event] = []
        for im in best.values {
            if maxHit == nil || im.speed > maxHit!.speed { maxHit = im }
            events += inj.apply(im, body: bodyInfo, sharp: map.sharp)
        }
        // bones that are already shattered still pay a little for extra punishment
        if inj.overkill > 0 {
            let ok = inj.overkill * 0.04 * map.mult * heightMult(H) * (1 + 0.25 * Float(lvl(Up.cash)))
            fallCash += ok
            inj.overkill = 0
        }
        if let m = maxHit, m.speed > 3.5, thudCD <= 0 {
            let v = min(1.2, (m.speed - 3) / 14)
            audio.play(m.wood ? "wood" : (m.rock ? "smack" : "thud"), volume: v, rate: 0.9 + rng.range(0, 0.2))
            thudCD = 0.06
            if m.speed > 7 {
                let s = dust.copy() as! SCNParticleSystem
                s.birthRate = CGFloat(min(400, m.speed * 12))
                s.particleVelocity = CGFloat(0.8 + m.speed * 0.08)
                s.loops = false; s.emissionDuration = 0.08
                scene.addParticleSystem(s, transform: SCNMatrix4MakeTranslation(CGFloat(m.point.x), CGFloat(m.point.y), CGFloat(m.point.z)))
                shake = max(shake, min(0.5, m.speed * 0.02))
            }
            if screaming && m.speed > 9 { audio.stopScream(); screaming = false }
        }
        guard !events.isEmpty else { return }
        calmT = 0
        body.tint(inj)
        if !headless { hud.mini.set(inj.state, flash: true) }
        for r in Region.allCases where !fractured.contains(r) && inj.regionBroken(r) {
            fractured.insert(r)
            rd.fracture(r)
        }
        var worst = Injury.fine
        var worstBone = events[0].bone
        var frameCash: Float = 0
        var byRegion: [Region: (count: Int, worst: Injury, bone: Int, cash: Float)] = [:]
        let cashMult = map.mult * heightMult(H) * (1 + 0.25 * Float(lvl(Up.cash)))
        for e in events {
            combo += 1
            comboT = 1.3
            bestCombo = max(bestCombo, combo)
            let comboMult = min(2, 1 + 0.02 * Float(combo - 1))
            let cash = e.baseCash * cashMult * comboMult * (bulletT > 0 ? 2 : 1)
            fallCash += cash
            frameCash += cash
            let r = e.def.region
            var g = byRegion[r] ?? (0, .fine, e.bone, 0)
            g.count += 1; g.cash += cash
            if e.to.rawValue > g.worst.rawValue { g.worst = e.to; g.bone = e.bone }
            byRegion[r] = g
            if e.to.rawValue > worst.rawValue || (e.to == worst && e.def.value > Skeleton.bones[worstBone].value) { worst = e.to; worstBone = e.bone }
        }
        if !headless {
            for (r, g) in byRegion where g.worst.rawValue >= Injury.cracked.rawValue {
                let text = g.count == 1 ? "\(g.worst.label) \(Skeleton.bones[g.bone].name.uppercased())"
                                        : "\(g.count) BONES · \(r.name.uppercased())"
                hud.feedEvent(text, "+" + money(Int(g.cash)), color: injuryColor(g.worst))
            }
            if let m = maxHit, let sp = screenPoint(m.point), frameCash >= 1 {
                let l = hud.floater("+" + money(Int(frameCash)), at: sp, color: color(0.55, 1, 0.45), size: worst.rawValue >= Injury.broken.rawValue ? 30 : 20)
                floaters.append((l, m.point, simTime))
            }
        }
        if worst.rawValue >= Injury.broken.rawValue, bloodCD <= 0, let m = maxHit {
            bloodCD = 0.35
            let b = blood.copy() as! SCNParticleSystem
            b.birthRate = worst == .shattered ? 500 : 250
            b.emittingDirection = SCNVector3(m.normal)
            scene.addParticleSystem(b, transform: SCNMatrix4MakeTranslation(CGFloat(m.point.x), CGFloat(m.point.y), CGFloat(m.point.z)))
        }
        switch worst {
        case .shattered: audio.play("crunch", volume: 1.1); audio.play("crack", volume: 0.8, rate: 0.8)
        case .broken: audio.play("crack", volume: 1.0)
        case .cracked: audio.play("crack", volume: 0.55, rate: 1.25)
        default: break
        }
        if coinCD <= 0 { audio.play(worst.rawValue >= Injury.broken.rawValue ? "cash" : "coin", volume: 0.35); coinCD = 0.25 }
        let canTalk = inj.state[0] != .shattered && !inj.regionBroken(.neck)
        if voiceCD <= 0 && canTalk && worst.rawValue >= Injury.bruised.rawValue {
            audio.play("ow", volume: 0.7, jitter: 0.1)
            voiceCD = 0.9
        }
        if worst.rawValue >= Injury.broken.rawValue {
            if !headless && toastCD <= 0 {
                let nm = Skeleton.bones[worstBone].name.uppercased()
                if worst == .shattered { hud.showToast("SHATTERED!", nm, color: color(1, 0.35, 0.3), dur: 0.7) }
                else { hud.showToast("SNAP!", nm, color: color(1, 0.6, 0.5), dur: 0.6) }
                toastCD = 0.7
            }
            if slowCooldown <= 0 && worst == .shattered && Skeleton.bones[worstBone].value >= 3 {
                slowT = 0.35; slowCooldown = 1.5
                audio.play("boom", volume: 0.6)
            }
            shake = max(shake, 0.35)
        }
    }

    private func finishFall() {
        if screaming { audio.stopScream(); screaming = false }
        audio.ambient.rush = 0
        timeScale = 1
        let cash = Int(fallCash.rounded())
        let broken = inj.brokenCount
        let bonusRate: Double = broken >= 206 ? 1 : (broken >= 150 ? 0.5 : (broken >= 100 ? 0.25 : 0))
        let bonus = Int(Double(cash) * bonusRate)
        let total = cash + bonus
        save.money += total
        save.falls += 1
        save.totalEarned += total
        let record = total > save.bestFall
        save.bestFall = max(save.bestFall, total)
        save.totalBones += broken
        persist()
        let r = ResultsData(damage: inj.damage, states: inj.state, hits: inj.hits, cash: cash, bonus: bonus, topSpeed: topSpeed,
                            height: H, time: fallTime, bestCombo: bestCombo, record: record && save.falls > 1)
        if !headless { hud.showResults(r) }
        enter(.results)
        audio.play("drumroll", volume: 0.7)
        let q = audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            q.play("crash", volume: 0.6)
            q.play("cash", volume: 0.8)
        }
    }

    // MARK: camera

    private func updateCamera(_ dt: Float) {
        var targetPos: V3, targetLook: V3
        var lerp: Float = 3
        let lvlg = world.level
        switch phase {
        case .title:
            let mid = V3(0, H * 0.55, lvlg.baseZ * 0.4)
            let D = max(40, H * 1.1 + lvlg.baseZ * 0.4)
            targetPos = mid + V3(cosf(orbit * 2 + 0.6) * D, H * 0.25 + 8, sinf(orbit * 2 + 0.6) * D * 0.6 + D * 0.5)
            targetLook = mid
            lerp = 1
        case .shop:
            let mid = V3(0, H * 0.5, lvlg.baseZ * 0.5)
            let D = max(26, H * 0.95 + lvlg.baseZ * 0.3)
            targetPos = mid + V3(D * 0.75, H * 0.12 + 4, D * 0.55)
            targetLook = mid + V3(-D * 0.28, 0, 0)
            lerp = 2.5
        case .ready:
            let fwd = V3(sinf(heading), 0, cosf(heading))
            let side = V3(fwd.z, 0, -fwd.x)
            let near = smoothstep(6, 0, -runPos.z)
            targetPos = runPos + fwd * -3.6 + side * -0.8 + V3(0, 2.2 + near * 1.2, 0)
            targetLook = runPos + fwd * 6 + V3(0, 0.6 - near * min(H * 0.4, 8), 0)
            lerp = 5
        case .falling, .stuck, .resting:
            updateFallCamera(dt)
            return
        case .results:
            let c = rd.com
            targetPos = c + V3(cosf(orbit) * 3.8 + 1.5, 2.4, sinf(orbit) * 3.8 + 1)
            targetLook = c + V3(-1.1, 0, 0)
            lerp = 2
        }
        let k = 1 - expf(-dt * lerp)
        camPos += (targetPos - camPos) * k
        camLook += (targetLook - camLook) * min(1, k * 1.8)
        let ground = lvlg.surfaceY(camPos.z) + 0.8
        if camPos.y < ground && abs(camPos.x) < 90 { camPos.y = ground }
        var p = camPos, l = camLook
        if shake > 0.001 {
            shake *= expf(-dt * 7)
            let j = V3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)) * shake * 0.3
            p += j; l += j * 0.5
        }
        if let fz = devFreezeCam { p = fz.0; l = fz.1 }
        camNode.simdPosition = p
        camNode.simdLook(at: l, up: V3(0, 1, 0), localFront: V3(0, 0, -1))
    }

    /// Critically damped spring toward a target (Unity-style SmoothDamp).
    private func smoothDamp(_ cur: V3, _ target: V3, _ vel: inout V3, _ time: Float, _ dt: Float) -> V3 {
        let omega = 2 / max(0.0001, time)
        let x = omega * dt
        let e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = cur - target
        let temp = (vel + change * omega) * dt
        vel = (vel - temp * omega) * e
        return target + (change + temp) * e
    }

    /// Chase camera for the fall: orbits the body (drag to turn, scroll to zoom), leads the motion,
    /// pulls back and widens with speed, and never goes inside the cliff.
    private func updateFallCamera(_ dt: Float) {
        let c = rd.com
        let v = rd.comVel
        let spd = simd_length(v)
        switch camMode {
        case 1: camPitch += (0.45 - camPitch) * min(1, dt * 2)
        case 2: camPitch += (1.25 - camPitch) * min(1, dt * 2)
        default: break
        }
        if phase == .resting { camYaw += dt * 0.35 }
        let dist = camDist * (1 + min(0.8, spd / 60)) * (slowT > 0 ? 0.75 : 1)
        let base = heading + camYaw
        let offset = V3(sinf(base) * cosf(camPitch), sinf(camPitch), cosf(base) * cosf(camPitch)) * dist
        let lead = spd > 1 ? v * min(0.25, 6 / max(spd, 1)) : .zero
        let targetLook = c + lead + V3(0, 0.3, 0)
        var targetPos = targetLook + offset
        // keep clear of the cliff: push out along the surface normal-ish direction (towards open air, +z / +y)
        let lvlg = world.level
        let clearance: Float = 1.6
        let sy = lvlg.surfaceY(targetPos.z)
        if targetPos.y < sy + clearance { targetPos.y = sy + clearance }
        var gap = lvlg.surfaceDistance(targetPos)
        var guardN = 0
        while gap < clearance && guardN < 6 { targetPos += V3(0, 0.6, 0.8) * (clearance - gap + 0.2); gap = lvlg.surfaceDistance(targetPos); guardN += 1 }
        // don't let trees or boulders get between the camera and the body
        var bestT: Float = 1
        let ray = targetPos - targetLook
        let rayLen = simd_length(ray)
        if rayLen > 0.5 {
            let dir = ray / rayLen
            for cb in world.camBlockers {
                let mid = (cb.a + cb.b) * 0.5
                let reach = simd_length(cb.b - cb.a) * 0.5 + cb.r
                let along = simd_dot(mid - targetLook, dir)
                if along < -reach || along > rayLen + reach { continue }
                if simd_length(targetLook + dir * clampf(along, 0, rayLen) - mid) > reach + 0.4 { continue }
                // sample the ray against the capsule
                for k in 1...12 {
                    let t = Float(k) / 12
                    let q = targetLook + ray * t
                    let ab = cb.b - cb.a
                    let L2 = simd_length_squared(ab)
                    let u = L2 > 1e-6 ? clampf(simd_dot(q - cb.a, ab) / L2, 0, 1) : 0
                    if simd_length(q - (cb.a + ab * u)) < cb.r + 0.35 { bestT = min(bestT, t - 1.0 / 12); break }
                }
            }
        }
        if bestT < 1 { targetPos = targetLook + ray * max(2.2 / max(rayLen, 0.01), bestT) }
        // and don't park the camera right next to foliage or a boulder either
        func tooClose(_ p: V3) -> Bool {
            for cb in world.camBlockers {
                let ab = cb.b - cb.a
                let L2 = simd_length_squared(ab)
                let u = L2 > 1e-6 ? clampf(simd_dot(p - cb.a, ab) / L2, 0, 1) : 0
                if simd_length(p - (cb.a + ab * u)) < cb.r + 1.2 { return true }
            }
            return false
        }
        var shrink = 0
        while tooClose(targetPos) && shrink < 6 { targetPos = targetLook + (targetPos - targetLook) * 0.8 + V3(0, 0.4, 0); shrink += 1; bestT = 0 }
        let snappy: Float = warp > 2 ? 0.08 : (bestT < 1 ? 0.12 : 0.28)
        camPos = smoothDamp(camPos, targetPos, &camVel, snappy, dt)
        camLook = smoothDamp(camLook, targetLook, &lookVel, snappy * 0.5, dt)
        if simd_length(camPos - c) > 200 { camPos = targetPos; camLook = targetLook; camVel = .zero; lookVel = .zero }
        let fov = 58 + min(16, spd * 0.28) + (warp - 1) * 1.2
        camera.fieldOfView += (CGFloat(fov) - camera.fieldOfView) * CGFloat(min(1, dt * 3))
        var p = camPos, l = camLook
        if shake > 0.001 {
            shake *= expf(-dt * 7)
            let j = V3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1)) * shake * 0.3
            p += j; l += j * 0.5
        }
        if let fz = devFreezeCam { p = fz.0; l = fz.1 }
        camNode.simdPosition = p
        camNode.simdLook(at: l, up: V3(0, 1, 0), localFront: V3(0, 0, -1))
    }

    // MARK: HUD

    private func updateHUD(_ dt: Double) {
        floaters.removeAll { $0.node.parent == nil }
        for f in floaters {
            if let sp = screenPoint(f.wp) {
                f.node.position = CGPoint(x: sp.x, y: sp.y + CGFloat(simTime - f.born) * 60)
                f.node.isHidden = false
            } else { f.node.isHidden = true }
        }
        var s = HUDState()
        s.money = save.money
        s.mapIdx = save.map; s.heightIdx = save.heightIdx
        s.ownedMaps = save.ownedMaps; s.ownedHeights = save.ownedHeights
        s.upLevels = save.upLevels
        s.cursorCol = cursorCol; s.cursorRow = cursorRow
        s.hover = hover
        s.musicOn = save.musicOn
        s.falls = save.falls; s.bestFall = save.bestFall; s.totalBones = save.totalBones
        s.runSpeed = runSpeed; s.runMax = runMax; s.toEdge = -runPos.z
        s.fallCash = fallCash
        s.broken = inj.brokenCount; s.shattered = inj.shatteredCount; s.hurt = inj.hurtCount
        s.speed = simd_length(rd.comVel)
        s.altitude = rd.com.y - 1
        s.combo = combo
        s.warp = warp
        s.abilities = abilities.indices.map { (save.ownedAbilities[$0], $0 == 6 ? Int(ceilf(fuel / 8 * 100)) : usesLeft[$0]) }
        s.ownedAbilities = save.ownedAbilities
        s.effects = (massT > 0 ? "MEGA MASS  " : "") + (magnetT > 0 ? "MAGNET  " : "") + (bulletT > 0 ? "BULLET TIME ×2 CASH" : "")
        s.altitude = rd.com.y - world.level.surfaceY(rd.com.z)
        switch phase {
        case .title: break
        case .shop:
            s.controls = "ARROWS / CLICK  choose     ⏎  buy or select     SPACE  go     M  music     ESC  title"
        case .ready:
            s.controls = "hold W (or mouse)  run     A / D  steer     SPACE  jump at the edge     ESC  shop"
            if runSpeed < 0.2 && phaseT > 0.6 { s.prompt = "Hold W to run at the cliff!" }
        case .falling:
            s.controls = (save.ownedAbilities[6] ? "hold 7  JETPACK    " : "") + "W / S  flip    A / D  roll    SPACE  starfish    SHIFT  tuck    F  fast-forward    drag / scroll  camera    C  camera mode    ESC  give up"
        case .stuck:
            s.prompt = "STUCK!  SPACE to wriggle off (\(wriggles) left)   ·   ⏎ to finish"
        case .resting:
            s.prompt = "..."
        case .results: s.controls = "SPACE  fall again     ⏎  shop"
        }
        hud.update(s, dt: dt)
    }

    // MARK: dev

    func devMap(_ i: Int, height h: Int) {
        save.map = min(maps.count - 1, max(0, i)); save.heightIdx = min(heights.count - 1, max(0, h))
        buildWorld()
    }

    func devScene(_ s: String) {
        switch s {
        case "shop": enter(.shop)
        case "ready": enter(.ready); runPos.z = -3; runSpeed = 5; runPhase = 1
        case "fall":
            enter(.ready); runSpeed = 7; runPos.z = -1
            launch(jumped: true)
        case "jet":
            save.ownedAbilities = [Bool](repeating: true, count: abilities.count)
            devJet = true
            enter(.ready); runSpeed = 7; runPos.z = -1
            launch(jumped: true)
        case "results":
            enter(.ready); runSpeed = 7; runPos.z = -1
            launch(jumped: true)
            autoplay = true
            for _ in 0..<(60 * 25) {
                step(1.0 / 60, input: InputState.Frame())
                if phase == .results { break }
            }
        default: break
        }
    }

    /// Headless checks: audio, and simulated falls on every map at several heights.
    func autotest() -> Bool {
        headless = true
        var ok = audio.selfCheck()
        print("bones: \(Skeleton.bones.count) (want 206)")
        ok = ok && Skeleton.bones.count == 206
        let saveBackup = save
        for mi in 0..<maps.count {
            for hi in (mi % 7 == 0 ? [0, 4] : [0]) {
                save.map = mi; save.heightIdx = hi
                buildWorld()
                var cashSum: Float = 0, brokenSum = 0, timeSum: Float = 0, minY: Float = 1e9
                let runs = 3
                var bad = false
                for r in 0..<runs {
                    enter(.ready)
                    heading = Float(r - 1) * 0.2
                    runSpeed = [4, 6, 8][r]
                    runPos.z = -1
                    launch(jumped: true)
                    var t: Float = 0
                    while phase != .results && t < 3000 {
                        step(1.0 / 60, input: InputState.Frame())
                        t += 1.0 / 60
                        
                        let py = (0..<PI.count).map { rd.wpos($0).y - world.level.surfaceY(rd.wpos($0).z) }.min() ?? 0
                        if !py.isFinite { bad = true; break }
                        if py < -1.5 && minY >= -1.5 {
                            let c = rd.com
                            print(String(format: "   INSIDE at t %.1f: com %.1f %.1f %.1f surfY %.1f dist %.2f vel %.1f pushes %d phase %@", fallTime, c.x, c.y, c.z, world.level.surfaceY(c.z), world.level.surfaceDistance(c), simd_length(rd.comVel), pushes, "\(phase)"))
                            if let i = world.level.profile.lastIndex(where: { $0.x <= c.z }) { let p = world.level.profile; print("   seg", i, p[max(0,i-1)], p[i], p[min(p.count-1,i+1)]) }
                        }
                        minY = min(minY, py)
                    }
                    cashSum += fallCash
                    brokenSum += inj.brokenCount
                    timeSum += fallTime
                    if phase != .results { bad = true }
                }
                let good = !bad && minY > -1.5
                ok = ok && good
                print(String(format: "%@ %-17@ %3.0fm  avg $%7.0f  broken %5.1f/206  time %4.1fs  minY %.2f", good ? "PASS" : "FAIL",
                             maps[mi].name as NSString, heights[hi], cashSum / Float(runs), Float(brokenSum) / Float(runs), timeSum / Float(runs), minY))
            }
        }
        save = saveBackup
        return ok
    }
}
