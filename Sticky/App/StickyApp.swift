import AppKit
import SwiftUI

extension Notification.Name {
    static let stickyRefreshRequested = Notification.Name("StickyRefreshRequested")
    static let stickyContentSize = Notification.Name("StickyContentSize")
}

final class NoteSizeBox: NSObject {
    let size: CGSize
    init(_ size: CGSize) { self.size = size }
}

enum NoteSizeStore {
    static var latest: CGSize = .zero
}

/// Borderless panels cannot become key unless a subclass says so.
/// Without that, the menu bar and Command-Q never reach the app.
final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class StickyApplication: NSObject, NSApplicationDelegate {
    private var panel: StickyPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        MimoBridgeServer.shared.start()

        let hosting = NSHostingView(rootView: NoteView())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = StickyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.title = ""
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false

        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 28,
                y: visible.maxY - size.height - 28
            ))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "Sticky")
        appItem.submenu = appMenu

        let refresh = NSMenuItem(
            title: StickyCopy.refresh,
            action: #selector(refreshNote(_:)),
            keyEquivalent: "r"
        )
        refresh.target = self
        appMenu.addItem(refresh)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: StickyCopy.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        NSApp.mainMenu = main
        NSApp.windowsMenu = nil
    }

    @objc private func refreshNote(_ sender: Any?) {
        NotificationCenter.default.post(name: .stickyRefreshRequested, object: nil)
    }
}

@main
enum StickyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = StickyApplication()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
