import Cocoa
import SceneKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var view: GameView!
    var game: Game!
    let args = CommandLine.arguments

    func arg(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    func vec(_ name: String) -> SIMD3<Float>? {
        guard let s = arg(name) else { return nil }
        let p = s.split(separator: ",").compactMap { Float($0) }
        return p.count == 3 ? SIMD3(p[0], p[1], p[2]) : nil
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        let w = CGFloat(Double(arg("--width") ?? "") ?? 1440), h = CGFloat(Double(arg("--height") ?? "") ?? 900)
        let frame = NSRect(x: 0, y: 0, width: w, height: h)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Scurry"
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 960, height: 600)
        window.center()
        view = GameView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        if arg("--shot") != nil { SaveData.disabled = true }
        game = Game(view: view, muted: args.contains("--mute"))
        window.contentView = view
        window.delegate = self
        if arg("--shot") != nil {
            window.orderFrontRegardless()   // test captures: never steal keyboard focus
        } else {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps: true)
        }
        if args.contains("--stats") { view.showsStatistics = true }
        if args.contains("--autotest") { game.autotest(); NSApp.terminate(nil) }
        devHooks()
    }

    /// Flags used for automated screenshots while developing.
    private func devHooks() {
        if arg("--shot") != nil { game.ignoreInput = true }
        if args.contains("--start") || vec("--pos") != nil {
            game.devStart(pos: vec("--pos"), yaw: arg("--yaw").flatMap(Float.init))
        }
        game.devCamera(yaw: arg("--camyaw").flatMap(Float.init), pitch: arg("--campitch").flatMap(Float.init), dist: arg("--dist").flatMap(Float.init))
        if arg("--camyaw") == nil && arg("--campitch") == nil && arg("--dist") == nil { game.devCamera(yaw: nil, pitch: nil, dist: nil) }
        if args.contains("--human") { game.devHuman() }
        if let t = arg("--time").flatMap(Float.init) { game.devTime(t) }
        if args.contains("--chase") { game.devCatChase() }
        if let c = vec("--catpos") { game.devCatPos(c, yaw: arg("--catyaw").flatMap(Float.init) ?? 0) }
        if args.contains("--fp") { game.devFirstPerson() }
        if args.contains("--summary") { game.devSummary() }
        if args.contains("--sniff") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.game.devSniff() } }
        if let path = arg("--shot") {
            let delay = Double(arg("--delay") ?? "5") ?? 5
            func attempt(_ n: Int) {
                let img = self.view.snapshot()
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]),
                   (try? png.write(to: URL(fileURLWithPath: path))) != nil {
                    NSApp.terminate(nil)
                } else if n < 6 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { attempt(n + 1) }
                } else {
                    NSLog("Scurry: snapshot failed")
                    NSApp.terminate(nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { attempt(0) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowDidResignKey(_ notification: Notification) { view?.input.clear() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Scurry", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Scurry", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Scurry", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"))
        viewItem.submenu = viewMenu
        NSApp.mainMenu = main
    }
}

enum IconMaker {
    /// Renders the app icon into an .iconset folder (the build script turns it into AppIcon.icns).
    static func run(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for s in [16, 32, 64, 128, 256, 512, 1024] {
            let img = draw(s)
            if s <= 512 { savePNG(img, to: "\(dir)/icon_\(s)x\(s).png") }
            if s >= 32 { savePNG(img, to: "\(dir)/icon_\(s / 2)x\(s / 2)@2x.png") }
        }
    }

    /// A rat silhouette in a moonlit baseboard hole.
    static func draw(_ size: Int) -> CGImage {
        makeImage(size, size) { ctx in
            let S = CGFloat(size)
            let inset = S * 0.08
            let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: S * 0.2, cornerHeight: S * 0.2, transform: nil))
            ctx.clip()
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let wall = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.08, green: 0.1, blue: 0.18, alpha: 1),
                                                            CGColor(srgbRed: 0.22, green: 0.26, blue: 0.38, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(wall, start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: S - inset), options: [])
            // floor + baseboard
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.09, blue: 0.08, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S * 0.3))
            ctx.setFillColor(CGColor(srgbRed: 0.75, green: 0.74, blue: 0.7, alpha: 1))
            ctx.fill(CGRect(x: 0, y: S * 0.3, width: S, height: S * 0.14))
            // hole with warm glow
            let hole = CGMutablePath()
            hole.move(to: CGPoint(x: S * 0.3, y: S * 0.3))
            hole.addLine(to: CGPoint(x: S * 0.3, y: S * 0.48))
            hole.addArc(center: CGPoint(x: S * 0.5, y: S * 0.48), radius: S * 0.2, startAngle: .pi, endAngle: 0, clockwise: true)
            hole.addLine(to: CGPoint(x: S * 0.7, y: S * 0.3))
            hole.closeSubpath()
            ctx.addPath(hole)
            ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.015, blue: 0.01, alpha: 1))
            ctx.fillPath()
            // two eyes glinting in the dark
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.5, alpha: 1))
            for x in [0.44, 0.56] as [CGFloat] { ctx.fillEllipse(in: CGRect(x: S * x - S * 0.025, y: S * 0.47, width: S * 0.05, height: S * 0.05)) }
            // tail curling out onto the floor
            ctx.setStrokeColor(CGColor(srgbRed: 0.8, green: 0.6, blue: 0.55, alpha: 1))
            ctx.setLineWidth(S * 0.025)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: S * 0.62, y: S * 0.31))
            ctx.addCurve(to: CGPoint(x: S * 0.86, y: S * 0.2), control1: CGPoint(x: S * 0.72, y: S * 0.22), control2: CGPoint(x: S * 0.8, y: S * 0.3))
            ctx.strokePath()
        }
    }
}
