import Foundation
import simd

enum FlightEvent {
    case touchdown(fpm: Double, surface: Surface)
    case liftoff
    case crash(water: Bool, reason: String)
    case tailStrike
}

/// Rigid-body flight model of a light sport monoplane (≈ 1150 kg, 10 m span).
/// Axes: body -Z forward, +Y up, +X right. World Y up, north = -Z.
final class FlightModel {
    // Airframe
    let mass = 1150.0
    let wingArea = 16.2
    let gearHeight = 1.52       // CG above ground with gear down
    let bellyHeight = 0.72
    let staticThrust = 5700.0
    let propVmax = 150.0

    // State
    var pos = SIMD3<Double>(0, 0, 0)
    var vel = SIMD3<Double>(0, 0, 0)
    var q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    var omega = SIMD3<Double>(0, 0, 0)   // body rates: x pitch(up+), y yaw(left+), z roll(left+)

    // Systems
    var engineOn = false
    var throttle = 0.0
    var rpm = 0.0
    var flapSetting = 0                  // 0...3 → 0/10/20/30°
    var flap = 0.0
    var gearDown = true
    var gearPos = 1.0
    var brake = false
    var assist = true                    // gentle wing-leveller for keyboard pilots

    // Smoothed controls
    var inPitch = 0.0, inRoll = 0.0, inYaw = 0.0

    // Derived / status
    var onGround = true
    var crashed = false
    var alpha = 0.0, beta = 0.0, airspeed = 0.0, gLoad = 1.0
    var stallWarning = 0.0
    var stalled = false
    var surface: Surface = .paved
    var agl = 0.0
    var events: [FlightEvent] = []
    var groundBump = 0.0

    private var stallRollSign = 1.0
    private var turbT = 0.0

    var ground: (Double, Double) -> (Double, Surface) = { _, _ in (0, .paved) }

    var forward: SIMD3<Double> { q.act(SIMD3(0, 0, -1)) }
    var up: SIMD3<Double> { q.act(SIMD3(0, 1, 0)) }
    var right: SIMD3<Double> { q.act(SIMD3(1, 0, 0)) }

    /// heading (0 = north, clockwise +), pitch (nose up +), roll (right wing down +)
    var euler: (heading: Double, pitch: Double, roll: Double) {
        let f = forward, r = right, u = up
        return (atan2(f.x, -f.z), asin(clampd(f.y, -1, 1)), atan2(-r.y, u.y))
    }

    static func quat(heading: Double, pitch: Double, roll: Double) -> simd_quatd {
        simd_quatd(angle: -heading, axis: SIMD3(0, 1, 0))
            * simd_quatd(angle: pitch, axis: SIMD3(1, 0, 0))
            * simd_quatd(angle: -roll, axis: SIMD3(0, 0, 1))
    }

    func reset(position: SIMD3<Double>, heading: Double, speed: Double, onRunway: Bool) {
        pos = position
        q = Self.quat(heading: heading, pitch: 0, roll: 0)
        vel = forward * speed
        omega = .zero
        crashed = false
        onGround = onRunway
        engineOn = !onRunway || engineOn
        throttle = onRunway ? 0 : 0.62
        rpm = onRunway ? (engineOn ? 0.08 : 0) : 0.6
        gearDown = onRunway
        gearPos = onRunway ? 1 : 0
        flapSetting = 0
        flap = 0
        inPitch = 0; inRoll = 0; inYaw = 0
        events.removeAll()
        stalled = false
    }

