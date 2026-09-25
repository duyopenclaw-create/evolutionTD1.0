import Foundation

// Synths run on the audio thread. The game thread writes their public parameters
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

/// Two-pole resonator (band-pass-ish). Output is roughly unity at the centre frequency.
struct Reso {
    var y1: Float = 0, y2: Float = 0
    @inline(__always) mutating func run(_ x: Float, f: Float, q: Float, sr: Float) -> Float {
        let w = 2 * Float.pi * min(f, sr * 0.45) / sr
        let r = max(0, 1 - w / (2 * q))
        let y = x * (1 - r) * 2 * sinf(w) + 2 * r * cosf(w) * y1 - r * r * y2
        y2 = y1; y1 = y
        return y
    }
}

@inline(__always) func equalPan(_ p: Float) -> (Float, Float) {
    let a = (max(-1, min(1, p)) + 1) * .pi / 4
    return (cosf(a) * 1.414, sinf(a) * 1.414)
}

/// A child's voice: a buzzy glottal source through three formant resonators.
struct Voice {
    var ph: Float = 0
    var r1 = Reso(), r2 = Reso(), r3 = Reso()
    var n = Noise32(s: 0x5EED)
    var lp: Float = 0
    @inline(__always) mutating func run(f0: Float, f1: Float, f2: Float, f3: Float, breath: Float, sr: Float) -> Float {
        ph += f0 / sr
        if ph > 1 { ph -= 1 }
        // Rosenberg-ish pulse: rounded open phase, sharp close
        let open: Float = 0.6
        let g: Float = ph < open ? 0.5 * (1 - cosf(.pi * ph / open)) : max(0, cosf(.pi * (ph - open) / (2 * (1 - open))))
        let src = (g - 0.45) + n.next() * breath
        lp += (src - lp) * 0.6
        return r1.run(lp, f: f1, q: 7, sr: sr) * 1.0 + r2.run(lp, f: f2, q: 10, sr: sr) * 0.55 + r3.run(lp, f: f3, q: 14, sr: sr) * 0.25
    }
}
