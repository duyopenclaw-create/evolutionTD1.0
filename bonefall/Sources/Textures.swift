import AppKit
import simd

/// Procedural, tileable textures. All grayscale detail maps: colour comes from vertex tints per map.
enum Tex {
    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    private static func cached(_ key: String, _ make: () -> CGImage) -> CGImage {
        lock.lock()
        if let c = cache[key] { lock.unlock(); return c }
        lock.unlock()
        let img = make()
        lock.lock(); cache[key] = img; lock.unlock()
        return img
    }

    /// Height field for a rock style, 0...1, tileable over u, v in 0...1.
    static func rockHeight(_ style: Int, _ u: Float, _ v: Float) -> Float {
        switch style {
        case 1: // strata: horizontal bands with erosion
            let warp = Noise.tfbm(u, v, freq: 4, octaves: 3, seed: 5) * 0.08
            let band = sinf((v + warp) * 2 * .pi * 9) * 0.5 + 0.5
            let fine = Noise.tfbm(u, v, freq: 16, octaves: 4, seed: 9)
            return clampf(0.45 + band * 0.3 + fine * 0.35, 0, 1)
        case 2: // chalk: soft, with flint dots and cracks
            let base = Noise.tfbm(u, v, freq: 6, octaves: 5, seed: 12)
            let crack = abs(Noise.tfbm(u, v, freq: 5, octaves: 2, seed: 31))
            return clampf(0.62 + base * 0.25 - (crack < 0.03 ? 0.3 : 0), 0, 1)
        case 3: // ice: smooth with deep cracks
            let base = Noise.tfbm(u, v, freq: 3, octaves: 4, seed: 41)
            let crack = abs(Noise.tfbm(u, v, freq: 6, octaves: 3, seed: 43))
            return clampf(0.7 + base * 0.2 - max(0, 0.04 - crack) * 8, 0, 1)
        case 4: // basalt: columns (cells) with glassy streaks
            let cx = u * 8, cy = v * 8
            var best: Float = 9, second: Float = 9
            for oy in -1...1 { for ox in -1...1 {
                let ix = Int(floorf(cx)) + ox, iy = Int(floorf(cy)) + oy
                let wx = ((ix % 8) + 8) % 8, wy = ((iy % 8) + 8) % 8
                let px = Float(ix) + Noise.cell(wx, wy, 3), py = Float(iy) + Noise.cell(wx, wy, 4)
                let d = hypotf(cx - px, cy - py)
                if d < best { second = best; best = d } else if d < second { second = d }
            } }
            let edge = second - best
            let fine = Noise.tfbm(u, v, freq: 20, octaves: 3, seed: 51)
            return clampf(0.35 + smoothstep(0, 0.12, edge) * 0.4 + fine * 0.2, 0, 1)
        case 5: // jagged: ridged, sharp
            let r = 1 - abs(Noise.tfbm(u, v, freq: 5, octaves: 5, seed: 61, gain: 0.55)) * 2.2
            let fine = Noise.tfbm(u, v, freq: 24, octaves: 3, seed: 63)
            return clampf(r * 0.7 + fine * 0.25 + 0.1, 0, 1)
        default: // granite
            let base = Noise.tfbm(u, v, freq: 5, octaves: 6, seed: 71)
            let speck = Noise.cell(Int(u * 512), Int(v * 512), 9) > 0.93 ? 0.12 : 0
            return clampf(0.5 + base * 0.4 + Float(speck), 0, 1)
        }
    }

