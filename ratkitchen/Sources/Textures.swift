import SceneKit
import simd

/// A procedurally painted PBR texture set.
struct TexSet {
    let diffuse: CGImage
    let rough: CGImage
    let normal: CGImage
}

/// Every surface in the kitchen is painted here from noise, so the app ships no image files.
enum Tex {
    /// f(u, v) returns (albedo, roughness, height). u, v run 0...1 and should tile.
    static func make(_ size: Int, bump: Float, _ f: (Float, Float) -> (SIMD3<Float>, Float, Float)) -> TexSet {
        let n = size * size
        var col = [SIMD3<Float>](repeating: .zero, count: n)
        var rough = [Float](repeating: 0, count: n)
        var height = [Float](repeating: 0, count: n)
        col.withUnsafeMutableBufferPointer { cp in
            rough.withUnsafeMutableBufferPointer { rp in
                height.withUnsafeMutableBufferPointer { hp in
                    let c = cp.baseAddress!, r = rp.baseAddress!, h = hp.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: size) { y in
                        for x in 0..<size {
                            let (a, b, d) = f((Float(x) + 0.5) / Float(size), (Float(y) + 0.5) / Float(size))
                            let i = y * size + x
                            c[i] = a; r[i] = b; h[i] = d
                        }
                    }
                }
            }
        }
        let diffuse = makePixelImage(size, size) { x, y in
            let c = col[y * size + x]
            // albedo authored in linear, stored as sRGB
            return SIMD4(powf(max(c.x, 0), 1 / 2.2), powf(max(c.y, 0), 1 / 2.2), powf(max(c.z, 0), 1 / 2.2), 1)
        }
        let roughImg = makePixelImage(size, size) { x, y in
            let r = rough[y * size + x]
            return SIMD4(r, r, r, 1)
        }
        let normal = makePixelImage(size, size) { x, y in
            let xl = (x + size - 1) % size, xr = (x + 1) % size
            let yu = (y + size - 1) % size, yd = (y + 1) % size
            let dx = (height[y * size + xr] - height[y * size + xl]) * bump
            let dy = (height[yd * size + x] - height[yu * size + x]) * bump
            let nn = simd_normalize(SIMD3<Float>(-dx, dy, 1))
            return SIMD4(nn.x * 0.5 + 0.5, nn.y * 0.5 + 0.5, nn.z * 0.5 + 0.5, 1)
        }
        return TexSet(diffuse: diffuse, rough: roughImg, normal: normal)
    }

    static func lin(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        SIMD3(powf(r, 2.2), powf(g, 2.2), powf(b, 2.2))
    }

    // MARK: Surfaces

    /// Two by two 30 cm glazed ceramic tiles in a checker, with grout and grime.
    static func floorTiles() -> TexSet {
        let cream = lin(0.84, 0.81, 0.74), slate = lin(0.25, 0.27, 0.28), grout = lin(0.42, 0.40, 0.36)
        return make(1024, bump: 4) { u, v in
            let tu = u * 2, tv = v * 2
            let ix = Int(tu), iy = Int(tv)
            let fu = tu - Float(ix), fv = tv - Float(iy)
            let edge = min(min(fu, 1 - fu), min(fv, 1 - fv))       // distance to tile edge in tile units
            let g: Float = 0.011
            let tileMask = smoothstep(g * 0.7, g * 1.4, edge)
            let bevel = smoothstep(g, g * 2.2, edge)
            let dark = (ix + iy) % 2 == 1
            var c = dark ? slate : cream
            let cv = Noise.cell(ix, iy)
            c *= 0.94 + 0.1 * cv
            let cloud = Noise.tfbm(u, v, freq: 6, octaves: 5, seed: 3)
            c *= 1 + cloud * 0.08
            let speck = Noise.tfbm(u, v, freq: 64, octaves: 2, seed: 9)
            if speck > 0.42 { c *= 0.85 }
            // grime collects in the grout and along the edges
            let grime = smoothstep(0.06, 0.0, edge) * (0.5 + 0.5 * Noise.tfbm(u, v, freq: 16, octaves: 3, seed: 5))
            c *= 1 - grime * 0.25
            let gcol = grout * (0.8 + 0.3 * Noise.tfbm(u, v, freq: 40, octaves: 3, seed: 11))
            let col = mix3(gcol, c, tileMask)
            let scuff = max(0, Noise.tfbm(u, v, freq: 12, octaves: 4, seed: 21))
            let r = mixf(0.85, 0.16 + scuff * 0.35 + cv * 0.06, tileMask)
            let h = bevel * 0.9 + tileMask * 0.1 + cloud * 0.01
            return (col, r, h)
        }
    }

    /// Wood grain along u; span is one texture repeat.
    static func wood(base: SIMD3<Float>, dark: SIMD3<Float>, seed: Int32, rings: Float = 18, gloss: Float = 0.45) -> TexSet {
        make(1024, bump: 2.5) { u, v in
            let warp = Noise.tfbm(u, v, freq: 3, octaves: 4, seed: seed) * 2.2
            let fine = Noise.tfbm(u * 1, v, freq: 8, octaves: 3, seed: seed + 5)
            let ring = sinf((v + warp * 0.12 + fine * 0.02) * rings * 2 * .pi) * 0.5 + 0.5
            let lines = powf(ring, 5)
            // pores: stretched noise along the grain
            let pore = Noise.tperlin(u * 16, v * 256, period: 16, seed: seed + 9)
            let plank = Noise.tfbm(u, v, freq: 2, octaves: 2, seed: seed + 13)
            var c = mix3(base, dark, lines * 0.65 + max(0, pore) * 0.25)
            c *= 0.92 + plank * 0.16
            let r = gloss + lines * 0.12 + max(0, pore) * 0.2
            let h = -lines * 0.3 - max(0, pore) * 0.6
            return (c, r, h)
        }
    }

    /// Painted cabinet doors: satin paint over faint grain.
    static func paintedWood(_ c0: SIMD3<Float>) -> TexSet {
        make(512, bump: 1.2) { u, v in
            let grain = Noise.tperlin(u * 4, v * 64, period: 4, seed: 41)
            let blotch = Noise.tfbm(u, v, freq: 4, octaves: 4, seed: 43)
            let c = c0 * (0.97 + blotch * 0.05 + grain * 0.02)
            return (c, 0.42 + blotch * 0.08, grain * 0.4)
        }
    }

    /// White quartz countertop with soft grey veins.
    static func quartz() -> TexSet {
        make(1024, bump: 1.5) { u, v in
            let w = Noise.tfbm(u, v, freq: 3, octaves: 5, seed: 71)
            let vein = 1 - smoothstep(0.0, 0.025, abs(sinf((u * 2 + v + w * 1.4) * .pi * 2) * 0.5))
            let vein2 = 1 - smoothstep(0.0, 0.012, abs(sinf((u - v * 3 + w * 2.1) * .pi * 3) * 0.5))
            let speck = Noise.tfbm(u, v, freq: 128, octaves: 1, seed: 75)
            var c = lin(0.9, 0.89, 0.86) * (0.97 + w * 0.04)
            c = mix3(c, lin(0.55, 0.55, 0.56), vein * 0.5 + vein2 * 0.3)
            if speck > 0.5 { c *= 0.9 }
            let r = 0.12 + max(0, Noise.tfbm(u, v, freq: 10, octaves: 3, seed: 77)) * 0.2
            return (c, r, speck * 0.05)
        }
    }

    /// Eggshell wall paint with orange-peel roller texture.
    static func plaster(_ c0: SIMD3<Float>) -> TexSet {
        make(512, bump: 0.5) { u, v in
            let peel = Noise.tfbm(u, v, freq: 48, octaves: 3, seed: 81)
            let stain = Noise.tfbm(u, v, freq: 2, octaves: 4, seed: 83)
            return (c0 * (0.95 + stain * 0.06 + peel * 0.02), 0.8 + peel * 0.08, peel)
        }
    }

    /// White subway tile backsplash, 4 rows × 2 bricks, running bond.
    static func subway() -> TexSet {
        make(1024, bump: 10) { u, v in
            let rows: Float = 8, cols: Float = 4
            let ry = v * rows
            let row = Int(ry)
            let rx = u * cols + (row % 2 == 0 ? 0 : 0.5)
            let col = Int(floorf(rx))
            let fu = rx - floorf(rx), fv = ry - Float(row)
            let ex = min(fu, 1 - fu) * 2.0, ey = min(fv, 1 - fv)   // bricks are 2:1
            let edge = min(ex / 2, ey)
            let g: Float = 0.03
            let mask = smoothstep(g * 0.6, g * 1.2, edge)
            let bevel = smoothstep(g, g * 4.0, edge)
            let cv = Noise.cell(col, row, 5)
            let wave = Noise.tfbm(u, v, freq: 8, octaves: 3, seed: 91)
            let c = mix3(lin(0.62, 0.61, 0.58), lin(0.92, 0.92, 0.9) * (0.96 + cv * 0.05), mask)
            return (c, mixf(0.8, 0.06 + cv * 0.05, mask), bevel + wave * 0.04)
        }
    }

    /// Brushed stainless steel: streaks along u.
    static func steel() -> TexSet {
        make(512, bump: 0.6) { u, v in
            let streak = Noise.tperlin(u * 2, v * 180, period: 2, seed: 101)
            let smudge = max(0, Noise.tfbm(u, v, freq: 4, octaves: 4, seed: 103))
            let c = lin(0.73, 0.74, 0.76) * (0.96 + streak * 0.05)
            return (c, 0.24 + streak * 0.05 + smudge * 0.25, streak)
        }
    }

    /// Short agouti rat fur: hairs run along v.
    static func ratFur() -> TexSet {
        make(512, bump: 4) { u, v in
            let hair = Noise.tperlin(u * 96, v * 12, period: 96, seed: 111)
            let hair2 = Noise.tperlin(u * 200, v * 20, period: 200, seed: 113)
            let clump = Noise.tfbm(u, v, freq: 6, octaves: 3, seed: 115)
            let tip = smoothstep(0.1, 0.6, hair2)            // agouti: lighter banded tips
            var c = mix3(lin(0.24, 0.2, 0.16), lin(0.47, 0.4, 0.31), tip * 0.7 + clump * 0.2)
            c *= 0.85 + hair * 0.25
            if hair2 < -0.45 { c = lin(0.12, 0.1, 0.09) }     // black guard hairs
            return (c, 0.62 + hair * 0.1, hair * 0.6 + hair2 * 0.4)
        }
    }

    /// Mackerel tabby: dark stripes wrap the body (bands in v on a pole-along-body sphere).
    static func tabby() -> TexSet {
        make(1024, bump: 3) { u, v in
            let hair = Noise.tperlin(u * 160, v * 20, period: 160, seed: 121)
            let w = Noise.tfbm(u, v, freq: 4, octaves: 4, seed: 123)
            let stripe = sinf((v * 14 + w * 1.6 + sinf(u * .pi * 2) * 0.4) * .pi * 2)
            let band = smoothstep(0.25, 0.7, stripe)
            let spine = smoothstep(0.12, 0.0, abs(u - 0.75)) * 0.6       // dark dorsal line
            var c = mix3(lin(0.56, 0.5, 0.42), lin(0.16, 0.14, 0.12), max(band * 0.85, spine))
            c *= 0.88 + hair * 0.2
            return (c, 0.7, hair * 0.7 + band * 0.1)
        }
    }

    /// Woven cloth. `pattern` returns the dye colour at (u, v).
    static func cloth(bump: Float = 3, _ pattern: @escaping (Float, Float) -> SIMD3<Float>) -> TexSet {
        make(512, bump: bump) { u, v in
            let weaveU = sinf(u * 512 * .pi / 2), weaveV = sinf(v * 512 * .pi / 2)
            let weave = (weaveU * weaveV) * 0.5 + 0.5
            let fuzz = Noise.tfbm(u, v, freq: 32, octaves: 3, seed: 131)
            let c = pattern(u, v) * (0.88 + weave * 0.14 + fuzz * 0.06)
            return (c, 0.9, weave * 0.6 + fuzz * 0.4)
        }
    }

    static func towelPlaid() -> TexSet {
        cloth { u, v in
            let a = fmodf(u * 6, 1) < 0.3, b = fmodf(v * 6, 1) < 0.3
            let r = lin(0.62, 0.1, 0.1), w = lin(0.9, 0.88, 0.84)
            if a && b { return r * 0.75 }
            if a || b { return mix3(w, r, 0.55) }
            return w
        }
    }

    static func linen() -> TexSet {
        cloth(bump: 4) { u, v in
            let slub = Noise.tperlin(u * 64, v * 4, period: 64, seed: 141)
            return lin(0.78, 0.72, 0.62) * (0.95 + slub * 0.06)
        }
    }

    static func pajamas() -> TexSet {
        cloth { u, v in
            let a = fmodf(u * 8, 1) < 0.18, b = fmodf(v * 8, 1) < 0.18
            let base = lin(0.2, 0.26, 0.42)
            if a && b { return lin(0.75, 0.75, 0.8) }
            if a || b { return base * 1.7 }
            return base
        }
    }

    static func runnerRug() -> TexSet {
        cloth(bump: 5) { u, v in
            let bu = min(u, 1 - u), bv = min(v, 1 - v)
            let border = min(bu * 3, bv)
            let red = lin(0.45, 0.12, 0.1), navy = lin(0.12, 0.14, 0.26), cream = lin(0.8, 0.72, 0.58)
            if border < 0.04 { return navy }
            if border < 0.06 { return cream }
            if border < 0.1 { return red * 0.8 }
            let cu = fmodf(u * 3, 1) - 0.5, cv = fmodf(v * 9, 1) - 0.5
            let d = abs(cu) + abs(cv)
            if d < 0.14 { return cream }
            if d < 0.2 { return navy }
            if abs(d - 0.34) < 0.03 { return cream * 0.9 }
            return red
        }
    }

    static func plush(_ c0: SIMD3<Float>) -> TexSet {
        make(512, bump: 5) { u, v in
            let f = Noise.tfbm(u, v, freq: 64, octaves: 3, seed: 151)
            let clump = Noise.tfbm(u, v, freq: 8, octaves: 3, seed: 153)
            return (c0 * (0.8 + f * 0.25 + clump * 0.1), 0.95, f)
        }
    }

    /// Crinkled black bin-bag plastic.
    static func binBag() -> TexSet {
        make(512, bump: 14) { u, v in
            let a = Noise.tfbm(u, v, freq: 5, octaves: 5, seed: 161)
            let crease = 1 - abs(Noise.tfbm(u, v, freq: 9, octaves: 3, seed: 163))
            let h = a * 0.5 + powf(crease, 6) * 0.5
            return (lin(0.06, 0.06, 0.065), 0.22 + (1 - crease) * 0.2, h)
        }
    }

    static func cardboard() -> TexSet {
        make(512, bump: 1.5) { u, v in
            let fib = Noise.tperlin(u * 128, v * 16, period: 128, seed: 171)
            let blot = Noise.tfbm(u, v, freq: 5, octaves: 4, seed: 173)
            let grease = max(0, Noise.tfbm(u, v, freq: 3, octaves: 3, seed: 175) - 0.2)
            let c = lin(0.66, 0.5, 0.33) * (0.93 + blot * 0.1 + fib * 0.03) * (1 - grease * 0.5)
            return (c, 0.9 - grease * 0.4, fib * 0.3)
        }
    }

    /// Generic food surface: base colour with bumpy crumb.
    static func food(_ c0: SIMD3<Float>, _ c1: SIMD3<Float>, freq: Int, seed: Int32, rough: Float = 0.6) -> TexSet {
        make(256, bump: 4) { u, v in
            let n = Noise.tfbm(u, v, freq: freq, octaves: 4, seed: seed)
            let t = smoothstep(-0.3, 0.4, n)
            return (mix3(c0, c1, t), rough + n * 0.15, n)
        }
    }

    static func cheese() -> TexSet {
        make(256, bump: 6) { u, v in
            var hole: Float = 0
            for k in 0..<9 {
                let cx = Noise.cell(k, 1, 181), cy = Noise.cell(k, 2, 181), r = 0.03 + Noise.cell(k, 3, 181) * 0.06
                var dx = abs(u - cx), dy = abs(v - cy)
                dx = min(dx, 1 - dx); dy = min(dy, 1 - dy)
                hole = max(hole, smoothstep(r, r * 0.6, sqrtf(dx * dx + dy * dy)))
            }
            let n = Noise.tfbm(u, v, freq: 8, octaves: 3, seed: 183)
            let c = lin(0.95, 0.76, 0.3) * (0.95 + n * 0.06) * (1 - hole * 0.35)
            return (c, 0.45, -hole + n * 0.05)
        }
    }

    // MARK: Environment

    /// Equirectangular reflection map: a dim kitchen with a cold window glow and a warm night-light.
    static func environment() -> CGImage {
        makePixelImage(512, 256) { x, y in
            let u = Float(x) / 512, v = Float(y) / 256
            var c = SIMD3<Float>(0.012, 0.013, 0.018) * (v > 0.5 ? 0.6 : 1)
            let wx = min(abs(u - 0.75), 1 - abs(u - 0.75))
            if wx < 0.06 && v > 0.22 && v < 0.42 { c = SIMD3(0.12, 0.16, 0.26) }
            let nl = min(abs(u - 0.25), 1 - abs(u - 0.25))
            let d = sqrtf(nl * nl * 4 + (v - 0.62) * (v - 0.62))
            c += SIMD3(0.35, 0.2, 0.08) * max(0, 1 - d * 14)
            return SIMD4(c.x, c.y, c.z, 1)
        }
    }
}

