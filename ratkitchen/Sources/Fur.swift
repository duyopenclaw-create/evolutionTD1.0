import SceneKit
import simd

/// Shell-texturing fur: a few slightly inflated, alpha-masked copies of a body part.
enum Fur {
    static let levels = 4
    static let masks: [CGImage] = (0..<levels).map { i in
        let thr = 0.18 + Float(i) * 0.17
        return makePixelImage(512, 512) { x, y in
            // hair cells 2 px across, 5 px along the hair direction
            let cx = x / 2, cy = y / 5
            let h = Noise.cell(cx, cy, 311)
            guard h > thr else { return SIMD4(1, 1, 1, 0) }
            let fx = (Float(x % 2) + 0.5) / 2 - 0.5, fy = (Float(y % 5) + 0.5) / 5 - 0.5
            let a = max(0, 1 - (fx * fx + fy * fy) * 3.2)
            return SIMD4(1, 1, 1, a)
        }
    }

    /// Adds shells as children of `node` (which already carries `geo`).
    static func grow(on node: SCNNode, geo: SCNGeometry, base: SCNMaterial, depth: Float, repeatUV: CGFloat, tipTint: CGFloat = 1.15) {
        for i in 0..<levels {
            let k = Float(i + 1) / Float(levels)
            let g = geo.copy() as! SCNGeometry
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = base.diffuse.contents
            m.diffuse.contentsTransform = base.diffuse.contentsTransform
            m.multiply.contents = NSColor(white: min(1, 0.8 + CGFloat(k) * (tipTint - 0.8)), alpha: 1)
            m.roughness.contents = NSNumber(value: 0.85)
            m.metalness.contents = NSNumber(value: 0)
            m.transparent.contents = masks[i]
            m.transparent.contentsTransform = SCNMatrix4MakeScale(repeatUV, repeatUV, 1)
            m.transparent.wrapS = .repeat
            m.transparent.wrapT = .repeat
            m.transparencyMode = .aOne
            m.blendMode = .alpha
            m.writesToDepthBuffer = false
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            g.materials = [m]
            let s = SCNNode(geometry: g)
            let sc = 1 + depth * k
            s.simdScale = SIMD3(repeating: sc)
            s.castsShadow = false
            s.renderingOrder = 10 + i
            node.addChildNode(s)
        }
    }
}

/// Helper: an ellipsoid whose texture poles run along local z (so hair and stripes run nose-to-tail).
func ellipsoid(_ rx: Float, _ ry: Float, _ rz: Float, _ m: SCNMaterial, segments: Int = 36) -> (SCNNode, SCNGeometry) {
    let g = SCNSphere(radius: 1)
    g.segmentCount = segments
    g.materials = [m]
    let inner = SCNNode(geometry: g)
    inner.simdEulerAngles.x = .pi / 2
    inner.simdScale = SIMD3(rx, rz, ry)
    let outer = SCNNode()
    outer.addChildNode(inner)
    return (outer, g)
}
