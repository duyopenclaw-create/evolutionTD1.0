import AVFoundation

/// AVAudioEngine graph. Music goes through a delay and a hall. The ambience is dry. A pool of panned
/// one-shot players goes through a flutter-echo slap and a large hall, which is how a gym sounds.
/// Every sound is synthesised at launch.
final class AudioSystem {
    let engine = AVAudioEngine()
    let format: AVAudioFormat
    let sr: Double
    let ambient: AmbientSynth
    let music: MusicSynth
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var variants: [String: Int] = [:]
    private let queue = DispatchQueue(label: "hailstone.sfx")
    private(set) var running = false
    var muted = false
    var sfxLevel: Float = 1

    static let buckets = 6
    static func bucket(_ r: Float) -> Int { max(0, min(buckets - 1, Int((r - 0.07) / 0.09))) }

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
        let mDelay = AVAudioUnitDelay()
        mDelay.delayTime = 60.0 / 72.0 * 0.75
        mDelay.feedback = 30
        mDelay.wetDryMix = 16
        mDelay.lowPassCutoff = 3000
        let mHall = AVAudioUnitReverb()
        mHall.loadFactoryPreset(.largeHall)
        mHall.wetDryMix = 30
        let sfxMix = AVAudioMixerNode()
        let slap = AVAudioUnitDelay()
        slap.delayTime = 0.062
        slap.feedback = 32
        slap.wetDryMix = 9
        slap.lowPassCutoff = 5000
        let gym = AVAudioUnitReverb()
        gym.loadFactoryPreset(.largeHall2)
        gym.wetDryMix = 24

