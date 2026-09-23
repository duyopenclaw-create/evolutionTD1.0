import AVFoundation

/// Owns the AVAudioEngine graph: engine synth (dry), music (delay → reverb), one-shot SFX pool, speech callouts.
final class AudioSystem {
    let engine = AVAudioEngine()
    let format: AVAudioFormat
    let sr: Double
    let synth: EngineSynth
    let music: MusicSynth
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let speech = AVSpeechSynthesizer()
    private let queue = DispatchQueue(label: "skybound.sfx")
    private(set) var running = false
    var muted = false

    init(muted: Bool = false) {
        self.muted = muted
        let out = engine.outputNode.outputFormat(forBus: 0)
        sr = out.sampleRate > 0 ? out.sampleRate : 48000
        format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        synth = EngineSynth(sampleRate: Float(sr))
        music = MusicSynth(sampleRate: Float(sr))
        let s = synth, m = music
        let engineNode = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let b = UnsafeMutableAudioBufferListPointer(abl)
            s.render(frames: Int(frames), b[0].mData!.assumingMemoryBound(to: Float.self), b[1].mData!.assumingMemoryBound(to: Float.self))
            return noErr
        }
        let musicNode = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let b = UnsafeMutableAudioBufferListPointer(abl)
            m.render(frames: Int(frames), b[0].mData!.assumingMemoryBound(to: Float.self), b[1].mData!.assumingMemoryBound(to: Float.self))
            return noErr
        }
        let delay = AVAudioUnitDelay()
        delay.delayTime = 60.0 / 84.0 * 0.75
        delay.feedback = 32
        delay.wetDryMix = 16
        delay.lowPassCutoff = 3200
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 30
        let sfxMix = AVAudioMixerNode()
        let sfxVerb = AVAudioUnitReverb()
        sfxVerb.loadFactoryPreset(.mediumRoom)
        sfxVerb.wetDryMix = 8

        for n in [engineNode, musicNode, delay, reverb, sfxMix, sfxVerb] as [AVAudioNode] { engine.attach(n) }
        engine.connect(musicNode, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.connect(engineNode, to: engine.mainMixerNode, format: format)
        engine.connect(sfxMix, to: sfxVerb, format: format)
        engine.connect(sfxVerb, to: engine.mainMixerNode, format: format)
        for _ in 0..<10 {
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
            NSLog("Skybound: audio unavailable: \(error)")
        }
    }

    func play(_ name: String, volume: Float = 1) {
        guard running, let buf = buffers[name] else { return }
        queue.async {
            let p = self.players[self.nextPlayer]
            self.nextPlayer = (self.nextPlayer + 1) % self.players.count
            p.volume = volume
            p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
            if !p.isPlaying { p.play() }
        }
    }

    func say(_ text: String, interrupt: Bool = true) {
        guard !muted else { return }
        DispatchQueue.main.async {
            if interrupt && self.speech.isSpeaking { self.speech.stopSpeaking(at: .immediate) }
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
            u.rate = 0.56
            u.pitchMultiplier = 0.8
            u.volume = 0.85
            self.speech.speak(u)
        }
    }

    // MARK: Synthesised one-shots

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
        // tiny fade-out to avoid clicks
        let fade = min(Int(frames), Int(0.01 * sr))
        for k in 0..<fade {
            let g = Float(k) / Float(fade)
            L[Int(frames) - 1 - k] *= g; R[Int(frames) - 1 - k] *= g
        }
        return b
    }

    private func buildBuffers() {
        let tau: Float = 2 * .pi
        var n = Noise32(s: 99)

        buffers["click"] = make(0.06) { t in
            let s = n.next() * expf(-t * 320) * 0.5 + sinf(tau * 2400 * t) * expf(-t * 180) * 0.25
            return (s, s)
        }
        buffers["blip"] = make(0.18) { t in
            let f: Float = t < 0.07 ? 880 : 1320
            let s = sinf(tau * f * t) * expf(-t * 14) * 0.3
            return (s, s)
        }

        // Electric gear motor + hydraulic hiss + clunk into the locks
        var lp: Float = 0, ph: Float = 0
        buffers["gear"] = make(2.4) { t in
            let env = smoothstep(0, 0.15, t) * (1 - smoothstep(1.9, 2.05, t))
            let f = 150 + 40 * sinf(t * 2.2) + 30 * t
            ph += f / Float(self.sr)
            let motor = (ph.truncatingRemainder(dividingBy: 1) * 2 - 1) * 0.12 + sinf(ph * tau * 2) * 0.08
            lp += (n.next() - lp) * 0.08
            let hiss = lp * 0.25
            let ct = t - 2.0
            let clunk: Float = ct > 0 ? (sinf(tau * 70 * ct) * 0.6 + n.next() * 0.4) * expf(-ct * 22) : 0
            let s = (motor + hiss) * env + clunk * 0.8
            return (s, s * 0.95)
        }
        var ph2: Float = 0
        buffers["flaps"] = make(1.3) { t in
            let env = smoothstep(0, 0.1, t) * (1 - smoothstep(0.95, 1.1, t))
            ph2 += 260 / Float(self.sr)
            let motor = (ph2.truncatingRemainder(dividingBy: 1) * 2 - 1) * 0.07 + sinf(ph2 * tau * 3) * 0.05
            let ct = t - 1.1
            let stop: Float = ct > 0 ? n.next() * expf(-ct * 60) * 0.4 : 0
            let s = motor * env + stop
            return (s, s)
        }

        // Ring chime: three-note bell arpeggio
        func bell(_ t: Float, _ f: Float) -> Float {
            guard t > 0 else { return 0 }
            return (sinf(tau * f * t) * expf(-t * 3.5) + sinf(tau * f * 2.76 * t) * 0.35 * expf(-t * 7)
                + sinf(tau * f * 5.4 * t) * 0.12 * expf(-t * 12)) * 0.22
        }
        buffers["chime"] = make(1.6) { t in
            let a = bell(t, 1318.5), b = bell(t - 0.07, 1661.2), c = bell(t - 0.14, 1975.5)
            return (a + b * 0.6 + c, a + b + c * 0.6)
        }
        buffers["fanfare"] = make(3.2) { t in
            let notes: [Float] = [587.3, 740, 880, 1174.7, 1480, 1760]
            var l: Float = 0, r: Float = 0
            for (i, f) in notes.enumerated() {
                let v = bell(t - Float(i) * 0.12, f)
                l += v * (i % 2 == 0 ? 1 : 0.6); r += v * (i % 2 == 0 ? 0.6 : 1)
            }
            return (l * 0.8, r * 0.8)
        }

        // Tyre chirp + thump
        var bp1: Float = 0, bp2: Float = 0
        buffers["touch"] = make(0.45) { t in
            let x = n.next()
            bp1 += (x - bp1) * 0.35; bp2 += (bp1 - bp2) * 0.35
            let band = (bp1 - bp2) * 2
            let squeal = sinf(tau * (1750 + 200 * sinf(t * 60)) * t) * 0.25
            let chirp = (band * 0.5 + squeal) * expf(-t * 11)
            let thump = sinf(tau * 85 * t) * expf(-t * 24) * 0.7
            return (chirp + thump, chirp * 0.9 + thump)
        }
        buffers["thud"] = make(0.4) { t in
            let s = (sinf(tau * 60 * t) * 0.8 + n.next() * 0.3) * expf(-t * 14)
            return (s, s)
        }
        var sc: Float = 0
        buffers["scrape"] = make(0.6) { t in
            sc += (n.next() - sc) * 0.5
            let s = (n.next() - sc) * 0.4 * expf(-t * 5)
            return (s, s)
        }

        // Crash: boom, rumbling noise, crackle and metal clangs
        var clp: Float = 0, clp2: Float = 0, crackle: Float = 0
        buffers["crash"] = make(4.0) { t in
            let boom = sinf(tau * (58 - 22 * min(t, 1)) * t) * expf(-t * 1.6) * 0.9
            let cut = 0.05 + 0.4 * expf(-t * 2.5)
            let x = n.next()
            clp += (x - clp) * cut; clp2 += (clp - clp2) * cut
            let rumble = clp2 * 2.2 * expf(-t * 0.9)
            if n.next() > 0.9985 { crackle = 1 }
            crackle *= 0.97
            let crk = crackle * n.next() * 0.5 * expf(-t * 0.6)
            let metal = (sinf(tau * 331 * t) + sinf(tau * 587 * t) * 0.7 + sinf(tau * 1129 * t) * 0.4) * expf(-t * 3.2) * 0.12
            let s = boom + rumble + crk + metal
            return (s * 0.95, s)
        }
        var wlp: Float = 0
        buffers["splash"] = make(3.0) { t in
            let x = n.next()
            wlp += (x - wlp) * (0.08 + 0.3 * expf(-t * 3))
            let body = wlp * 1.6 * smoothstep(0, 0.03, t) * expf(-t * 1.4)
            let bub = sinf(tau * (400 + 900 * fmodf(t * 7.3, 1)) * t) * 0.05 * expf(-t * 1.5) * (fmodf(t * 13, 1) < 0.2 ? 1 : 0)
            let thump = sinf(tau * 50 * t) * expf(-t * 8) * 0.8
            let s = body + bub + thump
            return (s, s * 0.95)
        }

        // Starter motor cranking, cough, catch
        var sph: Float = 0
        buffers["starter"] = make(1.5) { t in
            let crank = (0.5 + 0.5 * sinf(tau * 7 * t)) * (1 - smoothstep(1.0, 1.2, t))
            sph += (180 + 60 * t) / Float(self.sr)
            let whine = (sinf(sph * tau) * 0.1 + n.next() * 0.06) * crank
            let ct = t - 1.05
            let cough: Float = ct > 0 ? (n.next() * 0.5 + sinf(tau * 45 * ct) * 0.6) * expf(-ct * 9) : 0
            let s = whine + cough
            return (s, s)
        }
        buffers["warn"] = make(0.5) { t in
            let f: Float = t < 0.25 ? 740 : 587
            let s = (sinf(tau * f * t) > 0 ? 0.12 : -0.12) * (1 - smoothstep(0.45, 0.5, t))
            return (s, s)
        }
    }
}