    func step(_ dt: Double, pitch cmdPitch: Double, roll cmdRoll: Double, yaw cmdYaw: Double) {
        if crashed { return }
        let k = 1 - exp(-dt * 7)
        inPitch += (cmdPitch - inPitch) * k
        inRoll += (cmdRoll - inRoll) * k
        inYaw += (cmdYaw - inYaw) * k

        // Engine spools toward throttle (idle 8 %)
        let rpmTarget = engineOn ? 0.08 + 0.92 * throttle : 0
        rpm += (rpmTarget - rpm) * (1 - exp(-dt * (engineOn ? 1.6 : 0.5)))

        // Flaps & gear actuators
        let flapTarget = Double(flapSetting) / 3
        flap += clampd(flapTarget - flap, -dt * 0.3, dt * 0.3)
        if onGround { gearDown = true }
        gearPos += clampd((gearDown ? 1 : 0) - gearPos, -dt * 0.45, dt * 0.45)

        let fwd = forward, upv = up, rgt = right
        let V = simd_length(vel)
        let rho = 1.225 * exp(-max(pos.y, 0) / 8500)
        let qbar = 0.5 * rho * V * V
        let vl = q.inverse.act(vel)
        if V > 1 {
            alpha = atan2(-vl.y, -vl.z)
            beta = atan2(vl.x, -vl.z)
        } else {
            alpha = 0; beta = 0
        }
        airspeed = V

        // Lift curve with stall break
        let stallA = 0.27 - 0.035 * flap
        let cl0 = 0.3 + 0.5 * flap
        let cla = 5.2
        let clMax = cl0 + cla * stallA
        let a = clampd(alpha, -.pi / 2, .pi / 2)
        var CL: Double
        if a > stallA {
            CL = max(clMax - (a - stallA) * 3.2, 0.95 * sin(2 * a))
        } else if a < -0.24 {
            CL = min(cl0 - cla * 0.24 + (-0.24 - a) * 3.2, 0.95 * sin(2 * a))
        } else {
            CL = cl0 + cla * a
        }
        stalled = !onGround && V > 8 && a > stallA
        stallWarning = onGround || V < 8 ? 0 : Double(smoothstep(Float(stallA - 0.07), Float(stallA - 0.01), Float(a)))

        // Ground effect: less induced drag in the last half-wingspan
        let ge = agl < 8 ? 0.55 + 0.45 * agl / 8 : 1
        let CD = 0.026 + 0.02 * gearPos + 0.055 * flap * flap + 0.045 * CL * CL * ge
            + 0.9 * sin(a) * sin(a) + 0.6 * sin(beta) * sin(beta)

        var F = SIMD3<Double>(0, -mass * 9.81, 0)
        if V > 0.5 {
            let vDir = vel / V
            var liftDir = simd_cross(rgt, vDir)
            let ln = simd_length(liftDir)
            if ln > 1e-3 {
                liftDir /= ln
                F += liftDir * qbar * wingArea * CL
            }
            F += -vDir * qbar * wingArea * CD
            F += rgt * (-qbar * wingArea * 0.9 * sin(beta))
        }
        let prop = max(0, (rpm - 0.08) / 0.92)
        let thrust = staticThrust * pow(prop, 1.25) * max(0, 1 - max(0, -vl.z) / propVmax)
        F += fwd * thrust

        // Light turbulence aloft
        turbT += dt
        if !onGround {
            let tb = 0.018 * qbar * wingArea * min(1, max(pos.y - 30, 0) / 200)
            F += upv * tb * (sin(turbT * 1.7) * 0.6 + sin(turbT * 4.3 + 1) * 0.4) * 0.05
        }

        // Rotational dynamics (accelerations, rad/s²)
        let eff = min(qbar / 1900, 2.2)
        let effD = min(V / 55, 2.2)
        let wash = 0.45 * prop * max(0, 1 - V / 40)
        let ac = clampd(alpha, -0.6, 0.6)
        var acc = SIMD3<Double>.zero
        acc.x = inPitch * 2.2 * (eff + wash) - 3.8 * ac * eff - 3.0 * (alpha - ac) * eff - 2.9 * omega.x * (effD + 0.15)
        if a > stallA { acc.x -= (a - stallA) * 5 * eff }
        acc.y = -inYaw * 1.3 * (eff + wash) - 3.4 * beta * eff - 2.3 * omega.y * (effD + 0.2)
        acc.z = -inRoll * 5.2 * eff - 3.4 * omega.z * (effD + 0.1) + 0.9 * beta * eff
        if assist && abs(inRoll) < 0.1 && !onGround {
            let r = euler.roll
            if abs(r) < 1.2 { acc.z += 1.1 * sin(r) * min(eff, 1.2) }
        }
        if stalled {
            if Int(turbT * 0.7) % 2 == 0 { stallRollSign = inRoll >= 0 ? -1 : 1 }
            acc.z += stallRollSign * 1.4 * eff * min(1, (a - stallA) * 8)
            acc.x += sin(turbT * 23) * 0.6 * eff
        }
        omega += acc * dt
        let wl = simd_length(omega)
        if wl > 1e-9 {
            q = simd_normalize(q * simd_quatd(angle: wl * dt, axis: omega / wl))
        }

        let accLin = F / mass
        vel += accLin * dt
        pos += vel * dt
        gLoad = simd_dot(accLin + SIMD3(0, 9.81, 0), up) / 9.81

        groundContact(dt, liftF: F)
    }

