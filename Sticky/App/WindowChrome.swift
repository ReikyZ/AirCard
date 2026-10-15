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

/// Grips register here so the borderless window does not swallow their drags.
enum GripHoleRegistry {
    private static let lock = NSLock()
    private static var grips: [ObjectIdentifier: WeakGrip] = [:]

    static func register(_ view: RowGripView) {
        lock.lock()
        grips[ObjectIdentifier(view)] = WeakGrip(view)
        lock.unlock()
    }

    static func unregister(_ view: RowGripView) {
        lock.lock()
        grips.removeValue(forKey: ObjectIdentifier(view))
        lock.unlock()
    }

    static func grip(at windowPoint: NSPoint, window: NSWindow) -> RowGripView? {
        lock.lock()
        let views = grips.values.compactMap(\.view)
        lock.unlock()
        return views.first { view in
            guard view.window === window else { return false }
            return view.bounds.contains(view.convert(windowPoint, from: nil))
        }
    }
}

private final class WeakGrip {
    weak var view: RowGripView?
    init(_ view: RowGripView) { self.view = view }
}

final class RowGripView: NSView {
    var onDrag: ((CGFloat, Bool) -> Void)?
    private var anchorY: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            GripHoleRegistry.unregister(self)
        } else {
            GripHoleRegistry.register(self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        anchorY = event.locationInWindow.y
        onDrag?(0, false)
    }

    override func mouseDragged(with event: NSEvent) {
        // SwiftUI row coordinates grow downward; window coordinates grow upward.
        onDrag?(anchorY - event.locationInWindow.y, false)
    }

    override func mouseUp(with event: NSEvent) {
        onDrag?(anchorY - event.locationInWindow.y, true)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dot: CGFloat = 2.5
        let gap: CGFloat = 2
        context.setFillColor(NSColor(srgbRed: 0x5C / 255, green: 0x4A / 255, blue: 0x32 / 255, alpha: 0.55).cgColor)
        for row in 0..<3 {
            for column in 0..<2 {
                let origin = CGPoint(x: CGFloat(column) * (dot + gap), y: CGFloat(row) * (dot + gap))
                context.fillEllipse(in: CGRect(origin: origin, size: CGSize(width: dot, height: dot)))
            }
        }
    }
}

struct RowGrip: NSViewRepresentable {
    var onDrag: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> RowGripView {
        let view = RowGripView()
        view.onDrag = onDrag
        return view
    }

    func updateNSView(_ view: RowGripView, context: Context) {
        view.onDrag = onDrag
    }
}

final class ChromeView: NSView {
    weak var coordinator: WindowChrome.Coordinator?
    private var didConfigure = false
    private var anchorTopRight = false
    private var sizeObserver: NSObjectProtocol?

    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window else { return super.hitTest(point) }
        let windowPoint = convert(point, to: nil)
        if let grip = GripHoleRegistry.grip(at: windowPoint, window: window) {
            return grip
        }
        return super.hitTest(point)
    }

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
        if let window, GripHoleRegistry.grip(at: event.locationInWindow, window: window) != nil {
            return
        }
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
