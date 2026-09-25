import AVFoundation

/// AVAudioEngine graph. Every sound is synthesised at launch.
final class AudioSystem {
    let engine = AVAudioEngine()
    let format: AVAudioFormat
    let sr: Double
    let ambient: AmbientSynth
    let music: MusicSynth
    private var players: [AVAudioPlayerNode] = []
    private var speeds: [AVAudioUnitVarispeed] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var variants: [String: Int] = [:]
    private let queue = DispatchQueue(label: "bonefall.sfx")
    private(set) var running = false
    var muted = false
    private var screamPlayer = -1

    init(muted: Bool = false) {
        self.muted = muted
        let out = engine.outputNode.outputFormat(forBus: 0)
        sr = out.sampleRate > 0 ? out.sampleRate : 48000
        format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        ambient = AmbientSynth(sampleRate: Float(sr))
        music = MusicSynth(sampleRate: Float(sr))
        let a = ambient, m = music
        let ambNode = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let b = UnsafeMutableAudioBufferListPointer(abl)
            a.render(frames: Int(frames), b[0].mData!.assumingMemoryBound(to: Float.self), b[1].mData!.assumingMemoryBound(to: Float.self))
            return noErr
        }
        let musicNode = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let b = UnsafeMutableAudioBufferListPointer(abl)
            m.render(frames: Int(frames), b[0].mData!.assumingMemoryBound(to: Float.self), b[1].mData!.assumingMemoryBound(to: Float.self))
            return noErr
        }
        let plate = AVAudioUnitReverb()
        plate.loadFactoryPreset(.plate)
        plate.wetDryMix = 12
        let sfxMix = AVAudioMixerNode()
        let canyon = AVAudioUnitDelay()
        canyon.delayTime = 0.23
        canyon.feedback = 18
        canyon.wetDryMix = 9
        canyon.lowPassCutoff = 2500
        let hall = AVAudioUnitReverb()
        hall.loadFactoryPreset(.largeHall)
        hall.wetDryMix = 8

        for n in [ambNode, musicNode, plate, sfxMix, canyon, hall] as [AVAudioNode] { engine.attach(n) }
        engine.connect(musicNode, to: plate, format: format)
        engine.connect(plate, to: engine.mainMixerNode, format: format)
        engine.connect(ambNode, to: engine.mainMixerNode, format: format)
        engine.connect(sfxMix, to: canyon, format: format)
        engine.connect(canyon, to: hall, format: format)
        engine.connect(hall, to: engine.mainMixerNode, format: format)
        for _ in 0..<24 {
            let p = AVAudioPlayerNode(), vs = AVAudioUnitVarispeed()
            for n in [p, vs] as [AVAudioNode] { engine.attach(n) }
            engine.connect(p, to: vs, format: format)
            engine.connect(vs, to: sfxMix, format: format)
            players.append(p); speeds.append(vs)
        }
        engine.mainMixerNode.outputVolume = muted ? 0 : 0.9
        buildBuffers()
        do {
            try engine.start()
            for p in players { p.play() }
            running = true
        } catch {
            NSLog("BoneFall: audio unavailable: \(error)")
        }
    }

    /// Plays a one-shot. Names with variants ("crack") pick one at random.
    @discardableResult
    func play(_ name: String, volume: Float = 1, pan: Float = 0, jitter: Float = 0.05, rate: Float = 1) -> Int {
        guard running, !muted else { return -1 }
        var key = name
        if let n = variants[name] { key = "\(name)_\(Int.random(in: 0..<n))" }
        guard let buf = buffers[key] else { return -1 }
        let v = max(0, min(1.5, volume))
        guard v > 0.004 else { return -1 }
        let i = nextPlayer
        nextPlayer = (nextPlayer + 1) % players.count
        if i == screamPlayer { screamPlayer = -1 }
        queue.async {
            let p = self.players[i]
            self.speeds[i].rate = rate * (1 + Float.random(in: -jitter...jitter))
            p.volume = v
            p.pan = max(-1, min(1, pan))
            p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !p.isPlaying { p.play() }
        }
        return i
    }

    func scream() { screamPlayer = play("scream", volume: 0.75, jitter: 0.06) }
    func stopScream() {
        let i = screamPlayer
        guard i >= 0 else { return }
        screamPlayer = -1
        queue.async { self.players[i].stop(); self.players[i].play() }
    }

    func selfCheck() -> Bool {
        var bad: [String] = []
        for (k, b) in buffers.sorted(by: { $0.key < $1.key }) {
            var peak: Float = 0
            let L = b.floatChannelData![0]
            for i in 0..<Int(b.frameLength) { if !L[i].isFinite { peak = .nan; break }; peak = max(peak, abs(L[i])) }
            if !(peak > 0.02 && peak < 1.0) { bad.append("\(k)=\(peak)") }
        }
        print(bad.isEmpty ? "PASS sfx buffers (\(buffers.count))" : "FAIL sfx buffers: \(bad.joined(separator: ", "))")
        let n = 1024
        let L = UnsafeMutablePointer<Float>.allocate(capacity: n), R = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { L.deallocate(); R.deallocate() }
        var ok = bad.isEmpty
        for (name, rush) in [("wind", Float(0)), ("rush", 1)] {
            let amb = AmbientSynth(sampleRate: Float(sr))
            amb.rush = rush; amb.gulls = true; amb.rumble = true
            var p: Float = 0
            for _ in 0..<Int(20 * sr) / n { amb.render(frames: n, L, R); for i in 0..<n { p = max(p, abs(L[i]).isFinite ? abs(L[i]) : 99) } }
            let good = p < 0.9 && p > 0.01
            ok = ok && good
            print(String(format: "%@ ambience %@ peak %.3f", good ? "PASS" : "FAIL", name, p))
        }
        for mood in [MusicMood.menu, .ready, .fall, .results] {
            let mus = MusicSynth(sampleRate: Float(sr))
            mus.mood = mood
            var pm: Float = 0, rm: Double = 0, cm = 0
            for _ in 0..<Int(20 * sr) / n {
                mus.render(frames: n, L, R)
                for i in 0..<n { pm = max(pm, abs(L[i]).isFinite ? abs(L[i]) : 99); rm += Double(L[i] * L[i]); cm += 1 }
            }
            let good = pm < 0.95 && pm > 0.03
            ok = ok && good
            print(String(format: "%@ music %@ peak %.2f rms %.3f", good ? "PASS" : "FAIL", "\(mood)", pm, sqrt(rm / Double(cm))))
        }
        return ok
    }

    // MARK: Synthesis

    private func make(_ dur: Double, norm: Float? = nil, _ gen: (Float) -> (Float, Float)) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(dur * sr)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        b.frameLength = frames
        let L = b.floatChannelData![0], R = b.floatChannelData![1]
        let fsr = Float(sr)
        for i in 0..<Int(frames) {
            let (l, r) = gen(Float(i) / fsr)
            L[i] = l.isFinite ? l : 0; R[i] = r.isFinite ? r : 0
        }
        var peak: Float = 0
        for i in 0..<Int(frames) { peak = max(peak, abs(L[i]), abs(R[i])) }
        let want = norm ?? min(0.9, peak)
        if peak > 0 { let g = want / peak; for i in 0..<Int(frames) { L[i] *= g; R[i] *= g } }
        let fade = min(Int(frames), Int(0.006 * sr))
        for k in 0..<fade {
            let g = Float(k) / Float(fade)
            L[Int(frames) - 1 - k] *= g; R[Int(frames) - 1 - k] *= g
        }
        return b
    }

    private func set(_ name: String, _ count: Int, _ gen: (Int) -> AVAudioPCMBuffer) {
        variants[name] = count
        for i in 0..<count { buffers["\(name)_\(i)"] = gen(i) }
    }

    /// A man's voice. `vowels` are (time, F1, F2, F3) keyframes; `pitch` is a curve over 0…1.
    private func shout(_ dur: Double, f0: Float, seed: UInt32, vowels: [(Float, Float, Float, Float)],
                       pitch: @escaping (Float) -> Float, amp: @escaping (Float) -> Float, rasp: Float = 0.12, norm: Float = 0.8) -> AVAudioPCMBuffer {
        var v = Voice()
        v.n = Noise32(s: seed)
        var nz = Noise32(s: seed &+ 99)
        let fsr = Float(sr)
        let D = Float(dur)
        var jit: Float = 0
        return make(dur, norm: norm) { t in
            let u = t / D
            var k = 0
            while k < vowels.count - 2 && vowels[k + 1].0 < u { k += 1 }
            let a = vowels[k], b = vowels[min(k + 1, vowels.count - 1)]
            let w = smoothstep(a.0, max(a.0 + 0.001, b.0), u)
            jit += (nz.next() * 0.06 - jit) * 0.003
            let f = f0 * pitch(u) * (1 + jit)
            let s = softClip(v.run(f0: f, f1: mixf(a.1, b.1, w), f2: mixf(a.2, b.2, w), f3: mixf(a.3, b.3, w), breath: rasp, sr: fsr) * 1.6) * amp(u)
            return (s, s)
        }
    }

    private func buildBuffers() {
        let tau: Float = 2 * .pi
        let fsr = Float(sr)

        // Bone snap: a hard click, a woody resonant crack, splintering ticks, and a dull thunk in the flesh.
        set("crack", 5) { v in
            var r = RNG(UInt64(100 + v))
            var n = Noise32(s: UInt32(7 + v * 13))
            var hp: Float = 0
            var wood = Reso(), wood2 = Reso()
            let f1 = r.range(1600, 2600), f2 = r.range(3200, 4800)
            let ticks = (0..<5).map { _ in (r.range(0.004, 0.06), r.range(0.3, 0.9)) }
            return make(0.35) { t in
                let x = n.next()
                hp += (x - hp) * 0.25
                var click = (x - hp) * expf(-t * 900) * 1.2
                for (tt, a) in ticks where t > tt { click += (x - hp) * expf(-(t - tt) * 1500) * a }
                let cr = wood.run(x, f: f1, q: 7, sr: fsr) * expf(-t * 45) * 2.2 + wood2.run(x, f: f2, q: 9, sr: fsr) * expf(-t * 70) * 1.2
                let thunk = sinf(tau * (140 + 80 * expf(-t * 40)) * t) * expf(-t * 22) * 0.7
                let s = click + cr + thunk
                return (s, s * 0.95)
            }
        }
        // Shatter: a crunchy burst of many micro-cracks.
        set("crunch", 3) { v in
            var r = RNG(UInt64(200 + v))
            var n = Noise32(s: UInt32(31 + v * 7))
            var hp: Float = 0
            var res = Reso()
            let ticks = (0..<22).map { _ in (powf(r.float(), 1.5) * 0.3, r.range(0.3, 1), r.range(1200, 5000)) }
            var lp: Float = 0
            return make(0.5) { t in
                let x = n.next()
                hp += (x - hp) * 0.3
                var s: Float = 0
                for (tt, a, _) in ticks where t > tt && t < tt + 0.03 { s += (x - hp) * expf(-(t - tt) * 700) * a }
                lp += (x - lp) * 0.05
                s += res.run(x, f: ticks[Int(t * 60) % ticks.count].2, q: 5, sr: fsr) * expf(-t * 9) * 0.8
                s += lp * expf(-t * 12) * 2
                s += sinf(tau * 95 * t) * expf(-t * 18) * 0.6
                return (s, s)
            }
        }
        // Body on dirt/grass: deep thump.
        set("thud", 4) { v in
            var n = Noise32(s: UInt32(55 + v))
            var lp: Float = 0
            var rr = RNG(UInt64(300 + v))
            let f0 = rr.range(70, 100)
            return make(0.4) { t in
                let x = n.next()
                lp += (x - lp) * 0.08
                let s = sinf(tau * (f0 + 60 * expf(-t * 30)) * t) * expf(-t * 14) + lp * expf(-t * 25) * 2.5
                return (s, s)
            }
        }
        // Body on rock: a slap with a hard edge.
        set("smack", 4) { v in
            var n = Noise32(s: UInt32(900 + v * 5))
            var hp: Float = 0
            var r1 = Reso(), r2 = Reso()
            var rr = RNG(UInt64(400 + v))
            let fs = rr.range(700, 1100)
            return make(0.4) { t in
                let x = n.next()
                hp += (x - hp) * 0.15
                let crack = (x - hp) * expf(-t * 200) * 1.2
                let slap = r1.run(x, f: fs, q: 2, sr: fsr) * expf(-t * 40) * 2.2
                let thump = sinf(tau * (95 + 60 * expf(-t * 30)) * t) * expf(-t * 16) * 0.9
                let low = r2.run(x, f: 200, q: 1.5, sr: fsr) * expf(-t * 22) * 1.2
                let s = crack + slap + thump + low
                return (s, s * 0.97)
            }
        }
        // Body into a tree trunk or branch: a hollow woody knock with a creak.
        set("wood", 3) { v in
            var n = Noise32(s: UInt32(700 + v))
            var r1 = Reso(), r2 = Reso()
            var rr = RNG(UInt64(710 + v))
            let f1 = rr.range(320, 420), f2 = rr.range(900, 1200)
            return make(0.45) { t in
                let x = n.next()
                let knock = r1.run(x, f: f1, q: 12, sr: fsr) * expf(-t * 18) * 3
                let snap = r2.run(x, f: f2, q: 6, sr: fsr) * expf(-t * 60) * 1.6
                let thump = sinf(tau * 110 * t) * expf(-t * 20) * 0.6
                let s = knock + snap + thump
                return (s, s)
            }
        }
        // Grit sliding on stone.
        set("scrape", 3) { v in
            var n = Noise32(s: UInt32(600 + v))
            var bp = Reso()
            var rr = RNG(UInt64(610 + v))
            return make(0.3) { t in
                let grit = rr.chance(0.02) ? rr.range(0.5, 1.5) : 1
                let s = bp.run(n.next(), f: 900 + Float(v) * 300, q: 1.3, sr: fsr) * sinf(.pi * t / 0.3) * grit
                return (s, s)
            }
        }
        // Jump whoosh.
        buffers["whoosh"] = {
            var n = Noise32(s: 77)
            var bp = Reso()
            let d: Float = 0.5
            return make(Double(d), norm: 0.6) { t in
                let u = t / d
                let s = bp.run(n.next(), f: 300 + 1500 * u, q: 2.5, sr: fsr) * sinf(.pi * u)
                return (s * 0.9, s)
            }
        }()
        // The long scream off the edge.
        buffers["scream"] = shout(2.6, f0: 190, seed: 1000, vowels: [(0, 700, 1150, 2600), (0.08, 850, 1250, 2600), (0.9, 800, 1200, 2500), (1, 700, 1100, 2500)],
                                  pitch: { u in 1.0 + 0.45 * min(1, u * 6) + 0.05 * sinf(u * 60) - 0.25 * max(0, u - 0.7) },
                                  amp: { u in min(1, u * 20) * (u < 0.85 ? 1 : max(0, 1 - (u - 0.85) / 0.15)) }, rasp: 0.25, norm: 0.8)
        // OW / OOF / AAGH / UGH
        variants["ow"] = 4
        buffers["ow_0"] = shout(0.45, f0: 150, seed: 1100, vowels: [(0, 750, 1150, 2500), (0.4, 700, 1100, 2500), (0.8, 380, 800, 2400), (1, 350, 750, 2400)],
                                pitch: { u in 1.35 - 0.5 * u }, amp: { u in min(1, u * 25) * (u < 0.7 ? 1 : 1 - (u - 0.7) / 0.3) })
        buffers["ow_1"] = shout(0.3, f0: 120, seed: 1101, vowels: [(0, 450, 900, 2400), (0.5, 500, 950, 2400), (1, 450, 900, 2400)],
                                pitch: { u in 1.1 - 0.3 * u }, amp: { u in min(1, u * 20) * max(0, 1 - u * 1.1) }, rasp: 0.3)
        buffers["ow_2"] = shout(0.6, f0: 170, seed: 1102, vowels: [(0, 800, 1200, 2500), (0.5, 780, 1150, 2500), (1, 600, 1000, 2400)],
                                pitch: { u in 1.3 + 0.1 * sinf(u * 40) - 0.4 * u }, amp: { u in min(1, u * 15) * (1 - u) }, rasp: 0.35)
        buffers["ow_3"] = shout(0.4, f0: 135, seed: 1103, vowels: [(0, 300, 2200, 2900), (0.3, 700, 1200, 2500), (1, 600, 1000, 2400)],
                                pitch: { u in 1.25 - 0.4 * u }, amp: { u in min(1, u * 20) * (1 - u) }, rasp: 0.2)
        buffers["groan"] = shout(1.4, f0: 95, seed: 1200, vowels: [(0, 500, 900, 2400), (0.5, 550, 950, 2400), (1, 380, 800, 2300)],
                                 pitch: { u in 1.1 - 0.25 * u + 0.03 * sinf(u * 30) }, amp: { u in min(1, u * 5) * (1 - u) }, rasp: 0.4, norm: 0.6)
        buffers["hup"] = shout(0.2, f0: 160, seed: 1300, vowels: [(0, 400, 1000, 2400), (1, 600, 1100, 2400)],
                               pitch: { u in 1 + 0.2 * u }, amp: { u in min(1, u * 30) * (1 - u) }, rasp: 0.3, norm: 0.55)
        // Ka-ching.
        buffers["cash"] = {
            var n = Noise32(s: 12)
            var bp = Reso()
            return make(1.0, norm: 0.6) { t in
                var s: Float = 0
                for (t0, f) in [(Float(0.08), Float(2093)), (0.16, 2637)] where t >= t0 {
                    let d = t - t0
                    s += (sinf(tau * f * d) + 0.5 * sinf(tau * f * 2.4 * d) * expf(-d * 12)) * expf(-d * 5) * min(1, d * 800)
                }
                s += bp.run(n.next(), f: 3000, q: 3, sr: fsr) * expf(-t * 40) * 1.5
                s += n.next() * (t > 0.05 && t < 0.1 ? 0.3 : 0)
                return (s, s)
            }
        }()
        buffers["coin"] = make(0.25, norm: 0.4) { t in
            let f: Float = t < 0.06 ? 1976 : 2637
            let s = sinf(tau * f * t) * expf(-t * 14) * min(1, t * 900)
            return (s, s)
        }
        buffers["buy"] = make(0.8, norm: 0.55) { t in
            var s: Float = 0
            for (k, f) in [Float(1046.5), 1318.5, 1568, 2093].enumerated() {
                let t0 = Float(k) * 0.07
                if t >= t0 { let d = t - t0; s += sinf(tau * f * d) * expf(-d * 6) * min(1, d * 600) }
            }
            return (s, s)
        }
        buffers["nope"] = {
            var ph: Float = 0
            return make(0.35, norm: 0.4) { t in
                ph += 110 / fsr; if ph > 1 { ph -= 1 }
                let s = (ph < 0.5 ? 1 : -1) * 0.5 * (t < 0.14 || t > 0.18 ? 1 : 0) * (1 - t / 0.35)
                return (Float(s), Float(s))
            }
        }()
        buffers["click"] = {
            var n = Noise32(s: 5)
            return make(0.03, norm: 0.35) { t in
                let s = sinf(tau * 2400 * t) * expf(-t * 400) * 0.4 + n.next() * expf(-t * 1500) * 0.2
                return (s, s)
            }
        }()
        buffers["select"] = make(0.12, norm: 0.4) { t in
            let s = sinf(tau * (900 + 900 * t / 0.12) * t) * expf(-t * 20)
            return (s, s)
        }
        // Results: snare roll then a crash.
        buffers["drumroll"] = {
            var n = Noise32(s: 44)
            var hp: Float = 0
            return make(1.5, norm: 0.55) { t in
                let x = n.next()
                hp += (x - hp) * 0.5
                let ph = t * 30 - floorf(t * 30)
                let s = (x - hp) * (0.5 + 0.5 * expf(-ph * 5)) * (0.25 + 0.75 * t / 1.5)
                return (s, s)
            }
        }()
        buffers["crash"] = {
            var n = Noise32(s: 45)
            var hp: Float = 0
            return make(2.0, norm: 0.55) { t in
                let x = n.next()
                hp += (x - hp) * 0.45
                let s = (x - hp) * expf(-t * 2.2) + sinf(tau * 60 * t) * expf(-t * 12) * 0.4
                return (s, s * 0.95)
            }
        }()
        // Charging tick.
        buffers["notch"] = make(0.05, norm: 0.3) { t in
            let s = sinf(tau * (1200 + 6000 * t) * t) * expf(-t * 60)
            return (s, s)
        }
        // Jetpack roar: overlapping chunks make a continuous rumble.
        buffers["jet"] = {
            var n = Noise32(s: 48)
            var lp: Float = 0, bp = Reso()
            return make(0.32, norm: 0.6) { t in
                let x = n.next()
                lp += (x - lp) * 0.12
                let s = (lp * 2.5 + bp.run(x, f: 1400, q: 1.2, sr: fsr) * 0.6) * sinf(.pi * t / 0.32)
                return (s, s * 0.95)
            }
        }()
        // Explosion: a sharp crack, a roaring noise burst and a long rumble.
        buffers["explode"] = {
            var n = Noise32(s: 47)
            var lp: Float = 0, lp2: Float = 0
            return make(2.4, norm: 0.85) { t in
                let x = n.next()
                lp += (x - lp) * (0.02 + 0.3 * expf(-t * 6))
                lp2 += (lp - lp2) * 0.05
                let s = x * expf(-t * 40) * 0.8 + lp * expf(-t * 2.5) * 3 + lp2 * expf(-t * 1.2) * 4 + sinf(tau * (40 + 30 * expf(-t * 5)) * t) * expf(-t * 2) * 0.8
                return (s, s * 0.97)
            }
        }()
        // Heavy slow-mo "BOOM" under a big break.
        buffers["boom"] = {
            var n = Noise32(s: 46)
            var lp: Float = 0
            return make(1.2, norm: 0.7) { t in
                lp += (n.next() - lp) * 0.02
                let s = sinf(tau * (45 + 40 * expf(-t * 8)) * t) * expf(-t * 3.5) + lp * expf(-t * 4) * 3
                return (s, s)
            }
        }()
    }
}
