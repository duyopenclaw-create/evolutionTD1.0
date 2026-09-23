import AppKit
import simd

struct TimeOfDay {
    let name: String
    let sunElevation: Float     // radians above horizon
    let sunAzimuth: Float       // radians, 0 = north, clockwise
    let zenith: SIMD3<Float>
    let horizon: SIMD3<Float>
    let glow: SIMD3<Float>      // warm band near the sun at the horizon
    let sunColor: SIMD3<Float>
    let sunIntensity: CGFloat
    let ambient: CGFloat
    let cloudTint: SIMD3<Float>
    let exposure: CGFloat
    let fogDistance: CGFloat

    static let presets: [TimeOfDay] = [
        TimeOfDay(name: "MORNING", sunElevation: 0.32, sunAzimuth: 1.9,
                  zenith: SIMD3(0.18, 0.38, 0.72), horizon: SIMD3(0.72, 0.8, 0.88), glow: SIMD3(1.0, 0.82, 0.6),
                  sunColor: SIMD3(1.0, 0.9, 0.76), sunIntensity: 2300, ambient: 1.05,
                  cloudTint: SIMD3(1.0, 0.95, 0.9), exposure: 0.0, fogDistance: 14000),
        TimeOfDay(name: "MIDDAY", sunElevation: 1.0, sunAzimuth: 2.6,
                  zenith: SIMD3(0.12, 0.33, 0.72), horizon: SIMD3(0.66, 0.78, 0.9), glow: SIMD3(0.95, 0.95, 0.95),
                  sunColor: SIMD3(1.0, 0.97, 0.92), sunIntensity: 2700, ambient: 1.1,
                  cloudTint: SIMD3(1, 1, 1), exposure: -0.1, fogDistance: 17000),
        TimeOfDay(name: "GOLDEN HOUR", sunElevation: 0.14, sunAzimuth: 4.4,
                  zenith: SIMD3(0.2, 0.3, 0.55), horizon: SIMD3(0.95, 0.72, 0.5), glow: SIMD3(1.0, 0.55, 0.22),
                  sunColor: SIMD3(1.0, 0.68, 0.38), sunIntensity: 2100, ambient: 0.85,
                  cloudTint: SIMD3(1.0, 0.8, 0.62), exposure: 0.1, fogDistance: 11000),
        TimeOfDay(name: "DUSK", sunElevation: 0.035, sunAzimuth: 4.6,
                  zenith: SIMD3(0.1, 0.12, 0.3), horizon: SIMD3(0.85, 0.45, 0.32), glow: SIMD3(1.0, 0.38, 0.12),
                  sunColor: SIMD3(1.0, 0.45, 0.2), sunIntensity: 1300, ambient: 0.6,
                  cloudTint: SIMD3(0.95, 0.58, 0.5), exposure: 0.35, fogDistance: 9000),
    ]

    var sunDirection: SIMD3<Float> {
        // direction *towards* the sun
        SIMD3(sinf(sunAzimuth) * cosf(sunElevation), sinf(sunElevation), -cosf(sunAzimuth) * cosf(sunElevation))
    }
}

enum Sky {
    /// Colour of the sky looking along unit direction `d`.
    static func color(_ d: SIMD3<Float>, _ t: TimeOfDay) -> SIMD3<Float> {
        let s = t.sunDirection
        let up = max(d.y, 0)
        let cosA = simd_dot(d, s)
        let sunLow = 1 - smoothstep(0.0, 0.6, t.sunElevation)
        var c = mix3(t.horizon, t.zenith, powf(up, 0.45))
        // horizon warmth concentrated toward the sun
        let toward = powf(max(cosA, 0) * 0.5 + 0.5, 3)
        let band = powf(1 - up, 6)
        c = mix3(c, t.glow, band * toward * (0.35 + 0.6 * sunLow))
        // below horizon: hazy sea-coloured band
        if d.y < 0 {
            let dn = min(-d.y * 6, 1)
            c = mix3(t.horizon * 0.92, t.horizon * SIMD3(0.55, 0.62, 0.7), dn)
        }
        // sun glow + disc
        let g = max(cosA, 0)
        c += t.sunColor * (powf(g, 32) * 0.1 + powf(g, 400) * 0.45)
        if cosA > 0.99965 { c = mix3(c, SIMD3(1, 1, 0.95) * 1.6, smoothstep(0.99965, 0.99985, cosA)) }
        return c
    }

    /// Latitude/longitude panorama; SceneKit maps u=0.5 to -Z (north) — verified with a test render.
    static func image(_ t: TimeOfDay, width: Int = 2048) -> CGImage {
        let h = width / 2
        return makePixelImage(width, h) { x, y in
            let u = (Float(x) + 0.5) / Float(width), v = (Float(y) + 0.5) / Float(h)
            let lat = (0.5 - v) * .pi
            let lon = (u - 0.5) * 2 * .pi + lonOffset
            let d = SIMD3(sinf(lon) * cosf(lat), sinf(lat), -cosf(lon) * cosf(lat))
            var c = color(d, t)
            // gentle dither against banding
            let n = Float((x &* 1973 &+ y &* 9277) & 255) / 255 - 0.5
            c += n / 255
            return SIMD4(c, 1)
        }
    }

    /// Longitude correction so the painted sun lines up with the sun light; tuned once by render test.
    static var lonOffset: Float = 0

    static func fogColor(_ t: TimeOfDay) -> NSColor {
        // Average the horizon ring (slightly above) so distant terrain melts into the sky.
        var acc = SIMD3<Float>.zero
        for i in 0..<32 {
            let a = Float(i) / 32 * 2 * .pi
            acc += color(simd_normalize(SIMD3(sinf(a), 0.03, -cosf(a))), t)
        }
        return color(acc / 32)
    }
    private static func color(_ v: SIMD3<Float>) -> NSColor {
        NSColor(srgbRed: CGFloat(clampf(v.x, 0, 1)), green: CGFloat(clampf(v.y, 0, 1)), blue: CGFloat(clampf(v.z, 0, 1)), alpha: 1)
    }
}
