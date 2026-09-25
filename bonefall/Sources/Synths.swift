import Foundation

// MARK: - Ambience: mountain wind, a speed-driven rush when falling, gulls or a lava rumble per map

final class AmbientSynth {
    let sr: Float
    var master: Float = 1
    var rush: Float = 0          // 0...1, set from fall speed
    var gulls = false
    var rumble = false
    private var sM: Float = 0, sRush: Float = 0
    private var n = Noise32(s: 0xA11CE), n2 = Noise32(s: 0xB0B), n3 = Noise32(s: 0xC0FFEE)
    private var windL: Float = 0, windR: Float = 0, gust: Float = 0.5, gustT: Float = 0, gustPh: Float = 0.5
    private var whis1 = Reso(), whis2 = Reso(), rushHP: Float = 0, rushLP: Float = 0, rushLPR: Float = 0
    private var rng = RNG(0xB1BD)
    private var gullT: Float = 4, gullLeft = 0, gullCallT: Float = 0, gullPh: Float = 0, gullPan: Float = 0, gullAmp: Float = 0, gullGap: Float = 0
    private var gullF = Reso()
    private var rumLP: Float = 0, rumLP2: Float = 0

    init(sampleRate: Float) { sr = sampleRate }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let tp = 2 * Float.pi, inv = 1 / sr
        let tM = master, tR = rush
        for i in 0..<frames {
            sM += (tM - sM) * 0.0002
            sRush += (tR - sRush) * 0.0006
            gustT -= inv
            if gustT <= 0 { gustT = rng.range(2, 7); gust = rng.range(0.2, 1) }
            gustPh += (gust - gustPh) * 0.00004
            windL = windL * 0.996 + n.next() * 0.02
            windR = windR * 0.996 + n2.next() * 0.02
            let x = n3.next()
            var l = windL * (0.1 + 0.14 * gustPh)
            var r = windR * (0.1 + 0.14 * gustPh)
            // whistling through the rocks on strong gusts
            let wh = whis1.run(x, f: 700 + 300 * gustPh, q: 25, sr: sr) * 0.02 * gustPh * gustPh
            l += wh; r += whis2.run(x, f: 1040 + 200 * gustPh, q: 25, sr: sr) * 0.012 * gustPh * gustPh

            // falling air rush: loud, band-limited noise that opens up with speed
            if sRush > 0.002 {
                let y = n.next()
                rushHP += (y - rushHP) * (0.02 + sRush * 0.05)
                let hp = y - rushHP
                rushLP += (hp - rushLP) * (0.15 + sRush * 0.5)
                let y2 = n2.next()
                rushLPR += (y2 - rushLPR) * (0.15 + sRush * 0.5)
                let flutter: Float = 1 + 0.25 * sinf(tp * gustPh * 7 + rushLP)
                l += rushLP * sRush * sRush * 0.5 * flutter
                r += rushLPR * sRush * sRush * 0.35 * flutter
            }

            if gulls {
                gullT -= inv
                if gullT <= 0 && gullLeft == 0 { gullLeft = 2 + rng.int(4); gullPan = rng.range(-0.8, 0.8); gullAmp = rng.range(0.01, 0.03); gullT = rng.range(4, 12); gullCallT = 0; gullGap = 0 }
                if gullLeft > 0 {
                    if gullGap > 0 { gullGap -= inv } else {
                        gullCallT += inv
                        let u = gullCallT / 0.28
                        let f = 1500 + 700 * sinf(.pi * min(1, u)) - 500 * u
                        gullPh += f * inv; if gullPh > 1 { gullPh -= 1 }
                        let saw = gullPh * 2 - 1
                        let s = gullF.run(saw, f: 2200, q: 2, sr: sr) * sinf(.pi * min(1, u)) * gullAmp
                        let (gl, gr) = equalPan(gullPan)
                        l += s * gl; r += s * gr
                        if u >= 1 { gullLeft -= 1; gullCallT = 0; gullGap = rng.range(0.06, 0.2) }
                    }
                }
            }
            if rumble {
                rumLP += (n3.next() - rumLP) * 0.004
                rumLP2 += (rumLP - rumLP2) * 0.004
                l += rumLP2 * 1.4; r += rumLP2 * 1.4
            }
            L[i] = l * sM; R[i] = r * sM
        }
    }
}

