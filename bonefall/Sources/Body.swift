import SceneKit
import simd

/// The visible person, posed every frame from the ragdoll's particles.
/// Tapered limbs with ball joints, lathe-built torso and hips, sneakers, jeans, a T-shirt and a face.
final class BodyView {
    let root = SCNNode()
    let jetpack = SCNNode()
    private let head = SCNNode(), chest = SCNNode(), hips = SCNNode()
    private struct Limb { let node: SCNNode; let a: Int; let b: Int; let from: Float; let to: Float }
    private var limbs: [Limb] = []
    private var joints: [(node: SCNNode, i: Int)] = []
    private var feet: [(node: SCNNode, an: Int, toe: Int, kn: Int)] = []
    private var hands: [(node: SCNNode, i: Int, el: Int, left: Bool)] = []
    private var skinByRegion: [Region: [SCNMaterial]] = [:]
    static let skin = V3(0.87, 0.66, 0.53)
    static let bruise = V3(0.36, 0.2, 0.34)
    static let blood = V3(0.4, 0.04, 0.05)

    static func fabric(_ c: V3, seed: Int32, weave: Float, rough: CGFloat) -> SCNMaterial {
        let img = makePixelImage(128, 128) { x, y in
            let u = Float(x) / 128, v = Float(y) / 128
            let n = Noise.tfbm(u, v, freq: 8, octaves: 3, seed: seed) * 0.08
            let w = (sinf(u * 2 * .pi * 64) * sinf(v * 2 * .pi * 64)) * weave
            let k = 1 + n + w
            return SIMD4(c.x * k, c.y * k, c.z * k, 1)
        }
        let m = World.pbr(.white, rough: rough)
        m.diffuse.contents = img
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        return m
    }

    private func skinMat(_ r: Region) -> SCNMaterial {
        let m = World.pbr(color(BodyView.skin), rough: 0.55)
        m.lightingModel = .physicallyBased
        skinByRegion[r, default: []].append(m)
        return m
    }