        for n in [ambNode, musicNode, mDelay, mHall, sfxMix, slap, gym] as [AVAudioNode] { engine.attach(n) }
        engine.connect(musicNode, to: mDelay, format: format)
        engine.connect(mDelay, to: mHall, format: format)
        engine.connect(mHall, to: engine.mainMixerNode, format: format)
        engine.connect(ambNode, to: engine.mainMixerNode, format: format)
        engine.connect(sfxMix, to: slap, format: format)
        engine.connect(slap, to: gym, format: format)
        engine.connect(gym, to: engine.mainMixerNode, format: format)
        for _ in 0..<28 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: sfxMix, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = muted ? 0 : 0.9
        buildBuffers()
        do {
            try engine.start()
            for p in players { p.play() }
            running = true
        } catch {
            NSLog("Hailstone: audio unavailable: \(error)")
        }
    }

    var masterVolume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = muted ? 0 : max(0, min(1, newValue)) }
    }

    /// Plays a one-shot. Names with variants ("bounce_2") pick one at random.
    func play(_ name: String, volume: Float = 1, pan: Float = 0) {
        guard running, !muted else { return }
        var key = name
        if let n = variants[name] { key = "\(name)_\(Int.random(in: 0..<n))" }
        guard let buf = buffers[key] else { return }
        let v = max(0, min(1.4, volume * sfxLevel))
        guard v > 0.004 else { return }
        queue.async {
            let p = self.players[self.nextPlayer]
            self.nextPlayer = (self.nextPlayer + 1) % self.players.count
            p.volume = v
            p.pan = max(-1, min(1, pan))
            p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !p.isPlaying { p.play() }
        }
    }

    /// Peak and NaN check of every buffer plus 20 s of ambience and score (for --autotest).
    func selfCheck() -> Bool {
        var bad: [String] = []
        for (k, b) in buffers.sorted(by: { $0.key < $1.key }) {
            var peak: Float = 0
            let L = b.floatChannelData![0]
            for i in 0..<Int(b.frameLength) { if !L[i].isFinite { peak = .nan; break }; peak = max(peak, abs(L[i])) }
            if !(peak > 0.005 && peak < 1.6) { bad.append("\(k)=\(peak)") }
        }
        print(bad.isEmpty ? "PASS sfx buffers (\(buffers.count))" : "FAIL sfx buffers: \(bad.joined(separator: ", "))")
        let n = 1024
        let L = UnsafeMutablePointer<Float>.allocate(capacity: n), R = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { L.deallocate(); R.deallocate() }
        let amb = AmbientSynth(sampleRate: Float(sr)), mus = MusicSynth(sampleRate: Float(sr))
        amb.roll = 1; amb.motor = 1
        var pa: Float = 0, pm: Float = 0, rmsM: Double = 0, count = 0
        for b in 0..<Int(40 * sr) / n {
            if b % 20 == 0 { mus.push(b % 14) }
            amb.render(frames: n, L, R); for i in 0..<n { pa = max(pa, abs(L[i]).isFinite ? abs(L[i]) : 99) }
            mus.render(frames: n, L, R); for i in 0..<n { pm = max(pm, abs(L[i]).isFinite ? abs(L[i]) : 99); rmsM += Double(L[i] * L[i]); count += 1 }
        }
        let okA = pa < 1.2 && pa > 0.01, okM = pm < 1.2 && pm > 0.02
        print(String(format: "%@ ambience peak %.2f   %@ music peak %.2f rms %.3f", okA ? "PASS" : "FAIL", pa,
                     okM ? "PASS" : "FAIL", pm, sqrt(rmsM / Double(count))))
        return bad.isEmpty && okA && okM
    }

    // MARK: Synthesis

    private func make(_ dur: Double, _ gen: (Float) -> (Float, Float)) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(dur * sr)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        b.frameLength = frames
        let L = b.floatChannelData![0], R = b.floatChannelData![1]
        let fsr = Float(sr)
        for i in 0..<Int(frames) {
            let (l, r) = gen(Float(i) / fsr)
            L[i] = l; R[i] = r
        }
        var peak: Float = 0
        for i in 0..<Int(frames) { peak = max(peak, abs(L[i]), abs(R[i])) }
        if peak > 0.9 { let g = 0.9 / peak; for i in 0..<Int(frames) { L[i] *= g; R[i] *= g } }
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

    private func buildBuffers() {
        let tau: Float = 2 * .pi
        let fsr = Float(sr)

        // Resin ball on a sprung maple floor: a sharp contact tick, the ball's own ring (higher for
        // small balls), and the hollow thump of the boards and their subfloor.
        for b in 0..<AudioSystem.buckets {
            set("bounce_\(b)", 4) { v in
                var r = RNG(UInt64(1000 + b * 10 + v))
                var n = Noise32(s: UInt32(77 + b * 13 + v * 101))
                let rc = 0.1 + 0.09 * Float(b)
                let fBall = 2600 * powf(0.1 / rc, 0.85) * r.range(0.93, 1.07)
                let fThump = (150 - 14 * Float(b)) * r.range(0.9, 1.1)
                let modes: [(Float, Float, Float)] = [(r.range(280, 340), 30, 0.22), (r.range(480, 560), 45, 0.14), (r.range(820, 950), 70, 0.08), (r.range(1500, 1800), 110, 0.04)]
                let bodyW = 0.25 + 0.15 * Float(b)
                var ph: Float = 0, hp: Float = 0, lp: Float = 0
                var mph = [Float](repeating: 0, count: modes.count)
                return make(0.45) { t in
                    let x = n.next()
                    hp += (x - hp) * 0.25
                    let click = (x - hp) * expf(-t * 1600) * 0.7
                    lp += (x - lp) * 0.05
                    let slapN = lp * expf(-t * 180) * 0.8 * bodyW
                    ph += fThump * (1 + 0.5 * expf(-t * 45)) / fsr
                    let thump = sinf(tau * ph) * expf(-t * 24) * bodyW * 1.2
                    let ring = sinf(tau * fBall * t) * expf(-t * (95 - 9 * Float(b))) * 0.32
                        + sinf(tau * fBall * 2.41 * t) * expf(-t * 190) * 0.1
                    var board: Float = 0
                    for (k, m) in modes.enumerated() {
                        mph[k] += m.0 / fsr
                        board += sinf(tau * mph[k]) * expf(-t * m.1) * m.2
                    }
                    let s = click + slapN + thump + ring + board * (0.6 + 0.2 * Float(b))
                    return (s, s * 0.96 + board * 0.04)
                }
            }
            // Ball against ball: the billiard clack.
            set("clack_\(b)", 3) { v in
                var r = RNG(UInt64(5000 + b * 10 + v))
                var n = Noise32(s: UInt32(3 + b * 7 + v * 31))
                let rc = 0.1 + 0.09 * Float(b)
                let f = 3900 * powf(0.1 / rc, 0.55) * r.range(0.94, 1.06)
                var hp: Float = 0
                return make(0.2) { t in
                    let x = n.next()
                    hp += (x - hp) * 0.35
                    let s = sinf(tau * f * t) * expf(-t * 260) * 0.55
                        + sinf(tau * f * 1.53 * t) * expf(-t * 330) * 0.25
                        + sinf(tau * f * 0.31 * t) * expf(-t * 70) * 0.18 * (1 + Float(b) * 0.3)
                        + (x - hp) * expf(-t * 2600) * 0.7
                    return (s, s)
                }
            }
            // Birth pop. Halving gives a tight cork "pok". Tripling (3n+1) gives an inflating "fwump".
            let base = 1300 * powf(0.1 / (0.1 + 0.09 * Float(b)), 0.5)
            buffers["pop_even_\(b)"] = {
                var n = Noise32(s: UInt32(91 + b))
                var rs = Reso(), ph: Float = 0
                return make(0.22) { t in
                    ph += base * (1.25 - 0.45 * min(1, t / 0.08)) / fsr
                    let tone = sinf(tau * ph) * expf(-t * 32) * 0.45
                    let air = rs.run(n.next(), f: base * 1.8, q: 6, sr: fsr) * expf(-t * 60) * 1.6
                    let s = tone + air
                    return (s, s)
                }
            }()
            buffers["pop_odd_\(b)"] = {
                var n = Noise32(s: UInt32(191 + b))
                var rs = Reso(), ph: Float = 0, lp: Float = 0
                return make(0.42) { t in
                    let rise = min(1, t / 0.2)
                    ph += base * (0.25 + 0.6 * rise * rise) / fsr
                    let swell = sinf(.pi * min(1, t / 0.24))
                    let tone = sinf(tau * ph) * swell * expf(-max(0, t - 0.24) * 25) * 0.4
                    lp += (n.next() - lp) * (0.02 + 0.2 * rise)
                    let whoosh = lp * swell * 0.9
                    let pt = t - 0.22
                    let pop = pt > 0 ? rs.run(n.next(), f: base * 2.2, q: 5, sr: fsr) * expf(-pt * 70) * 2.2 : 0
                    let s = tone + whoosh + pop
                    return (s * 0.95, s)
                }
            }()
        }
        // Acrylic sheet knock: a plasticky panel boom with a short rattle in its frame.
        set("glass", 4) { v in
            var r = RNG(UInt64(900 + v))
            var n = Noise32(s: UInt32(17 + v))
            let modes: [(Float, Float, Float)] = [(r.range(85, 105), 10, 0.4), (r.range(180, 210), 13, 0.3), (r.range(330, 380), 18, 0.2),
                                                  (r.range(610, 680), 26, 0.12), (r.range(1100, 1250), 40, 0.07), (r.range(2000, 2300), 70, 0.04)]
            var hp: Float = 0
            return make(0.7) { t in
                var s: Float = 0
                for m in modes { s += sinf(tau * m.0 * t) * expf(-t * m.1) * m.2 }
                let x = n.next()
                hp += (x - hp) * 0.3
                s += (x - hp) * expf(-t * 900) * 0.5
                s += x * expf(-t * 30) * 0.03 * (sinf(tau * 38 * t) > 0.6 ? 1 : 0)
                return (s, s * 0.97)
            }
        }
        // Reaching 1: a struck tubular chime, then a fifth and an octave above (D, A, D).
        buffers["one"] = {
            let notes: [(Float, Float)] = [(587.33, 0), (880, 0.16), (1174.66, 0.32)]
            let partials: [(Float, Float, Float)] = [(1, 1.0, 0.5), (2.76, 0.5, 1.2), (5.40, 0.3, 2.4), (8.93, 0.15, 4), (0.5, 0.18, 0.9)]
            return make(4.5) { t in
                var l: Float = 0, rr: Float = 0
                for (k, (f, t0)) in notes.enumerated() where t >= t0 {
                    let dt = t - t0
                    var s: Float = 0
                    for p in partials { s += sinf(tau * f * p.0 * dt) * p.1 * expf(-dt * p.2) }
                    s *= min(1, dt * 800) * 0.35
                    let pan: Float = [-0.3, 0.3, 0][k]
                    l += s * (1 - pan); rr += s * (1 + pan)
                }
                return (l, rr)
            }
        }()
        // Dispenser: solenoid latch clack and a hiss of air as the ball drops out.
        buffers["drop"] = {
            var n = Noise32(s: 4242)
            var rs = Reso(), rs2 = Reso()
            return make(0.5) { t in
                let x = n.next()
                var s = rs.run(x, f: 2400, q: 8, sr: fsr) * expf(-t * 250) * 2.5
                let t2 = t - 0.035
                if t2 > 0 { s += rs2.run(x, f: 1500, q: 6, sr: fsr) * expf(-t2 * 300) * 2 }
                s += sinf(tau * 190 * t) * expf(-t * 60) * 0.35
                s += x * 0.22 * expf(-t * 7) * min(1, t * 40)
                return (s, s)
            }
        }()
        // Clearing the pen: floor hatches swing open with a long air rush.
        buffers["clear"] = {
            var n = Noise32(s: 999)
            var lp: Float = 0
            return make(1.6) { t in
                let e = sinf(.pi * min(1, t / 1.6))
                lp += (n.next() - lp) * (0.02 + 0.12 * e)
                var s = lp * e * 1.4
                if t < 0.12 { s += sinf(tau * 70 * t) * expf(-t * 25) * 0.6 }
                return (s, s * 0.9)
            }
        }()
        buffers["tick"] = {
            var n = Noise32(s: 5)
            return make(0.03) { t in
                let s = sinf(tau * 3200 * t) * expf(-t * 500) * 0.35 + n.next() * expf(-t * 1500) * 0.2
                return (s, s)
            }
        }()
        buffers["gantry_stop"] = {
            var n = Noise32(s: 77)
            return make(0.25) { t in
                let s = sinf(tau * 140 * t) * expf(-t * 40) * 0.4 + n.next() * expf(-t * 120) * 0.15 + sinf(tau * 2900 * t) * expf(-t * 90) * 0.06
                return (s, s)
            }
        }()
    }
}