// MARK: - Materials

enum Mat {
    static func pbr(_ t: TexSet, metal: Float = 0, normalScale: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = t.diffuse
        m.roughness.contents = t.rough
        m.normal.contents = t.normal
        m.normal.intensity = normalScale
        m.metalness.contents = NSNumber(value: metal)
        for p in [m.diffuse, m.roughness, m.normal] {
            p.wrapS = .repeat; p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 8
        }
        return m
    }

    static func plain(_ c: NSColor, rough: CGFloat = 0.6, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = NSNumber(value: Double(rough))
        m.metalness.contents = NSNumber(value: Double(metal))
        return m
    }

    static func glow(_ c: NSColor, _ intensity: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.black
        m.emission.contents = c
        m.emission.intensity = intensity
        return m
    }

    /// Copy of `m` whose textures repeat every `span` metres across a face `w` × `h` metres.
    static func scaled(_ m: SCNMaterial, _ w: Float, _ h: Float, span: Float, rotate: Bool = false) -> SCNMaterial {
        let c = m.copy() as! SCNMaterial
        var t = SCNMatrix4MakeScale(CGFloat(w / span), CGFloat(h / span), 1)
        if rotate { t = SCNMatrix4Mult(SCNMatrix4MakeRotation(.pi / 2, 0, 0, 1), SCNMatrix4MakeScale(CGFloat(h / span), CGFloat(w / span), 1)) }
        for p in [c.diffuse, c.roughness, c.normal] { p.contentsTransform = t }
        return c
    }
}

/// A chamfered box whose six faces keep a constant texel density.
func texturedBox(_ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial, span: Float, chamfer: Float = 0.002, grainVertical: Bool = false) -> SCNNode {
    let b = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(chamfer))
    // SCNBox face order: front, right, back, left, top, bottom
    b.materials = [
        Mat.scaled(m, w, h, span: span, rotate: grainVertical),
        Mat.scaled(m, l, h, span: span, rotate: grainVertical),
        Mat.scaled(m, w, h, span: span, rotate: grainVertical),
        Mat.scaled(m, l, h, span: span, rotate: grainVertical),
        Mat.scaled(m, w, l, span: span),
        Mat.scaled(m, w, l, span: span),
    ]
    return SCNNode(geometry: b)
}
