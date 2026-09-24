import Foundation

// Synths run on the audio thread. The game thread writes their public Float parameters
// (benign single-word races); render() smooths them.

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

/// Two-pole resonator (band-pass-ish).
struct Reso {
    var y1: Float = 0, y2: Float = 0
    @inline(__always) mutating func run(_ x: Float, f: Float, q: Float, sr: Float) -> Float {
        let w = 2 * Float.pi * f / sr
        let r = 1 - w / (2 * q)
        let y = x * (1 - r) * 2 + 2 * r * cosf(w) * y1 - r * r * y2
        y2 = y1; y1 = y
        return y
    }
}

@inline(__always) func equalPan(_ p: Float) -> (Float, Float) {
    let a = (max(-1, min(1, p)) + 1) * .pi / 4
    return (cosf(a) * 1.414, sinf(a) * 1.414)
}

// MARK: - Hall ambience: room tone, air handling, lamp buzz, rolling balls, gantry motor

final class AmbientSynth {
    let sr: Float
    var roll: Float = 0          // 0…1, how much resin is rolling on the maple
    var rollPitch: Float = 0     // 0…1, bigger balls rumble lower
    var motor: Float = 0         // 0…1 gantry speed
    var master: Float = 1

    private var sR: Float = 0, sRP: Float = 0, sMo: Float = 0, sM: Float = 0
    private var n = Noise32(s: 0xA11CE), n2 = Noise32(s: 0xB0B), n3 = Noise32(s: 0xC0FFEE)
    private var brownL: Float = 0, brownR: Float = 0
    private var hv = Reso(), hv2 = Reso()
    private var rl1: Float = 0, rl2: Float = 0, rollGrain: Float = 0
    private var mPh: Float = 0, mPh2: Float = 0, mLP: Float = 0
    private var bPh: Float = 0, hvacLFO: Float = 0

    init(sampleRate: Float) { sr = sampleRate }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let tp = 2 * Float.pi, inv = 1 / sr
        let tR = roll, tRP = rollPitch, tMo = motor, tM = master
        for i in 0..<frames {
            sR += (tR - sR) * 0.0008; sRP += (tRP - sRP) * 0.0005
            sMo += (tMo - sMo) * 0.0015; sM += (tM - sM) * 0.0002

            // room tone: big empty hall, mostly sub-200 Hz air
            brownL = brownL * 0.996 + n.next() * 0.02
            brownR = brownR * 0.996 + n2.next() * 0.02
            hvacLFO += inv * 0.05
            let hvac = hv.run(n3.next(), f: 380, q: 1.2, sr: sr) * (0.012 + 0.004 * sinf(tp * hvacLFO))
                + hv2.run(n3.next(), f: 1400, q: 2, sr: sr) * 0.0025
            // metal-halide lamps: faint 120 Hz buzz with harmonics
            bPh += 120 * inv; if bPh > 1 { bPh -= 1 }
            let buzz = (sinf(tp * bPh) * 0.5 + sinf(tp * bPh * 3) * 0.3 + sinf(tp * bPh * 5) * 0.15) * 0.0022

            // rolling: low rumble of resin on hollow maple, with grainy board-joint ticks
            let cut = 0.012 + 0.03 * (1 - sRP)
            rl1 += (n.next() - rl1) * cut
            rl2 += (rl1 - rl2) * cut
            rollGrain *= 0.995
            if n2.next() > 1 - 0.0009 * (0.3 + sR * 3) { rollGrain = 0.6 + 0.4 * n3.next() }
            let roll = (rl2 * 3.2 + rollGrain * rl1 * 1.5) * sR * sR * 0.45

            // gantry: servo whine and gear hum
            let mf = 90 + 260 * sMo
            mPh += mf * inv; if mPh > 1 { mPh -= 1 }
            mPh2 += mf * 7.03 * inv; if mPh2 > 1 { mPh2 -= 1 }
            let saw = mPh * 2 - 1
            mLP += (saw - mLP) * 0.12
            let motor = (mLP * 0.6 + sinf(tp * mPh2) * 0.12 + n.next() * 0.05) * sMo * 0.09

            let l = (brownL * 0.14 + hvac + buzz + roll + motor) * sM
            let r = (brownR * 0.14 + hvac * 0.9 + buzz + roll * 0.95 + motor * 0.9) * sM
            L[i] = l; R[i] = r
        }
    }
}

