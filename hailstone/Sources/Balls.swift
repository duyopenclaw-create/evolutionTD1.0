import SceneKit
import CoreText

enum Collatz {
    @inline(__always) static func next(_ n: Int) -> Int { n % 2 == 0 ? n / 2 : 3 * n + 1 }

    /// The full hailstone sequence from n down to 1 (inclusive).
    static func sequence(_ n: Int) -> [Int] {
        var s = [max(1, n)]
        while s.last! != 1 { s.append(next(s.last!)) }
        return s
    }

    /// Number of bits: 1 → 1, 2–3 → 2, 4–7 → 3 … Each halving drops exactly one band.
    static func band(_ n: Int) -> Int { Int.bitWidth - max(1, n).leadingZeroBitCount }
}

/// Physics categories.
enum Mask {
    static let floor = 1, glass = 2, ball = 4, room = 8
    static let all = 0xFF
}

final class Ball {
    let value: Int
    let radius: Float
    let node: SCNNode
    let material: SCNMaterial
    let chain: Int
    let step: Int
    let born: Double
    var spawned = false
    var lastVel = SIMD3<Float>(repeating: 0)
    var lastSound = -1.0
    /// Soft ambient-occlusion disc on the floor under the ball.
    let contact: SCNNode

    init(value: Int, chain: Int, step: Int, born: Double) {
        self.value = value
        self.chain = chain
        self.step = step
        self.born = born
        radius = BallFactory.radius(value)
        (node, material) = BallFactory.make(value, radius: radius)
        let plane = SCNPlane(width: CGFloat(radius * 3.4), height: CGFloat(radius * 3.4))
        plane.materials = [BallFactory.contactMaterial]
        contact = SCNNode(geometry: plane)
        contact.eulerAngles.x = -.pi / 2
        contact.castsShadow = false
        contact.renderingOrder = 5
        contact.categoryBitMask = 1 << 3      // kept out of the floor's reflection
    }

    /// Keeps the occlusion disc under the ball; it fades and widens as the ball leaves the floor.
    func updateContact() {
        let p = position
        let h = max(0, p.y - radius)
        let k = max(0, 1 - h / (radius * 2.5))
        contact.simdPosition = SIMD3(p.x, 0.003, p.z)
        contact.opacity = CGFloat(k * k * 0.85)
        contact.simdScale = SIMD3(repeating: 1 + (1 - k) * 0.6)
        contact.isHidden = k <= 0.01
    }

    var position: SIMD3<Float> { SIMD3(node.presentation.simdWorldPosition) }
    var mass: Float { Float(node.physicsBody?.mass ?? 1) }
    var volume: Float { 4 / 3 * .pi * radius * radius * radius }

    /// Brief glow, used when the ball gives birth or reaches 1.
    func flash(_ c: NSColor, peak: CGFloat, duration: Double) {
        let m = material
        m.emission.contents = c
        m.emission.intensity = peak
        node.runAction(.customAction(duration: duration) { _, t in
            let k = 1 - t / CGFloat(duration)
            m.emission.intensity = peak * k * k
        }, forKey: "flash")
    }
}

enum BallFactory {
    static let density: Float = 1150      // cast resin, kg/m³