    private func crash(_ reason: String, water: Bool) {
        crashed = true
        vel = .zero
        airspeed = 0
        gLoad = 1
        stallWarning = 0
        omega = .zero
        events.append(.crash(water: water, reason: reason))
    }

    private func groundContact(_ dt: Double, liftF: SIMD3<Double>) {
        let (gh, surf) = ground(pos.x, pos.z)
        surface = surf
        let contactH = gearPos > 0.95 ? gearHeight : bellyHeight
        agl = pos.y - gh - contactH
        if surf == .water && pos.y < 0.6 {
            crash(simd_length(vel) > 25 ? "Ditched into the sea" : "Splashdown", water: true)
            return
        }
        if agl > 0.02 {
            if onGround { onGround = false; events.append(.liftoff) }
            return
        }
        var (hdg, pitch, roll) = euler
        let hSpeed = simd_length(SIMD2(vel.x, vel.z))
        if !onGround {
            let impact = -vel.y
            if impact > 5.5 { crash("Hard impact — \(Int(impact * 196.85)) ft/min", water: false); return }
            if abs(roll) > 0.38 { crash("Wingtip struck the ground", water: false); return }
            if pitch < -0.14 { crash("Nosed in", water: false); return }
            if gearPos < 0.95 && hSpeed > 14 { crash("Belly landing — gear was up!", water: false); return }
            events.append(.touchdown(fpm: impact * 196.85, surface: surf))
            onGround = true
        }
        if surf == .grass && hSpeed > 58 { crash("Ran off into rough terrain", water: false); return }
        pos.y = gh + contactH
        if vel.y < 0 { vel.y = 0 }

        // Keep wings level and nose wheel on the ground
        roll *= max(0, 1 - dt * 14)
        omega.z *= max(0, 1 - dt * 14)
        if pitch < 0 { pitch = 0; omega.x = max(omega.x, 0) }
        if pitch > 0.23 {
            pitch = 0.23
            omega.x = min(omega.x, 0)
            if hSpeed > 15 { events.append(.tailStrike) }
        }

        // Tyres: rolling resistance, brakes and side grip along the heading
        let hf = SIMD3<Double>(sin(hdg), 0, -cos(hdg))
        let hr = SIMD3<Double>(cos(hdg), 0, sin(hdg))
        var vf = simd_dot(vel, hf), vr = simd_dot(vel, hr)
        vr *= exp(-dt * 9)
        let normalF = max(0, -liftF.y)
        let mu = (surf == .paved ? 0.022 : 0.075) + (brake ? 0.6 : 0)
        let decel = mu * normalF / mass
        vf = vf >= 0 ? max(0, vf - decel * dt) : min(0, vf + decel * dt)
        vel = hf * vf + hr * vr + SIMD3(0, vel.y, 0)

        // Nose-wheel steering blends with rudder authority
        if pitch < 0.06 {
            let steer = -inYaw * 0.55 * min(1, hSpeed / 4) / (1 + hSpeed / 22)
            omega.y += (steer - omega.y) * min(1, dt * 10)
        }
        groundBump = surf == .grass ? min(1, hSpeed / 25) : min(0.35, hSpeed / 80)
        q = Self.quat(heading: hdg, pitch: pitch, roll: roll)
    }
}
