import AppKit
import CoreText
import simd

/// Builds a CGImage from raw RGBA bytes.
func bufferImage(_ w: Int, _ h: Int, _ bytes: [UInt8]) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// Tangent-space normal map from a wrapping height field.
func normalImage(_ w: Int, _ h: Int, _ height: [Float], strength: Float) -> CGImage {
    var out = [UInt8](repeating: 255, count: w * h * 4)
    out.withUnsafeMutableBufferPointer { ob in
        let o = ob.baseAddress!
        height.withUnsafeBufferPointer { hb in
            let H = hb.baseAddress!
            DispatchQueue.concurrentPerform(iterations: h) { y in
                for x in 0..<w {
                    let xl = (x + w - 1) % w, xr = (x + 1) % w, yu = (y + h - 1) % h, yd = (y + 1) % h
                    let dx = (H[y * w + xr] - H[y * w + xl]) * strength
                    let dy = (H[yd * w + x] - H[yu * w + x]) * strength
                    let n = simd_normalize(SIMD3<Float>(-dx, dy, 1))
                    let i = (y * w + x) * 4
                    o[i] = UInt8(clampf(n.x * 0.5 + 0.5, 0, 1) * 255)
                    o[i + 1] = UInt8(clampf(n.y * 0.5 + 0.5, 0, 1) * 255)
                    o[i + 2] = UInt8(clampf(n.z * 0.5 + 0.5, 0, 1) * 255)
                }
            }
        }
    }
    return bufferImage(w, h, out)
}

struct SurfaceMaps { let diffuse: CGImage; let rough: CGImage; let normal: CGImage }