    /// Solid of revolution with elliptical rings: (y, halfWidth, halfDepth), bottom to top, capped. Smooth normals, cylindrical UVs.
    static func lathe(_ rings: [(Float, Float, Float)], segments: Int = 28) -> SCNGeometry {
        var v = [V3](), uv = [CGPoint](), idx = [Int32]()
        for (r, (y, w, d)) in rings.enumerated() {
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                v.append(V3(cosf(a) * w, y, sinf(a) * d))
                uv.append(CGPoint(x: CGFloat(s) / CGFloat(segments), y: CGFloat(r) / CGFloat(rings.count - 1)))
            }
        }
        let row = segments + 1
        for r in 0..<(rings.count - 1) {
            for s in 0..<segments {
                let a = Int32(r * row + s), b = a + 1, c = Int32((r + 1) * row + s), e = c + 1
                idx += [a, c, b, b, c, e]
            }
        }
        for (ri, up) in [(0, false), (rings.count - 1, true)] {
            let ci = Int32(v.count)
            v.append(V3(0, rings[ri].0, 0)); uv.append(CGPoint(x: 0.5, y: up ? 1 : 0))
            for s in 0..<segments {
                let a = Int32(ri * row + s), b = a + 1
                idx += up ? [ci, b, a] : [ci, a, b]
            }
        }
        // outward winding check, then accumulate face normals
        let t0 = v[Int(idx[0])], t1 = v[Int(idx[1])], t2 = v[Int(idx[2])]
        let fn = simd_cross(t1 - t0, t2 - t0)
        let mid = (t0 + t1 + t2) / 3
        if simd_dot(fn, V3(mid.x, 0, mid.z)) < 0 { for k in stride(from: 0, to: idx.count, by: 3) { idx.swapAt(k + 1, k + 2) } }
        var n = [V3](repeating: .zero, count: v.count)
        for k in stride(from: 0, to: idx.count, by: 3) {
            let a = Int(idx[k]), b = Int(idx[k + 1]), c = Int(idx[k + 2])
            let f = simd_cross(v[b] - v[a], v[c] - v[a])
            n[a] += f; n[b] += f; n[c] += f
        }
        // seam: average the duplicated first/last column
        for r in 0..<rings.count {
            let s = n[r * row] + n[r * row + segments]
            n[r * row] = s; n[r * row + segments] = s
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: v.map { SCNVector3($0) }),
                                     SCNGeometrySource(normals: n.map { SCNVector3(simd_length($0) > 1e-9 ? simd_normalize($0) : V3(0, 1, 0)) }),
                                     SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    init() {
        let shirt = BodyView.fabric(V3(0.78, 0.16, 0.12), seed: 3, weave: 0.02, rough: 0.9)
        let jeans = BodyView.fabric(V3(0.2, 0.3, 0.5), seed: 5, weave: 0.07, rough: 0.85)
        let shoe = World.pbr(color(0.16, 0.16, 0.18), rough: 0.5)
        let sole = World.pbr(color(0.92, 0.92, 0.9), rough: 0.7)
        let hairM = World.pbr(color(0.2, 0.12, 0.07), rough: 0.75)
        let headSkin = skinMat(.skull)
        skinByRegion[.jaw] = [headSkin]

        // ---- head
        let skullG = SCNSphere(radius: 0.1)
        skullG.segmentCount = 36
        skullG.materials = [headSkin]
        let skullN = SCNNode(geometry: skullG)
        skullN.simdScale = V3(0.92, 1.1, 1.02)
        head.addChildNode(skullN)
        let jawN = SCNNode(geometry: SCNSphere(radius: 0.07))
        jawN.geometry!.materials = [headSkin]
        jawN.simdPosition = V3(0, -0.05, 0.025); jawN.simdScale = V3(0.95, 0.85, 1)
        head.addChildNode(jawN)
        let eyeW = World.pbr(color(0.95, 0.94, 0.9), rough: 0.25)
        let iris = World.pbr(color(0.25, 0.4, 0.55), rough: 0.2)
        let pupil = World.pbr(color(0.02, 0.02, 0.03), rough: 0.1)
        let brow = World.pbr(color(0.18, 0.11, 0.07), rough: 0.9)
        for s in [Float(-1), 1] {
            let e = SCNNode(geometry: SCNSphere(radius: 0.017)); e.geometry!.materials = [eyeW]
            e.simdPosition = V3(s * 0.037, 0.018, 0.085)
            let ir = SCNNode(geometry: SCNSphere(radius: 0.009)); ir.geometry!.materials = [iris]
            ir.simdPosition = V3(0, 0, 0.012)
            let pu = SCNNode(geometry: SCNSphere(radius: 0.0045)); pu.geometry!.materials = [pupil]
            pu.simdPosition = V3(0, 0, 0.007)
            ir.addChildNode(pu); e.addChildNode(ir); head.addChildNode(e)
            let lid = SCNNode(geometry: SCNSphere(radius: 0.019)); lid.geometry!.materials = [headSkin]
            lid.simdPosition = V3(s * 0.037, 0.026, 0.082); lid.simdScale = V3(1.05, 0.55, 1)
            head.addChildNode(lid)
            let b = SCNNode(geometry: SCNBox(width: 0.034, height: 0.007, length: 0.01, chamferRadius: 0.003)); b.geometry!.materials = [brow]
            b.simdPosition = V3(s * 0.037, 0.045, 0.092); b.eulerAngles.z = CGFloat(-s * 0.12)
            head.addChildNode(b)
            let ear = SCNNode(geometry: SCNSphere(radius: 0.024)); ear.geometry!.materials = [headSkin]
            ear.simdPosition = V3(s * 0.093, 0.005, -0.005); ear.simdScale = V3(0.4, 1, 0.75)
            head.addChildNode(ear)
        }
        let nose = SCNNode(geometry: SCNCone(topRadius: 0.006, bottomRadius: 0.017, height: 0.045))
        nose.geometry!.materials = [headSkin]
        nose.simdPosition = V3(0, -0.005, 0.1); nose.eulerAngles.x = -0.35
        head.addChildNode(nose)
        let tip = SCNNode(geometry: SCNSphere(radius: 0.012)); tip.geometry!.materials = [headSkin]
        tip.simdPosition = V3(0, -0.024, 0.107)
        head.addChildNode(tip)
        let lips = SCNNode(geometry: SCNCapsule(capRadius: 0.007, height: 0.04))
        lips.geometry!.materials = [World.pbr(color(0.62, 0.33, 0.32), rough: 0.5)]
        lips.simdPosition = V3(0, -0.055, 0.088); lips.eulerAngles.z = .pi / 2
        head.addChildNode(lips)
        // hair: a cap over the top and back, and a fringe
        let hair = SCNNode(geometry: SCNSphere(radius: 0.106))
        hair.geometry!.materials = [hairM]
        hair.simdPosition = V3(0, 0.03, -0.012); hair.simdScale = V3(0.96, 0.95, 1.04)
        head.addChildNode(hair)
        let fringe = SCNNode(geometry: SCNCapsule(capRadius: 0.025, height: 0.17))
        fringe.geometry!.materials = [hairM]
        fringe.simdPosition = V3(0, 0.085, 0.055); fringe.eulerAngles.z = .pi / 2; fringe.simdScale = V3(1, 1, 0.7)
        head.addChildNode(fringe)

        // ---- torso (chest in shirt) and hips (jeans with a belt)
        let chestG = BodyView.lathe([(-0.2, 0.135, 0.095), (-0.12, 0.14, 0.105), (-0.03, 0.155, 0.115), (0.06, 0.17, 0.12), (0.13, 0.18, 0.11),
                                     (0.17, 0.175, 0.095), (0.2, 0.14, 0.075), (0.225, 0.07, 0.055), (0.235, 0.05, 0.045)])
        chestG.materials = [shirt]
        chest.addChildNode(SCNNode(geometry: chestG))
        let hipsG = BodyView.lathe([(-0.13, 0.12, 0.085), (-0.08, 0.165, 0.11), (-0.02, 0.17, 0.115), (0.05, 0.155, 0.1), (0.11, 0.14, 0.095)])
        hipsG.materials = [jeans]
        hips.addChildNode(SCNNode(geometry: hipsG))
        let beltG = BodyView.lathe([(0.075, 0.152, 0.101), (0.105, 0.147, 0.099)])
        beltG.materials = [World.pbr(color(0.18, 0.1, 0.06), rough: 0.5)]
        hips.addChildNode(SCNNode(geometry: beltG))
        let buckle = SCNNode(geometry: SCNBox(width: 0.035, height: 0.026, length: 0.006, chamferRadius: 0.003))
        buckle.geometry!.materials = [World.pbr(color(0.75, 0.7, 0.55), rough: 0.3, metal: 1)]
        buckle.simdPosition = V3(0, 0.09, 0.1)
        hips.addChildNode(buckle)
        for n in [head, chest, hips] { root.addChildNode(n) }
        // jetpack: two tanks on the back with nozzles
        let metal = World.pbr(color(0.7, 0.72, 0.75), rough: 0.3, metal: 1)
        let redM = World.pbr(color(0.8, 0.12, 0.1), rough: 0.4)
        for s in [Float(-1), 1] {
            let tank = SCNNode(geometry: SCNCapsule(capRadius: 0.07, height: 0.42))
            tank.geometry!.materials = [redM]
            tank.simdPosition = V3(s * 0.08, 0.02, -0.19)
            jetpack.addChildNode(tank)
            let noz = SCNNode(geometry: SCNCone(topRadius: 0.035, bottomRadius: 0.06, height: 0.09))
            noz.geometry!.materials = [metal]
            noz.simdPosition = V3(s * 0.08, -0.22, -0.19)
            jetpack.addChildNode(noz)
        }
        let strap = SCNNode(geometry: SCNBox(width: 0.3, height: 0.05, length: 0.04, chamferRadius: 0.01))
        strap.geometry!.materials = [metal]
        strap.simdPosition = V3(0, 0.1, -0.16)
        jetpack.addChildNode(strap)
        jetpack.isHidden = true
        chest.addChildNode(jetpack)

        // ---- limbs: tapered cones between particles (from/to trims the ends along the segment)
        func limb(_ a: Int, _ b: Int, r0: CGFloat, r1: CGFloat, _ m: SCNMaterial, from: Float = 0, to: Float = 1) {
            let g = SCNCone(topRadius: r1, bottomRadius: r0, height: 1)
            g.radialSegmentCount = 20
            g.materials = [m]
            let n = SCNNode(geometry: g)
            root.addChildNode(n)
            limbs.append(Limb(node: n, a: a, b: b, from: from, to: to))
        }
        func joint(_ i: Int, _ r: CGFloat, _ m: SCNMaterial) {
            let g = SCNSphere(radius: r)
            g.segmentCount = 18
            g.materials = [m]
            let n = SCNNode(geometry: g)
            root.addChildNode(n)
            joints.append((n, i))
        }
        let neckSkin = skinMat(.neck)
        limb(PI.neck, PI.head, r0: 0.05, r1: 0.043, neckSkin, from: -0.1, to: 0.55)
        for (L, sh, el, ha, hip, kn, an) in [(true, PI.lSh, PI.lEl, PI.lHa, PI.lHip, PI.lKn, PI.lAn), (false, PI.rSh, PI.rEl, PI.rHa, PI.rHip, PI.rKn, PI.rAn)] {
            let armSkin = skinMat(L ? .lHum : .rHum), foreSkin = skinMat(L ? .lFore : .rFore)
            // upper arm: short sleeve over skin
            limb(sh, el, r0: 0.052, r1: 0.041, armSkin)
            limb(sh, el, r0: 0.064, r1: 0.056, shirt, from: -0.05, to: 0.5)
            joint(sh, 0.064, shirt)
            joint(el, 0.042, foreSkin)
            limb(el, ha, r0: 0.041, r1: 0.029, foreSkin, from: 0, to: 0.92)
            // legs in jeans
            limb(hip, kn, r0: 0.088, r1: 0.06, jeans, from: -0.08, to: 1)
            joint(kn, 0.061, jeans)
            limb(kn, an, r0: 0.058, r1: 0.045, jeans, from: 0, to: 0.93)
            joint(an, 0.038, skinMat(L ? .lShin : .rShin))
            // hand: palm and thumb
            let hm = skinMat(L ? .lHand : .rHand)
            let hand = SCNNode()
            let palm = SCNNode(geometry: SCNBox(width: 0.075, height: 0.1, length: 0.03, chamferRadius: 0.014))
            palm.geometry!.materials = [hm]
            palm.simdPosition = V3(0, -0.035, 0)
            hand.addChildNode(palm)
            let fingers = SCNNode(geometry: SCNBox(width: 0.07, height: 0.07, length: 0.022, chamferRadius: 0.01))
            fingers.geometry!.materials = [hm]
            fingers.simdPosition = V3(0, -0.105, 0.006); fingers.eulerAngles.x = 0.25
            hand.addChildNode(fingers)
            let thumb = SCNNode(geometry: SCNCapsule(capRadius: 0.012, height: 0.06))
            thumb.geometry!.materials = [hm]
            thumb.simdPosition = V3(L ? 0.04 : -0.04, -0.035, 0.014); thumb.eulerAngles.z = CGFloat(L ? 0.5 : -0.5)
            hand.addChildNode(thumb)
            root.addChildNode(hand)
            hands.append((hand, ha, el, L))
            // sneaker
            let f = SCNNode()
            let upper = SCNNode(geometry: SCNBox(width: 0.1, height: 0.075, length: 0.26, chamferRadius: 0.035))
            upper.geometry!.materials = [shoe]
            upper.simdPosition = V3(0, 0.012, 0)
            f.addChildNode(upper)
            let soleN = SCNNode(geometry: SCNBox(width: 0.106, height: 0.025, length: 0.275, chamferRadius: 0.012))
            soleN.geometry!.materials = [sole]
            soleN.simdPosition = V3(0, -0.03, 0.003)
            f.addChildNode(soleN)
            let tongue = SCNNode(geometry: SCNBox(width: 0.06, height: 0.02, length: 0.1, chamferRadius: 0.008))
            tongue.geometry!.materials = [sole]
            tongue.simdPosition = V3(0, 0.05, 0.02)
            f.addChildNode(tongue)
            root.addChildNode(f)
            feet.append((f, an, L ? PI.lToe : PI.rToe, kn))
        }
        root.enumerateHierarchy { n, _ in n.castsShadow = true }
    }

