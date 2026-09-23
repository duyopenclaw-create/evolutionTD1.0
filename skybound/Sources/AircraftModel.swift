import SceneKit
import simd

/// Procedurally modelled low-wing sport plane. Nose points to -Z.
final class AircraftModel {
    let node = SCNNode()
    let body = SCNNode()
    let prop = SCNNode()
    let propDisc = SCNNode()
    let blades = SCNNode()
    let aileronL = SCNNode(), aileronR = SCNNode()
    let flapL = SCNNode(), flapR = SCNNode()
    let elevator = SCNNode(), rudder = SCNNode()
    let gearNose = SCNNode(), gearL = SCNNode(), gearR = SCNNode()
    let pilot = SCNNode()
    var canopy = SCNNode()
    let strobe = AircraftModel.emissive(color(1, 1, 1))
    let navL = AircraftModel.emissive(color(1, 0.1, 0.08)), navR = AircraftModel.emissive(color(0.1, 1, 0.25))
    let tipL = SCNNode(), tipR = SCNNode(), tail = SCNNode()
    let paint = AircraftModel.paintMaterial()
    var propAngle: Float = 0

    static func paintMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor.white
        m.roughness.contents = 0.28
        m.metalness.contents = 0.05
        m.clearCoat.contents = 0.6
        m.clearCoatRoughness.contents = 0.05
        return m
    }

    static func pbr(_ c: NSColor, rough: CGFloat, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    static func emissive(_ c: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        m.emission.contents = c
        return m
    }

    init(primary: SIMD4<Float> = SIMD4(0.78, 0.07, 0.06, 1), accent: SIMD4<Float> = SIMD4(0.08, 0.1, 0.18, 1), tint: NSColor? = nil) {
        if let tint = tint { paint.diffuse.contents = tint }
        let white = SIMD4<Float>(0.93, 0.93, 0.94, 1)
        let belly = SIMD4<Float>(0.72, 0.73, 0.76, 1)

        // Fuselage: lofted rings (z, half-width, half-height, centre y)
        let prof: [(Float, Float, Float, Float)] = [
            (-3.55, 0.36, 0.38, 0.05), (-3.45, 0.47, 0.5, 0.05), (-3.2, 0.56, 0.6, 0.06), (-2.7, 0.61, 0.68, 0.08),
            (-2.0, 0.63, 0.71, 0.1), (-1.2, 0.62, 0.72, 0.1), (-0.3, 0.57, 0.68, 0.1), (0.7, 0.46, 0.56, 0.14),
            (1.8, 0.33, 0.43, 0.2), (2.9, 0.2, 0.31, 0.27), (3.8, 0.1, 0.19, 0.33), (4.15, 0.05, 0.1, 0.36),
        ]
        // extra rings either side of paint boundaries keep the livery edges crisp
        var prof2 = prof
        for zc: Float in [-3.03, -2.97, 3.17, 3.23] {
            if let k = prof2.firstIndex(where: { $0.0 > zc }), k > 0 {
                let a = prof2[k - 1], b = prof2[k]
                let t = (zc - a.0) / (b.0 - a.0)
                prof2.insert((zc, mixf(a.1, b.1, t), mixf(a.2, b.2, t), mixf(a.3, b.3, t)), at: k)
            }
        }
        let segs = 28
        var rings: [[SIMD3<Float>]] = [], cols: [[SIMD4<Float>]] = []
        for (z, w, h, yc) in prof2 {
            var r: [SIMD3<Float>] = [], c: [SIMD4<Float>] = []
            for i in 0..<segs {
                let a = Float(i) / Float(segs) * 2 * .pi
                let s = sinf(a), co = cosf(a)
                let flat: Float = s < 0 ? 0.85 : 1
                r.append(SIMD3(co * w, yc + s * h * flat, z))
                var col = white
                if z < -3.0 { col = primary }
                else if s > -0.12 && s < 0.14 { col = primary }
                else if s > 0.14 && s < 0.22 { col = accent }
                else if s < -0.55 { col = belly }
                if z > 3.2 && s > 0.3 { col = primary }
                c.append(col)
            }
            rings.append(r); cols.append(c)
        }
        let fus = MeshBuilder()
        fus.tube(rings, colors: cols, capStart: true, capEnd: true)

        // Wings: NACA-ish section lofted from root to tip, with dihedral + taper
        func airfoil(chord: Float, thick: Float, le: SIMD3<Float>, pts: Int = 22, vertical: Bool = false, camber: Float = 0.02) -> [SIMD3<Float>] {
            var out: [SIMD3<Float>] = []
            for i in 0..<pts {
                let th = Float(i) / Float(pts) * 2 * .pi
                let xc = 0.5 * (1 + cosf(th))
                let yt = 5 * thick * (0.2969 * sqrtf(xc) - 0.126 * xc - 0.3516 * xc * xc + 0.2843 * xc * xc * xc - 0.1036 * xc * xc * xc * xc)
                let yc = camber * 4 * xc * (1 - xc)
                let y = (sinf(th) >= 0 ? yt : -yt) + yc
                if vertical {
                    out.append(le + SIMD3(y * chord, 0, xc * chord))
                } else {
                    out.append(le + SIMD3(0, y * chord, xc * chord))
                }
            }
            return out
        }
        let wing = MeshBuilder()
        for side: Float in [-1, 1] {
            var wr: [[SIMD3<Float>]] = [], wc: [[SIMD4<Float>]] = []
            let spans: [Float] = [0.35, 1.2, 2.2, 3.2, 4.1, 4.75, 5.0]
            for sp in spans {
                let t = (sp - 0.35) / 4.65
                let chord = mixf(1.75, 1.05, t)
                let le = SIMD3<Float>(side * sp, -0.42 + sp * 0.085, -1.95 + t * 0.35)
                let pts = airfoil(chord: chord, thick: 0.15 - 0.03 * t, le: le)
                wr.append(pts)
                wc.append(pts.map { _ in sp > 4.3 ? primary : white })
            }
            if side < 0 { wr.reverse(); wc.reverse() }
            wing.tube(wr, colors: wc)
        }
        // Horizontal stabiliser + fin
        let tailMB = MeshBuilder()
        for side: Float in [-1, 1] {
            var sr: [[SIMD3<Float>]] = [], sc: [[SIMD4<Float>]] = []
            for sp: Float in [0.05, 0.9, 1.75] {
                let t = sp / 1.75
                let chord = mixf(0.95, 0.6, t)
                let pts = airfoil(chord: chord, thick: 0.1, le: SIMD3(side * sp, 0.3, 3.05 + t * 0.3), camber: 0)
                sr.append(pts); sc.append(pts.map { _ in white })
            }
            if side < 0 { sr.reverse(); sc.reverse() }
            tailMB.tube(sr, colors: sc)
        }
        var fr: [[SIMD3<Float>]] = [], fc: [[SIMD4<Float>]] = []
        for h: Float in [0.25, 0.9, 1.6] {
            let t = (h - 0.25) / 1.35
            let chord = mixf(1.25, 0.65, t)
            let pts = airfoil(chord: chord, thick: 0.1, le: SIMD3(0, h, 2.75 + t * 0.75), vertical: true, camber: 0)
            fr.append(pts); fc.append(pts.map { _ in t > 0.45 ? primary : white })
        }
        tailMB.tube(fr, colors: fc)

        let geomNode = SCNNode()
        geomNode.addChildNode(fus.node([paint]))
        geomNode.addChildNode(wing.node([paint]))
        geomNode.addChildNode(tailMB.node([paint]))
        body.addChildNode(geomNode)

        // Control surfaces: thin hinged plates just aft of each trailing edge
        func plate(_ w: Float, _ chord: Float, _ col: SIMD4<Float>, vertical: Bool = false) -> SCNNode {
            let mb = MeshBuilder()
            if vertical {
                mb.box(xform(SIMD3(0, 0, chord / 2)), size: SIMD3(0.05, w, chord), color: col)
            } else {
                mb.box(xform(SIMD3(0, 0, chord / 2)), size: SIMD3(w, 0.05, chord), color: col)
            }
            return mb.node([paint])
        }
        func place(_ n: SCNNode, _ p: SIMD3<Float>, _ child: SCNNode, yaw: Float = 0) {
            n.simdPosition = p
            let holder = SCNNode(); holder.simdEulerAngles = SIMD3(0, yaw, 0)
            holder.addChildNode(child); n.addChildNode(holder)
            body.addChildNode(n)
        }
        let tipTE: Float = -1.95 + 0.35 * 0.85 + mixf(1.75, 1.05, 0.8)
        place(aileronL, SIMD3(-3.7, -0.42 + 3.7 * 0.085, tipTE - 0.05), plate(1.7, 0.32, white), yaw: -0.03)
        place(aileronR, SIMD3(3.7, -0.42 + 3.7 * 0.085, tipTE - 0.05), plate(1.7, 0.32, white), yaw: 0.03)
        let rootTE: Float = -1.95 + 0.35 * 0.3 + mixf(1.75, 1.05, 0.3)
        place(flapL, SIMD3(-1.75, -0.42 + 1.75 * 0.085, rootTE - 0.05), plate(1.9, 0.34, white), yaw: -0.02)
        place(flapR, SIMD3(1.75, -0.42 + 1.75 * 0.085, rootTE - 0.05), plate(1.9, 0.34, white), yaw: 0.02)
        place(elevator, SIMD3(0, 0.3, 3.95), plate(3.0, 0.36, primary))
        place(rudder, SIMD3(0, 0.95, 4.05), plate(1.3, 0.4, primary, vertical: true))

        // Canopy + pilot
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = color(0.05, 0.09, 0.13, 1)
        glass.metalness.contents = 0.9
        glass.roughness.contents = 0.04
        glass.transparency = 0.55
        glass.isDoubleSided = true
        glass.transparencyMode = .dualLayer
        canopy = SCNNode(geometry: SCNSphere(radius: 1))
        canopy.geometry?.materials = [glass]
        canopy.simdScale = SIMD3(0.5, 0.42, 1.35)
        canopy.simdPosition = SIMD3(0, 0.66, -1.05)
        body.addChildNode(canopy)
        let helmet = SCNNode(geometry: SCNSphere(radius: 0.15))
        helmet.geometry?.materials = [Self.pbr(color(0.9, 0.9, 0.92), rough: 0.3)]
        helmet.simdPosition = SIMD3(0, 0.82, -0.95)
        let torso = SCNNode(geometry: SCNCapsule(capRadius: 0.2, height: 0.7))
        torso.geometry?.materials = [Self.pbr(color(0.2, 0.26, 0.2), rough: 0.8)]
        torso.simdPosition = SIMD3(0, 0.45, -0.85)
        pilot.addChildNode(helmet); pilot.addChildNode(torso)
        body.addChildNode(pilot)

        // Spinner + propeller
        let spinner = SCNNode(geometry: SCNCone(topRadius: 0.02, bottomRadius: 0.3, height: 0.55))
        spinner.geometry?.materials = [Self.pbr(NSColor(srgbRed: CGFloat(primary.x), green: CGFloat(primary.y), blue: CGFloat(primary.z), alpha: 1), rough: 0.25, metal: 0.2)]
        spinner.simdEulerAngles = SIMD3(-.pi / 2, 0, 0)
        spinner.simdPosition = SIMD3(0, 0, -0.25)
        prop.addChildNode(spinner)
        let bladeMat = Self.pbr(color(0.1, 0.1, 0.1), rough: 0.5)
        let tipMat = Self.pbr(color(0.95, 0.8, 0.1), rough: 0.4)
        for k in 0..<3 {
            let b = SCNNode(geometry: SCNBox(width: 0.13, height: 0.92, length: 0.035, chamferRadius: 0.015))
            b.geometry?.materials = [bladeMat]
            let tipN = SCNNode(geometry: SCNBox(width: 0.13, height: 0.1, length: 0.037, chamferRadius: 0.015))
            tipN.geometry?.materials = [tipMat]
            tipN.simdPosition = SIMD3(0, 0.48, 0)
            let arm = SCNNode()
            b.simdPosition = SIMD3(0, 0.5, 0)
            b.simdEulerAngles = SIMD3(0, 0.35, 0)
            b.addChildNode(tipN)
            arm.addChildNode(b)
            arm.simdEulerAngles = SIMD3(0, 0, Float(k) * 2 * .pi / 3)
            blades.addChildNode(arm)
        }
        prop.addChildNode(blades)
        let disc = propDisc
        disc.geometry = SCNCylinder(radius: 1.0, height: 0.01)
        let discMat = SCNMaterial()
        discMat.lightingModel = .constant
        discMat.diffuse.contents = makePixelImage(128, 128) { x, y in
            let dx = Float(x) / 64 - 1, dy = Float(y) / 64 - 1
            let r = sqrtf(dx * dx + dy * dy)
            let a: Float = r > 1 ? 0 : (r < 0.3 ? 0 : 0.22 + 0.3 * smoothstep(0.85, 0.95, r) * (1 - smoothstep(0.95, 1, r)))
            return SIMD4(0.15, 0.15, 0.15, a)
        }
        discMat.isDoubleSided = true
        discMat.writesToDepthBuffer = false
        disc.geometry?.materials = [discMat]
        disc.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
        disc.opacity = 0
        prop.addChildNode(disc)
        prop.simdPosition = SIMD3(0, 0.05, -3.6)
        body.addChildNode(prop)

        // Landing gear
        let strutMat = Self.pbr(color(0.75, 0.75, 0.78), rough: 0.25, metal: 0.9)
        let tyreMat = Self.pbr(color(0.05, 0.05, 0.05), rough: 0.85)
        let fairMat = paint
        func leg(_ n: SCNNode, at p: SIMD3<Float>, length: Float) {
            n.simdPosition = p
            let strut = SCNNode(geometry: SCNCylinder(radius: 0.045, height: CGFloat(length)))
            strut.geometry?.materials = [strutMat]
            strut.simdPosition = SIMD3(0, -length / 2, 0)
            n.addChildNode(strut)
            let wheel = SCNNode(geometry: SCNCylinder(radius: 0.27, height: 0.16))
            wheel.geometry?.materials = [tyreMat]
            wheel.simdEulerAngles = SIMD3(0, 0, .pi / 2)
            wheel.simdPosition = SIMD3(0, -length, 0)
            n.addChildNode(wheel)
            let fairing = SCNNode(geometry: SCNCapsule(capRadius: 0.16, height: 0.75))
            fairing.geometry?.materials = [fairMat]
            fairing.simdEulerAngles = SIMD3(.pi / 2, 0, 0)
            fairing.simdPosition = SIMD3(0, -length + 0.12, 0)
            fairing.simdScale = SIMD3(1, 1, 0.9)
            n.addChildNode(fairing)
            body.addChildNode(n)
        }
        leg(gearL, at: SIMD3(-1.35, -0.38, -1.25), length: 0.87)
        leg(gearR, at: SIMD3(1.35, -0.38, -1.25), length: 0.87)
        leg(gearNose, at: SIMD3(0, -0.4, -2.95), length: 0.85)

        // Navigation lights and strobe
        func light(_ m: SCNMaterial, _ p: SIMD3<Float>) {
            let s = SCNNode(geometry: SCNSphere(radius: 0.07))
            s.geometry?.materials = [m]
            s.simdPosition = p
            body.addChildNode(s)
        }
        let tipY: Float = -0.42 + 5.0 * 0.085
        light(navL, SIMD3(-5.03, tipY, -1.2))
        light(navR, SIMD3(5.03, tipY, -1.2))
        light(strobe, SIMD3(0, 1.62, 3.55))
        tipL.simdPosition = SIMD3(-5.0, tipY, -0.8)
        tipR.simdPosition = SIMD3(5.0, tipY, -0.8)
        tail.simdPosition = SIMD3(0, 0.2, 4.2)
        body.addChildNode(tipL); body.addChildNode(tipR); body.addChildNode(tail)

        node.addChildNode(body)
        body.enumerateHierarchy { n, _ in n.castsShadow = true }
        canopy.castsShadow = false
    }

    func update(dt: Float, rpm: Float, pitch: Float, roll: Float, yaw: Float, flap: Float, gear: Float, time: Double) {
        propAngle += rpm * 150 * dt
        if propAngle > 1000 { propAngle -= 2 * .pi * 100 }
        prop.simdEulerAngles = SIMD3(0, 0, -propAngle)
        let blur = smoothstep(0.12, 0.3, rpm)
        blades.opacity = CGFloat(1 - blur * 0.85)
        propDisc.opacity = CGFloat(blur)

        aileronL.simdEulerAngles = SIMD3(roll * 0.35, 0, 0)
        aileronR.simdEulerAngles = SIMD3(-roll * 0.35, 0, 0)
        elevator.simdEulerAngles = SIMD3(-pitch * 0.4, 0, 0)
        rudder.simdEulerAngles = SIMD3(0, yaw * 0.4, 0)
        flapL.simdEulerAngles = SIMD3(flap * 0.55, 0, 0)
        flapR.simdEulerAngles = SIMD3(flap * 0.55, 0, 0)
        gearNose.simdEulerAngles = SIMD3(-(1 - gear) * 1.6, -yaw * 0.3 * gear, 0)
        gearL.simdEulerAngles = SIMD3(0, 0, (1 - gear) * 1.55)
        gearR.simdEulerAngles = SIMD3(0, 0, -(1 - gear) * 1.55)
        let hidden = gear < 0.02
        gearNose.isHidden = hidden; gearL.isHidden = hidden; gearR.isHidden = hidden

        let ph = time.truncatingRemainder(dividingBy: 1.3)
        strobe.emission.intensity = ph < 0.06 || (ph > 0.14 && ph < 0.2) ? 6 : 0.05
        strobe.diffuse.intensity = strobe.emission.intensity > 1 ? 1 : 0.1
    }
}
