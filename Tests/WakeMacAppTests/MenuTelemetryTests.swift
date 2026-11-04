// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
import AppKit
@testable import WakeMac

@MainActor final class MenuTelemetryTests: XCTestCase {
    func testArrowButtonsScrollBothDirectionsAndRespectBounds() throws {
        let rail = MenuRailView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        rail.scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 44))
        let window = NSWindow(contentRect: rail.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = rail; window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        rail.layout()
        let buttons = rail.subviews.compactMap { $0 as? NSButton }
        let left = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "rail.previous" })
        let right = try XCTUnwrap(buttons.first { $0.identifier?.rawValue == "rail.next" })
        XCTAssertFalse(left.isEnabled)
        XCTAssertTrue(right.isEnabled)
        XCTAssertLessThan(left.frame.maxX, rail.scrollView.frame.minX)
        XCTAssertGreaterThan(right.frame.minX, rail.scrollView.frame.maxX)
        right.performClick(nil)
        let advanced = rail.scrollView.contentView.bounds.minX
        XCTAssertGreaterThan(advanced, 0)
        XCTAssertTrue(left.isEnabled)
        left.performClick(nil)
        XCTAssertEqual(rail.scrollView.contentView.bounds.minX, 0, accuracy: 0.5)
        rail.scrollHorizontally(by: 5000)
        XCTAssertFalse(right.isEnabled)
        XCTAssertTrue(left.isEnabled)
    }
    func testRailScrollRevealsBothEndsAndClampsToDocumentBounds() {
        let rail = MenuRailView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        rail.scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 44))
        rail.layout()
        rail.scrollHorizontally(by: 5000)
        XCTAssertEqual(rail.scrollView.contentView.bounds.minX, 900 - rail.scrollView.contentView.bounds.width, accuracy: 0.5)
        rail.scrollHorizontally(by: -100)
        XCTAssertGreaterThan(rail.scrollView.contentView.bounds.minX, 0)
        rail.scrollHorizontally(by: -5000)
        XCTAssertEqual(rail.scrollView.contentView.bounds.minX, 0, accuracy: 0.5)
    }
    func testStatusTextUsesOnlyAwakeAndNormalForTheTwoWorkModes() {
        let suite = "MenuModeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(backend: AutomationBackend(), preferences: defaults)
        model.menuLabelEnabled = true
        model.active = .background; XCTAssertEqual(model.menuText, L("唤醒"))
        model.active = .desk; XCTAssertEqual(model.menuText, L("唤醒"))
        model.busy = true; XCTAssertEqual(model.menuText, L("唤醒"))
        model.active = .normal; XCTAssertEqual(model.menuText, L("正常"))
        model.active = nil; XCTAssertEqual(model.menuText, "")
    }
}