    static func groundHeight(_ style: Int, _ u: Float, _ v: Float) -> Float {
        switch style {
        case 0: // grass: streaky blades
            let blades = Noise.tfbm(u, v, freq: 64, octaves: 2, seed: 81)
            let patch = Noise.tfbm(u, v, freq: 4, octaves: 3, seed: 83)
            return clampf(0.55 + blades * 0.3 + patch * 0.25, 0, 1)
        case 1: // sand ripples
            let warp = Noise.tfbm(u, v, freq: 3, octaves: 2, seed: 91) * 0.1
            let rip = sinf((v + warp) * 2 * .pi * 24) * 0.5 + 0.5
            return clampf(0.55 + rip * 0.15 + Noise.tfbm(u, v, freq: 32, octaves: 2, seed: 93) * 0.2, 0, 1)
        case 2: // pebbles
            let cx = u * 24, cy = v * 24
            var best: Float = 9
            for oy in -1...1 { for ox in -1...1 {
                let ix = Int(floorf(cx)) + ox, iy = Int(floorf(cy)) + oy
                let wx = ((ix % 24) + 24) % 24, wy = ((iy % 24) + 24) % 24
                let px = Float(ix) + Noise.cell(wx, wy, 13), py = Float(iy) + Noise.cell(wx, wy, 14)
                best = min(best, hypotf(cx - px, cy - py))
            } }
            return clampf(1 - best * 1.2 + Noise.tfbm(u, v, freq: 16, octaves: 2, seed: 95) * 0.15, 0, 1)
        case 3: // snow: soft drifts, sparkle
            let d = Noise.tfbm(u, v, freq: 4, octaves: 4, seed: 101)
            return clampf(0.8 + d * 0.15, 0, 1)
        case 4: // ash with cracks
            let c = abs(Noise.tfbm(u, v, freq: 6, octaves: 3, seed: 111))
            return clampf(0.45 + Noise.tfbm(u, v, freq: 16, octaves: 3, seed: 113) * 0.25 - (c < 0.035 ? 0.35 : 0), 0, 1)
        default: // dirt and gravel
            let g = Noise.cell(Int(u * 256), Int(v * 256), 17)
            return clampf(0.5 + Noise.tfbm(u, v, freq: 8, octaves: 5, seed: 121) * 0.3 + (g > 0.85 ? 0.15 : 0), 0, 1)
        }
    }

    private static func albedo(_ size: Int, _ hf: (Float, Float) -> Float) -> CGImage {
        makePixelImage(size, size) { x, y in
            let h = hf(Float(x) / Float(size), Float(y) / Float(size))
            let g = 0.55 + h * 0.5
            return SIMD4(g, g, g, 1)
        }
    }

    private static func normalMap(_ size: Int, strength: Float, _ hf: (Float, Float) -> Float) -> CGImage {
        let s = Float(size)
        return makePixelImage(size, size) { x, y in
            let u = Float(x) / s, v = Float(y) / s, e = 1 / s
            let dx = hf(u + e, v) - hf(u - e, v)
            let dy = hf(u, v + e) - hf(u, v - e)
            let n = simd_normalize(V3(-dx * strength, dy * strength, 1))
            return SIMD4(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1)
        }
    }

    static func rock(_ style: Int) -> CGImage { cached("rock\(style)") { albedo(512) { rockHeight(style, $0, $1) } } }
    static func rockNormal(_ style: Int) -> CGImage { cached("rockN\(style)") { normalMap(512, strength: 40) { rockHeight(style, $0, $1) } } }
    static func ground(_ style: Int) -> CGImage { cached("ground\(style)") { albedo(512) { groundHeight(style, $0, $1) } } }
    static func groundNormal(_ style: Int) -> CGImage { cached("groundN\(style)") { normalMap(512, strength: 25) { groundHeight(style, $0, $1) } } }

    /// Vertical sky gradient with a bright horizon band.
    static func sky(_ top: V3, _ horizon: V3, _ key: String) -> CGImage {
        cached("sky" + key) {
            makePixelImage(8, 512) { _, y in
                let t = Float(y) / 511   // 0 top ... 1 bottom
                let up = smoothstep(0, 0.52, t)
                var c = mix3(top, horizon, powf(up, 1.6))
                if t > 0.52 { c = mix3(horizon, horizon * 0.8, smoothstep(0.52, 1, t)) }
                return SIMD4(c.x, c.y, c.z, 1)
            }
        }
    }

    /// Ember glow for the volcano floor (emission map).
    static func lavaGlow() -> CGImage {
        cached("lava") {
            makePixelImage(256, 256) { x, y in
                let u = Float(x) / 256, v = Float(y) / 256
                let c = abs(Noise.tfbm(u, v, freq: 6, octaves: 3, seed: 111))
                let g = c < 0.035 ? (1 - c / 0.035) : 0
                return SIMD4(g, g * 0.35, g * 0.05, 1)
            }
        }
    }

