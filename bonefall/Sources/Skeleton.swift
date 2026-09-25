import CoreGraphics
import simd

/// Body regions. The ragdoll feels hits per region; each region holds real bones.
enum Region: Int, CaseIterable {
    case skull, jaw, neck, lClav, rClav, ribs, spine, pelvis, lHum, rHum, lFore, rFore, lHand, rHand, lFem, rFem, lShin, rShin, lFoot, rFoot

    var name: String {
        ["Skull", "Jaw", "Neck", "Left Shoulder", "Right Shoulder", "Ribcage", "Spine", "Pelvis",
         "Left Upper Arm", "Right Upper Arm", "Left Forearm", "Right Forearm", "Left Hand", "Right Hand",
         "Left Thigh", "Right Thigh", "Left Shin", "Right Shin", "Left Foot", "Right Foot"][rawValue]
    }
    var neighbours: [Region] {
        switch self {
        case .skull: return [.jaw, .neck]
        case .jaw: return [.skull, .neck]
        case .neck: return [.skull, .spine, .lClav, .rClav]
        case .lClav: return [.neck, .ribs, .lHum]
        case .rClav: return [.neck, .ribs, .rHum]
        case .ribs: return [.spine, .lClav, .rClav]
        case .spine: return [.neck, .ribs, .pelvis]
        case .pelvis: return [.spine, .lFem, .rFem]
        case .lHum: return [.lClav, .lFore]
        case .rHum: return [.rClav, .rFore]
        case .lFore: return [.lHum, .lHand]
        case .rFore: return [.rHum, .rHand]
        case .lHand: return [.lFore]
        case .rHand: return [.rFore]
        case .lFem: return [.pelvis, .lShin]
        case .rFem: return [.pelvis, .rShin]
        case .lShin: return [.lFem, .lFoot]
        case .rShin: return [.rFem, .rFoot]
        case .lFoot: return [.lShin]
        case .rFoot: return [.rShin]
        }
    }
    var side: Float {
        switch self {
        case .lClav, .lHum, .lFore, .lHand, .lFem, .lShin, .lFoot: return 1
        case .rClav, .rHum, .rFore, .rHand, .rFem, .rShin, .rFoot: return -1
        default: return 0
        }
    }
}

enum BoneKind { case cranial, facial, ossicle, mandible, hyoid, cervical, thoracic, lumbar, sacrum, coccyx, rib, sternum, clavicle, scapula, hip,
                humerus, radius, ulna, carpal, metacarpal, phalanx, femur, patella, tibia, fibula, tarsal, metatarsal }

struct BoneDef {
    let name: String
    let region: Region
    let kind: BoneKind
    let order: Int          // position along the spine / rib row / finger number
    let side: Float         // +1 left, -1 right, 0 middle
    let value: Float
    let fragility: Float
    let path: CGPath        // X-ray outline (front view; the body's left is on the viewer's right)
    let center: CGPoint
    let z: CGFloat
}

