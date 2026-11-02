// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import CoreGraphics

/// Observe without consuming Esc or the system's brightness adjustment.
@MainActor final class DimExitKeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    var onKey: (() -> Void)?

    static func matches(_ event: NSEvent) -> Bool {
        if event.type == .keyDown { return event.keyCode == 53 && !event.isARepeat }
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return false }
        let key = (event.data1 >> 16) & 0xffff
        let state = (event.data1 >> 8) & 0xff
        return (key == 2 || key == 3) && state == 0x0a // NX brightness up/down, key down
    }

    /// Install in the GUI process: the headless service has no AppKit event queue.
    func startLocal() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            if DimExitKeyMonitor.matches(event) { self?.onKey?() }
            return event
        }
    }

    /// Passive cross-app observation; requesting permission is a separate UI action.
    @discardableResult func start() -> Bool {
        // A non-nil tap may have had its keyDown mask stripped by macOS.
        // Check access first instead of treating a partial tap as keyboard access.
        guard CGPreflightListenEventAccess() else { stop(); return false }
        if tap != nil { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << 14)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            MainActor.assumeIsolated {
                let monitor = Unmanaged<DimExitKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if let input = NSEvent(cgEvent: event), DimExitKeyMonitor.matches(input) { monitor.onKey?() }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        return false
    }
    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        if let tap { CFMachPortInvalidate(tap) }; tap = nil
    }
    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }
}
