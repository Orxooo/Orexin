// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

struct OrbitalReadout: View {
    let label: String
    let value: String
    var color: Color = TerminalStyle.accent
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            Text(L(label)).font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted).lineLimit(1).minimumScaleFactor(0.6)
            Text(L(value)).font(TerminalStyle.mono(14)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(compact ? 8 : 12).background(TerminalStyle.surface)
    }
}

struct OrbitalMoon: View {
    var compact = false
    var phase = "normal"
    var labels = true
    @AppStorage("orexin.appearance.theme") private var themeID = "dark"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var visible = false
    @State private var windowVisible = false
    @State private var appActive = NSApp.isActive
    private var animate: Bool { visible && windowVisible && appActive && !reduceMotion }
    private var artworkTheme: AppearanceController.Theme {
        let selected = AppearanceController.Theme(rawValue: themeID) ?? .dark
        return selected == .system ? (scheme == .dark ? .dark : .light) : selected
    }
    var body: some View {
        VStack(spacing: compact ? 0 : 10) {
            if !compact && labels {
                HStack {
                    Text("OREXIN // LUNA.CORE")
                    Spacer()
                    Text("POWER")
                }.font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
            }
            if let image = ConsoleAssets.artwork(for: artworkTheme) {
                Image(nsImage: image).resizable().scaledToFit()
                    // Preserve supplied bitmaps; crop their decorative outer rims at presentation.
                    .scaleEffect(!compact && artworkTheme != .dark ? 1.055 : 1)
                    .clipped()
                    .scaleEffect(breathing ? (artworkTheme == .dark ? 1.018 : 1.035) : 1)
                    .brightness(breathing && artworkTheme != .dark ? 0.10 : 0)
                    .opacity(breathing ? 1 : 0.91)
                    .animation(animate ? .easeInOut(duration: 2.6).repeatForever(autoreverses: true) : nil, value: breathing)
                    .shadow(color: TerminalStyle.accent.opacity(phase == "normal" ? 0.11 : 0.25), radius: phase == "normal" ? 4 : 10)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: phase)
                    .accessibilityHidden(true)
            }
            if !compact && labels {
                Text("POWER TERMINAL").font(TerminalStyle.mono(9)).tracking(1.6).foregroundStyle(TerminalStyle.accent)
            }
        }.frame(maxWidth: .infinity).accessibilityHidden(true)
            .background(WindowVisibilityProbe { windowVisible = $0; breathing = animate }.frame(width: 0, height: 0))
            .onAppear { visible = true; appActive = NSApp.isActive; breathing = animate }
            .onDisappear { visible = false; breathing = false }
            .onChange(of: reduceMotion) { _, _ in breathing = animate }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true; breathing = animate }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false; breathing = false }
    }
}

extension Notification.Name {
    static let wakeMacOpenTemperature = Notification.Name("Orexin.openTemperature")
    static let wakeMacOpenCommandTask = Notification.Name("Orexin.openCommandTask")
    static let orexinOpenAbout = Notification.Name("Orexin.openAbout")
}

/// Decorative, static scanlines use no timer and never cover input controls.
struct CRTLines: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            guard scheme == .dark else { return }
            var lines = Path()
            for y in stride(from: CGFloat(0), through: size.height, by: 3) {
                lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(.black.opacity(0.14)), lineWidth: 0.5)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct OrbitalEventFeed: View {
    let entries: [HistoryEntry]
    var title = "运行状态"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TerminalSignal()
                Text(L(title)).font(.system(size: 11, weight: .medium))
                Text("// EVENT STREAM").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                Spacer()
                Text("LOCAL").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.signal)
            }
            if entries.isEmpty {
                Text(L("等待运行记录")).foregroundStyle(TerminalStyle.muted)
            }
            ForEach(entries.prefix(3)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.date.formatted(date: .omitted, time: .standard)).foregroundStyle(TerminalStyle.muted)
                    Text(L(entry.text)).foregroundStyle(TerminalStyle.accent).lineLimit(2)
                }.font(TerminalStyle.mono(10))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(TerminalStyle.recess)
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
    }
}

extension AppModel {
    var thermalSummary: String {
        switch thermalStateProvider() {
        case .nominal: return "正常"
        case .fair: return "轻度压力"
        case .serious: return "严重压力"
        case .critical: return "危急压力"
        @unknown default: return "未知"
        }
    }
}