    static let contactMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = makePixelImage(128, 128) { x, y in
            let dx = (Float(x) + 0.5) / 64 - 1, dy = (Float(y) + 0.5) / 64 - 1
            let d = sqrtf(dx * dx + dy * dy)
            // tight dark core where the ball touches, long soft falloff around it
            let a = clampf(expf(-d * d * 7) * 0.9 + expf(-d * d * 2.6) * 0.42 - 0.03, 0, 1) * smoothstep(1, 0.75, d)
            return CommandLine.arguments.contains("--dbg") ? SIMD4(1, 0, 0, 1) : SIMD4(0, 0, 0, a)
        }
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        return m
    }()

    /// Shared clear-coat roughness: mostly glassy, with fine hairline scratches and a few dull scuffs
    /// from rolling on the floor.
    static let wear: CGImage = {
        var rng = RNG(4242)
        return makeImage(1024, 512) { ctx in
            ctx.setFillColor(CGColor(gray: 0.04, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            ctx.setLineCap(.round)
            for _ in 0..<260 {
                let x = CGFloat(rng.float()) * 1024, y = CGFloat(rng.float()) * 512
                let a = CGFloat(rng.range(0, 6.28)), l = CGFloat(rng.range(6, 50))
                ctx.setStrokeColor(CGColor(gray: CGFloat(rng.range(0.15, 0.4)), alpha: 1))
                ctx.setLineWidth(CGFloat(rng.range(0.5, 1.4)))
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
                ctx.strokePath()
            }
            for _ in 0..<40 {
                let x = CGFloat(rng.float()) * 1024, y = CGFloat(rng.float()) * 512, r = CGFloat(rng.range(4, 22))
                ctx.setFillColor(CGColor(gray: 0.22, alpha: 0.35))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
            }
        }
    }()

    static func radius(_ n: Int) -> Float { min(0.7, 0.07 + 0.028 * log2(Float(max(1, n)))) }

    /// One colour per power-of-two band, in the spirit of a pool set.
    static let palette: [SIMD3<Float>] = [
        SIMD3(0.86, 0.64, 0.12),   // 1: gold
        SIMD3(0.95, 0.76, 0.10),   // 2–3: yellow
        SIMD3(0.07, 0.22, 0.62),   // 4–7: blue
        SIMD3(0.78, 0.08, 0.07),   // 8–15: red
        SIMD3(0.33, 0.12, 0.50),   // purple
        SIMD3(0.93, 0.40, 0.06),   // orange
        SIMD3(0.05, 0.42, 0.20),   // green
        SIMD3(0.45, 0.08, 0.10),   // maroon
        SIMD3(0.06, 0.06, 0.07),   // black
        SIMD3(0.02, 0.50, 0.55),   // teal
        SIMD3(0.88, 0.36, 0.55),   // pink
        SIMD3(0.10, 0.12, 0.32),   // navy
        SIMD3(0.46, 0.46, 0.12),   // olive
        SIMD3(0.62, 0.02, 0.22),   // crimson
        SIMD3(0.35, 0.42, 0.50),   // slate
        SIMD3(0.55, 0.30, 0.12),   // bronze
        SIMD3(0.20, 0.55, 0.85),   // sky
        SIMD3(0.70, 0.70, 0.72),   // silver
    ]
    static func tint(_ n: Int) -> SIMD3<Float> { palette[(Collatz.band(n) - 1) % palette.count] }

    static func make(_ n: Int, radius r: Float) -> (SCNNode, SCNMaterial) {
        let geo = SCNSphere(radius: CGFloat(r))
        geo.segmentCount = r > 0.3 ? 72 : (r > 0.15 ? 56 : 40)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = texture(n, radius: r)
        m.diffuse.mipFilter = .linear
        m.metalness.contents = 0.0
        m.roughness.contents = 0.32
        m.clearCoat.contents = 1.0
        m.clearCoatRoughness.contents = BallFactory.wear
        m.clearCoatRoughness.intensity = 1
        m.emission.contents = NSColor.black
        geo.materials = [m]
        let node = SCNNode(geometry: geo)
        node.name = "ball"
        node.categoryBitMask = 3        // bit 2 = clickable

        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: SCNSphere(radius: CGFloat(r)), options: nil))
        // Real resin mass for small balls; the big ones scale with r² rather than r³. At true weight,
        // a stack of half-tonne balls pushes the solver's contacts into the walls.
        body.mass = CGFloat(density * 4 / 3 * .pi * 0.1 * r * r)
        body.restitution = 0.9
        body.friction = 0.35
        body.rollingFriction = 0.02
        body.damping = 0.015
        body.angularDamping = 0.12
        body.categoryBitMask = Mask.ball
        body.collisionBitMask = Mask.all
        body.contactTestBitMask = Mask.all
        body.continuousCollisionDetectionThreshold = CGFloat(r)
        body.allowsResting = true
        node.physicsBody = body
        return (node, m)
    }

    /// Equirectangular skin: solid for even numbers, ivory with a wide band for odd ones (like stripes),
    /// and the number on two ivory roundels.
    static func texture(_ n: Int, radius r: Float) -> CGImage {
        let w = r < 0.14 ? 512 : (r < 0.3 ? 1024 : 2048), h = w / 2
        let odd = n % 2 == 1
        let tc = tint(n)
        let base = CGColor(srgbRed: CGFloat(tc.x), green: CGFloat(tc.y), blue: CGFloat(tc.z), alpha: 1)
        let ivory = CGColor(srgbRed: 0.94, green: 0.92, blue: 0.85, alpha: 1)
        let text = n.formatted(.number.grouping(.never))
        return makeImage(w, h) { ctx in
            let W = CGFloat(w), H = CGFloat(h)
            if odd {
                ctx.setFillColor(ivory); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
                ctx.setFillColor(base); ctx.fill(CGRect(x: 0, y: H * 0.29, width: W, height: H * 0.42))
            } else {
                ctx.setFillColor(base); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            }
            // faint mottling so the resin isn't a flat CG colour
            var rng = RNG(UInt64(n) &* 2654435761 &+ 17)
            for _ in 0..<60 {
                let x = CGFloat(rng.float()) * W, y = CGFloat(rng.float()) * H, s = CGFloat(rng.range(0.02, 0.08)) * H
                ctx.setFillColor(CGColor(gray: rng.chance(0.5) ? 1 : 0, alpha: 0.025))
                ctx.fillEllipse(in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
            }
            let digits = CGFloat(text.count)
            let dr = H * 0.15
            let rx = dr * max(1, 0.72 + 0.2 * digits)
            let fontSize = min(dr * 1.3, rx * 1.75 / (0.62 * digits))
            let font = CTFontCreateWithName("Futura-Bold" as CFString, fontSize, nil)
            let ink = CGColor(srgbRed: 0.06, green: 0.05, blue: 0.05, alpha: 1)
            let attr = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink])
            let line = CTLineCreateWithAttributedString(attr)
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            for cx in [W * 0.25, W * 0.75] {
                ctx.setFillColor(ivory)
                ctx.fillEllipse(in: CGRect(x: cx - rx, y: H / 2 - dr, width: rx * 2, height: dr * 2))
                ctx.textPosition = CGPoint(x: cx - b.midX, y: H / 2 - b.midY)
                CTLineDraw(line, ctx)
                if n == 6 || n == 9 || n == 66 || n == 99 || n == 68 || n == 86 || n == 89 || n == 98 {
                    // underline like real pool balls, so 6 and 9 can be told apart
                    ctx.setFillColor(ink)
                    ctx.fill(CGRect(x: cx - b.width * 0.4, y: H / 2 - b.height * 0.5 - fontSize * 0.14, width: b.width * 0.8, height: fontSize * 0.07))
                }
            }
        }
    }
}
