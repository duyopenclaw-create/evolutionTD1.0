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

// MARK: - House ambience: fridge, clock, wind, purr, heartbeat, light buzz

final class AmbientSynth {
    let sr: Float
    // written by the game
    var fridgeGain: Float = 0, fridgePan: Float = 0
    var clockGain: Float = 0, clockPan: Float = 0
    var windGain: Float = 0, windPan: Float = 0
    var purrGain: Float = 0, purrPan: Float = 0
    var heart: Float = 0, heartRate: Float = 80
    var buzz: Float = 0
    var master: Float = 1
    var underStove: Float = 0          // muffles everything when hiding

    private var sF: Float = 0, sFP: Float = 0, sC: Float = 0, sCP: Float = 0, sW: Float = 0, sWP: Float = 0
    private var sP: Float = 0, sPP: Float = 0, sH: Float = 0, sB: Float = 0, sM: Float = 0, sU: Float = 0
    private var n = Noise32(s: 0xA11CE), n2 = Noise32(s: 0xB0B)
    private var ph60: Float = 0, whine: Float = 0, fLP: Float = 0
    private var compOn = true, compT: Float = 0, compLevel: Float = 1, clunk: Float = 0
    private var clockT: Float = 0, tick: Float = 0, tickF: Float = 2600, tickPh: Float = 0, tickCount = 0
    private var w1: Float = 0, w2: Float = 0, gust: Float = 0
    private var purrPh: Float = 0, breathPh: Float = 0, pLP: Float = 0, pLP2: Float = 0
    private var hbT: Float = 0, hbEnv: Float = 0, hbPh: Float = 0, hbF: Float = 55
    private var bPh: Float = 0
    private var brown: Float = 0
    private var muffL: Float = 0, muffR: Float = 0

    init(sampleRate: Float) { sr = sampleRate }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let tp = 2 * Float.pi, inv = 1 / sr
        let tF = fridgeGain, tFP = fridgePan, tC = clockGain, tCP = clockPan, tW = windGain, tWP = windPan
        let tP = purrGain, tPP = purrPan, tH = heart, tB = buzz, tM = master, tU = underStove
        let hr = max(40, heartRate)
        for i in 0..<frames {
            let a: Float = 0.0004
            sF += (tF - sF) * a; sFP += (tFP - sFP) * a; sC += (tC - sC) * a; sCP += (tCP - sCP) * a
            sW += (tW - sW) * a; sWP += (tWP - sWP) * a; sP += (tP - sP) * a; sPP += (tPP - sPP) * a
            sH += (tH - sH) * 0.0003; sB += (tB - sB) * 0.002; sM += (tM - sM) * 0.0002; sU += (tU - sU) * 0.0005

            // fridge compressor: runs ~45 s, rests ~25 s, clunks on start and stop
            compT += inv
            if compOn && compT > 45 { compOn = false; compT = 0; clunk = 1 }
            if !compOn && compT > 25 { compOn = true; compT = 0; clunk = 1 }
            compLevel += ((compOn ? 1 : 0.12) - compLevel) * 0.00003
            ph60 += 60 * inv; if ph60 >= 1 { ph60 -= 1 }
            whine += 1290 * inv; if whine >= 1 { whine -= 1 }
            fLP += (n.next() - fLP) * 0.02
            let hum = (sinf(ph60 * tp) * 0.5 + sinf(ph60 * tp * 2) * 0.35 + sinf(ph60 * tp * 3 + 0.5) * 0.15) * 0.12 * compLevel
                + fLP * 0.25 * compLevel + sinf(whine * tp) * 0.004 * compLevel
            clunk *= 0.9993
            let cl = clunk * (sinf(Float(i) * 0.05) * 0.4 + n.next() * 0.2) * clunk
            let fridge = (hum + cl) * sF
            let (fl, fr) = equalPan(sFP)

            // wall clock: tick… tock
            clockT += inv
            if clockT >= 1 { clockT -= 1; tick = 1; tickCount += 1; tickF = tickCount % 2 == 0 ? 2900 : 2300; tickPh = 0 }
            tick *= 0.9965
            tickPh += tickF * inv
            let clock = (sinf(tickPh * tp) * 0.5 + n.next() * 0.3) * tick * tick * 0.25 * sC
            let (cl2, cr2) = equalPan(sCP)

            // wind outside the window: slow gusts
            gust += inv * 0.07; if gust > 1 { gust -= 1 }
            let g = 0.55 + 0.45 * sinf(gust * tp) * sinf(gust * tp * 2.7 + 1)
            let k = 0.01 + 0.02 * g
            w1 += (n2.next() - w1) * k; w2 += (w1 - w2) * k
            let wind = w2 * 2.2 * g * sW
            let (wl, wr) = equalPan(sWP)

            // purr: ~26 Hz pulsed rumble, louder on the out-breath
            breathPh += inv / 2.3; if breathPh > 1 { breathPh -= 1 }
            let outBreath = breathPh < 0.55
            purrPh += (outBreath ? 26 : 22) * inv; if purrPh >= 1 { purrPh -= 1 }
            let pulse = powf(max(0, sinf(purrPh * tp)), 6)
            pLP += (n.next() - pLP) * 0.06; pLP2 += (pLP - pLP2) * 0.06
            let breathEnv = outBreath ? sinf(breathPh / 0.55 * .pi) : sinf((breathPh - 0.55) / 0.45 * .pi) * 0.45
            let purr = (pLP2 * 6 + sinf(purrPh * tp) * 0.2) * pulse * breathEnv * sP * 0.6
            let (pl, pr) = equalPan(sPP)

            // heartbeat: lub-dub
            hbT += inv * hr / 60
            if hbT >= 1 { hbT -= 1 }
            let lub = hbT < 0.08 ? sinf(hbT / 0.08 * .pi) : 0
            let dub = hbT > 0.2 && hbT < 0.27 ? sinf((hbT - 0.2) / 0.07 * .pi) * 0.7 : 0
            hbPh += (hbT < 0.1 ? 58 : 48) * inv; if hbPh >= 1 { hbPh -= 1 }
            let heartS = sinf(hbPh * tp) * (lub + dub) * 0.5 * sH

            // light buzz (120 Hz with odd harmonics)
            bPh += 120 * inv; if bPh >= 1 { bPh -= 1 }
            let bz = (sinf(bPh * tp) + 0.3 * sinf(bPh * tp * 3) + 0.15 * sinf(bPh * tp * 5)) * 0.012 * sB

            // room tone
            brown = brown * 0.998 + n2.next() * 0.02
            var l = fridge * fl + clock * cl2 + wind * wl + purr * pl + heartS + bz + brown * 0.08
            var r = fridge * fr + clock * cr2 + wind * wr + purr * pr + heartS + bz + brown * 0.08
            // under the stove: muffled
            muffL += (l - muffL) * 0.08; muffR += (r - muffR) * 0.08
            l = mixf(l, muffL * 1.4, sU); r = mixf(r, muffR * 1.4, sU)
            L[i] = softClip(l) * sM
            R[i] = softClip(r) * sM
        }
    }
}