// MARK: - Score: 124 BPM, E minor. Chill hub, a heartbeat on the ledge, a punk thrash for the fall, a game-show jingle for the results.

enum MusicMood: Int32 { case menu = 0, ready = 1, fall = 2, results = 3, quiet = 4 }

final class MusicSynth {
    let sr: Float
    var on: Float = 1
    var mood: MusicMood = .menu

    private let sps: Int
    private var sc = 0, step = -1
    private var rng = RNG(0x5EED)
    private var n = Noise32(s: 0x9A11)
    private var lastMood: MusicMood = .menu

    // drums
    private var kickT: Float = 9, kickPh: Float = 0, kickA: Float = 1
    private var snT: Float = 9, snA: Float = 1, snPh: Float = 0
    private var hatT: Float = 9, hatA: Float = 0, hatHP: Float = 0, hatOpen = false
    private var crT: Float = 9, crHP: Float = 0
    // bass
    private var bassF: Float = 55, bassT: Float = 9, bassPh: Float = 0, bassPh2: Float = 0, bassLP: Float = 0, bassA: Float = 0, bassDecay: Float = 6, bassDrive: Float = 1
    // power-chord guitar
    private var gF: Float = 82, gT: Float = 9, gA: Float = 0, gMute = false, gPh: [Float] = [0, 0, 0, 0], gLP: Float = 0, gLP2: Float = 0
    // keys (FM e-piano) and mallets
    struct Note { var f: Float = 0; var t: Float = 99; var a: Float = 0; var pan: Float = 0; var kind = 0 }
    private var notes = [Note](repeating: Note(), count: 14)
    private var nNext = 0
    // pad
    private var padPh: [Float] = [0, 0, 0, 0, 0, 0], padLP: Float = 0, padA: Float = 0, padTA: Float = 0, padCut: Float = 0.01
    private var padF: [Float] = [82.4, 123.5, 164.8]
    // lead
    private var ldF: Float = 440, ldTF: Float = 440, ldA: Float = 0, ldTA: Float = 0, ldPh: Float = 0, ldVib: Float = 0, ldLP: Float = 0

    private var sOn: Float = 0

    // Em7 Cmaj7 Am7 B7
    private let menuRoots: [Float] = [40, 36, 45, 47]
    private let menuChords: [[Float]] = [[64, 67, 71, 74], [64, 67, 71, 72], [64, 67, 69, 72], [63, 66, 69, 71]]
    // fall: E E C D | E E G A (power chords)
    private let fallRoots: [Float] = [40, 40, 36, 38, 40, 40, 43, 45]
    private let fallLead: [Float] = [76, 0, 79, 76, 74, 0, 71, 0, 72, 0, 74, 76, 79, 0, 81, 79]
    // results: G C D G, bright
    private let resRoots: [Float] = [43, 48, 50, 43]
    private let resChords: [[Float]] = [[67, 71, 74], [67, 72, 76], [66, 69, 74], [67, 71, 74]]
    private let resTune: [Float] = [79, 83, 86, 83, 84, 0, 81, 0, 78, 81, 86, 84, 83, 0, 79, 0]

    init(sampleRate: Float) {
        sr = sampleRate
        sps = Int(sampleRate * 60 / 124 / 4)
    }

    private func note(_ midi: Float, _ vel: Float, pan: Float, kind: Int) {
        notes[nNext] = Note(f: midiHz(midi), t: 0, a: vel, pan: pan, kind: kind)
        nNext = (nNext + 1) % notes.count
    }
    private func kick(_ a: Float = 1) { kickT = 0; kickPh = 0; kickA = a }
    private func snare(_ a: Float) { snT = 0; snA = a }
    private func hat(_ a: Float, open: Bool = false) { hatT = 0; hatA = a; hatOpen = open }