enum Tex {
    /// Varnished maple strip flooring. One tile covers `meters` × `meters`; strips run along +x.
    static func maple(size w: Int = 2048, meters: Float = 4) -> SurfaceMaps {
        let rows = 70
        let pw = meters / Float(rows)
        var col = [UInt8](repeating: 255, count: w * w * 4)
        var rough = [UInt8](repeating: 255, count: w * w * 4)
        var height = [Float](repeating: 0, count: w * w)
        col.withUnsafeMutableBufferPointer { cb in
        rough.withUnsafeMutableBufferPointer { rb in
        height.withUnsafeMutableBufferPointer { hb in
            let C = cb.baseAddress!, R = rb.baseAddress!, Hh = hb.baseAddress!
            DispatchQueue.concurrentPerform(iterations: w) { y in
                for x in 0..<w {
                    let mx = (Float(x) + 0.5) / Float(w) * meters, mz = (Float(y) + 0.5) / Float(w) * meters
                    let j = min(rows - 1, Int(mz / pw))
                    let fy = mz / pw - Float(j)
                    let k = Noise.cell(j, 0, 3) < 0.5 ? 2 : 3
                    let L = meters / Float(k)
                    let bx = (mx + Noise.cell(j, 1, 5) * meters) / L
                    let fx = bx - floorf(bx)
                    let bi = Int(floorf(bx)) % k
                    let bid = j * 7 + bi
                    let seam = min(min(fx, 1 - fx) * L, min(fy, 1 - fy) * pw)
                    let groove = smoothstep(0.0, 0.0011, seam)
                    let tone = Noise.cell(bid, 2, 11)
                    var base = mix3(SIMD3<Float>(0.83, 0.62, 0.39), SIMD3<Float>(0.72, 0.49, 0.28), tone)
                    if Noise.cell(bid, 3, 13) > 0.86 { base = mix3(base, SIMD3<Float>(0.88, 0.71, 0.49), 0.7) }
                    if Noise.cell(bid, 4, 17) < 0.07 { base = mix3(base, SIMD3<Float>(0.62, 0.40, 0.22), 0.6) }
                    let lx = fx * L
                    let g1 = Noise.fbm(lx * 1.3 + Float(bid) * 3.1, fy * 2.2 + Float(bid) * 1.7, octaves: 3, seed: 3)
                    let streak = 0.5 + 0.5 * sinf(fy * 38 + g1 * 9 + lx * 0.6)
                    let fleck = Noise.perlin(lx * 40, fy * 30 + Float(bid), seed: 8)
                    var g: Float = 1 - 0.075 * streak - 0.05 * g1 - 0.03 * max(0, fleck)
                    let scuff = Noise.tfbm(mx / meters, mz / meters, freq: 5, octaves: 4, seed: 9)
                    g *= 1 - 0.05 * scuff
                    var c = base * g * (0.5 + 0.5 * groove)
                    c = simd_clamp(c, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
                    let i = (y * w + x) * 4
                    C[i] = UInt8(c.x * 255); C[i + 1] = UInt8(c.y * 255); C[i + 2] = UInt8(c.z * 255)
                    let r = clampf(0.16 + 0.12 * max(0, scuff) + 0.05 * streak + (1 - groove) * 0.45, 0, 1)
                    R[i] = UInt8(r * 255); R[i + 1] = R[i]; R[i + 2] = R[i]
                    Hh[y * w + x] = groove + 0.04 * streak
                }
            }
        }}}
        return SurfaceMaps(diffuse: bufferImage(w, w, col), rough: bufferImage(w, w, rough), normal: normalImage(w, w, height, strength: 2.2))
    }

    /// Painted concrete block, running bond, 400 × 200 mm units. One tile is 1.6 m square.
    static func blocks(paint: SIMD3<Float>, size w: Int = 1024) -> SurfaceMaps {
        let meters: Float = 1.6
        var col = [UInt8](repeating: 255, count: w * w * 4)
        var rough = [UInt8](repeating: 255, count: w * w * 4)
        var height = [Float](repeating: 0, count: w * w)
        col.withUnsafeMutableBufferPointer { cb in
        rough.withUnsafeMutableBufferPointer { rb in
        height.withUnsafeMutableBufferPointer { hb in
            let C = cb.baseAddress!, R = rb.baseAddress!, Hh = hb.baseAddress!
            DispatchQueue.concurrentPerform(iterations: w) { y in
                for x in 0..<w {
                    let u = (Float(x) + 0.5) / Float(w), v = (Float(y) + 0.5) / Float(w)
                    let mx = u * meters, my = v * meters
                    let row = Int(my / 0.2)
                    let fy = my / 0.2 - Float(row)
                    let bx = mx / 0.4 + (row % 2 == 0 ? 0 : 0.5)
                    let fx = bx - floorf(bx)
                    let bid = row * 11 + Int(floorf(bx))
                    let m = min(min(fx, 1 - fx) * 0.4, min(fy, 1 - fy) * 0.2)
                    let mortar = smoothstep(0.004, 0.009, m)
                    let pores = Noise.tfbm(u, v, freq: 64, octaves: 3, seed: 21)
                    let blotch = Noise.tfbm(u, v, freq: 4, octaves: 3, seed: 5)
                    let shade = 1 - 0.04 * Noise.cell(bid, 1, 9) - 0.03 * blotch - 0.035 * max(0, pores)
                    var c = paint * shade * (0.82 + 0.18 * mortar)
                    c = simd_clamp(c, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
                    let i = (y * w + x) * 4
                    C[i] = UInt8(c.x * 255); C[i + 1] = UInt8(c.y * 255); C[i + 2] = UInt8(c.z * 255)
                    let r = clampf(0.55 + 0.15 * pores + (1 - mortar) * 0.2, 0, 1)
                    R[i] = UInt8(r * 255); R[i + 1] = R[i]; R[i + 2] = R[i]
                    Hh[y * w + x] = mortar * 0.8 + pores * 0.12
                }
            }
        }}}
        return SurfaceMaps(diffuse: bufferImage(w, w, col), rough: bufferImage(w, w, rough), normal: normalImage(w, w, height, strength: 2.5))
    }

    /// Equirectangular reflection/lighting map of the hall: dark ceiling with rows of high-bay lamps,
    /// cream and blue walls, warm maple floor.
    static func environment(w: Int = 2048) -> CGImage {
        let h = w / 2
        let lamps: [SIMD2<Float>] = (0..<5).flatMap { i in (0..<3).map { k in SIMD2(Float(i - 2) * 6, Float(k - 1) * 6) } }
        return makePixelImage(w, h) { x, y in
            let theta = (Float(x) + 0.5) / Float(w) * 2 * .pi
            let phi = (Float(y) + 0.5) / Float(h) * .pi
            let d = SIMD3<Float>(sinf(phi) * cosf(theta), cosf(phi), sinf(phi) * sinf(theta))
            let eye = SIMD3<Float>(0, 1.5, 0)
            // ceiling
            if d.y > 0.001 {
                let t = (8.4 - eye.y) / d.y
                let p = eye + d * t
                if abs(p.x) < 16 && abs(p.z) < 10 {
                    var c = SIMD3<Float>(0.07, 0.075, 0.08)
                    for l in lamps {
                        let q = SIMD2(p.x, p.z) - l
                        let r = simd_length(q)
                        if r < 0.45 { c = SIMD3(1, 0.97, 0.9) }
                        else { c += SIMD3(1, 0.95, 0.85) * 0.18 * expf(-(r - 0.45) * 3) }
                    }
                    // trusses
                    if abs(p.x.truncatingRemainder(dividingBy: 4)) < 0.12 { c *= 0.5 }
                    return SIMD4(c, 1)
                }
            }
            // floor
            if d.y < -0.001 {
                let t = -eye.y / d.y
                let p = eye + d * t
                if abs(p.x) < 16 && abs(p.z) < 10 {
                    let dist = simd_length(SIMD2(p.x, p.z))
                    let c = SIMD3<Float>(0.62, 0.44, 0.26) * (0.85 + 0.15 * expf(-dist * 0.08))
                    return SIMD4(c, 1)
                }
            }
            // walls: find which wall the ray reaches first
            let tx = d.x != 0 ? ((d.x > 0 ? 16 : -16) - eye.x) / d.x : 1e9
            let tz = d.z != 0 ? ((d.z > 0 ? 10 : -10) - eye.z) / d.z : 1e9
            let t = min(tx, tz)
            let hy = eye.y + d.y * t
            var c: SIMD3<Float> = hy < 2.4 ? SIMD3(0.14, 0.24, 0.45) : SIMD3(0.78, 0.75, 0.66)
            c *= 0.55 + 0.25 * smoothstep(8.5, 3, hy)
            if hy > 5.2 && hy < 6.4 && tz < tx && d.z < 0 && abs(eye.x + d.x * t) < 2.2 { c = SIMD3(0.04, 0.04, 0.04) }  // scoreboard
            return SIMD4(c, 1)
        }
    }

    /// Stadium-style LED scoreboard face.
    static func scoreboard(seed: Int?, step: Int, total: Int, now: Int?, peak: Int) -> CGImage {
        let w = 1024, h = 512
        return makeImage(w, h) { ctx in
            let W = CGFloat(w), H = CGFloat(h)
            ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.025, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setStrokeColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.52, alpha: 1))
            ctx.setLineWidth(10)
            ctx.stroke(CGRect(x: 14, y: 14, width: W - 28, height: H - 28))
            func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: CGColor, center: Bool = false, right: Bool = false) {
                let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
                let a = NSAttributedString(string: s, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): c])
                let line = CTLineCreateWithAttributedString(a)
                let b = CTLineGetBoundsWithOptions(line, [])
                ctx.textPosition = CGPoint(x: center ? x - b.width / 2 : (right ? x - b.width : x), y: y)
                CTLineDraw(line, ctx)
            }
            let amber = CGColor(srgbRed: 1, green: 0.62, blue: 0.1, alpha: 1)
            let red = CGColor(srgbRed: 1, green: 0.16, blue: 0.08, alpha: 1)
            let white = CGColor(srgbRed: 0.95, green: 0.95, blue: 0.9, alpha: 1)
            text("HAILSTONE", W / 2, H - 92, 56, white, center: true)
            text("SEED", 70, H - 170, 30, white)
            text("STEP", W - 70, H - 170, 30, white, right: true)
            text(seed.map { "\($0)" } ?? "--", 70, H - 260, 76, red)
            text(seed == nil ? "--" : "\(step)/\(total)", W - 70, H - 260, 76, red, right: true)
            text("NOW", W / 2, 150, 30, white, center: true)
            text(now.map { "\($0)" } ?? "--", W / 2, 50, 96, amber, center: true)
            text("PEAK \(peak > 0 ? "\(peak)" : "--")", 70, 60, 28, white)
        }
    }
}