// MARK: - Adaptive score

/// "Scurry": a sneaky nocturne in D minor at 76 BPM. Layers fade with the game state:
/// drone + felt piano always; pizzicato walking bass and shaker while exploring;
/// tremolo strings, low drums and a faster ostinato when hunted; a music box at the nest.
final class MusicSynth {
    let sr: Float
    var enabled = true
    var volume: Float = 0.8
    var explore: Float = 0          // rat is moving about
    var tension: Float = 0          // cat hunting / human in the room
    var home: Float = 0             // in the nest
    private var gain: Float = 0, sExp: Float = 0, sTen: Float = 0, sHome: Float = 0
    private let stepLen: Int
    private var sampleInStep = 0
    private var step = -1
    private var rng = Noise32(s: 0x5CA77)

    // chords: [bass, notes…]
    private let prog: [[Int]] = [
        [38, 50, 53, 57, 62], [34, 50, 53, 58, 62], [41, 53, 57, 60, 65], [36, 52, 55, 60, 64],
        [38, 50, 53, 57, 62], [43, 50, 55, 58, 62], [34, 50, 53, 58, 65], [33, 49, 52, 57, 61],
    ]
    // sneaky motif in scale steps from the chord root (in semitones), -1 = rest
    private let motif: [Int] = [0, -1, 2, 3, -1, 7, 6, 7, -1, -1, 10, -1, 7, -1, 3, 2]

    // felt piano voices
    private var pnF = [Float](repeating: 0, count: 10), pnP = [Float](repeating: 0, count: 10)
    private var pnE = [Float](repeating: 0, count: 10), pnV = [Float](repeating: 0, count: 10), pnPan = [Float](repeating: 0, count: 10)
    private var pnHam = [Float](repeating: 0, count: 10)
    private var pnNext = 0
    // Karplus-Strong pizzicato
    private var ksBuf: [[Float]]
    private var ksLen = [Int](repeating: 100, count: 6), ksIdx = [Int](repeating: 0, count: 6), ksAmp = [Float](repeating: 0, count: 6)
    private var ksNext = 0
    // drone
    private var drF: Float = 73.4, drCur: Float = 73.4, drP1: Float = 0, drP2: Float = 0, drP3: Float = 0, drLP: Float = 0, drLP2: Float = 0
    // strings tremolo
    private var stF: [Float] = [440, 466], stP: [Float] = [0, 0], stLP: Float = 0, stTrem: Float = 0
    // drums
    private var tomP: Float = 0, tomEnv: Float = 0, tomPE: Float = 0
    private var shEnv: Float = 0, shLP: Float = 0, shVel: Float = 0
    // music box
    private var mbF: Float = 880, mbP: Float = 0, mbM: Float = 0, mbE: Float = 0
    private var chord: [Int]