    private func tick() {
        step += 1
        if mood != lastMood { lastMood = mood; step = 0; if mood == .fall || mood == .results { crT = 0 } }
        let s16 = step % 16, bar = step / 16
        padTA = 0; ldTA = mood == .fall || mood == .results ? ldTA : 0
        switch mood {
        case .menu:
            let b = bar % 4
            let root = menuRoots[b], ch = menuChords[b]
            if s16 == 0 || s16 == 10 { kick(0.8) }
            if s16 == 4 || s16 == 12 { snare(0.45) }
            if s16 % 2 == 0 { hat(s16 % 4 == 2 ? 0.55 : 0.3) }
            if s16 == 14 && rng.chance(0.5) { hat(0.4, open: true) }
            let bp: [Float] = [0, -99, -99, 0, -99, -99, 7, -99, 12, -99, -99, 10, -99, 7, -99, -99]
            if bp[s16] > -50 { bassF = midiHz(root - 12 + bp[s16] + 12); bassT = 0; bassA = 0.9; bassDecay = 5; bassDrive = 1 }
            if s16 == 4 || s16 == 11 {
                for (k, m) in ch.enumerated() { note(m - 12, 0.3, pan: Float(k) * 0.25 - 0.4, kind: 0) }
            }
            if s16 % 4 == 2 && rng.chance(0.45) { note(ch[rng.int(4)] + 12, 0.18, pan: rng.range(-0.6, 0.6), kind: 1) }
        case .ready:
            // heartbeat: lub-dub
            if s16 == 0 { kick(0.9) }
            if s16 == 2 { kick(0.6) }
            if s16 == 8 { kick(0.9) }
            if s16 == 10 { kick(0.6) }
            if s16 % 4 == 0 { hat(0.2) }
            padTA = 1
            padCut = min(0.12, 0.01 + Float(step) * 0.0007)
            if s16 == 0 && bar % 2 == 1 { note(88, 0.12, pan: 0.5, kind: 1) }
        case .fall:
            let b = bar % 8
            let root = fallRoots[b]
            if s16 == 0 || s16 == 8 || s16 == 10 { kick(1.1) }
            if s16 == 4 || s16 == 12 { snare(0.95) }
            if s16 == 15 && b % 2 == 1 { snare(0.6) }
            if s16 % 2 == 0 { hat(0.6) }
            if s16 == 0 && b % 4 == 0 { crT = 0 }
            // driving eighths
            if s16 % 2 == 0 {
                bassF = midiHz(root - 12); bassT = 0; bassA = 1; bassDecay = 9; bassDrive = 3
                gF = midiHz(root); gT = 0; gA = 1
                gMute = !(s16 == 0 || s16 == 6 || s16 == 12)
            }
            if b >= 4 {
                let m = fallLead[s16]
                if m > 0 { ldTF = midiHz(m + (b == 6 || b == 7 ? 3 : 0)); ldTA = 1 } else if s16 % 4 == 3 { ldTA = 0 }
            } else { ldTA = 0 }
        case .results:
            let b = bar % 4
            let root = resRoots[b], ch = resChords[b]
            if s16 == 0 || s16 == 8 { kick(0.9) }
            if s16 == 4 || s16 == 12 { snare(0.6) }
            if s16 % 2 == 0 { hat(0.4) }
            let bp: [Float] = [0, -99, -99, -99, 7, -99, -99, -99, 12, -99, -99, -99, 7, -99, 5, -99]
            if bp[s16] > -50 { bassF = midiHz(root - 12 + bp[s16]); bassT = 0; bassA = 1; bassDecay = 7; bassDrive = 1 }
            if s16 % 4 == 2 { for (k, m) in ch.enumerated() { note(m, 0.2, pan: Float(k) * 0.3 - 0.3, kind: 1) } }
            let m = resTune[s16]
            if bar % 8 >= 4 { if m > 0 { ldTF = midiHz(m); ldTA = 0.6 } else { ldTA = 0 } } else { ldTA = 0 }
        case .quiet:
            break
        }
    }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let tp = 2 * Float.pi, inv = 1 / sr
        let target = on * (mood == .quiet ? 0 : 1)
        for i in 0..<frames {
            if sc == 0 { tick() }
            sc += 1; if sc >= sps { sc = 0 }
            sOn += (target - sOn) * 0.00008
            var l: Float = 0, r: Float = 0

            if kickT < 0.45 {
                kickT += inv
                kickPh += (48 + 130 * expf(-kickT * 30)) * inv
                let k = sinf(tp * kickPh) * expf(-kickT * 9) * 0.4 * kickA
                l += k; r += k
            }
            if snT < 0.35 {
                snT += inv
                snPh += 190 * inv
                let s = (n.next() * 0.75 * expf(-snT * 18) + sinf(tp * snPh) * 0.45 * expf(-snT * 28)) * 0.14 * snA
                l += s * 0.95; r += s * 1.05
            }
            if hatT < 0.4 {
                hatT += inv
                let x = n.next()
                hatHP += (x - hatHP) * 0.6
                let s = (x - hatHP) * expf(-hatT * (hatOpen ? 12 : 80)) * 0.055 * hatA
                l += s * 0.8; r += s * 1.2
            }
            if crT < 2.5 {
                crT += inv
                let x = n.next()
                crHP += (x - crHP) * 0.5
                let s = (x - crHP) * expf(-crT * 2.2) * 0.06 * (mood == .fall ? 1 : 0.6)
                l += s * 1.1; r += s * 0.9
            }
            if bassT < 1.2 {
                bassT += inv
                bassPh += bassF * inv; if bassPh > 1 { bassPh -= 1 }
                bassPh2 += bassF * 1.005 * inv; if bassPh2 > 1 { bassPh2 -= 1 }
                let saw = (bassPh * 2 - 1) + (bassPh2 * 2 - 1) * 0.5
                bassLP += (saw - bassLP) * (0.03 + 0.1 * expf(-bassT * 20))
                let x = bassLP * bassDrive
                let b = (bassDrive > 1 ? softClip(x) : x * 0.8 + sinf(tp * bassPh) * 0.4) * expf(-bassT * bassDecay) * min(1, bassT * 500) * 0.16 * bassA
                l += b; r += b
            }
            if gT < 1 {
                gT += inv
                let ratios: [Float] = [1, 1.4983, 2, 1.003]
                var s: Float = 0
                for k in 0..<4 {
                    gPh[k] += gF * ratios[k] * inv; if gPh[k] > 1 { gPh[k] -= 1 }
                    s += gPh[k] * 2 - 1
                }
                let env = expf(-gT * (gMute ? 22 : 4)) * min(1, gT * 800) * gA
                let d = softClip(s * 2.2 * env)
                gLP += (d - gLP) * (gMute ? 0.12 : 0.28)
                gLP2 += (gLP - gLP2) * 0.5
                let out = gLP2 * 0.085
                l += out * 1.15; r += out * 0.85
            }
            for k in 0..<notes.count where notes[k].t < 1.6 {
                var v = notes[k]
                v.t += inv
                let t = v.t
                var s: Float
                if v.kind == 0 {   // e-piano: FM tine
                    let mod = sinf(tp * v.f * t) * 1.2 * expf(-t * 8)
                    s = sinf(tp * v.f * t + mod) * expf(-t * 2.6) * min(1, t * 400)
                } else {           // mallet
                    s = (sinf(tp * v.f * t) + 0.3 * sinf(tp * v.f * 3.99 * t) * expf(-t * 25)) * expf(-t * 7) * min(1, t * 900)
                }
                s *= v.a * 0.2
                let (gl, gr) = equalPan(v.pan)
                l += s * gl; r += s * gr
                notes[k] = v
            }
            padA += (padTA - padA) * 0.00003
            if padA > 0.001 {
                var s: Float = 0
                for k in 0..<6 {
                    let f = padF[k % 3] * (k < 3 ? 1 : 1.006)
                    padPh[k] += f * inv; if padPh[k] > 1 { padPh[k] -= 1 }
                    s += padPh[k] * 2 - 1
                }
                padLP += (s - padLP) * padCut
                let o = padLP * padA * 0.05
                l += o; r += o
            }
            ldF += (ldTF - ldF) * 0.006
            ldA += (ldTA - ldA) * (ldTA > ldA ? 0.01 : 0.002)
            if ldA > 0.001 {
                ldVib += 5.5 * inv; if ldVib > 1 { ldVib -= 1 }
                ldPh += ldF * (1 + 0.008 * sinf(tp * ldVib)) * inv; if ldPh > 1 { ldPh -= 1 }
                let sq: Float = ldPh < 0.5 ? 1 : -1
                ldLP += (sq - ldLP) * 0.12
                let s = ldLP * ldA * 0.05
                l += s * 0.9; r += s * 1.1
            }
            L[i] = softClip(l * sOn * 1.2) * 0.8
            R[i] = softClip(r * sOn * 1.2) * 0.8
        }
    }
}
