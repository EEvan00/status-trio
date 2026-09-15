import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct StatusPopupPanelTests {
    @Test func closingPanelRunsCleanupOnce() {
        let panel = StatusPopupPanel()
        var closes = 0
        panel.onClose = { closes += 1 }
        panel.setFrame(NSRect(x: 0, y: 0, width: 100, height: 100), display: false)
        panel.orderFront(nil)
        panel.performClose(nil)
        panel.performClose(nil)
        #expect(panel.isVisible == false)
        #expect(closes == 1)
    }

    @Test func attachedPasswordSheetDoesNotDismissParent() {
        let panel = StatusPopupPanel()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        panel.setFrame(NSRect(x: 0, y: 0, width: 200, height: 200), display: false)
        panel.orderFront(nil)
        panel.beginSheet(sheet)
        panel.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
        #expect(panel.isVisible)
        panel.endSheet(sheet)
        sheet.orderOut(nil)
        panel.performClose(nil)
    }

    @Test func escapeClosesPanel() {
        let panel = StatusPopupPanel()
        panel.setFrame(NSRect(x: 0, y: 0, width: 100, height: 100), display: false)
        panel.orderFront(nil)
        panel.cancelOperation(nil)
        #expect(panel.isVisible == false)
    }
}
