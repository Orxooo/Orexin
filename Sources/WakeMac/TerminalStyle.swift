// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import CoreText
import SwiftUI

/// The same instrument hierarchy in dark orbital and light cobalt appearances.
enum TerminalStyle {
    static var ink: Color { adaptive(0x242A30, 0xCEE8EB) }
    static var muted: Color { adaptive(0x65717D, 0x82959B) }
    static var line: Color { adaptive(0xBBC5D0, 0x2C3C44) }
    static var paper: Color { adaptive(0xF3F5F7, 0x0C141C) }
    static var surface: Color { adaptive(0xFFFFFF, 0x151F28) }
    static var recess: Color { adaptive(0xEAF0F5, 0x070F17) }
    static var silver: Color { adaptive(0xE0E5EA, 0x202D37) }
    static var accent: Color { adaptive(0x002FA7, 0x00D9EB) }
    static var selection: Color { adaptive(0xE4E9F7, 0x103B43) }
    static var signal: Color { adaptive(0x002FA7, 0x42EDAE) }
    static var amber: Color { adaptive(0xA97125, 0xF3A567) }
    static var steel: Color { adaptive(0x5D7D9B, 0x789BA9) }
    static var warning: Color { adaptive(0xA14E43, 0xF3A29A) }
    static var secondary: Color { adaptive(0x63509B, 0xBFA2E1) }
    static var onAccent: Color { adaptive(0xFFFFFF, 0x06212B) }
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func mono(_ size: CGFloat) -> Font { .custom("IBMPlexMono", size: size) }
    private static let colors = NSCache<NSString, NSColor>()
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        let selectedTheme = UserDefaults.standard.string(forKey: "orexin.appearance.theme") ?? "dark"
        let key = "Orexin.\(selectedTheme).\(light).\(dark)" as NSString
        if let color = colors.object(forKey: key) { return Color(nsColor: color) }
        let color = NSColor(name: NSColor.Name(key as String)) { appearance in
            let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let amber = selectedTheme == "amber"
            let amberColor: UInt32 = dark == 0x00D9EB ? 0xF3A567 : dark == 0x42EDAE ? 0xFFC568 : dark == 0x103B43 ? 0x3B2C1C : dark
            let hex = darkMode ? (amber ? amberColor : dark) : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        colors.setObject(color, forKey: key)
        return Color(nsColor: color)
    }
    @MainActor static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "IBMPlexMono-Regular", withExtension: "ttf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

struct TerminalFrame: Shape {
    var cut: CGFloat = 0
    func path(in r: CGRect) -> Path {
        let c = min(cut, min(r.width, r.height) / 2)
        return Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

struct TerminalBrackets: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0),
                                  (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
                p.move(to: CGPoint(x: x + dx * 8, y: y))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y + dy * 8))
            }
        }
    }
}

struct TerminalGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: CGFloat(0), through: size.width, by: 16) {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: 16) {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(TerminalStyle.line.opacity(0.12)), lineWidth: 0.5)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct TerminalButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    var sound = true
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            if sound { ControlAudio.shared.click() }
            configuration.trigger()
        } label: { configuration.label }
            .buttonStyle(TerminalRenderedButtonStyle(prominent: prominent))
    }
}

private struct TerminalRenderedButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        TerminalButtonBody(configuration: configuration, prominent: prominent, enabled: enabled, reduceMotion: reduceMotion)
    }
    private struct TerminalButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        let enabled: Bool
        let reduceMotion: Bool
        @State private var hovered = false
        private var destructive: Bool { configuration.role == .destructive }
        private var color: Color { destructive ? TerminalStyle.warning : TerminalStyle.accent }
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 15).frame(minHeight: 36)
                .foregroundStyle(prominent ? TerminalStyle.onAccent : destructive ? TerminalStyle.warning : TerminalStyle.ink)
                .background(prominent ? color : hovered && enabled ? TerminalStyle.selection : TerminalStyle.silver.opacity(0.65))
                .clipShape(Rectangle())
                .overlay(Rectangle().strokeBorder(prominent ? color : TerminalStyle.line, lineWidth: 1))
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .offset(y: configuration.isPressed && !reduceMotion ? 2 : 0)
                .brightness(configuration.isPressed ? -0.15 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .onHover { hovered = $0 }
                .modifier(ControlPressFeedback(pressed: configuration.isPressed, enabled: enabled))
        }
    }
}

struct TerminalPlainButtonStyle: PrimitiveButtonStyle {
    var sound = true
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            if sound { ControlAudio.shared.click() }
            configuration.trigger()
        } label: { configuration.label }
            .buttonStyle(TerminalRenderedPlainButtonStyle())
    }
}

private struct TerminalRenderedPlainButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .offset(y: configuration.isPressed && !reduceMotion ? 1.5 : 0)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58), value: configuration.isPressed)
            .modifier(ControlPressFeedback(pressed: configuration.isPressed, enabled: enabled))
    }
}

struct TerminalSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let binding = Binding(get: { configuration.isOn }, set: { value in
            guard value != configuration.isOn else { return }
            configuration.isOn = value
            ControlAudio.shared.click()
        })
        return Button { binding.wrappedValue.toggle() } label: {
            ZStack(alignment: .leading) {
                Rectangle().fill(configuration.isOn ? TerminalStyle.accent : TerminalStyle.silver)
                    .frame(width: 31, height: 25)
                    .offset(x: configuration.isOn ? 0 : 31)
                HStack(spacing: 0) {
                    Text("ON").foregroundStyle(configuration.isOn ? TerminalStyle.onAccent : TerminalStyle.muted).frame(width: 31, height: 25)
                    Text("OFF").foregroundStyle(configuration.isOn ? TerminalStyle.muted : TerminalStyle.ink).frame(width: 31, height: 25)
                }
            }.font(TerminalStyle.mono(10))
                .padding(3).background(TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(configuration.isOn ? TerminalStyle.accent.opacity(0.65) : TerminalStyle.line))
                .opacity(enabled ? 1 : 0.4).padding(.vertical, 3).contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle(sound: false)).workKeyboardFocus(radius: 0)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: configuration.isOn)
            .accessibilityRepresentation {
                Toggle(isOn: binding) { configuration.label }.toggleStyle(.switch)
            }
    }
}

extension View {
    func terminalSurface(cut: CGFloat = 0) -> some View {
        background(TerminalStyle.surface)
            .clipShape(TerminalFrame(cut: cut))
            .overlay(TerminalFrame(cut: cut).stroke(TerminalStyle.line, lineWidth: 1))
            .overlay(TerminalBrackets().stroke(TerminalStyle.accent.opacity(0.6), lineWidth: 1).padding(6).allowsHitTesting(false))
    }
}

private struct TerminalReveal: ViewModifier {
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { visible = true } }
    }
}

extension View {
    func terminalReveal() -> some View { modifier(TerminalReveal()) }
}
