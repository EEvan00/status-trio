import AppKit

/// A menu-bar panel without NSPopover's system-drawn arrow.
@MainActor
final class StatusPopupPanel: NSPanel, NSWindowDelegate {
    static let cornerRadius: CGFloat = 6
    var onClose: (() -> Void)?
    var preventsAutomaticDismissal: (() -> Bool)?
    private var sizeObservation: NSKeyValueObservation?
    private var anchor = NSRect.zero
    private var screenFrame = NSRect.zero

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .fullScreenAuxiliary]
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var isShown: Bool { isVisible }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        guard let window = view.window, let controller = contentViewController else { return }
        anchor = window.convertToScreen(view.convert(rect, to: nil))
        screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let content = controller.view
        content.wantsLayer = true
        content.layer?.cornerRadius = Self.cornerRadius
        content.layer?.masksToBounds = true
        resizeToContent()
        sizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible else { return }
                self.resizeToContent()
            }
        }
        orderFront(nil)
    }

    private func resizeToContent() {
        guard let controller = contentViewController else { return }
        var size = controller.preferredContentSize
        if size.width <= 0 || size.height <= 0 { size = controller.view.fittingSize }
        guard size.width > 0, size.height > 0 else { return }
        size.width = min(size.width, screenFrame.width)
        size.height = min(size.height, screenFrame.height)
        let x = max(screenFrame.minX, min(anchor.midX - size.width / 2, screenFrame.maxX - size.width))
        let y = max(screenFrame.minY, anchor.minY - size.height - 6)
        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    override func performClose(_ sender: Any?) {
        guard isVisible else { return }
        sizeObservation = nil
        orderOut(sender)
        onClose?()
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    func windowDidResignKey(_ notification: Notification) {
        dismissAutomatically()
    }

    func dismissAutomatically() {
        // Sheets and system credential prompts temporarily take keyboard focus.
        guard attachedSheet == nil, preventsAutomaticDismissal?() != true else { return }
        performClose(nil)
    }
}