    init(sampleRate: Float) {
        sr = sampleRate
        stepLen = Int(sampleRate * 60 / 76 / 4)
        ksBuf = (0..<6).map { _ in [Float](repeating: 0, count: 2400) }
        chord = [38, 50, 53, 57, 62]
    }

    private func rand() -> Float { rng.next() * 0.5 + 0.5 }

    private func piano(_ note: Int, vel: Float, pan: Float) {
        let v = pnNext; pnNext = (pnNext + 1) % pnF.count
        pnF[v] = midiHz(Float(note)); pnP[v] = 0; pnE[v] = 1; pnV[v] = vel; pnPan[v] = pan; pnHam[v] = 1
    }

    private func pluck(_ note: Int, vel: Float) {
        let v = ksNext; ksNext = (ksNext + 1) % 6
        let len = min(2399, max(20, Int(sr / midiHz(Float(note)))))
        ksLen[v] = len; ksIdx[v] = 0; ksAmp[v] = vel
        var lp: Float = 0
        for j in 0..<len {
            lp += (rng.next() - lp) * 0.45          // softer, rounder pluck
            ksBuf[v][j] = lp
        }
    }

    private func onStep(_ s: Int) {
        let bar = s / 16, st = s % 16
        chord = prog[(bar / 2) % prog.count]
        let root = chord[0]
        // drone follows the bass
        if st == 0 { drF = midiHz(Float(root + 12)) }

        // felt piano: chord bloom at the top of each 2-bar chord, motif phrases in between
        if st == 0 && bar % 2 == 0 {
            for (j, n) in chord.dropFirst().enumerated() where rand() > 0.25 {
                piano(n + (j == 3 && rand() > 0.6 ? 12 : 0), vel: 0.22 + rand() * 0.1, pan: Float(j) * 0.3 - 0.45)
            }
        }
        let phraseOn = (bar % 4 == 1 || bar % 4 == 3) || sExp > 0.5
        if phraseOn && st % 1 == 0 && (bar % 2 == 1) {
            let m = motif[st]
            if m >= 0 && rand() > 0.18 {
                piano(root + 24 + m, vel: 0.32 + rand() * 0.15, pan: 0.2)
            }
        } else if st % 4 == 2 && rand() > 0.75 {
            piano(chord[1 + Int(rand() * 3.99)] + 12, vel: 0.2, pan: -0.2)
        }

        // pizzicato walking bass while exploring (quarters) — eighths when tense
        if sExp > 0.1 || sTen > 0.3 {
            let pattern: [Int] = [0, 7, 12, 7]
            if st % 4 == 0 { pluck(root + 12 + pattern[(st / 4) % 4], vel: 0.9) }
            else if st % 4 == 2 && sTen > 0.4 { pluck(root + 12 + (st == 6 ? 10 : 3), vel: 0.6) }
        }
        // shaker on eighths while exploring
        if st % 2 == 0 && (sExp > 0.15 || sTen > 0.3) { shEnv = 1; shVel = st % 4 == 0 ? 0.5 : 1 }
        // low drums when hunted
        if sTen > 0.25 && (st == 0 || st == 6 || st == 8 || (st == 14 && rand() > 0.5)) { tomEnv = 1; tomPE = 1; tomP = 0 }
        // tension strings: a minor second rubbing against the chord's fifth
        if st == 0 {
            let top = chord[3] + 12
            stF = [midiHz(Float(top)), midiHz(Float(top + 1))]
        }
        // music box at home
        if sHome > 0.1 && st % 4 == 0 && rand() > 0.3 {
            let scale = [74, 77, 81, 79, 76, 74, 72, 69]
            mbF = midiHz(Float(scale[(s / 4) % scale.count] + (rand() > 0.8 ? 12 : 0)))
            mbE = 1; mbP = 0; mbM = 0
        }
    }