// MARK: - Score: a slow electric-piano piece in D whose melody is the hailstone sequence itself

final class MusicSynth {
    let sr: Float
    var on: Float = 1
    var level: Float = 1

    // Melody queue: the game pushes pitch indices, the audio thread pops them.
    private let q = UnsafeMutablePointer<Int32>.allocate(capacity: 32)
    private var qw = 0
    private var qr = 0
    func push(_ idx: Int) { q[qw & 31] = Int32(idx); qw &+= 1 }

    private let spe: Int
    private var sc = 0, eighth = -1
    private var rng = RNG(0x5EED)
    private let chords: [[Float]] = [[50, 57, 61, 64, 66], [47, 54, 57, 61, 62], [43, 50, 54, 57, 59], [45, 52, 54, 59, 62]]
    private let roots: [Float] = [38, 35, 31, 33]
    private let pent: [Float] = [0, 2, 4, 7, 9]

    private var padF = [Float](repeating: 110, count: 5), padT = [Float](repeating: 110, count: 5)
    private var padPh = [Float](repeating: 0, count: 10)
    private var padLPL: Float = 0, padLPR: Float = 0, lfo: Float = 0, padGain: Float = 0
    private var bassF: Float = 73, bassPh: Float = 0, bassT: Float = 9, bassA: Float = 0
    private var kickT: Float = 9, kickPh: Float = 0
    private var shT: Float = 9, shA: Float = 0, shHP: Float = 0
    private var rimT: Float = 9, rimPh: Float = 0
    private var n = Noise32(s: 0x9A11)
    private var sOn: Float = 0

    struct EP { var f: Float = 0; var phC: Float = 0; var phM: Float = 0; var phT: Float = 0; var t: Float = 99; var amp: Float = 0; var pan: Float = 0 }
    private var ep = [EP](repeating: EP(), count: 14)
    private var epNext = 0

    init(sampleRate: Float) {
        sr = sampleRate
        spe = Int(sampleRate * 60 / 72 / 2)
        for k in 0..<5 { padF[k] = midiHz(chords[0][k]); padT[k] = padF[k] }
    }

    private func note(_ midi: Float, vel: Float) {
        var v = EP()
        v.f = midiHz(midi)
        v.t = 0
        v.amp = vel
        v.pan = rng.range(-0.45, 0.45)
        ep[epNext] = v
        epNext = (epNext + 1) % ep.count
    }