enum Skeleton {
    static let bones: [BoneDef] = build()
    static let byRegion: [[Int]] = {
        var r = [[Int]](repeating: [], count: Region.allCases.count)
        for (i, b) in bones.enumerated() { r[b.region.rawValue].append(i) }
        return r
    }()
    static let regionCenter: [CGPoint] = byRegion.map { ids in
        let s = ids.reduce(CGPoint.zero) { CGPoint(x: $0.x + bones[$1].center.x, y: $0.y + bones[$1].center.y) }
        return CGPoint(x: s.x / CGFloat(max(1, ids.count)), y: s.y / CGFloat(max(1, ids.count)))
    }
    /// Dark cut-outs drawn over the X-ray (eye sockets, nasal cavity, pelvic holes).
    static let decorations: [CGPath] = {
        var d: [CGPath] = []
        for s in [CGFloat(-1), 1] {
            d.append(CGPath(ellipseIn: CGRect(x: s * 12 - 8.5, y: 162, width: 17, height: 15), transform: nil))
            d.append(CGPath(ellipseIn: CGRect(x: s * 22 - 7, y: -52, width: 14, height: 18), transform: nil))
        }
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 0, y: 163)); nose.addLine(to: CGPoint(x: -6, y: 147)); nose.addLine(to: CGPoint(x: 6, y: 147)); nose.closeSubpath()
        d.append(nose)
        return d
    }()

    // MARK: geometry helpers

    static func longBone(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let dx = b.x - a.x, dy = b.y - a.y
        let L = max(1, hypot(dx, dy))
        let t = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(dy, dx))
        p.addRoundedRect(in: CGRect(x: 0, y: -w / 2, width: L, height: w), cornerWidth: w / 2 - 0.05, cornerHeight: w / 2 - 0.05, transform: t)
        if w > 4 {
            for e in [CGFloat(0), L] {
                for s in [CGFloat(-1), 1] {
                    p.addEllipse(in: CGRect(x: e - w * 0.55, y: s * w * 0.32 - w * 0.5, width: w * 1.1, height: w), transform: t)
                }
            }
        }
        return p
    }
    static func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), transform: nil)
    }
    static func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 1.5) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: min(r, w / 2 - 0.01), cornerHeight: min(r, h / 2 - 0.01), transform: nil)
    }
    static func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }
    static func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGPath {
        CGPath(rect: CGRect(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0)), transform: nil)
    }

    // MARK: the 206 bones

    private static func build() -> [BoneDef] {
        var out: [BoneDef] = []
        func add(_ name: String, _ r: Region, _ k: BoneKind, _ value: Float, _ frag: Float, _ path: CGPath, order: Int = 0, side: Float = 0, z: CGFloat = 0) {
            let bb = path.boundingBoxOfPath
            out.append(BoneDef(name: name, region: r, kind: k, order: order, side: side, value: value, fragility: frag, path: path,
                               center: CGPoint(x: bb.midX, y: bb.midY), z: z))
        }
        let LR: [(CGFloat, String, Float)] = [(1, "Left", 1), (-1, "Right", -1)]

        // Skull: 8 cranial, 13 facial (not counting the mandible), 6 ear ossicles = 27
        let E = CGPath(ellipseIn: CGRect(x: -32, y: 148, width: 64, height: 80), transform: nil)
        add("Frontal Bone", .skull, .cranial, 3, 0.85, E.intersection(rect(-19, 178, 19, 216)), order: 0)
        add("Occipital Bone", .skull, .cranial, 3, 0.85, E.intersection(rect(-33, 216, 33, 230)), order: 1)
        for (s, n, sd) in LR {
            add("\(n) Parietal Bone", .skull, .cranial, 3, 0.85, E.intersection(rect(s * 19, 178, s * 33, 216)), order: 2, side: sd)
            add("\(n) Temporal Bone", .skull, .cranial, 3, 0.9, E.intersection(rect(s * 17, 148, s * 33, 178)), order: 3, side: sd)
        }
        let sph = CGMutablePath(); sph.addPath(ellipse(20, 177, 8, 5)); sph.addPath(ellipse(-20, 177, 8, 5))
        add("Sphenoid Bone", .skull, .cranial, 3, 0.9, sph, order: 4, z: 2)
        add("Ethmoid Bone", .skull, .cranial, 3, 1, rrect(-3, 163, 6, 9), order: 5, z: 2)
        let faceClip = E.intersection(rect(-18, 136, 18, 178))
        for (s, n, sd) in LR {
            add("\(n) Nasal Bone", .skull, .facial, 1.5, 1.4, rrect(s > 0 ? 0.6 : -4.6, 157, 4, 9, 1.5), side: sd, z: 3)
            add("\(n) Lacrimal Bone", .skull, .facial, 1.5, 1.5, ellipse(s * 4.8, 168, 3, 4.5), side: sd, z: 3)
            add("\(n) Zygomatic Bone", .skull, .facial, 1.5, 1.2, ellipse(s * 22, 157, 13, 8), side: sd, z: 3)
            add("\(n) Maxilla", .skull, .facial, 1.5, 1.1, faceClip.intersection(rrect(s > 0 ? 1 : -17, 138, 16, 13, 4)), side: sd, z: 2)
            add("\(n) Palatine Bone", .skull, .facial, 1.5, 1.3, rrect(s > 0 ? 1.5 : -7.5, 136, 6, 3, 1), side: sd, z: 3)
            add("\(n) Inferior Nasal Concha", .skull, .facial, 1.5, 1.5, ellipse(s * 2.6, 152, 2.6, 6), side: sd, z: 3)
        }
        add("Vomer", .skull, .facial, 1.5, 1.4, rrect(-0.9, 146, 1.8, 11, 0.8), z: 3)
        for (s, n, sd) in LR {
            add("\(n) Malleus", .skull, .ossicle, 3, 2, ellipse(s * 36, 172, 3.6, 3.6), order: 0, side: sd, z: 4)
            add("\(n) Incus", .skull, .ossicle, 3, 2, ellipse(s * 38.6, 168.5, 3.2, 3.2), order: 1, side: sd, z: 4)
            add("\(n) Stapes", .skull, .ossicle, 3, 2, ellipse(s * 41, 165, 2.8, 2.8), order: 2, side: sd, z: 4)
        }
        // Jaw: mandible + hyoid = 2
        let jaw = CGMutablePath()
        jaw.move(to: CGPoint(x: -27, y: 152)); jaw.addQuadCurve(to: CGPoint(x: 0, y: 118), control: CGPoint(x: -25, y: 116))
        jaw.addQuadCurve(to: CGPoint(x: 27, y: 152), control: CGPoint(x: 25, y: 116))
        jaw.addLine(to: CGPoint(x: 19, y: 152)); jaw.addQuadCurve(to: CGPoint(x: 0, y: 127), control: CGPoint(x: 17, y: 126))
        jaw.addQuadCurve(to: CGPoint(x: -19, y: 152), control: CGPoint(x: -17, y: 126)); jaw.closeSubpath()
        add("Mandible", .jaw, .mandible, 3, 1, jaw, z: 2)
        let hy = CGMutablePath(); hy.move(to: CGPoint(x: -10, y: 114)); hy.addQuadCurve(to: CGPoint(x: 10, y: 114), control: CGPoint(x: 0, y: 106))
        add("Hyoid Bone", .jaw, .hyoid, 2, 1.3, hy.copy(strokingWithWidth: 3, lineCap: .round, lineJoin: .round, miterLimit: 2), z: 3)

        // Spine: 7 cervical, 12 thoracic, 5 lumbar, sacrum, coccyx = 26
        for k in 0..<7 { add("C\(k + 1) Vertebra", .neck, .cervical, 1.5, 0.95, rrect(-8, 126 - CGFloat(k) * 3.8 - 3.2, 16, 3.2, 1), order: k) }
        for k in 0..<12 { add("T\(k + 1) Vertebra", .spine, .thoracic, 1.5, 0.9, rrect(-9, 99 - CGFloat(k) * 6.4 - 5.2, 18, 5.2, 1.5), order: k, z: 1) }
        for k in 0..<5 { add("L\(k + 1) Vertebra", .spine, .lumbar, 1.5, 0.85, rrect(-10.5, 22 - CGFloat(k) * 7 - 6, 21, 6, 2), order: 12 + k, z: 1) }
        let sacrum = poly([(-11, -13), (11, -13), (0, -40)])
        add("Sacrum", .pelvis, .sacrum, 3, 0.8, sacrum, z: 1)
        add("Coccyx", .pelvis, .coccyx, 2, 1.2, poly([(-3.5, -41), (3.5, -41), (0, -50)]), z: 1)

        // Ribcage: 24 ribs + sternum = 25
        for (s, n, sd) in LR {
            for k in 0..<12 {
                let y = 90 - CGFloat(k) * 5.6
                var w = 34 + CGFloat(min(k, 5)) * 4 - CGFloat(max(0, k - 7)) * 3
                if k >= 10 { w *= 0.72 }
                let arc = CGMutablePath()
                arc.move(to: CGPoint(x: s * 5, y: y))
                arc.addQuadCurve(to: CGPoint(x: s * w * 0.95, y: y - 12), control: CGPoint(x: s * w * 1.08, y: y + 5))
                add("\(n) Rib \(k + 1)", .ribs, .rib, 1.2, 1.25, arc.copy(strokingWithWidth: 3.2, lineCap: .round, lineJoin: .round, miterLimit: 2), order: k, side: sd)
            }
        }
        add("Sternum", .ribs, .sternum, 2, 1, rrect(-4.5, 34, 9, 58, 4), z: 2)

        // Shoulder girdle: clavicles + scapulae = 4
        for (s, n, sd) in LR {
            let r: Region = s > 0 ? .lClav : .rClav
            add("\(n) Clavicle", r, .clavicle, 2.5, 1.3, longBone(CGPoint(x: s * 10, y: 98), CGPoint(x: s * 60, y: 104), 7), side: sd, z: 2)
            add("\(n) Scapula", r, .scapula, 2.5, 0.9, poly([(s * 40, 98), (s * 63, 97), (s * 47, 52)]), side: sd, z: -1)
        }

        // Pelvis: two hip bones (sacrum and coccyx are above) = 2
        let pel = CGMutablePath()
        pel.move(to: CGPoint(x: 0, y: -14))
        pel.addCurve(to: CGPoint(x: 58, y: -12), control1: CGPoint(x: 20, y: -2), control2: CGPoint(x: 50, y: 8))
        pel.addCurve(to: CGPoint(x: 28, y: -58), control1: CGPoint(x: 64, y: -34), control2: CGPoint(x: 44, y: -52))
        pel.addCurve(to: CGPoint(x: 0, y: -52), control1: CGPoint(x: 18, y: -62), control2: CGPoint(x: 8, y: -56))
        pel.addCurve(to: CGPoint(x: -28, y: -58), control1: CGPoint(x: -8, y: -56), control2: CGPoint(x: -18, y: -62))
        pel.addCurve(to: CGPoint(x: -58, y: -12), control1: CGPoint(x: -44, y: -52), control2: CGPoint(x: -64, y: -34))
        pel.addCurve(to: CGPoint(x: 0, y: -14), control1: CGPoint(x: -50, y: 8), control2: CGPoint(x: -20, y: -2))
        pel.closeSubpath()
        for (s, n, sd) in LR {
            add("\(n) Hip Bone", .pelvis, .hip, 4, 0.8, pel.intersection(rect(0, -70, s * 70, 20)).subtracting(sacrum), side: sd)
        }

        // Arms: humerus, radius, ulna, and 27 bones per hand
        let carpals1 = ["Scaphoid", "Lunate", "Triquetrum", "Pisiform"], carpals2 = ["Trapezium", "Trapezoid", "Capitate", "Hamate"]
        let fingers = ["Thumb", "Index", "Middle", "Ring", "Little"]
        for (s, n, sd) in LR {
            let hum: Region = s > 0 ? .lHum : .rHum, fore: Region = s > 0 ? .lFore : .rFore, hand: Region = s > 0 ? .lHand : .rHand
            add("\(n) Humerus", hum, .humerus, 4, 0.8, longBone(CGPoint(x: s * 66, y: 96), CGPoint(x: s * 80, y: 12), 10), side: sd)
            add("\(n) Radius", fore, .radius, 4, 1.05, longBone(CGPoint(x: s * 86, y: 6), CGPoint(x: s * 97, y: -70), 6), side: sd)
            add("\(n) Ulna", fore, .ulna, 4, 1.05, longBone(CGPoint(x: s * 77, y: 8), CGPoint(x: s * 86, y: -72), 5.5), side: sd)
            for (k, nm) in carpals1.enumerated() {
                add("\(n) \(nm)", hand, .carpal, 0.8, 1.4, ellipse(s * (99.5 - CGFloat(k) * 5), -79, 5, 5), order: k, side: sd, z: 1)
            }
            for (k, nm) in carpals2.enumerated() {
                add("\(n) \(nm)", hand, .carpal, 0.8, 1.4, ellipse(s * (101 - CGFloat(k) * 5), -86, 5, 5), order: 4 + k, side: sd, z: 1)
            }
            for i in 1...5 {
                let fx = 92 + CGFloat(3 - i) * 4.5
                if i == 1 {
                    add("\(n) \(fingers[0]) Metacarpal", hand, .metacarpal, 0.8, 1.3, longBone(CGPoint(x: s * 103, y: -90), CGPoint(x: s * 109, y: -101), 3.2), order: 1, side: sd)
                    add("\(n) \(fingers[0]) Proximal Phalanx", hand, .phalanx, 0.6, 1.5, longBone(CGPoint(x: s * 109.6, y: -102.5), CGPoint(x: s * 113.5, y: -110), 2.8), order: 1, side: sd)
                    add("\(n) \(fingers[0]) Distal Phalanx", hand, .phalanx, 0.6, 1.5, longBone(CGPoint(x: s * 114, y: -111.5), CGPoint(x: s * 116.3, y: -116.5), 2.6), order: 1, side: sd)
                } else {
                    let tip = CGFloat(i == 3 ? 1.5 : (i == 5 ? -2 : 0))
                    let spread = CGFloat(3 - i) * 0.9
                    add("\(n) \(fingers[i - 1]) Metacarpal", hand, .metacarpal, 0.8, 1.3, longBone(CGPoint(x: s * fx, y: -91), CGPoint(x: s * (fx + spread), y: -105), 2.8), order: i, side: sd)
                    add("\(n) \(fingers[i - 1]) Proximal Phalanx", hand, .phalanx, 0.6, 1.5, longBone(CGPoint(x: s * (fx + spread), y: -106.5), CGPoint(x: s * (fx + spread * 1.7), y: -115 - tip), 2.6), order: i, side: sd)
                    add("\(n) \(fingers[i - 1]) Middle Phalanx", hand, .phalanx, 0.6, 1.5, longBone(CGPoint(x: s * (fx + spread * 1.75), y: -116.5 - tip), CGPoint(x: s * (fx + spread * 2.1), y: -122 - tip * 1.5), 2.4), order: i, side: sd)
                    add("\(n) \(fingers[i - 1]) Distal Phalanx", hand, .phalanx, 0.6, 1.5, longBone(CGPoint(x: s * (fx + spread * 2.15), y: -123.5 - tip * 1.5), CGPoint(x: s * (fx + spread * 2.35), y: -127.5 - tip * 1.7), 2.2), order: i, side: sd)
                }
            }
        }

        // Legs: femur, patella, tibia, fibula, and 26 bones per foot
        let toes = ["Big Toe", "2nd Toe", "3rd Toe", "4th Toe", "Little Toe"]
        for (s, n, sd) in LR {
            let fem: Region = s > 0 ? .lFem : .rFem, shin: Region = s > 0 ? .lShin : .rShin, foot: Region = s > 0 ? .lFoot : .rFoot
            add("\(n) Femur", fem, .femur, 4, 0.7, longBone(CGPoint(x: s * 34, y: -46), CGPoint(x: s * 38, y: -166), 13), side: sd)
            add("\(n) Patella", fem, .patella, 2, 1.1, ellipse(s * 38, -169, 10, 12), side: sd, z: 1)
            add("\(n) Tibia", shin, .tibia, 4, 0.9, longBone(CGPoint(x: s * 36, y: -178), CGPoint(x: s * 38, y: -284), 10), side: sd)
            add("\(n) Fibula", shin, .fibula, 4, 1.1, longBone(CGPoint(x: s * 50, y: -181), CGPoint(x: s * 50, y: -280), 4.5), side: sd)
            let tarsals: [(String, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                ("Talus", 42, -291, 11, 7, 1), ("Calcaneus", 47, -286, 10, 6, -1), ("Navicular", 37, -298, 8, 5, 1), ("Cuboid", 50, -299, 8, 6, 1),
                ("Medial Cuneiform", 31, -305, 5, 6, 1), ("Intermediate Cuneiform", 36.5, -305, 5, 6, 1), ("Lateral Cuneiform", 42, -305, 5, 6, 1)]
            for (k, t) in tarsals.enumerated() {
                add("\(n) \(t.0)", foot, .tarsal, 0.8, 1.2, ellipse(s * t.1, t.2, t.3, t.4), order: k, side: sd, z: t.5)
            }
            for i in 1...5 {
                let xb = 30 + CGFloat(i - 1) * 6.5
                let lean = CGFloat(i - 3) * 1.2
                add("\(n) \(toes[i - 1]) Metatarsal", foot, .metatarsal, 0.8, 1.25, longBone(CGPoint(x: s * xb, y: -309), CGPoint(x: s * (xb + lean), y: -322), i == 1 ? 4.5 : 3), order: i, side: sd)
                add("\(n) \(toes[i - 1]) Proximal Phalanx", foot, .phalanx, 0.6, 1.45, longBone(CGPoint(x: s * (xb + lean), y: -323.5), CGPoint(x: s * (xb + lean * 1.3), y: -329), i == 1 ? 4 : 2.6), order: i, side: sd)
                if i > 1 {
                    add("\(n) \(toes[i - 1]) Middle Phalanx", foot, .phalanx, 0.6, 1.5, longBone(CGPoint(x: s * (xb + lean * 1.35), y: -330.5), CGPoint(x: s * (xb + lean * 1.5), y: -333), 2.3), order: i, side: sd)
                    add("\(n) \(toes[i - 1]) Distal Phalanx", foot, .phalanx, 0.6, 1.5, longBone(CGPoint(x: s * (xb + lean * 1.55), y: -334.5), CGPoint(x: s * (xb + lean * 1.65), y: -337), 2.1), order: i, side: sd)
                } else {
                    add("\(n) \(toes[0]) Distal Phalanx", foot, .phalanx, 0.6, 1.45, longBone(CGPoint(x: s * (xb + lean * 1.35), y: -330.5), CGPoint(x: s * (xb + lean * 1.45), y: -335.5), 3.6), order: i, side: sd)
                }
            }
        }
        return out
    }
}