    func render(frames: Int, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>) {
        let target: Float = enabled ? volume : 0
        let tp = 2 * Float.pi, inv = 1 / sr
        let tE = explore, tT = tension, tHm = home
        let pnDecay = expf(-1 / (sr * 1.6))
        let tomDecay = expf(-1 / (sr * 0.35)), tomPD = expf(-1 / (sr * 0.05)), shDecay = expf(-1 / (sr * 0.03))
        let mbDecay = expf(-1 / (sr * 0.9))
        for i in 0..<frames {
            gain += (target - gain) * 0.00006
            sExp += (tE - sExp) * 0.00002
            sTen += (tT - sTen) * (tT > sTen ? 0.0002 : 0.00003)
            sHome += (tHm - sHome) * 0.00004
            if sampleInStep == 0 { step += 1; onStep(step) }
            sampleInStep += 1
            if sampleInStep >= stepLen { sampleInStep = 0 }

            var l: Float = 0, r: Float = 0

            // drone: detuned saws, low-passed, very soft
            drCur += (drF - drCur) * 0.0003
            drP1 += drCur * inv; if drP1 >= 1 { drP1 -= 1 }
            drP2 += drCur * 1.004 * inv; if drP2 >= 1 { drP2 -= 1 }
            drP3 += drCur * 0.5 * inv; if drP3 >= 1 { drP3 -= 1 }
            let saw = (drP1 * 2 - 1) + (drP2 * 2 - 1) + sinf(drP3 * tp) * 1.2
            drLP += (saw - drLP) * 0.012; drLP2 += (drLP - drLP2) * 0.012
            let drone = drLP2 * 0.09 * (0.8 + 0.2 * sinf(Float(step) * 0.05))
            l += drone; r += drone

            // felt piano
            for v in 0..<pnF.count where pnE[v] > 0.0004 {
                pnP[v] += pnF[v] * inv; if pnP[v] >= 1 { pnP[v] -= 1 }
                let p = pnP[v] * tp
                let partials = sinf(p) + sinf(2 * p) * 0.38 * pnE[v] + sinf(3 * p) * 0.16 * pnE[v] * pnE[v] + sinf(4.02 * p) * 0.06 * pnE[v]
                pnHam[v] *= 0.992
                let ham = rng.next() * pnHam[v] * 0.08
                let s = (partials * pnE[v] + ham) * pnV[v] * 0.2
                pnE[v] *= pnDecay
                let (pl, pr) = equalPan(pnPan[v])
                l += s * pl; r += s * pr
            }

            // pizzicato
            for v in 0..<6 where ksAmp[v] > 0.001 {
                let len = ksLen[v]
                let j = ksIdx[v], j2 = (j + 1) % len
                let out = ksBuf[v][j]
                ksBuf[v][j] = (out + ksBuf[v][j2]) * 0.5 * 0.994
                ksIdx[v] = j2
                let s = out * ksAmp[v] * 0.5 * max(sExp, sTen)
                ksAmp[v] *= 0.99997
                l += s * 0.9; r += s * 1.1
            }

            // shaker
            let nz = rng.next()
            if shEnv > 0.001 {
                shEnv *= shDecay
                shLP += (nz - shLP) * 0.5
                let h = (nz - shLP) * shEnv * shVel * 0.035 * max(sExp, sTen)
                l += h * 1.2; r += h * 0.8
            }
            // low tom
            if tomEnv > 0.001 {
                tomEnv *= tomDecay; tomPE *= tomPD
                tomP += (52 + 70 * tomPE) * inv; if tomP >= 1 { tomP -= 1 }
                let t = (sinf(tomP * tp) + nz * 0.15 * tomPE) * tomEnv * 0.45 * sTen
                l += t; r += t
            }
            // tremolo strings
            if sTen > 0.01 {
                stTrem += 11 * inv; if stTrem >= 1 { stTrem -= 1 }
                var sw: Float = 0
                for k in 0..<2 {
                    stP[k] += stF[k] * inv; if stP[k] >= 1 { stP[k] -= 1 }
                    sw += stP[k] * 2 - 1
                }
                stLP += (sw - stLP) * 0.08
                let trem = 0.55 + 0.45 * sinf(stTrem * tp)
                let s = stLP * trem * 0.05 * sTen * sTen
                l += s * 0.8; r += s * 1.2
            }
            // music box
            if mbE > 0.001 {
                mbE *= mbDecay
                mbP += mbF * inv; if mbP >= 1 { mbP -= 1 }
                mbM += mbF * 5.02 * inv; if mbM >= 1 { mbM -= 1 }
                let s = sinf(mbP * tp + sinf(mbM * tp) * mbE * 0.8) * mbE * 0.06 * sHome
                l += s * 1.1; r += s * 0.9
            }
            L[i] = softClip(l * 1.3) * gain
            R[i] = softClip(r * 1.3) * gain
        }
    }
}

