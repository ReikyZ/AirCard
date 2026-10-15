import AppKit
import SwiftUI

struct WindowChrome: NSViewRepresentable {
    var onRefresh: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRefresh: onRefresh)
    }

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        context.coordinator.onRefresh = onRefresh
        view.coordinator = context.coordinator
        view.configureIfNeeded()
    }

    final class Coordinator: NSObject {
        var onRefresh: () -> Void

        init(onRefresh: @escaping () -> Void) {
            self.onRefresh = onRefresh
        }

        @objc func refresh(_ sender: Any?) {
            onRefresh()
        }

        @objc func quit(_ sender: Any?) {
            NSApplication.shared.terminate(nil)
        }
    }
}

final class ChromeView: NSView {
    weak var coordinator: WindowChrome.Coordinator?
    private var didConfigure = false
    private var anchorTopRight = false
    private var sizeObserver: NSObjectProtocol?

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureIfNeeded()
    }

    func configureIfNeeded() {
        guard let window, !didConfigure else { return }
        didConfigure = true
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        if sizeObserver == nil {
            sizeObserver = NotificationCenter.default.addObserver(
                forName: .stickyContentSize,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let box = note.object as? NoteSizeBox else { return }
                self?.applyContentSize(box.size)
            }
        }
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isMovable = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let size = NoteSizeStore.latest
            if size.width > 1, size.height > 1 {
                self.applyContentSize(size)
            }
            self.restoreOrPin()
        }
    }

    deinit {
        if let sizeObserver {
            NotificationCenter.default.removeObserver(sizeObserver)
        }
    }

    private func restoreOrPin() {
        guard let window else { return }
        let name = "StickyNote"
        if UserDefaults.standard.object(forKey: "NSWindow Frame \(name)") != nil {
            window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
            anchorTopRight = false
        } else {
            anchorTopRight = true
            pin(window)
            window.setFrameAutosaveName(name)
        }
    }

    override func layout() {
        super.layout()
        guard anchorTopRight, let window else { return }
        pin(window)
    }

    private func applyContentSize(_ size: CGSize) {
        guard let window else { return }
        let frame = window.frame
        if abs(frame.width - size.width) < 1, abs(frame.height - size.height) < 1 { return }
        let next = NSRect(
            x: frame.origin.x,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(next, display: true)
        if anchorTopRight {
            pin(window)
        }
        window.invalidateShadow()
    }

    private func pin(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 28,
            y: visible.maxY - size.height - 28
        )
        let current = window.frame.origin
        if abs(current.x - origin.x) > 0.5 || abs(current.y - origin.y) > 0.5 {
            window.setFrameOrigin(origin)
        }
    }

    override func mouseDown(with event: NSEvent) {
        anchorTopRight = false
        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let coordinator else { return }
        let menu = NSMenu()
        let refresh = NSMenuItem(
            title: StickyCopy.refresh,
            action: #selector(WindowChrome.Coordinator.refresh(_:)),
            keyEquivalent: ""
        )
        refresh.target = coordinator
        let quit = NSMenuItem(
            title: StickyCopy.quit,
            action: #selector(WindowChrome.Coordinator.quit(_:)),
            keyEquivalent: ""
        )
        quit.target = coordinator
        menu.addItem(refresh)
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
