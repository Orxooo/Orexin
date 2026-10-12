// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import SwiftUI
import QuartzCore

/// A square child window; the background view supplies the control's screen anchor.
struct TerminalPopup: NSViewRepresentable {
    @Binding private var isPresented: Bool
    private let width: CGFloat
    private let content: () -> AnyView

    init<Content: View>(isPresented: Binding<Bool>, width: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        _isPresented = isPresented
        self.width = width
        self.content = { AnyView(content()) }
    }

    final class AnchorView: NSView {
        var detached: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { detached?() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.setAccessibilityElement(false)
        view.detached = { [weak coordinator = context.coordinator, weak view] in
            DispatchQueue.main.async {
                guard view?.window == nil else { return }
                coordinator?.dismiss(restoreFocus: false)
            }
        }
        return view
    }
    func updateNSView(_ view: AnchorView, context: Context) {
        let environment = context.environment
        let root = AnyView(content()
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .disabled(!environment.isEnabled)
            .frame(width: width).fixedSize(horizontal: false, vertical: true))
        context.coordinator.update(anchor: view, presented: $isPresented, enabled: environment.isEnabled, width: width, root: root)
    }
    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        view.detached = nil
        coordinator.attached = false
        coordinator.dismiss(restoreFocus: false, resetBinding: false)
    }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        var attached = true
        private weak var anchor: AnchorView?
        private weak var owner: NSWindow?
        private weak var previousResponder: NSResponder?
        private var presented: Binding<Bool> = .constant(false)
        private var root = AnyView(EmptyView())
        private var width: CGFloat = 260
        private var enabled = true
        private var panel: ConsoleMenuPanel?
        private var host: PopupHostingView?
        private var viewport: NSScrollView?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var openingScheduled = false
        private var layoutScheduled = false
        private var closing = false

