import AppKit
import SwiftUI
import Combine

final class Store: ObservableObject {
    @Published var usage: Usage?
    @Published var lastUpdated: String = "加载中…"

    func refresh() {
        DataLoader.load { [weak self] u in
            guard let self = self else { return }
            if let u = u { self.usage = u }
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            self.lastUpdated = "更新 " + f.string(from: Date())
            (NSApp.delegate as? AppDelegate)?.updateStatusTitle()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.action = #selector(togglePopover)
            b.target = self
        }
        updateStatusTitle()

        let host = NSHostingController(rootView: PanelView(store: store))
        let vc = NSViewController()
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host.view)
        let container = NSView()
        container.addSubview(effect)
        vc.view = container
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: effect.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = true

        store.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
    }

    func updateStatusTitle() {
        guard let b = statusItem?.button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let s = NSMutableAttributedString()
        func sym(_ name: String) -> NSAttributedString {
            let att = NSTextAttachment()
            att.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            return NSAttributedString(attachment: att)
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 1]

        if let u = store.usage {
            s.append(sym("bolt.fill"))
            s.append(NSAttributedString(string: String(format: " %.0f", u.claude.ranges.today.hit), attributes: attrs))
            if let p5 = u.codex.p5 {
                s.append(NSAttributedString(string: "  ", attributes: attrs))
                s.append(sym("clock.fill"))
                s.append(NSAttributedString(string: String(format: " %.0f", 100 - p5), attributes: attrs))
            }
        } else {
            s.append(sym("bolt.fill"))
            s.append(NSAttributedString(string: " …", attributes: attrs))
        }
        b.attributedTitle = s
        b.image = nil
    }

    @objc func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// 离屏截图模式:Tokei --shot /path/out.png
enum Shot {
    static func run(path: String) {
        _ = NSApplication.shared
        var usage: Usage?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { usage = DataLoader.loadSync(); sem.signal() }
        sem.wait()
        MainActor.assumeIsolated {
            let store = Store()
            store.usage = usage
            store.lastUpdated = "预览"
            let content = PanelView(store: store)
                .background(Color(red: 0.13, green: 0.13, blue: 0.14))
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        exit(0)
    }
}

if let idx = CommandLine.arguments.firstIndex(of: "--shot") {
    let out = CommandLine.arguments.count > idx + 1
        ? CommandLine.arguments[idx + 1] : "/tmp/tokei_shot.png"
    Shot.run(path: out)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