    private static func heightImage(_ size: Int, _ hf: (Float, Float) -> Float) -> CGImage {
        makePixelImage(size, size) { x, y in
            let h = hf(Float(x) / Float(size), Float(y) / Float(size))
            return SIMD4(h, h, h, 1)
        }
    }
    static func rockH(_ style: Int) -> CGImage { cached("rockH\(style)") { heightImage(512) { rockHeight(style, $0, $1) } } }
    static func groundH(_ style: Int) -> CGImage { cached("groundH\(style)") { heightImage(512) { groundHeight(style, $0, $1) } } }

    /// A clump of grass blades on a transparent background.
    static func grassBlades() -> CGImage {
        cached("blades") {
            makeImage(128, 256) { ctx in
                var r = RNG(42)
                for k in 0..<34 {
                    let x0 = CGFloat(r.range(10, 118))
                    let h = CGFloat(r.range(120, 250))
                    let lean = CGFloat(r.range(-40, 40))
                    let w = CGFloat(r.range(3, 7))
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: x0 - w, y: 0))
                    p.addQuadCurve(to: CGPoint(x: x0 + lean, y: h), control: CGPoint(x: x0 - w * 0.5 + lean * 0.2, y: h * 0.6))
                    p.addQuadCurve(to: CGPoint(x: x0 + w, y: 0), control: CGPoint(x: x0 + w * 0.5 + lean * 0.2, y: h * 0.6))
                    p.closeSubpath()
                    let t = CGFloat(r.range(0.7, 1.15))
                    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       colors: [CGColor(srgbRed: 0.55 * t, green: 0.6 * t, blue: 0.45 * t, alpha: 1),
                                                CGColor(srgbRed: 0.95 * t, green: 1.0 * t, blue: 0.75 * t, alpha: 1)] as CFArray, locations: [0, 1])!
                    ctx.saveGState()
                    ctx.addPath(p); ctx.clip()
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
                    ctx.restoreGState()
                    _ = k
                }
            }
        }
    }

    /// Equirectangular sky: gradient, sun disc with glow, fbm clouds, hazy horizon.
    static func skyDome(_ m: MapDef, sunDir: V3) -> CGImage {
        cached("dome" + m.name) {
            let W = 1024, H = 512
            return makePixelImage(W, H) { x, y in
                let lon = (Float(x) + 0.5) / Float(W) * 2 * .pi - .pi
                let lat = .pi / 2 - (Float(y) + 0.5) / Float(H) * .pi
                let d = V3(sinf(lon) * cosf(lat), sinf(lat), -cosf(lon) * cosf(lat))
                let el = max(0, d.y)
                var c = mix3(m.skyHorizon, m.skyTop, powf(el, 0.55))
                if d.y < 0 { c = mix3(m.skyHorizon, m.fog * 0.85, smoothstep(0, 0.25, -d.y)) }
                let sd = max(0, simd_dot(d, sunDir))
                c += m.sun * (powf(sd, 8) * 0.25 + powf(sd, 64) * 0.5)
                if sd > 0.9995 { c = mix3(c, V3(1.6, 1.5, 1.3), 0.95) }
                if d.y > 0.04 {
                    let px = d.x / (d.y + 0.35), pz = d.z / (d.y + 0.35)
                    let n = Noise.fbm(px * 2.2 + 3, pz * 2.2, octaves: 6, seed: Int32(truncatingIfNeeded: m.seed))
                    let cov = smoothstep(0.05, 0.4, n + (m.extra == .lava ? 0.15 : 0))
                    let fade = smoothstep(0.04, 0.3, d.y)
                    let lit = 0.8 + 0.35 * sd
                    let cloudC = mix3(m.skyHorizon * 0.9 + V3(0.12, 0.12, 0.12), V3(1, 1, 1), 0.5) * lit
                    c = mix3(c, cloudC, cov * fade * 0.85)
                }
                let dither = (Noise.cell(x, y, 5) - 0.5) / 128
                return SIMD4(c.x + dither, c.y + dither, c.z + dither, 1)
            }
        }
    }
}
