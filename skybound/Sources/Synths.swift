import Foundation

// All synths are plain classes whose render() runs on the audio thread.
// Parameters are written by the game thread as single Floats (benign races).

@inline(__always) func softClip(_ x: Float) -> Float {
    let c = max(-3, min(3, x))
    return c * (27 + c * c) / (27 + 9 * c * c)
}

struct Noise32 {
    var s: UInt32
    @inline(__always) mutating func next() -> Float {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5
        return Float(s) / 2_147_483_648.0 - 1
    }
}

@inline(__always) func midiHz(_ m: Float) -> Float { 440 * powf(2, (m - 69) / 12) }

// MARK: - Engine, wind, rumble, stall horn

final class EngineSynth {
    let sr: Float
    var rpm: Float = 0, airspeed: Float = 0, groundRoll: Float = 0, stall: Float = 0
    var alive: Float = 1, cockpit: Float = 0, volume: Float = 1

    private var sRpm: Float = 0, sAir: Float = 0, sRoll: Float = 0, sStall: Float = 0, sAlive: Float = 1, sVol: Float = 0, sCock: Float = 0
    private var phase: Float = 0, cam: Float = 0, hornPh: Float = 0, gustPh: Float = 0
    private var n = Noise32(s: 0x1234_5678), n2 = Noise32(s: 0x0BAD_F00D)
    private var nlp: Float = 0, wl1: Float = 0, wl2: Float = 0, wr1: Float = 0, wr2: Float = 0, brown: Float = 0
    private var outLP: Float = 0, outLPR: Float = 0, hp: Float = 0

    init(sampleRate: Float) { sr = sampleRate }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let tRpm = rpm, tAir = airspeed, tRoll = groundRoll, tStall = stall, tAlive = alive, tVol = volume, tCock = cockpit
        let twoPi: Float = 2 * .pi
        for i in 0..<frames {
            sRpm += (tRpm - sRpm) * 0.0006
            sAir += (tAir - sAir) * 0.0004
            sRoll += (tRoll - sRoll) * 0.002
            sStall += (tStall - sStall) * 0.003
            sAlive += (tAlive - sAlive) * 0.004
            sVol += (tVol - sVol) * 0.0015
            sCock += (tCock - sCock) * 0.002

            // Engine: firing-frequency harmonic stack with combustion pulses
            let running = sRpm > 0.01 ? Float(1) : 0
            let f0 = 15 + 66 * sRpm
            phase += f0 / sr
            if phase >= 1 { phase -= 1 }
            cam += f0 * 0.25 / sr
            if cam >= 1 { cam -= 1 }
            let p = phase * twoPi
            var eng = sinf(p) * 0.55 + sinf(2 * p + 0.4) * 0.42 + sinf(3 * p + 1.1) * 0.3
                + sinf(4 * p) * 0.2 + sinf(5 * p + 0.7) * 0.12 + sinf(7 * p + 2) * 0.07
            let pp = max(0, sinf(p))
            let pulse = pp * pp * pp * pp
            let wn = n.next()
            nlp += (wn - nlp) * (0.06 + 0.3 * sRpm)
            eng += pulse * nlp * 2.6
            // slight roughness per engine cycle
            eng *= 0.85 + 0.15 * sinf(cam * twoPi)
            let engGain = (0.07 + 0.26 * sRpm) * running * sAlive
            eng *= engGain

            // Wind / airflow noise rises with airspeed
            let V = sAir
            let k = min(0.015 + V * 0.0011, 0.35)
            let a = n.next(), b = n2.next()
            wl1 += (a - wl1) * k; wl2 += (wl1 - wl2) * k
            wr1 += (b - wr1) * k; wr2 += (wr1 - wr2) * k
            gustPh += 0.23 / sr
            if gustPh > 1 { gustPh -= 1 }
            let gust = 0.78 + 0.22 * sinf(gustPh * twoPi) * sinf(gustPh * twoPi * 3.3 + 1)
            let wg = min(1, (V / 70) * (V / 70)) * 1.6 * gust * (1 - 0.4 * sCock)

            // Tyre rumble
            brown = brown * 0.996 + n2.next() * 0.03
            let rumble = brown * sRoll * 1.4

            // Stall horn (reed ~1.6 kHz)
            hornPh += 1650 / sr
            if hornPh >= 1 { hornPh -= 1 }
            let horn = (sinf(hornPh * twoPi) + 0.35 * sinf(hornPh * twoPi * 2)) * 0.16 * sStall

            // Cockpit: muffled engine
            outLP += (eng - outLP) * 0.25
            let engOut = eng * (1 - sCock) + outLP * sCock * 1.3

            let l = engOut + wl2 * wg + rumble + horn
            let r = engOut * 0.96 + wr2 * wg + rumble + horn
            L[i] = softClip(l * 1.1) * sVol * 0.72
            R[i] = softClip(r * 1.1) * sVol * 0.72
        }
    }
}