    private func orient(_ n: SCNNode, _ a: V3, _ b: V3) {
        let d = b - a
        let L = simd_length(d)
        n.simdPosition = (a + b) / 2
        if L > 1e-5 { n.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: d / L) }
        n.simdScale = V3(1, max(L, 0.01), 1)
    }

    private static func basis(_ r: V3, _ u: V3) -> simd_quatf {
        let rr = simd_normalize(r + V3(1e-6, 0, 0))
        let uu = simd_normalize(u - rr * simd_dot(u, rr) + V3(0, 1e-6, 0))
        return simd_quatf(simd_float3x3(columns: (rr, uu, simd_cross(rr, uu))))
    }

    func update(_ rd: Ragdoll) {
        let p = rd.worldPos
        let f = rd.frame
        // chest follows the shoulders; hips follow the hip joints
        let shR = p[PI.lSh] - p[PI.rSh]
        chest.simdPosition = p[PI.chest] + f.up * -0.02
        chest.simdOrientation = BodyView.basis(shR, p[PI.neck] - p[PI.chest] * 0.5 - p[PI.pelvis] * 0.5)
        let hipR = p[PI.lHip] - p[PI.rHip]
        hips.simdPosition = p[PI.pelvis] + V3(0, 0, 0) - f.up * 0.01
        hips.simdOrientation = BodyView.basis(hipR, p[PI.chest] - p[PI.pelvis])
        // head faces the chest's forward, tilted by the neck
        let hu = simd_normalize(p[PI.head] - p[PI.neck] + V3(0, 1e-5, 0))
        let hf = simd_normalize(f.fwd - hu * simd_dot(f.fwd, hu) + V3(0, 0, 1e-5))
        head.simdPosition = p[PI.head] + hu * 0.01
        head.simdOrientation = simd_quatf(simd_float3x3(columns: (simd_cross(hu, hf), hu, hf)))
        for l in limbs {
            let a = p[l.a], b = p[l.b]
            orient(l.node, a + (b - a) * l.from, a + (b - a) * l.to)
        }
        for j in joints { j.node.simdPosition = p[j.i] }
        for h in hands {
            let dir = simd_normalize(p[h.i] - p[h.el] + V3(0, 1e-5, 0))
            // palm faces the body's side; build from the forearm direction and torso right
            let side = f.right * (h.left ? 1 : -1)
            let fwd = simd_normalize(simd_cross(side, dir) + V3(0, 0, 1e-5))
            let right = simd_cross(-dir, fwd)
            h.node.simdPosition = p[h.i] + dir * 0.01
            h.node.simdOrientation = simd_quatf(simd_float3x3(columns: (right, -dir, fwd)))
        }
        for ft in feet {
            let a = p[ft.an], t = p[ft.toe]
            let fwd = simd_normalize(t - a + V3(0, 0, 1e-5))
            let shin = simd_normalize(p[ft.kn] - a + V3(0, 1e-5, 0))
            let side = simd_normalize(simd_cross(shin, fwd) + V3(1e-5, 0, 0))
            let up = simd_cross(fwd, side)
            ft.node.simdPosition = a + fwd * 0.075 + up * -0.03
            ft.node.simdOrientation = simd_quatf(simd_float3x3(columns: (side, up, fwd)))
        }
    }

    /// Skin darkens toward bruise purple, then blood red, as the bones underneath take damage.
    func tint(_ inj: Injuries) {
        for (r, ms) in skinByRegion {
            let d = inj.regionDamage(r)
            let t1 = smoothstep(10, 60, d), t2 = smoothstep(60, 130, d)
            let c = color(mix3(mix3(BodyView.skin, BodyView.bruise, t1 * 0.7), BodyView.blood, t2 * 0.65))
            for m in ms { m.diffuse.contents = c }
        }
    }
}
