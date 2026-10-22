// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import XCTest
@testable import WakeMac

@MainActor final class ConsoleWindowTests: XCTestCase {
    private final class CloseDelegate: NSObject, NSWindowDelegate {
        var allowsClose = true
        var closeRequests = 0
        var closeNotifications = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            closeRequests += 1
            return allowsClose
        }
        func windowWillClose(_ notification: Notification) { closeNotifications += 1 }
    }

    func testPerformCloseClosesBorderlessMainWindowAndQuickPanel() {
        _ = NSApplication.shared
        for style: NSWindow.StyleMask in [
            [.borderless, .closable, .miniaturizable, .resizable],
            [.borderless, .closable, .miniaturizable]
        ] {
            let window = ConsoleWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                       styleMask: style, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let delegate = CloseDelegate()
            window.delegate = delegate
            defer { window.delegate = nil; window.close() }

            window.performClose(nil)

            XCTAssertEqual(delegate.closeRequests, 1)
            XCTAssertEqual(delegate.closeNotifications, 1, "Closing a console must reach its lifecycle delegate.")
        }
    }

    func testPerformCloseRespectsDelegateVeto() {
        _ = NSApplication.shared
        let window = ConsoleWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                   styleMask: [.borderless, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let delegate = CloseDelegate()
        delegate.allowsClose = false
        window.delegate = delegate
        defer { window.delegate = nil; window.close() }

        window.performClose(nil)

        XCTAssertEqual(delegate.closeRequests, 1)
        XCTAssertEqual(delegate.closeNotifications, 0)
    }

    func testCloseMenuIsEnabledForBorderlessConsole() {
        _ = NSApplication.shared
        let window = ConsoleWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                   styleMask: [.borderless, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let item = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        XCTAssertTrue(window.validateMenuItem(item), "The Close menu and Command-W must remain available without a native close button.")
    }
}