// MARK: - Generative score

/// A calm, warm "flying over islands" loop: pads, FM-bell arpeggio, bass, soft drums and a bell lead.
/// 32-bar arrangement, 84 BPM, D major.
final class MusicSynth {
    let sr: Float
    var enabled = true
    var volume: Float = 0.75
    private var gain: Float = 0
    private let bpm: Float = 84
    private let stepLen: Int
    private var sampleInStep = 0
    private var step = -1
    private var rng = Noise32(s: 0xC0FF_EE11)

    // chords: 4 pad notes + bass root
    private let progA: [[Int]] = [[57, 61, 64, 66, 38], [54, 57, 62, 64, 47], [54, 57, 59, 62, 43], [55, 57, 62, 64, 45]]
    private let progB: [[Int]] = [[55, 59, 62, 66, 40], [54, 59, 62, 67, 43], [57, 61, 64, 66, 42], [57, 61, 64, 69, 45]]
    private let penta: [Int] = [74, 76, 78, 81, 83, 86, 88, 90]

    // voices (struct-of-arrays for the audio thread)
    private var padF = [Float](repeating: 220, count: 8), padP1 = [Float](repeating: 0, count: 8)
    private var padP2 = [Float](repeating: 0.3, count: 8), padP3 = [Float](repeating: 0.6, count: 8)
    private var padA = [Float](repeating: 0, count: 8), padT = [Float](repeating: 0, count: 8)
    private var padSet = 0
    private var lpL: Float = 0, bpL: Float = 0, lpR: Float = 0, bpR: Float = 0, lfo: Float = 0

    private var plF = [Float](repeating: 440, count: 8), plP = [Float](repeating: 0, count: 8), plM = [Float](repeating: 0, count: 8)
    private var plE = [Float](repeating: 0, count: 8), plV = [Float](repeating: 0, count: 8), plPan = [Float](repeating: 0.5, count: 8)
    private var plNext = 0

    private var bassF: Float = 73, bassP: Float = 0, bassEnv: Float = 0, bassAmp: Float = 0
    private var kickP: Float = 0, kickEnv: Float = 0, kickPEnv: Float = 0
    private var hatEnv: Float = 0, hatVel: Float = 0, hatLP: Float = 0
    private var snEnv: Float = 0, snLP: Float = 0, snP: Float = 0
    private var leadF: Float = 587, leadCur: Float = 587, leadP: Float = 0, leadEnv: Float = 0, leadAmp: Float = 0, vib: Float = 0
    private var leadIdx = 3
    private var arpPattern = 0
    private let arpPatterns: [[Int]] = [[0, 1, 2, 3, 4, 3, 2, 1], [0, 2, 1, 3, 2, 4, 3, 1], [4, 3, 2, 1, 0, 1, 2, 3]]

    private let padSlew: Float, pluckDecay: Float, bassDecay: Float, kickDecay: Float, kickPDecay: Float
    private let hatDecay: Float, snDecay: Float, leadDecay: Float

