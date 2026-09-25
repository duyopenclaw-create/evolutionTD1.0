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
        window.title = "BoneFall"
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 1100, height: 760)
        window.acceptsMouseMovedEvents = true
        window.center()
        view = GameView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        let shot = arg("--shot")
        if shot != nil || args.contains("--autotest") { SaveData.disabled = true }
        game = Game(view: view, muted: args.contains("--mute"))
        view.frame = frame
        window.contentView = view
        window.delegate = self
        game.backing = window.backingScaleFactor
        if args.contains("--autotest") {
            view.isPlaying = false
            view.delegate = nil
            exit(game.autotest() ? 0 : 1)
        }
        if shot != nil {
            view.inputEnabled = false
            game.ignoreInput = true
            // Test captures never steal keyboard focus. They float on every Space so macOS doesn't
            // throttle an occluded window.
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.orderFrontRegardless()
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
        if args.contains("--autoplay") { game.autoplay = true }
        if let m = arg("--map") { game.devMap(Int(m) ?? 0, height: Int(arg("--h") ?? "0") ?? 0) }
        if let s = arg("--scene") { game.devScene(s) }
        if let c = arg("--cam") {
            let v = c.split(separator: ",").compactMap { Float($0) }
            if v.count == 6 { game.devFreezeCam = (SIMD3(v[0], v[1], v[2]), SIMD3(v[3], v[4], v[5])) }
        }
        if let path = arg("--shot") {
            let delay = Double(arg("--delay") ?? "4") ?? 4
            func attempt(_ n: Int) {
                let img = self.view.snapshot()
                if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]),
                   (try? png.write(to: URL(fileURLWithPath: path))) != nil {
                    NSApp.terminate(nil)
                } else if n < 6 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { attempt(n + 1) }
                } else {
                    NSLog("BoneFall: snapshot failed")
                    NSApp.terminate(nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { attempt(0) }
        }
    }

    // Test captures keep the window unfocused, and AppKit can count it as closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { arg("--shot") == nil }
    func applicationWillTerminate(_ notification: Notification) { if !SaveData.disabled { game?.saveNow() } }
    func windowDidChangeBackingProperties(_ notification: Notification) { game?.backing = window.backingScaleFactor }
    func windowDidResignKey(_ notification: Notification) { view?.input.clear() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About BoneFall", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide BoneFall", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit BoneFall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
    static func run(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for s in [16, 32, 64, 128, 256, 512, 1024] {
            let img = draw(s)
            if s <= 512 { savePNG(img, to: "\(dir)/icon_\(s)x\(s).png") }
            if s >= 32 { savePNG(img, to: "\(dir)/icon_\(s / 2)x\(s / 2)@2x.png") }
        }
    }

    /// A cracked bone falling past a cliff edge at sunset.
    static func draw(_ size: Int) -> CGImage {
        makeImage(size, size) { ctx in
            let S = CGFloat(size)
            let inset = S * 0.08
            let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: S * 0.2, cornerHeight: S * 0.2, transform: nil))
            ctx.clip()
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let grad = CGGradient(colorsSpace: cs, colors: [CGColor(srgbRed: 0.98, green: 0.62, blue: 0.3, alpha: 1), CGColor(srgbRed: 0.35, green: 0.2, blue: 0.45, alpha: 1)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: S), options: [])
            // cliff
            ctx.setFillColor(CGColor(srgbRed: 0.28, green: 0.2, blue: 0.18, alpha: 1))
            ctx.move(to: CGPoint(x: 0, y: S * 0.8)); ctx.addLine(to: CGPoint(x: S * 0.3, y: S * 0.8)); ctx.addLine(to: CGPoint(x: S * 0.34, y: S * 0.55))
            ctx.addLine(to: CGPoint(x: S * 0.42, y: S * 0.5)); ctx.addLine(to: CGPoint(x: S * 0.46, y: S * 0.2)); ctx.addLine(to: CGPoint(x: S * 0.7, y: S * 0.12))
            ctx.addLine(to: CGPoint(x: S, y: S * 0.1)); ctx.addLine(to: CGPoint(x: S, y: 0)); ctx.addLine(to: CGPoint(x: 0, y: 0)); ctx.closePath(); ctx.fillPath()
            // bone, tilted
            ctx.saveGState()
            ctx.translateBy(x: S * 0.64, y: S * 0.58)
            ctx.rotate(by: -0.7)
            let bone = CGColor(srgbRed: 0.97, green: 0.95, blue: 0.88, alpha: 1)
            ctx.setFillColor(bone)
            let L = S * 0.26, w = S * 0.08
            ctx.fill(CGRect(x: -L, y: -w / 2, width: L * 2, height: w))
            for x in [-L, L] { for y in [-w * 0.45, w * 0.45] { ctx.fillEllipse(in: CGRect(x: x - w * 0.62, y: y - w * 0.62, width: w * 1.24, height: w * 1.24)) } }
            ctx.setStrokeColor(CGColor(srgbRed: 0.15, green: 0.05, blue: 0.05, alpha: 1))
            ctx.setLineWidth(max(1, S * 0.014))
            ctx.move(to: CGPoint(x: -S * 0.01, y: w * 0.6)); ctx.addLine(to: CGPoint(x: S * 0.02, y: w * 0.1)); ctx.addLine(to: CGPoint(x: -S * 0.015, y: -w * 0.15)); ctx.addLine(to: CGPoint(x: S * 0.01, y: -w * 0.6))
            ctx.strokePath()
            ctx.restoreGState()
            // motion lines
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.7))
            ctx.setLineWidth(max(1, S * 0.016))
            ctx.setLineCap(.round)
            for i in 0..<3 {
                let o = CGFloat(i) * S * 0.06
                ctx.move(to: CGPoint(x: S * 0.5 + o, y: S * 0.86)); ctx.addLine(to: CGPoint(x: S * 0.54 + o, y: S * 0.76))
            }
            ctx.strokePath()
        }
    }
}
