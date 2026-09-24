import AVFoundation

/// AVAudioEngine graph: ambience (dry), music (delay → hall), and a pool of panned one-shot players
/// through a small-room reverb. Every sound is synthesised at launch.
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
    private let speech = AVSpeechSynthesizer()
    private let queue = DispatchQueue(label: "scurry.sfx")
    private(set) var running = false
    private let sfxVerb = AVAudioUnitReverb()
    var muted = false

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
        let delay = AVAudioUnitDelay()
        delay.delayTime = 60.0 / 76.0 * 0.75
        delay.feedback = 28
        delay.wetDryMix = 14
        delay.lowPassCutoff = 2600
        let hall = AVAudioUnitReverb()
        hall.loadFactoryPreset(.largeHall)
        hall.wetDryMix = 34
        let sfxMix = AVAudioMixerNode()
        sfxVerb.loadFactoryPreset(.smallRoom)
        sfxVerb.wetDryMix = 14

        for n in [ambNode, musicNode, delay, hall, sfxMix, sfxVerb] as [AVAudioNode] { engine.attach(n) }
        engine.connect(musicNode, to: delay, format: format)
        engine.connect(delay, to: hall, format: format)
        engine.connect(hall, to: engine.mainMixerNode, format: format)
        engine.connect(ambNode, to: engine.mainMixerNode, format: format)
        engine.connect(sfxMix, to: sfxVerb, format: format)
        engine.connect(sfxVerb, to: engine.mainMixerNode, format: format)
        for _ in 0..<16 {
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
            NSLog("Scurry: audio unavailable: \(error)")
        }
    }

    /// Plays a one-shot. Names with variants ("step_hard") pick one at random.
    func play(_ name: String, volume: Float = 1, pan: Float = 0) {
        guard running, !muted else { return }
        var key = name
        if let n = variants[name] { key = "\(name)_\(Int.random(in: 0..<n))" }
        guard let buf = buffers[key] else { return }
        let v = max(0, min(1.5, volume))
        guard v > 0.003 else { return }
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
    func selfCheck() {
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
        amb.fridgeGain = 1; amb.clockGain = 1; amb.windGain = 1; amb.purrGain = 1; amb.heart = 1; amb.buzz = 1
        mus.explore = 1; mus.tension = 1; mus.home = 1
        var pa: Float = 0, pm: Float = 0, rmsM: Double = 0, count = 0
        for _ in 0..<Int(20 * sr) / n {
            amb.render(frames: n, L, R); for i in 0..<n { pa = max(pa, abs(L[i]).isFinite ? abs(L[i]) : 99) }
            mus.render(frames: n, L, R); for i in 0..<n { pm = max(pm, abs(L[i]).isFinite ? abs(L[i]) : 99); rmsM += Double(L[i] * L[i]); count += 1 }
        }
        print(String(format: "%@ ambience peak %.2f   %@ music peak %.2f rms %.3f", pa < 1.2 && pa > 0.01 ? "PASS" : "FAIL", pa,
                     pm < 1.2 && pm > 0.02 ? "PASS" : "FAIL", pm, sqrt(rmsM / Double(count))))
    }

    func setRoomWet(_ w: Float) { sfxVerb.wetDryMix = w }

    func say(_ text: String, pitch: Float = 1.0, rate: Float = 0.55) {
        guard !muted, running else { return }
        DispatchQueue.main.async {
            if self.speech.isSpeaking { self.speech.stopSpeaking(at: .immediate) }
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
            u.rate = rate
            u.pitchMultiplier = pitch
            u.volume = 0.9
            self.speech.speak(u)
        }
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
        // keep every one-shot below full scale
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
        var n = Noise32(s: 12345)

        // Claw ticks on hard floors: 2–3 tiny bright clicks.
        func clawTicks(_ seed: Int, _ count: Int, bright: Float, ring: Float) -> AVAudioPCMBuffer {
            var r = Noise32(s: UInt32(seed * 7919 + 13))
            var times: [Float] = [], freqs: [Float] = []
            for k in 0..<count {
                let u1: Float = r.next() * 0.5 + 0.5, u2: Float = r.next() * 0.5 + 0.5
                times.append(Float(k) * (0.006 + u1 * 0.008))
                freqs.append(bright * (0.8 + u2 * 0.5))
            }
            var hp: Float = 0
            return make(0.06) { t in
                var s: Float = 0
                for (k, t0) in times.enumerated() where t >= t0 {
                    let dt = t - t0
                    s += sinf(tau * freqs[k] * dt) * expf(-dt * 900) * 0.5
                    s += sinf(tau * freqs[k] * 1.7 * dt) * expf(-dt * 300) * ring
                }
                let x = n.next() * expf(-t * 400) * 0.25
                hp += (x - hp) * 0.3
                s += x - hp
                return (s * 0.6, s * 0.6)
            }
        }
        set("step_hard", 5) { i in clawTicks(i, 2 + i % 2, bright: 4200, ring: 0.05) }
        set("step_metal", 4) { i in clawTicks(i + 20, 2 + i % 2, bright: 3100, ring: 0.25) }
        set("step_wood", 4) { i in clawTicks(i + 40, 2, bright: 1900, ring: 0.02) }
        set("step_soft", 4) { i in
            var lp: Float = 0
            var r = Noise32(s: UInt32(900 + i))
            return make(0.05) { t in
                lp += (r.next() - lp) * 0.08
                let s = lp * expf(-t * 90) * 0.5
                return (s, s)
            }
        }
        set("step_card", 3) { i in
            var r = Noise32(s: UInt32(700 + i))
            var hp: Float = 0
            return make(0.09) { t in
                let x = r.next()
                hp += (x - hp) * 0.2
                let crackle: Float = r.next() > 0.8 ? 1 : 0.2
                let s = (x - hp) * crackle * expf(-t * 50) * 0.4
                return (s, s)
            }
        }

        // Rat squeaks: FM chirps around 4–6 kHz.
        set("squeak", 3) { i in
            let base: Float = 4200 + Float(i) * 500
            var ph: Float = 0
            return make(0.26) { t in
                let chirp1 = t < 0.09 ? sinf(t / 0.09 * .pi) : 0
                let t2 = t - 0.12
                let chirp2 = t2 > 0 && t2 < 0.11 ? sinf(t2 / 0.11 * .pi) : 0
                let f = base * (1 + 0.25 * sinf(t * 70)) * (t < 0.1 ? 1 + t * 3 : 1.2 - t2 * 1.5)
                ph += f / fsr
                let s = sinf(ph * tau) * (chirp1 + chirp2 * 0.8) * 0.28
                return (s, s)
            }
        }
        buffers["squeal"] = {
            var ph: Float = 0
            return make(0.5) { t in
                let f: Float = 3800 + 1400 * sinf(t * 30) + 800 * t
                ph += f / fsr
                let env = smoothstep(0, 0.02, t) * (1 - smoothstep(0.35, 0.5, t))
                let s = (sinf(ph * tau) + 0.3 * sinf(ph * tau * 2)) * env * 0.35
                return (s, s)
            }
        }()

        // Chewing: crunchy grains (hard food) or soft mouthing.
        set("crunch", 4) { i in
            var r = Noise32(s: UInt32(300 + i))
            var hp: Float = 0, grain: Float = 0
            return make(0.2) { t in
                if r.next() > 0.985 { grain = 1 }
                grain *= 0.994
                let x = r.next()
                hp += (x - hp) * 0.25
                let s = (x - hp) * grain * 0.5 * (1 - smoothstep(0.12, 0.2, t))
                return (s, s)
            }
        }
        set("nibble", 4) { i in
            var r = Noise32(s: UInt32(500 + i))
            var lp: Float = 0
            return make(0.16) { t in
                lp += (r.next() - lp) * 0.15
                let pulse = max(0, sinf(t * 45 + Float(i)))
                let s = lp * pulse * 0.5 * (1 - smoothstep(0.1, 0.16, t))
                return (s, s)
            }
        }
        buffers["pickup"] = make(0.18) { t in
            let s = n.next() * expf(-t * 30) * 0.15 + sinf(tau * 1800 * t) * expf(-t * 60) * 0.1
            return (s, s)
        }
        buffers["drop"] = make(0.12) { t in
            let s = sinf(tau * 320 * t) * expf(-t * 40) * 0.2 + n.next() * expf(-t * 70) * 0.1
            return (s, s)
        }

        // Soft bell pair for stashing food, a gentle arpeggio for dawn.
        func bell(_ t: Float, _ f: Float) -> Float {
            guard t > 0 else { return 0 }
            return (sinf(tau * f * t) * expf(-t * 3) + sinf(tau * f * 2.76 * t) * 0.3 * expf(-t * 6)
                + sinf(tau * f * 5.4 * t) * 0.1 * expf(-t * 10)) * 0.2
        }
        buffers["stash"] = make(1.4) { t in
            let a = bell(t, 1174.7), b = bell(t - 0.09, 1568)
            return (a + b * 0.7, a * 0.7 + b)
        }
        buffers["dawn"] = make(4.0) { t in
            let notes: [Float] = [587.3, 698.5, 880, 1046.5, 1174.7, 1396.9]
            var l: Float = 0, r: Float = 0
            for (i, f) in notes.enumerated() {
                let v = bell(t - Float(i) * 0.22, f)
                l += v * (i % 2 == 0 ? 1 : 0.6); r += v * (i % 2 == 0 ? 0.6 : 1)
            }
            return (l * 0.7, r * 0.7)
        }
        buffers["blip"] = make(0.12) { t in
            let s = sinf(tau * (t < 0.05 ? 880 : 1320) * t) * expf(-t * 18) * 0.2
            return (s, s)
        }

        // Movement
        var wlp: Float = 0
        buffers["jump"] = make(0.14) { t in
            wlp += (n.next() - wlp) * (0.05 + t * 2)
            let s = wlp * smoothstep(0, 0.03, t) * (1 - smoothstep(0.06, 0.14, t)) * 0.5
            return (s, s)
        }
        buffers["land"] = make(0.12) { t in
            let s = sinf(tau * 180 * t) * expf(-t * 60) * 0.25 + n.next() * expf(-t * 120) * 0.12
            return (s, s)
        }
        set("scratch", 4) { i in
            var r = Noise32(s: UInt32(1100 + i))
            var hp: Float = 0
            return make(0.09) { t in
                let x = r.next()
                hp += (x - hp) * 0.35
                let bursts = max(0, sinf(t * 180 + Float(i))) * expf(-t * 25)
                let s = (x - hp) * bursts * 0.4
                return (s, s)
            }
        }

        // Cat voice: glottal pulse train through two sweeping formants.
        func catVoice(_ dur: Float, f0: (Float) -> Float, f1: (Float) -> Float, f2: (Float) -> Float, amp: Float, breath: Float) -> AVAudioPCMBuffer {
            var ph: Float = 0
            var r1 = Reso(), r2 = Reso(), r3 = Reso()
            var rr = Noise32(s: 4242)
            return make(Double(dur)) { t in
                let k = t / dur
                ph += f0(k) / fsr
                if ph >= 1 { ph -= 1 }
                let glot = powf(max(0, sinf(ph * .pi)), 3) * 2 - 0.5 + rr.next() * breath
                let a = r1.run(glot, f: f1(k), q: 5, sr: fsr) + r2.run(glot, f: f2(k), q: 7, sr: fsr) * 0.7 + r3.run(glot, f: 3400, q: 9, sr: fsr) * 0.2
                let env = smoothstep(0, 0.08, k) * (1 - smoothstep(0.75, 1, k))
                let s = a * env * amp
                return (s, s * 0.95)
            }
        }
        set("meow", 2) { i in
            let hi: Float = i == 0 ? 1 : 1.15
            return catVoice(0.85, f0: { k in (480 + 320 * sinf(min(1, k * 1.4) * .pi) - 60 * k) * hi },
                            f1: { k in 550 + 600 * sinf(min(1, k * 1.2) * .pi) }, f2: { k in 1800 - 500 * k },
                            amp: 0.16, breath: 0.15)
        }
        buffers["mrrp"] = {
            let v = catVoice(0.32, f0: { k in 380 + 260 * k }, f1: { _ in 650 }, f2: { k in 1500 + 400 * k }, amp: 0.15, breath: 0.2)
            let L = v.floatChannelData![0], R = v.floatChannelData![1]
            for i in 0..<Int(v.frameLength) { let g = 0.5 + 0.5 * sinf(Float(i) / fsr * tau * 28); L[i] *= g; R[i] *= g }   // rolled "rr"
            return v
        }()
        buffers["chatter"] = make(0.7) { t in
            let clicks = fmodf(t * 16, 1)
            let tone = sinf(tau * (900 + 200 * sinf(t * 9)) * t) * 0.08
            let c = clicks < 0.1 ? n.next() * 0.35 : 0
            let env = smoothstep(0, 0.05, t) * (1 - smoothstep(0.55, 0.7, t))
            let s = (c + tone * (clicks < 0.5 ? 1 : 0.3)) * env
            return (s, s)
        }
        var hlp: Float = 0
        var hr = Reso()
        buffers["hiss"] = make(1.0) { t in
            let x = n.next()
            hlp += (x - hlp) * 0.4
            let hp = x - hlp
            let res = hr.run(hp, f: 4800, q: 2, sr: fsr) * 0.6
            let env = smoothstep(0, 0.04, t) * (1 - smoothstep(0.6, 1.0, t)) * (0.85 + 0.15 * sinf(t * 60))
            let s = (hp * 0.35 + res) * env * 0.7
            return (s, s)
        }
        var plp: Float = 0
        buffers["pounce"] = make(0.4) { t in
            plp += (n.next() - plp) * (0.03 + t * 0.3)
            let whoosh = plp * smoothstep(0, 0.1, t) * (1 - smoothstep(0.2, 0.3, t)) * 1.4
            let tt = t - 0.28
            let thump: Float = tt > 0 ? sinf(tau * 70 * tt) * expf(-tt * 25) * 0.7 : 0
            return (whoosh + thump, whoosh * 0.9 + thump)
        }
        buffers["catland"] = make(0.25) { t in
            let s = sinf(tau * 65 * t) * expf(-t * 22) * 0.5 + n.next() * expf(-t * 60) * 0.1
            return (s, s)
        }
        var slp: Float = 0
        buffers["swipe"] = make(0.3) { t in
            slp += (n.next() - slp) * 0.25
            let scr = (n.next() - slp) * (t > 0.08 && t < 0.2 ? 1 : 0) * 0.4
            let wh = slp * smoothstep(0, 0.05, t) * (1 - smoothstep(0.08, 0.15, t))
            let ring = sinf(tau * 2700 * t) * (t > 0.1 ? expf(-(t - 0.1) * 30) : 0) * 0.06
            return (scr + wh + ring, scr + wh * 0.9 + ring)
        }

        // Trap snap: dry wood crack + wire ring.
        buffers["snap"] = make(0.7) { t in
            let crack = n.next() * expf(-t * 250) * 1.2
            let wood = sinf(tau * 820 * t) * expf(-t * 40) * 0.5 + sinf(tau * 1930 * t) * expf(-t * 60) * 0.3
            let spring = sinf(tau * 3150 * t + sinf(tau * 7 * t)) * expf(-t * 7) * 0.12
            let s = crack + wood + spring
            return (s, s * 0.95)
        }
        // Ceramic mug smash and glass smash
        func breakage(_ seed: UInt32, bright: Float, dur: Double) -> AVAudioPCMBuffer {
            var r = Noise32(s: seed)
            var pings: [(Float, Float, Float)] = []
            for _ in 0..<40 { pings.append(((r.next() * 0.5 + 0.5) * 0.6, bright * (0.6 + (r.next() * 0.5 + 0.5)), 0.2 + (r.next() * 0.5 + 0.5) * 0.5)) }
            var hp: Float = 0
            return make(dur) { t in
                let x = r.next()
                hp += (x - hp) * 0.2
                var s = (x - hp) * expf(-t * 18) * 0.8 + sinf(tau * 90 * t) * expf(-t * 30) * 0.6
                for (t0, f, a) in pings where t > t0 {
                    let dt = t - t0
                    s += sinf(tau * f * dt) * expf(-dt * 35) * a * 0.18
                }
                return (s, s * 0.9)
            }
        }
        buffers["shatter"] = breakage(77, bright: 2800, dur: 1.2)
        buffers["glassbreak"] = breakage(99, bright: 5200, dur: 1.4)
        buffers["clatter"] = make(1.0) { t in
            var s: Float = 0
            for (i, t0) in [0.0, 0.14, 0.24, 0.31, 0.36].enumerated() where t > Float(t0) {
                let dt = t - Float(t0)
                let a = 0.5 / Float(i + 1)
                s += (sinf(tau * 2350 * dt) + sinf(tau * 3920 * dt) * 0.6 + sinf(tau * 6100 * dt) * 0.3) * expf(-dt * 18) * a * 0.3
            }
            return (s, s)
        }
        buffers["tip"] = make(0.18) { t in
            let s = sinf(tau * 500 * t) * expf(-t * 40) * 0.2 + n.next() * expf(-t * 80) * 0.08
            return (s, s)
        }

        // The person: heavy footsteps (huge at rat scale), switch, fridge, stomp.
        set("footfall", 3) { i in
            var lp: Float = 0
            var r = Noise32(s: UInt32(1300 + i))
            return make(0.5) { t in
                lp += (r.next() - lp) * 0.03
                let thud = sinf(tau * (55 + Float(i) * 6) * t) * expf(-t * 14) * 0.9
                let creak = (i == 1 ? sinf(tau * (300 + 120 * t) * t) * 0.05 * smoothstep(0.05, 0.1, t) * (1 - smoothstep(0.2, 0.4, t)) : 0)
                let s = thud + lp * expf(-t * 10) * 1.5 + creak
                return (s, s)
            }
        }
        buffers["switch"] = make(0.08) { t in
            let s = (n.next() * 0.5 + sinf(tau * 1600 * t)) * expf(-t * 160) * 0.5
            return (s, s)
        }
        buffers["fridgeOpen"] = make(1.2) { t in
            let pop = t < 0.06 ? n.next() * (1 - t / 0.06) * 0.4 : 0
            let suck = sinf(tau * 120 * t) * expf(-t * 20) * 0.3
            var s = pop + suck
            for t0 in [0.35, 0.42, 0.6] as [Float] where t > t0 {
                let dt = t - t0
                s += (sinf(tau * 2100 * dt) + sinf(tau * 3300 * dt) * 0.5) * expf(-dt * 30) * 0.08
            }
            return (s, s)
        }
        buffers["fridgeClose"] = make(0.6) { t in
            let s = sinf(tau * 70 * t) * expf(-t * 18) * 0.8 + n.next() * expf(-t * 40) * 0.3
            return (s, s)
        }
        buffers["bottles"] = make(0.9) { t in
            var s: Float = 0
            for (i, t0) in [0.0, 0.07, 0.2, 0.26, 0.45].enumerated() where t > Float(t0) {
                let dt = t - Float(t0)
                let f: Float = [2200, 2750, 1900, 3100, 2400][i]
                s += sinf(tau * f * dt) * expf(-dt * 25) * 0.1
            }
            return (s, s)
        }
        var stlp: Float = 0
        buffers["stomp"] = make(1.2) { t in
            stlp += (n.next() - stlp) * 0.05
            let boom = sinf(tau * (48 - 10 * min(t, 1)) * t) * expf(-t * 6) * 1.2
            let s = boom + stlp * expf(-t * 8) * 2
            return (s, s)
        }
        // Caught: a dissonant low cluster
        buffers["caught"] = make(2.5) { t in
            var s: Float = 0
            for f in [55, 58.3, 82.4, 87.3, 116.5] as [Float] { s += sinf(tau * f * t) * 0.14 }
            s *= expf(-t * 1.4)
            s += n.next() * expf(-t * 12) * 0.3
            return (s, s)
        }
        buffers["drip"] = make(0.25) { t in
            let f = 1100 + 1400 * min(1, t * 22)
            let s = sinf(tau * f * t) * expf(-t * 45) * 0.25 + n.next() * expf(-t * 200) * 0.06
            return (s, s)
        }
    }
}