    private func tick() {
        eighth += 1
        let bar = eighth / 8, e = eighth % 8
        let section = bar % 24                 // 4 intro, 12 groove, 4 break, 4 groove
        let drums = (section >= 4 && section < 16) || section >= 20
        let ci = (bar / 2) % 4
        if e == 0 && bar % 2 == 0 { for k in 0..<5 { padT[k] = midiHz(chords[ci][k]) } }
        if drums {
            if e == 0 || (e == 5 && rng.chance(0.4)) {
                bassF = midiHz(roots[ci] + (e == 5 ? 7 : 0)); bassT = 0; bassA = e == 0 ? 1 : 0.6
            }
            if e == 0 || e == 4 || (e == 7 && rng.chance(0.25)) { kickT = 0; kickPh = 0 }
            if e == 2 || e == 6 { rimT = 0; rimPh = 0 }
            shT = 0; shA = e % 2 == 1 ? 1 : 0.55
        }
        // melody: the newest hailstone value, else an occasional chord tone
        let backlog = qw - qr
        if backlog > 0 {
            if backlog > 3 { qr = qw - 1 }
            let idx = Int(q[qr & 31]); qr += 1
            let i = max(0, min(13, idx))
            note(62 + 12 * Float(i / 5) + pent[i % 5], vel: rng.range(0.5, 0.7))
        } else if e % 2 == 0 && rng.chance(0.14) {
            let c = chords[ci]
            note(c[rng.int(c.count)] + 12, vel: rng.range(0.28, 0.4))
        }
    }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let tp = 2 * Float.pi, inv = 1 / sr
        let target = on * level
        for i in 0..<frames {
            if sc == 0 { tick() }
            sc += 1; if sc >= spe { sc = 0 }
            sOn += (target - sOn) * 0.00004
            padGain += (1 - padGain) * 0.00001

            // pad: five voices gliding between chord tones, detuned pair per voice
            lfo += inv * 0.06; if lfo > 1 { lfo -= 1 }
            var pl: Float = 0, pr: Float = 0
            for k in 0..<5 {
                padF[k] += (padT[k] - padF[k]) * 0.00006
                let f = padF[k]
                padPh[2 * k] += f * 1.0016 * inv; if padPh[2 * k] > 1 { padPh[2 * k] -= 1 }
                padPh[2 * k + 1] += f * 0.9984 * inv; if padPh[2 * k + 1] > 1 { padPh[2 * k + 1] -= 1 }
                let a = padPh[2 * k], b = padPh[2 * k + 1]
                pl += sinf(tp * a) + 0.25 * sinf(2 * tp * a)
                pr += sinf(tp * b) + 0.25 * sinf(2 * tp * b)
            }
            let c = 0.07 + 0.04 * sinf(tp * lfo)
            padLPL += (pl - padLPL) * c; padLPR += (pr - padLPR) * c
            var l = padLPL * 0.028 * padGain, r = padLPR * 0.028 * padGain

            // electric piano (2-op FM with a tine click)
            for k in 0..<ep.count where ep[k].t < 5 {
                var v = ep[k]
                v.t += inv
                v.phC += v.f * inv; if v.phC > 1 { v.phC -= 1 }
                v.phM += v.f * inv; if v.phM > 1 { v.phM -= 1 }
                v.phT += v.f * 13.9 * inv; if v.phT > 1 { v.phT -= 1 }
                let env = expf(-v.t * 1.3) * min(1, v.t * 500)
                let idx = 1.6 * expf(-v.t * 5) + 0.25
                let s = sinf(tp * v.phC + idx * sinf(tp * v.phM)) + sinf(tp * v.phT) * 0.1 * expf(-v.t * 40)
                let out = s * env * v.amp * 0.16
                let (gl, gr) = equalPan(v.pan)
                l += out * gl; r += out * gr
                ep[k] = v
            }

            // bass: round sine with a little 2nd/3rd for small speakers
            if bassT < 4 {
                bassT += inv
                bassPh += bassF * inv; if bassPh > 1 { bassPh -= 1 }
                let env = expf(-bassT * 0.9) * min(1, bassT * 200) * bassA
                let b = (sinf(tp * bassPh) + 0.35 * sinf(2 * tp * bassPh) + 0.12 * sinf(3 * tp * bassPh)) * env * 0.16
                l += b; r += b
            }
            // felt kick
            if kickT < 0.5 {
                kickT += inv
                kickPh += (48 + 70 * expf(-kickT * 30)) * inv
                let k = sinf(tp * kickPh) * expf(-kickT * 9) * 0.26
                l += k; r += k
            }
            // rim / woodblock
            if rimT < 0.2 {
                rimT += inv
                rimPh += 1750 * inv
                let s = (sinf(tp * rimPh) * 0.6 + n.next() * 0.4) * expf(-rimT * 55) * 0.045
                l += s * 0.8; r += s * 1.1
            }
            // brushed shaker
            if shT < 0.2 {
                shT += inv
                let x = n.next()
                shHP += (x - shHP) * 0.4
                let s = (x - shHP) * expf(-shT * 45) * min(1, shT * 300) * shA * 0.035
                l += s * 1.1; r += s * 0.8
            }
            L[i] = softClip(l * sOn * 1.2) * 0.8
            R[i] = softClip(r * sOn * 1.2) * 0.8
        }
    }
}