        func update(anchor: AnchorView, presented: Binding<Bool>, enabled: Bool, width: CGFloat, root: AnyView) {
            self.anchor = anchor; self.presented = presented; self.enabled = enabled; self.width = width; self.root = root
            guard enabled else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.enabled else { return }
                    self.dismiss(restoreFocus: false)
                }
                return
            }
            if presented.wrappedValue {
                if let panel, let owner {
                    panel.appearance = owner.appearance
                    host?.rootView = root
                    scheduleLayout()
                } else if !openingScheduled {
                    openingScheduled = true
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.openingScheduled = false
                        guard self.attached, self.enabled, self.presented.wrappedValue else { return }
                        self.present()
                    }
                }
            } else {
                dismiss(restoreFocus: true, resetBinding: false)
            }
        }

        private func present() {
            guard panel == nil, let anchor, let owner = anchor.window, owner.isVisible else {
                presented.wrappedValue = false
                return
            }
            self.owner = owner
            previousResponder = owner.firstResponder
            var mask: NSWindow.StyleMask = [.borderless]
            if owner.styleMask.contains(.nonactivatingPanel) { mask.insert(.nonactivatingPanel) }
            let popup = ConsoleMenuPanel(contentRect: .zero, styleMask: mask, backing: .buffered, defer: false)
            popup.title = L("Orexin · 选择器")
            popup.isReleasedWhenClosed = false
            popup.isFloatingPanel = true
            popup.becomesKeyOnlyIfNeeded = false
            popup.hidesOnDeactivate = true
            popup.hasShadow = true
            popup.isOpaque = false
            popup.backgroundColor = .clear
            popup.appearance = owner.appearance
            popup.level = owner.level
            popup.collectionBehavior = [.transient, .fullScreenAuxiliary]
            popup.delegate = self
            let host = PopupHostingView(rootView: root)
            host.sizingOptions = [.intrinsicContentSize]
            host.sizeChanged = { [weak self] in self?.scheduleLayout() }
            let viewport = NSScrollView()
            viewport.borderType = .noBorder
            viewport.drawsBackground = false
            viewport.hasVerticalScroller = true
            viewport.hasHorizontalScroller = true
            viewport.autohidesScrollers = true
            viewport.automaticallyAdjustsContentInsets = false
            viewport.documentView = host
            popup.contentView = viewport
            self.panel = popup; self.host = host; self.viewport = viewport
            layout()
            owner.addChildWindow(popup, ordered: .above)
            installDismissalHandlers(owner: owner)
            let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popup.alphaValue = animated ? 0 : 1
            popup.makeKeyAndOrderFront(nil)
            popup.makeFirstResponder(host)
            if !host.isFlipped { viewport.contentView.scroll(to: NSPoint(x: 0, y: max(0, host.frame.height - viewport.contentSize.height))) }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    popup.animator().alphaValue = 1
                }
            }
        }

        private func scheduleLayout() {
            guard panel != nil, !layoutScheduled else { return }
            layoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layoutScheduled = false
                self.layout()
            }
        }
        private func layout() {
            guard let panel, let host, let viewport, let anchor, let owner,
                  anchor.window === owner, owner.isVisible else {
                if panel != nil { dismiss(restoreFocus: false) }
                return
            }
            let control = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: control.midX, y: control.midY)) } ?? owner.screen ?? NSScreen.main
            guard let screen else { return }
            let available = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            let height = max(1, ceil(host.fittingSize.height))
            let size = NSSize(width: min(width, available.width), height: min(height, available.height))
            let documentFrame = NSRect(x: 0, y: 0, width: width, height: height)
            if host.frame != documentFrame { host.frame = documentFrame }
            let below = control.minY - 5 - size.height
            let above = control.maxY + 5
            let desiredY = below < available.minY && above + size.height <= available.maxY ? above : below
            let frame = NSRect(x: min(max(control.minX, available.minX), available.maxX - size.width),
                               y: min(max(desiredY, available.minY), available.maxY - size.height), width: size.width, height: size.height)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            let viewportFrame = NSRect(origin: .zero, size: size)
            if viewport.frame != viewportFrame { viewport.frame = viewportFrame }
        }

        private func contains(_ window: NSWindow?) -> Bool {
            guard let panel else { return false }
            var candidate = window
            while let window = candidate {
                if window === panel { return true }
                candidate = window.parent ?? window.sheetParent
            }
            return false
        }
        private func installDismissalHandlers(owner: NSWindow) {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                if event.type == .keyDown {
                    if event.window === panel, event.keyCode == 53 {
                        self.dismiss(restoreFocus: true)
                        return nil
                    }
                    return event
                }
                guard !self.contains(event.window) else { return event }
                let clickedAnchor: Bool
                if event.type != .scrollWheel, let anchor = self.anchor, let owner = anchor.window, event.window === owner {
                    clickedAnchor = anchor.convert(anchor.bounds, to: nil).contains(event.locationInWindow)
                } else { clickedAnchor = false }
                self.dismiss(restoreFocus: clickedAnchor)
                return clickedAnchor ? nil : event
            }
            // Mouse-only monitoring needs no Accessibility/key-monitor authorization.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                DispatchQueue.main.async { self?.dismiss(restoreFocus: false) }
            }
            observe(NSApplication.didResignActiveNotification, object: NSApp) { [weak self] in self?.dismiss(restoreFocus: false) }
            observe(NSWindow.willCloseNotification, object: owner) { [weak self] in self?.dismiss(restoreFocus: false) }
            observe(NSWindow.didMiniaturizeNotification, object: owner) { [weak self] in self?.dismiss(restoreFocus: false) }
            observe(NSWindow.didChangeOcclusionStateNotification, object: owner) { [weak self, weak owner] in
                if owner?.isVisible != true { self?.dismiss(restoreFocus: false) }
            }
            observe(NSWindow.didMoveNotification, object: owner) { [weak self] in self?.scheduleLayout() }
            observe(NSWindow.didResizeNotification, object: owner) { [weak self] in self?.scheduleLayout() }
        }
        private func observe(_ name: Notification.Name, object: AnyObject, action: @escaping () -> Void) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in action() })
        }
        func windowDidResignKey(_ notification: Notification) {
            guard !closing else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let panel = self.panel, !panel.isKeyWindow,
                      panel.attachedSheet == nil,
                      !(panel.childWindows ?? []).contains(where: { $0.isVisible }) else { return }
                self.dismiss(restoreFocus: false)
            }
        }
        func dismiss(restoreFocus: Bool, resetBinding: Bool = true) {
            guard !closing else { return }
            closing = true
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            localMonitor = nil; globalMonitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            let owner = owner
            let responder = previousResponder
            let popup = panel
            // A fading popup is visual only. It must not retain keyboard or
            // pointer access to handlers whose bindings were just dismissed.
            if let popup {
                popup.acceptsInteraction = false
                popup.ignoresMouseEvents = true
                popup.makeFirstResponder(nil)
                if let host { host.rootView = AnyView(host.rootView.disabled(true).allowsHitTesting(false)) }
                if popup.isKeyWindow {
                    popup.resignKey()
                    if owner?.isVisible == true { owner?.makeKey() }
                }
            }
            panel = nil; host?.sizeChanged = nil; host = nil; viewport = nil
            if let popup {
                owner?.removeChildWindow(popup)
                popup.delegate = nil
                let finish = { popup.close(); popup.contentView = nil }
                if popup.isVisible && NSApp.isActive && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.13
                        popup.animator().alphaValue = 0
                    } completionHandler: { finish() }
                } else { finish() }
            }
            self.owner = nil; previousResponder = nil
            if resetBinding, presented.wrappedValue { presented.wrappedValue = false }
            if restoreFocus, let owner, owner.isVisible {
                owner.makeKeyAndOrderFront(nil)
                if let responder, (responder as? NSView).map({ $0.window === owner }) ?? true {
                    owner.makeFirstResponder(responder)
                }
            }
            closing = false
        }
    }

    @MainActor private final class PopupHostingView: NSHostingView<AnyView> {
        var sizeChanged: (() -> Void)?
        override func invalidateIntrinsicContentSize() {
            super.invalidateIntrinsicContentSize()
            sizeChanged?()
        }
    }
}

extension View {
    func terminalPopup<Content: View>(isPresented: Binding<Bool>, width: CGFloat, @ViewBuilder content: @escaping () -> Content) -> some View {
        background(TerminalPopup(isPresented: isPresented, width: width, content: content))
    }
}
