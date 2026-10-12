// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

final class ConsoleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class ConsoleMenuPanel: NSPanel {
    var acceptsInteraction = true
    override var canBecomeKey: Bool { acceptsInteraction }
    override var canBecomeMain: Bool { false }
}

struct ApplicationBadge: View {
    var body: some View {
        if let image = ConsoleAssets.appIcon {
            Image(nsImage: image).resizable().scaledToFit().accessibilityHidden(true)
        }
    }
}

/// Bundle artwork is immutable during a run; keep it out of view refresh paths.
enum ConsoleAssets {
    static let appIcon = load("AppIcon", extension: "icns")
    static let orbitalCore = load("OrbitalCore", extension: "png")
    static let orbitalMoon = load("OrbitalMoon", extension: "png")
    static let orbitalZima = load("OrbitalZima", extension: "png")
    static let orbital2049 = load("Orbital2049", extension: "png")
    static func artwork(for theme: AppearanceController.Theme) -> NSImage? {
        switch theme {
        case .dark, .system: orbitalCore
        case .light: orbitalZima
        case .amber: orbital2049
        }
    }
    private static func load(_ name: String, extension fileExtension: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: fileExtension).flatMap(NSImage.init(contentsOf:))
    }
}

struct ConsoleWindowControls: View {
    var body: some View {
        HStack(spacing: 6) {
            control("关闭窗口", symbol: "xmark", color: TerminalStyle.warning) { NSApp.keyWindow?.performClose(nil) }
            control("最小化窗口", symbol: "minus", color: TerminalStyle.amber) { NSApp.keyWindow?.miniaturize(nil) }
            control("缩放窗口", symbol: "arrow.up.left.and.arrow.down.right", color: TerminalStyle.signal) { NSApp.keyWindow?.zoom(nil) }
        }
    }
    private func control(_ label: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(TerminalStyle.recess)
                .frame(width: 13, height: 13).background(color)
        }.buttonStyle(TerminalPlainButtonStyle()).accessibilityLabel(L(label)).help(L(label)).workKeyboardFocus(radius: 0)
    }
}

struct WindowDragRegion: NSViewRepresentable {
    final class Region: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func mouseUp(with event: NSEvent) {
            if event.clickCount == 2 { window?.zoom(nil) }
        }
    }
    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) {}
}

/// One low-frequency clock per decoration, paused offscreen/inactive or with reduced motion.
struct TerminalPulse<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var appActive = NSApp.isActive
    @State private var windowVisible = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.65, paused: !visible || !windowVisible || !appActive || reduceMotion)) { context in
            let bright = reduceMotion || !appActive || Int(context.date.timeIntervalSinceReferenceDate / 0.65) % 2 == 0
            content(bright)
        }.background(WindowVisibilityProbe { windowVisible = $0 }.frame(width: 0, height: 0))
            .onAppear { visible = true; appActive = NSApp.isActive }
            .onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct TerminalCursor: View {
    var body: some View { TerminalPulse { bright in Rectangle().fill(TerminalStyle.accent).frame(width: 7, height: 14).opacity(bright ? 0.9 : 0.12).shadow(color: TerminalStyle.accent.opacity(0.4), radius: 4) } }
}
struct TerminalSignal: View {
    var color: Color = TerminalStyle.signal
    var body: some View { TerminalPulse { bright in Rectangle().fill(color).frame(width: 6, height: 6).opacity(bright ? 1 : 0.4).shadow(color: color.opacity(bright ? 0.5 : 0), radius: 4) } }
}
struct TerminalAtmosphere: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var visible = false
    @State private var appActive = NSApp.isActive
    @State private var windowVisible = false
    var body: some View {
        ZStack {
            Canvas { context, size in
                let opacity = scheme == .dark ? 0.065 : 0.035
                var dots = Path()
                for x in stride(from: CGFloat(12), through: size.width, by: 24) {
                    for y in stride(from: CGFloat(12), through: size.height, by: 24) {
                        dots.addRect(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                context.fill(dots, with: .color(TerminalStyle.accent.opacity(opacity)))
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !visible || !windowVisible || !appActive || reduceMotion)) { timeline in
                Canvas { context, size in
                    let accent = TerminalStyle.accent
                if !reduceMotion && appActive {
                    let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 18) / 18
                    let y = CGFloat(progress) * (size.height + 70) - 70
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 60)), with: .color(accent.opacity(scheme == .dark ? 0.014 : 0.008)))
                    context.fill(Path(CGRect(x: 0, y: y + 60, width: size.width, height: 0.5)), with: .color(accent.opacity(0.055)))
                }
                }
            }
        }.background(WindowVisibilityProbe { windowVisible = $0 }.frame(width: 0, height: 0))
            .onAppear { visible = true; appActive = NSApp.isActive }.onDisappear { visible = false }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// NSHostingView remains mounted when a window is hidden; observe actual window visibility.
struct WindowVisibilityProbe: NSViewRepresentable {
    let changed: (Bool) -> Void
    final class Probe: NSView {
        var changed: (Bool) -> Void = { _ in }
        private var observations: [NSObjectProtocol] = []
        private var previous: Bool?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                    observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.report() })
                }
            }
            report()
        }
        func report() {
            let value = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            guard value != previous else { return }; previous = value
            DispatchQueue.main.async { [weak self] in self?.changed(value) }
        }
        deinit { observations.forEach(NotificationCenter.default.removeObserver) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.changed = changed; return view }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.report() }
}
