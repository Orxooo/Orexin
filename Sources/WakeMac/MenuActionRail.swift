// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

struct MenuActionRail<Content: View>: NSViewRepresentable {
    let content: Content
    let accent: Color
    let background: Color
    let border: Color
    let previousLabel: String
    let nextLabel: String

    init(accent: Color, background: Color, border: Color, previousLabel: String, nextLabel: String, @ViewBuilder content: () -> Content) {
        self.content = content(); self.accent = accent; self.background = background; self.border = border
        self.previousLabel = previousLabel; self.nextLabel = nextLabel
    }
    func makeNSView(context: Context) -> MenuRailView {
        let view = MenuRailView()
        let host = NSHostingView(rootView: AnyView(content.fixedSize(horizontal: true, vertical: false).frame(height: 44)))
        host.sizingOptions = [.intrinsicContentSize]
        view.scrollView.documentView = host
        return view
    }
    func updateNSView(_ view: MenuRailView, context: Context) {
        guard let host = view.scrollView.documentView as? NSHostingView<AnyView> else { return }
        view.configureArrows(accent: NSColor(accent), background: NSColor(background), border: NSColor(border), previousLabel: previousLabel, nextLabel: nextLabel)
        let offset = max(0, view.scrollView.contentView.bounds.minX)
        host.rootView = AnyView(content.fixedSize(horizontal: true, vertical: false).frame(height: 44))
        host.invalidateIntrinsicContentSize()
        host.frame = NSRect(x: 0, y: 0, width: max(0, host.intrinsicContentSize.width), height: 44)
        view.scrollView.contentView.scroll(to: CGPoint(x: offset, y: 0))
        view.updateArrowStates()
    }
}

private final class MenuRailClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = proposedBounds
        rect.origin.x = min(max(0, proposedBounds.origin.x), max(0, (documentView?.frame.width ?? 0) - proposedBounds.width))
        rect.origin.y = 0
        return rect
    }
}

final class MenuRailView: NSView {
    let scrollView = MenuRailScrollView()
    private lazy var leftArrow = makeArrow(direction: -1)
    private lazy var rightArrow = makeArrow(direction: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false; scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false; scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none; scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        let clip = MenuRailClipView(); clip.drawsBackground = false
        clip.postsBoundsChangedNotifications = true; scrollView.contentView = clip
        scrollView.rail = self
        addSubview(scrollView); addSubview(leftArrow); addSubview(rightArrow)
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: clip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func makeArrow(direction: Int) -> MenuRailArrow {
        let button = MenuRailArrow(direction: direction)
        button.target = self; button.action = #selector(scrollFromArrow(_:))
        button.isContinuous = true
        button.setPeriodicDelay(0.35, interval: 0.12)
        button.sendAction(on: [.leftMouseUp, .periodic])
        return button
    }
    func configureArrows(accent: NSColor, background: NSColor, border: NSColor, previousLabel: String, nextLabel: String) {
        leftArrow.configure(accent: accent, background: background, border: border, label: previousLabel)
        rightArrow.configure(accent: accent, background: background, border: border, label: nextLabel)
    }
    override func layout() {
        super.layout()
        let width = min(30, max(0, (bounds.width - 40) / 2 - 4))
        let inset = width + 4
        leftArrow.frame = NSRect(x: 0, y: (bounds.height - 32) / 2, width: width, height: 32)
        rightArrow.frame = NSRect(x: bounds.width - width, y: (bounds.height - 32) / 2, width: width, height: 32)
        scrollView.frame = NSRect(x: inset, y: 0, width: max(0, bounds.width - inset * 2), height: bounds.height)
        scrollView.tile()
        updateArrowStates()
    }
    @objc private func boundsChanged(_ notification: Notification) { updateArrowStates() }
    @objc private func scrollFromArrow(_ sender: MenuRailArrow) {
        scrollHorizontally(by: CGFloat(sender.direction) * max(40, scrollView.contentView.bounds.width * 0.65))
    }
    func scrollHorizontally(by delta: CGFloat) {
        let clip = scrollView.contentView
        let limit = max(0, (scrollView.documentView?.frame.width ?? 0) - clip.bounds.width)
        clip.scroll(to: CGPoint(x: min(limit, max(0, clip.bounds.minX + delta)), y: 0))
        scrollView.reflectScrolledClipView(clip)
        updateArrowStates()
    }
    func updateArrowStates() {
        let clip = scrollView.contentView
        let limit = max(0, (scrollView.documentView?.frame.width ?? 0) - clip.bounds.width)
        leftArrow.isEnabled = clip.bounds.minX > 0.5
        rightArrow.isEnabled = clip.bounds.minX < limit - 0.5
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

final class MenuRailScrollView: NSScrollView {
    weak var rail: MenuRailView?
    override func scrollWheel(with event: NSEvent) {
        rail?.scrollHorizontally(by: event.scrollingDeltaX == 0 ? -event.scrollingDeltaY : -event.scrollingDeltaX)
    }
}

private final class MenuRailArrow: NSButton {
    let direction: Int
    private var fill = NSColor.clear
    private var stroke = NSColor.clear
    init(direction: Int) {
        self.direction = direction
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(direction < 0 ? "rail.previous" : "rail.next")
        isBordered = false; title = ""; imagePosition = .imageOnly
        image = NSImage(systemSymbolName: direction < 0 ? "chevron.left" : "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(accent: NSColor, background: NSColor, border: NSColor, label: String) {
        contentTintColor = accent; fill = background; stroke = border
        setAccessibilityLabel(label); toolTip = label; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        fill.withAlphaComponent(isEnabled ? 1 : 0.45).setFill(); bounds.fill()
        stroke.withAlphaComponent(isEnabled ? 1 : 0.4).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        super.draw(dirtyRect)
    }
}
