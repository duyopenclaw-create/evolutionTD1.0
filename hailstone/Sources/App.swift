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
        window.title = "Hailstone"
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 960, height: 600)
        window.center()
        view = GameView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        let shot = arg("--shot")
        if shot != nil || args.contains("--autotest") { SaveData.disabled = true }
        game = Game(view: view, muted: args.contains("--mute"))
        window.contentView = view
        window.delegate = self
        if args.contains("--autotest") { exit(game.autotest() ? 0 : 1) }
        if shot != nil {
            view.inputEnabled = false
            game.ignoreInput = true
            window.orderFrontRegardless()     // test captures never steal keyboard focus
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
        game.devCamera(yaw: arg("--camyaw").flatMap(Float.init), pitch: arg("--campitch").flatMap(Float.init), dist: arg("--dist").flatMap(Float.init))
        if args.contains("--nohelp") { game.devHideHelp() }
        if let s = arg("--pile").flatMap(Int.init) { game.devPile(s) }
        if let s = arg("--drop").flatMap(Int.init) { game.devDrop(s) }
        if args.contains("--slowmo") { game.devSlowmo() }
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
                    NSLog("Hailstone: snapshot failed")
                    NSApp.terminate(nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { attempt(0) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { if !SaveData.disabled { game?.saveNow() } }
    func windowDidResignKey(_ notification: Notification) { view?.input.clear() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Hailstone", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Hailstone", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hailstone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    /// A striped 27 ball bouncing on maple, with its bounce arcs traced behind it.
    static func draw(_ size: Int) -> CGImage {
        makeImage(size, size) { ctx in
            let S = CGFloat(size)
            let inset = S * 0.08
            let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: S * 0.2, cornerHeight: S * 0.2, transform: nil))
            ctx.clip()
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let bg = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.1, green: 0.12, blue: 0.2, alpha: 1),
                                                          CGColor(srgbRed: 0.2, green: 0.24, blue: 0.36, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: inset), end: CGPoint(x: 0, y: S - inset), options: [])
            ctx.setFillColor(CGColor(srgbRed: 0.78, green: 0.56, blue: 0.33, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S * 0.3))
            ctx.setStrokeColor(CGColor(srgbRed: 0.6, green: 0.42, blue: 0.24, alpha: 1))
            ctx.setLineWidth(max(1, S * 0.004))
            for i in 0..<6 { let y = S * 0.3 * CGFloat(i) / 6; ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: S, y: y)) }
            ctx.strokePath()
            // bounce arcs
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.8, blue: 0.4, alpha: 0.7))
            ctx.setLineWidth(S * 0.012)
            ctx.setLineDash(phase: 0, lengths: [S * 0.025, S * 0.02])
            ctx.move(to: CGPoint(x: S * 0.12, y: S * 0.82))
            ctx.addQuadCurve(to: CGPoint(x: S * 0.34, y: S * 0.3), control: CGPoint(x: S * 0.28, y: S * 0.9))
            ctx.addQuadCurve(to: CGPoint(x: S * 0.56, y: S * 0.3), control: CGPoint(x: S * 0.45, y: S * 0.8))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            // shadow
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
            ctx.fillEllipse(in: CGRect(x: S * 0.52, y: S * 0.24, width: S * 0.36, height: S * 0.07))
            // the ball
            let c = CGPoint(x: S * 0.7, y: S * 0.48), r = S * 0.2
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.clip()
            ctx.setFillColor(CGColor(srgbRed: 0.94, green: 0.92, blue: 0.85, alpha: 1))
            ctx.fill(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.08, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(x: c.x - r, y: c.y - r * 0.55, width: r * 2, height: r * 1.1))
            ctx.setFillColor(CGColor(srgbRed: 0.94, green: 0.92, blue: 0.85, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84))
            let shade = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0.35), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.45)] as CFArray, locations: [0, 0.45, 1])!
            ctx.drawRadialGradient(shade, startCenter: CGPoint(x: c.x - r * 0.4, y: c.y + r * 0.45), startRadius: 0, endCenter: c, endRadius: r * 1.05, options: [])
            ctx.restoreGState()
            let font = CTFontCreateWithName("Futura-Bold" as CFString, r * 0.5, nil)
            let a = NSAttributedString(string: "27", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                  NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.05, alpha: 1)])
            let line = CTLineCreateWithAttributedString(a)
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: c.x - b.midX, y: c.y - b.midY)
            CTLineDraw(line, ctx)
        }
    }
}
