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

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMenu()
        let w = CGFloat(Double(arg("--width") ?? "") ?? 1440), h = CGFloat(Double(arg("--height") ?? "") ?? 900)
        let frame = NSRect(x: 0, y: 0, width: w, height: h)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Skybound"
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 960, height: 600)
        window.center()
        view = GameView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
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
        devHooks()
    }

    /// Flags used for automated screenshots while developing.
    private func devHooks() {
        if arg("--shot") != nil && !args.contains("--log") { game.ignoreInput = true }
        if let t = arg("--tod").flatMap(Int.init) { game.todIndex = t; game.applyTime(t) }
        if args.contains("--start") { game.startFlying() }
        if args.contains("--air") { game.startFlying(); game.airStart(course: true) }
        if args.contains("--summit") { game.startFlying(); game.airStart(course: false) }
        if let c = arg("--cam").flatMap(Int.init) {
            for _ in 0..<c { view.input.keyDown(Key.c, isRepeat: false) }
        }
        if let dp = arg("--dev-pitch").flatMap(Double.init) { game.devPitch = dp }
        if let throttle = arg("--throttle").flatMap(Double.init) { game.fm.throttle = throttle }
        if let path = arg("--shot") {
            let delay = Double(arg("--delay") ?? "6") ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let img = self.view.snapshot()
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                if let p2 = self.arg("--shot2") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + (Double(self.arg("--delay2") ?? "4") ?? 4)) {
                        let img2 = self.view.snapshot()
                        if let t2 = img2.tiffRepresentation, let r2 = NSBitmapImageRep(data: t2), let d2 = r2.representation(using: .png, properties: [:]) {
                            try? d2.write(to: URL(fileURLWithPath: p2))
                        }
                        NSApp.terminate(nil)
                    }
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowDidResignKey(_ notification: Notification) { view?.input.clear() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Skybound", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Skybound", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Skybound", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let fs = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenu.addItem(fs)
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

    static func draw(_ size: Int) -> CGImage {
        makeImage(size, size) { ctx in
            let S = CGFloat(size)
            let inset = S * 0.08
            let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
            let path = CGPath(roundedRect: rect, cornerWidth: S * 0.2, cornerHeight: S * 0.2, transform: nil)
            ctx.addPath(path)
            ctx.clip()
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let sky = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 1.0, green: 0.62, blue: 0.3, alpha: 1),
                                                           CGColor(srgbRed: 0.95, green: 0.45, blue: 0.4, alpha: 1),
                                                           CGColor(srgbRed: 0.2, green: 0.28, blue: 0.6, alpha: 1)] as CFArray,
                                 locations: [0, 0.35, 1])!
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: S - inset), options: [])
            // sun
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.93, blue: 0.7, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: S * 0.28, y: S * 0.26, width: S * 0.44, height: S * 0.44))
            // sea + island
            ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.2, blue: 0.38, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S * 0.34))
            ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.2, alpha: 1))
            let isl = CGMutablePath()
            isl.move(to: CGPoint(x: S * 0.05, y: S * 0.34))
            isl.addCurve(to: CGPoint(x: S * 0.62, y: S * 0.34), control1: CGPoint(x: S * 0.25, y: S * 0.52), control2: CGPoint(x: S * 0.4, y: S * 0.6))
            isl.closeSubpath()
            ctx.addPath(isl); ctx.fillPath()
            // plane silhouette, banking
            ctx.saveGState()
            ctx.translateBy(x: S * 0.54, y: S * 0.6)
            ctx.rotate(by: 0.32)
            ctx.scaleBy(x: S / 100, y: S / 100)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: -26, y: -3.5, width: 52, height: 7))            // fuselage
            p.move(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: 6, y: 0)); p.addLine(to: CGPoint(x: 2, y: 30)); p.addLine(to: CGPoint(x: -6, y: 30)); p.closeSubpath()
            p.move(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: 6, y: 0)); p.addLine(to: CGPoint(x: 2, y: -30)); p.addLine(to: CGPoint(x: -6, y: -30)); p.closeSubpath()
            p.move(to: CGPoint(x: -24, y: 0)); p.addLine(to: CGPoint(x: -18, y: 0)); p.addLine(to: CGPoint(x: -22, y: 11)); p.addLine(to: CGPoint(x: -27, y: 11)); p.closeSubpath()
            p.move(to: CGPoint(x: -24, y: 0)); p.addLine(to: CGPoint(x: -18, y: 0)); p.addLine(to: CGPoint(x: -22, y: -11)); p.addLine(to: CGPoint(x: -27, y: -11)); p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
            ctx.restoreGState()
            // smoke trail
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
            ctx.setLineWidth(S * 0.03)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: S * 0.1, y: S * 0.38))
            ctx.addCurve(to: CGPoint(x: S * 0.4, y: S * 0.53), control1: CGPoint(x: S * 0.2, y: S * 0.4), control2: CGPoint(x: S * 0.3, y: S * 0.5))
            ctx.strokePath()
        }
    }
}