    init(sampleRate: Float) {
        sr = sampleRate
        stepLen = Int(sampleRate * 60 / 84 / 4)
        padSlew = 1 / (sampleRate * 0.9)
        pluckDecay = expf(-1 / (sampleRate * 0.42))
        bassDecay = expf(-1 / (sampleRate * 0.55))
        kickDecay = expf(-1 / (sampleRate * 0.26))
        kickPDecay = expf(-1 / (sampleRate * 0.035))
        hatDecay = expf(-1 / (sampleRate * 0.032))
        snDecay = expf(-1 / (sampleRate * 0.12))
        leadDecay = expf(-1 / (sampleRate * 1.0))
    }

    private func rand() -> Float { rng.next() * 0.5 + 0.5 }

    private func onStep(_ s: Int) {
        let bar = s / 16, st = s % 16, cb = bar % 32
        let chord = cb < 16 ? progA[(cb / 2) % 4] : progB[(cb / 2) % 4]
        let arp = cb >= 4
        let drums = (cb >= 8 && cb < 24) || cb >= 28
        let bass = cb >= 6
        let lead = cb >= 16 && cb < 28
        let snare = cb >= 16 && cb < 24

        if st == 0 && bar % 2 == 0 {
            let old = padSet * 4
            for v in 0..<4 { padT[old + v] = 0 }
            padSet ^= 1
            let nw = padSet * 4
            for v in 0..<4 {
                padF[nw + v] = midiHz(Float(chord[v]))
                padT[nw + v] = 0.028
            }
            arpPattern = Int(rand() * 3)
        }
        if arp && st % 2 == 0 && rand() > 0.1 {
            let idx = arpPatterns[arpPattern][(st / 2) % 8]
            var note = idx < 4 ? chord[idx] + 12 : chord[0] + 24
            if rand() > 0.9 { note += 12 }
            let v = plNext; plNext = (plNext + 1) % 8
            plF[v] = midiHz(Float(note)); plP[v] = 0; plM[v] = 0
            plE[v] = 1; plV[v] = 0.55 + 0.45 * rand()
            plPan[v] = 0.5 + 0.35 * sinf(Float(s) * 0.7)
        }
        if bass && (st == 0 || st == 7 || st == 10 || (st == 14 && rand() > 0.6)) {
            bassF = midiHz(Float(chord[4])) * (st == 14 ? 1.5 : 1)
            bassEnv = st == 0 ? 1 : 0.7
        }
        if drums {
            if st == 0 || st == 8 || (st == 11 && rand() > 0.55) { kickP = 0; kickEnv = 1; kickPEnv = 1 }
            if st % 4 == 2 { hatEnv = 1; hatVel = 0.9 }
            else if st % 2 == 1 && rand() > 0.35 { hatEnv = 1; hatVel = 0.35 }
        }
        if snare && (st == 4 || st == 12) { snEnv = 1; snP = 0 }
        if lead && st % 4 == 0 && rand() > 0.42 {
            leadIdx = max(0, min(penta.count - 1, leadIdx + Int((rand() * 4).rounded()) - 2))
            leadF = midiHz(Float(penta[leadIdx]))
            leadEnv = 1
        }
    }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let target: Float = enabled ? volume : 0
        let twoPi: Float = 2 * .pi
        let inv = 1 / sr
        for i in 0..<frames {
            gain += (target - gain) * 0.00008
            if sampleInStep == 0 {
                step += 1
                onStep(step)
            }
            sampleInStep += 1
            if sampleInStep >= stepLen { sampleInStep = 0 }

            // pads
            var pl: Float = 0, pr: Float = 0
            for v in 0..<8 {
                padA[v] += (padT[v] - padA[v]) * padSlew * 3
                if padA[v] < 1e-5 && padT[v] == 0 { continue }
                let f = padF[v]
                padP1[v] += f * inv; if padP1[v] >= 1 { padP1[v] -= 1 }
                padP2[v] += f * 1.0041 * inv; if padP2[v] >= 1 { padP2[v] -= 1 }
                padP3[v] += f * 0.9962 * inv; if padP3[v] >= 1 { padP3[v] -= 1 }
                let s = (padP1[v] * 2 - 1) + (padP2[v] * 2 - 1) + (padP3[v] * 2 - 1)
                let pan: Float = (v % 4) < 2 ? 0.3 : 0.7
                pl += s * padA[v] * (1 - pan) * 1.4
                pr += s * padA[v] * pan * 1.4
            }
            lfo += 0.06 * inv
            if lfo >= 1 { lfo -= 1 }
            let fc = 700 + 450 * sinf(lfo * twoPi)
            let ff = 2 * sinf(.pi * fc * inv)
            lpL += ff * bpL; let hpL = pl - lpL - 0.9 * bpL; bpL += ff * hpL
            lpR += ff * bpR; let hpR = pr - lpR - 0.9 * bpR; bpR += ff * hpR
            var outL = lpL, outR = lpR

            // FM bell plucks
            for v in 0..<8 where plE[v] > 0.0005 {
                plP[v] += plF[v] * inv; if plP[v] >= 1 { plP[v] -= 1 }
                plM[v] += plF[v] * 3.5 * inv; if plM[v] >= 1 { plM[v] -= 1 }
                let mod = sinf(plM[v] * twoPi) * plE[v] * 1.3
                let s = sinf(plP[v] * twoPi + mod) * plE[v] * plV[v] * 0.085
                plE[v] *= pluckDecay
                outL += s * (1 - plPan[v]) * 2
                outR += s * plPan[v] * 2
            }

            // bass
            bassEnv *= bassDecay
            bassAmp += (bassEnv - bassAmp) * 0.004
            bassP += bassF * inv; if bassP >= 1 { bassP -= 1 }
            let bs = (sinf(bassP * twoPi) + 0.22 * sinf(bassP * twoPi * 2)) * bassAmp * 0.3
            outL += bs; outR += bs

            // kick
            if kickEnv > 0.0005 {
                kickPEnv *= kickPDecay
                kickEnv *= kickDecay
                kickP += (42 + 110 * kickPEnv) * inv; if kickP >= 1 { kickP -= 1 }
                let k = sinf(kickP * twoPi) * kickEnv * 0.42
                outL += k; outR += k
            }
            // hats
            let nz = rng.next()
            if hatEnv > 0.001 {
                hatEnv *= hatDecay
                hatLP += (nz - hatLP) * 0.4
                let h = (nz - hatLP) * hatEnv * hatVel * 0.05
                outL += h * 0.8; outR += h * 1.2
            }
            // rim / soft snare
            if snEnv > 0.001 {
                snEnv *= snDecay
                snLP += (nz - snLP) * 0.25
                snP += 190 * inv; if snP >= 1 { snP -= 1 }
                let sn = ((nz - snLP) * 0.8 + sinf(snP * twoPi) * 0.5) * snEnv * 0.07
                outL += sn; outR += sn
            }
            // bell lead with glide and vibrato
            leadEnv *= leadDecay
            leadAmp += (leadEnv - leadAmp) * 0.003
            if leadAmp > 0.0005 {
                leadCur += (leadF - leadCur) * 0.0015
                vib += 5.2 * inv; if vib >= 1 { vib -= 1 }
                leadP += leadCur * (1 + 0.004 * sinf(vib * twoPi)) * inv; if leadP >= 1 { leadP -= 1 }
                let ph = leadP * twoPi
                let s = (sinf(ph) + 0.18 * sinf(2 * ph) + 0.06 * sinf(3 * ph)) * leadAmp * 0.075
                outL += s * 0.8; outR += s * 1.1
            }
            L[i] = softClip(outL * 1.2) * gain
            R[i] = softClip(outR * 1.2) * gain
        }
    }
}
