// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI
import AppKit
import WakeMacCore

enum MenuMark {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let moon = NSBezierPath()
            moon.move(to: NSPoint(x: 10.5, y: 17))
            moon.curve(to: NSPoint(x: 2.3, y: 7.5), controlPoint1: NSPoint(x: 5.7, y: 15.8), controlPoint2: NSPoint(x: 1.8, y: 12.2))
            moon.curve(to: NSPoint(x: 10.5, y: 1.5), controlPoint1: NSPoint(x: 2.7, y: 3.5), controlPoint2: NSPoint(x: 6.5, y: 1.0))
            moon.curve(to: NSPoint(x: 18, y: 6.8), controlPoint1: NSPoint(x: 14.2, y: 1.8), controlPoint2: NSPoint(x: 16.7, y: 4.0))
            moon.curve(to: NSPoint(x: 10.5, y: 17), controlPoint1: NSPoint(x: 10.6, y: 5.7), controlPoint2: NSPoint(x: 7.9, y: 10.0))
            moon.close(); moon.fill()
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState(); context.setBlendMode(.clear)
                context.setLineWidth(0.55)
                context.move(to: CGPoint(x: 10.0, y: 16.1))
                context.addCurve(to: CGPoint(x: 13.3, y: 2.2), control1: CGPoint(x: 6.6, y: 10.8), control2: CGPoint(x: 8.1, y: 3.9))
                context.strokePath(); context.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Orexin"
        return image
    }
}

struct ControlPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var sessions: SessionController
    @ObservedObject private var appearance: AppearanceController
    @ObservedObject private var screen: WorkScreenPolicy
    var standalone = false
    var height: CGFloat = 720
    var closePopover: (() -> Void)?
    var availableSize: CGSize?
    @AppStorage("orexin.appearance.language") private var languageID = "zh-Hans"

    init(model: AppModel, standalone: Bool = false, height: CGFloat = 720, closePopover: (() -> Void)? = nil, availableSize: CGSize? = nil) {
        self.model = model; self.sessions = model.sessions; self.appearance = model.appearance
        self.screen = model.workScreen; self.standalone = standalone; self.height = height
        self.closePopover = closePopover; self.availableSize = availableSize
    }
    private var size: CGSize {
        appearance.menuLayout.size(available: availableSize ?? NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: height + 64))
    }
    private var disabled: Bool { model.busy || sessions.isStarting || model.snapshot == nil || model.pending != nil }
    private var title: String {
        model.busy ? "正在切换" : model.pending != nil ? "等待确认" : model.error ? "需要检查" : model.active?.title ?? "等待核验"
    }
    private var signal: Color { model.error || model.pending != nil ? MenuHUD.warning : model.keepsAwake ? MenuHUD.signal : MenuHUD.muted }
    private var assertion: String {
        model.snapshot == nil ? "READING" : sessions.effectReport.displayAssertionActive ? "NoDisplaySleep" : model.keepsAwake ? "NoIdleSleep" : "RELEASED"
    }
    private var deadline: Date? { [model.automation.nextDeadline, sessions.deadline, model.serviceSleepAt].compactMap { $0 }.min() }
    private var missionTime: String {
        let seconds: Int
        if let deadline { seconds = max(0, Int(ceil(deadline.timeIntervalSince(model.now)))) }
        else if let start = model.workRequests.active.map(\.createdAt).min() { seconds = max(0, Int(model.now.timeIntervalSince(start))) }
        else { seconds = 0 }
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    private var timeCaption: String { deadline != nil ? "REMAINING" : model.keepsAwake ? "ACTIVE MISSION TIME" : "STANDBY" }
    private var screenChoices: [WorkScreenBehavior] { WorkScreenBehavior.choices(for: model.active ?? .desk) }
    private var keepAwake: Binding<Bool> { Binding(get: { model.keepsAwake }, set: { value in Task { await model.setKeepsAwake(value) } }) }
    private var clamshell: Binding<Bool> { Binding(get: { model.clamshellOptionEnabled }, set: { value in Task { await model.setClamshellOption(value) } }) }
    private var display: Binding<Bool> { Binding(get: { screen.behavior(for: model.active ?? .desk) == .normalBrightness }, set: { value in
        Task { await model.setWorkScreenBehavior(value ? .normalBrightness : .systemIdle) }
    }) }
    private var saver: Binding<Bool> { Binding(get: { sessions.effectivePreventScreenSaver }, set: { value in Task { await model.changeScreenSaverPrevention(value) } }) }
    private var unlocked: Binding<Bool> { Binding(get: { model.unlockedWorkEnabled }, set: { value in Task { await model.setUnlockedWork(value) } }) }


    private var dimmed: Binding<Bool> {
        Binding(get: { screen.behavior(for: model.active ?? .desk) == .dim }, set: { value in
            Task { await model.setWorkScreenBehavior(value ? .dim : .normalBrightness) }
        })
    }
    private var modeCode: String { model.active == .normal ? "NORMAL" : model.active == nil ? "—" : "AWAKE" }
    private var thermalLevel: Int {
        switch model.thermalStateProvider() { case .nominal: 3; case .fair: 5; case .serious: 7; case .critical: 8; @unknown default: 0 }
    }
    private var thermalColor: Color { thermalLevel <= 3 ? MenuHUD.signal : thermalLevel < 8 ? MenuHUD.amber : MenuHUD.warning }

    var body: some View {
        Group { if appearance.menuLayout == .deck { deck } else { band } }
            .frame(width: size.width, height: size.height)
            .environment(\.locale, (AppLanguage(rawValue: languageID) ?? .simplifiedChinese).locale)
            .background(appearance.menuLayout == .band ? Color.clear : MenuHUD.paper)
            .foregroundStyle(MenuHUD.ink).tint(MenuHUD.accent).font(.system(size: 11))
            .preferredColorScheme(appearance.theme.colorScheme).focusEffectDisabled()
            .onExitCommand { if !standalone { closePopover?() } }
    }

    private var deck: some View {
        VStack(spacing: 10) {
            deckHeader
            ScrollView {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) { statusDeck; interlocks }.frame(maxWidth: .infinity)
                    missionPresets.frame(width: (size.width - 30) * 0.325)
                }.padding(.bottom, 1)
            }.scrollIndicators(.hidden)
            eventStream
        }.padding(10)
    }
    private var deckHeader: some View {
        HStack(spacing: 12) {
            if standalone { ConsoleWindowControls() }
            MenuLight(color: MenuHUD.accent, size: 8)
            Text("OREXIN //\nSYS.ORBITAL").font(MenuHUD.serif(17, bold: true))
                .foregroundStyle(MenuHUD.accent).lineSpacing(0)
            if standalone { WindowDragRegion().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { Spacer(minLength: 0) }
            headerReading("AVIONICS", value: "HUD / " + OrexinRelease.displayVersion, color: MenuHUD.muted)
            headerReading("IOPM:", value: model.snapshot == nil ? "READING" : model.keepsAwake ? "ASSERTED" : "RELEASED", color: signal)
            headerReading("SYSTEM //", value: "\(ProcessInfo.processInfo.activeProcessorCount) CPU / \(Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)) GB", color: MenuHUD.secondary)
            moreMenu
        }.padding(.horizontal, 14).frame(height: 54).background(MenuHUD.surface, in: MenuCutShape(cut: 14))
    }
    private func headerReading(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title); Text(value)
        }.font(MenuHUD.serif(9, bold: true)).foregroundStyle(color).fixedSize()
    }
    private var statusDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            sector("01", title: "RETICLE DECK", color: MenuHUD.accent)
            HStack(spacing: 14) {
                OrbitalMoon(phase: model.active?.rawValue ?? "unknown", labels: false)
                    .environment(\.consoleArtworkModule, standalone ? .notices : .command)
                    .frame(width: min(144, (size.width - 30) * 0.24), height: 144)
                VStack(alignment: .leading, spacing: 5) {
                    Button(action: cycleMode) {
                        HStack(spacing: 6) {
                            Text(model.keepsAwake ? "AWAKE.VEC" : "NORMAL.VEC").font(MenuHUD.serif(10, bold: true))
                                .padding(.horizontal, 6).padding(.vertical, 3).background(MenuHUD.accent).foregroundStyle(MenuHUD.onAccent)
                            Text(L(model.keepsAwake ? "唤醒模式运行中" : title)).font(MenuHUD.song(16)).foregroundStyle(signal)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(MenuActionStyle()).disabled(disabled).accessibilityHint(L("切换模式"))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(timeCaption); Spacer(minLength: 0); Text(model.keepsAwake ? "RUNNING" : "IDLE").foregroundStyle(MenuHUD.accent) }
                            .font(MenuHUD.serif(9, bold: true)).foregroundStyle(MenuHUD.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(String(missionTime.dropLast(2))).foregroundStyle(MenuHUD.ink)
                            Text(String(missionTime.suffix(2))).foregroundStyle(model.keepsAwake ? MenuHUD.signal : MenuHUD.muted)
                        }.font(MenuHUD.serif(30, bold: true)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    }.padding(7).frame(maxWidth: .infinity, alignment: .leading).background(MenuHUD.recess)
                    HStack(spacing: 5) {
                        metric("ASSERTION", value: assertion, color: MenuHUD.ink)
                        metric("POWER", value: model.battery.map { "\($0.percent)%" } ?? "—", color: MenuHUD.signal)
                    }
                }.frame(maxWidth: .infinity)
            }
            HStack(spacing: 5) {
                Text(model.keepsAwake ? "CARRIER: CONTINUOUS WAKE-LOCK" : "CARRIER: SYSTEM POWER POLICY")
                    .font(MenuHUD.serif(9)).foregroundStyle(MenuHUD.muted).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                ForEach(0..<7) { index in Rectangle().fill(model.keepsAwake && index < 5 ? index == 4 ? MenuHUD.signal : MenuHUD.accent : MenuHUD.line).frame(width: 7, height: 10) }
            }.padding(.horizontal, 3).padding(.vertical, 3).background(MenuHUD.recess)
        }.padding(14).frame(height: 234).background { MenuHUD.surface; MenuDeckGrid() }
            .clipShape(MenuCutShape(cut: 20))
    }
    private func metric(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(MenuHUD.serif(9)).foregroundStyle(MenuHUD.muted)
            Text(value).font(MenuHUD.serif(10, bold: true)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(5).background(MenuHUD.silver)
    }
    private func sector(_ number: String, title: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: number == "01" ? "scope" : "slider.horizontal.3").font(.system(size: 15))
            Text("SECTOR." + number + " // " + title).font(MenuHUD.serif(13, bold: true)).tracking(0.3)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }.foregroundStyle(color)
    }
    private var interlocks: some View {
        VStack(spacing: 5) {
            sector("02", title: "POWER INTERLOCK ARRAY", color: MenuHUD.signal).padding(.bottom, 8)
            interlock("01", title: "保持唤醒", code: "HOLD_CPU_EXECUTION_STATE", binding: keepAwake, effective: model.keepsAwake)
                .disabled(disabled)
            interlock("02", title: "合盖继续运行", code: "CLAMSHELL_MODE_OVERRIDE", binding: clamshell, effective: model.runsWithLidClosed)
                .disabled(disabled || model.helperStatus != .enabled)
            interlock("03", title: "屏幕最暗", code: "PANEL_BACKLIGHT_DIM", binding: dimmed, effective: model.verifiedWork && dimmed.wrappedValue)
                .disabled(disabled || !model.verifiedWork || !model.allowsScreenChoice(.dim))

            interlock("04", title: "防止闲时屏保", code: "BLOCK_SAVER_ACTIVATION", binding: saver, effective: model.verifiedWork && sessions.effectReport.screenSaverAssertionActive)
                .disabled(disabled || model.screenEffectsControlledByOtherTasks || model.otherTasksRequireScreenSaverPrevention)
            interlock("05", title: "工作时保持未锁定", code: "SESSION_AUTHORIZATION", binding: unlocked, effective: model.verifiedWork && model.snapshot?.lockPolicy == .off)
                .disabled(disabled || (!model.unlockedWorkEnabled && model.helperStatus != .enabled))
            if model.error || model.pending != nil {
                Text(L(model.message)).font(.system(size: 9)).foregroundStyle(MenuHUD.warning).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.horizontal, 14).padding(.vertical, 16).frame(minHeight: 284).background(MenuHUD.surface, in: MenuCutShape(cut: 20))
    }
    private func interlock(_ number: String, title: String, code: String, binding: Binding<Bool>, effective: Bool) -> some View {
        HStack(spacing: 9) {
            Text("PWR." + number).font(MenuHUD.serif(10, bold: true)).foregroundStyle(binding.wrappedValue ? MenuHUD.accent : MenuHUD.muted)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title)).font(MenuHUD.song(14.5)).foregroundStyle(MenuHUD.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(code).font(MenuHUD.serif(10)).foregroundStyle(MenuHUD.muted).lineLimit(1).minimumScaleFactor(0.65)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(L(title), isOn: binding).labelsHidden().toggleStyle(MenuDeckSwitchStyle(title: L(title), effective: effective))
        }.padding(.horizontal, 10).frame(height: 42)
            .background(binding.wrappedValue ? MenuHUD.silver : MenuHUD.surface.opacity(0.3), in: MenuInterlockShape(reverse: number == "02" || number == "04"))
    }
    private var missionPresets: some View {
        VStack(spacing: 10) {
            thermalDeck.frame(height: 106)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text("MISSION PRESET"); Spacer(minLength: 0); Text("DIAL").foregroundStyle(MenuHUD.accent) }
                    .font(MenuHUD.serif(11, bold: true)).padding(.bottom, 8)
                ForEach([15, 30, 60, 120], id: \.self) { minutes in preset(minutes) }
                Button { engage(nil) } label: {
                    HStack { Text("∞ INFINITY"); Spacer(minLength: 0); Text("ORBIT").font(MenuHUD.serif(8)) }
                        .font(MenuHUD.serif(20, bold: true)).foregroundStyle(MenuHUD.secondary)
                        .padding(.horizontal, 10).frame(height: 38).background(MenuHUD.recess, in: MenuCutShape(cut: 10))
                }.buttonStyle(MenuActionStyle(cut: 10)).disabled(disabled || model.jobRunning || sessions.isActive)
                Spacer(minLength: 12)
                Button { Task { await model.sleepDisplayNow() } } label: {
                    HStack { Image(systemName: "display").font(.system(size: 16)); Text(L("立即熄屏")); Spacer(minLength: 0); Text("DISP.OFF").font(MenuHUD.serif(8)) }
                }.buttonStyle(MenuDeckButtonStyle()).disabled(disabled || !model.verifiedWork || model.otherTasksRequireDisplay)
                Button(role: .destructive) { Task { await model.choose(.normal, sleep: true) } } label: {
                    HStack { Image(systemName: "power").font(.system(size: 17)); Text(L("立即休眠")); Spacer(minLength: 0); Text("SLEEP").font(MenuHUD.serif(8)) }
                }.buttonStyle(MenuDeckButtonStyle(prominent: true)).disabled(model.busy)
            }.padding(14).frame(height: 412).background(MenuHUD.surface, in: MenuCutShape(cut: 20))
        }
    }
    private func preset(_ minutes: Int) -> some View {
        let selected = sessions.isActive && sessions.deadline != nil && Int(sessions.durationMinutes) == minutes
        let captions = [15: "BURST", 30: "STAGING", 60: "ACTIVE", 120: "EXTENDED"]
        return Button { engage(Double(minutes)) } label: {
            HStack {
                Text(minutes < 60 ? "+\(minutes) MIN" : String(format: "+%.1f HOUR", Double(minutes) / 60))
                    .font(MenuHUD.serif(20, bold: true)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(selected ? "ACTIVE" : minutes == 60 ? "STANDARD" : captions[minutes] ?? "").font(MenuHUD.serif(8))
            }.padding(.horizontal, 10).frame(height: 38)
                .foregroundStyle(selected ? MenuHUD.onAccent : MenuHUD.ink)
                .background(selected ? MenuHUD.accent : MenuHUD.recess, in: MenuCutShape(cut: 10))
        }.buttonStyle(MenuActionStyle(cut: 10)).disabled(disabled || model.jobRunning || model.error || (sessions.isActive && sessions.deadline == nil))
            .accessibilityLabel(L(selected ? "延长会话" : "开始默认会话") + " \(minutes) min")
    }
    private var thermalDeck: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text("THERMAL.IO"); Spacer(minLength: 0); Text(L(model.thermalSummary)).foregroundStyle(thermalColor) }
                .font(MenuHUD.serif(12, bold: true))
            VStack(spacing: 4) {
                HStack(spacing: 4) { ForEach(0..<8) { index in Rectangle().fill(index >= thermalLevel ? MenuHUD.line : index < 3 ? MenuHUD.signal : index < 5 ? MenuHUD.accent : index == 7 ? MenuHUD.warning : MenuHUD.amber).frame(height: 15) } }
                HStack { Text("COOL"); Spacer(minLength: 0); Text("MED"); Spacer(minLength: 0); Text("CRIT") }
                    .font(MenuHUD.serif(9)).foregroundStyle(MenuHUD.muted)
            }.padding(5).background(MenuHUD.recess)
            HStack {
                Text("POWER:").foregroundStyle(MenuHUD.muted)
                Spacer(minLength: 0)
                Text(model.battery.map { "\($0.percent)% / " + ($0.onBattery ? "BAT" : "AC") } ?? "—").foregroundStyle(MenuHUD.signal)
            }.font(MenuHUD.serif(10, bold: true))
        }.padding(14).background(MenuHUD.surface, in: MenuCutShape(cut: 20))
    }
    private var eventStream: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "terminal").foregroundStyle(MenuHUD.accent)
                Text("TLM.STREAM // IOPM_ASSERTIONS").foregroundStyle(MenuHUD.muted)
                Spacer(minLength: 0)
                Button(L(model.helperStatus == .enabled ? "重新核验" : "启用服务")) {
                    if model.helperStatus == .enabled { Task { await model.refresh() } } else { model.enableHelper() }
                }.buttonStyle(MenuActionStyle()).foregroundStyle(model.helperStatus == .enabled ? MenuHUD.signal : MenuHUD.amber)
                Text("LOCAL").foregroundStyle(MenuHUD.accent)
            }.font(MenuHUD.serif(9)).padding(.bottom, 2)
            if model.history.isEmpty { Text(L("等待运行记录")).font(.system(size: 9)).foregroundStyle(MenuHUD.muted) }
            ForEach(model.history.prefix(2)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.date.formatted(date: .omitted, time: .standard)).foregroundStyle(MenuHUD.muted)
                    Text(L(entry.text)).foregroundStyle(MenuHUD.accent).lineLimit(1)
                }.font(MenuHUD.mono(8))
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).frame(height: 72).background(MenuHUD.recess, in: MenuCutShape(cut: 14))
    }

    private var band: some View {
        bandRack(compact: size.width < 1000)
            .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading).frame(height: 74)
            .background(MenuHUD.surface)
            .overlay(Rectangle().strokeBorder(MenuHUD.line.opacity(0.55), lineWidth: 0.6))
            .shadow(color: MenuHUD.accent.opacity(0.18), radius: 8, x: -4)
            .shadow(color: MenuHUD.secondary.opacity(0.15), radius: 8, x: 4)
            .padding(4)
    }
    private func bandRack(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Button(action: cycleMode) {
                HStack(spacing: 9) {
                    ZStack(alignment: .bottomTrailing) {
                        ApplicationBadge().frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                        MenuLight(color: signal, size: 6).padding(1)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(L(title)).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(modeCode).font(MenuHUD.mono(8)).padding(.horizontal, 4).padding(.vertical, 2).background(MenuHUD.silver)
                        }
                        HStack(spacing: 5) { Text(L("切换模式")); Image(systemName: "chevron.right") }.font(.system(size: 9)).foregroundStyle(MenuHUD.muted)
                    }
                }.frame(width: compact ? 132 : 158, alignment: .leading)
            }.buttonStyle(MenuActionStyle()).disabled(disabled)
            separator
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    MenuLight(color: signal, size: 6)
                    Text(model.keepsAwake ? "AWAKE ACTIVE" : "SYSTEM NORMAL").font(MenuHUD.mono(9))
                    if !compact, let pid = model.serviceInfo?.pid { Text("PID \(pid)").font(MenuHUD.mono(7)).padding(.horizontal, 3).background(MenuHUD.silver) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(missionTime).font(.system(size: compact ? 18 : 21, weight: .semibold, design: .monospaced)).tracking(0.5)
                    if !compact { Text(deadline != nil ? "REMAINING" : "ELAPSED").font(MenuHUD.mono(6)).foregroundStyle(MenuHUD.muted) }
                }
            }.frame(width: compact ? 118 : 170, alignment: .leading)
            if !compact {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium").foregroundStyle(thermalColor)
                    Text(L(model.thermalSummary)).font(MenuHUD.mono(10))
                }.frame(width: 84, height: 44, alignment: .center)
                separator
            }
            MenuActionRail(accent: MenuHUD.accent, background: MenuHUD.recess, border: MenuHUD.line,
                           previousLabel: L("向左滚动"), nextLabel: L("向右滚动")) {
                HStack(spacing: compact ? 6 : 8) {
            bandToggle("合盖继续运行", label: "合盖运行", binding: clamshell, enabled: !disabled && model.helperStatus == .enabled, width: compact ? 72 : 90)
            bandToggle("正常亮度", label: "屏幕常亮", binding: display, enabled: !disabled && model.verifiedWork && (!display.wrappedValue || model.allowsScreenChoice(.systemIdle)), width: compact ? 82 : 96)
            bandToggle("防止闲时屏保", label: "防屏保", binding: saver, enabled: !disabled && !model.screenEffectsControlledByOtherTasks && !model.otherTasksRequireScreenSaverPrevention, width: compact ? 74 : 82)
            bandToggle("工作时保持未锁定", label: "未锁定", binding: unlocked, enabled: !disabled && (model.unlockedWorkEnabled || model.helperStatus == .enabled), width: compact ? 74 : 82)
            separator
            HStack(spacing: 0) { bandPreset(15); bandPreset(30) }.background(MenuHUD.recess)
            railCommands
                }.padding(.horizontal, 12)
            }.frame(maxWidth: .infinity).frame(height: 44)

        }.foregroundStyle(MenuHUD.ink)
    }
    private var separator: some View { Rectangle().fill(MenuHUD.line).frame(width: 1, height: 40) }
    private func bandToggle(_ title: String, label: String, binding: Binding<Bool>, enabled: Bool, width: CGFloat) -> some View {
        Toggle(L(title), isOn: binding).toggleStyle(MenuBandSwitchStyle(label: L(label), width: width)).disabled(!enabled).accessibilityLabel(L(title))
    }
    private func bandPreset(_ minutes: Int) -> some View {
        Button { engage(Double(minutes)) } label: { Text("+\(minutes)m").font(MenuHUD.mono(10)).frame(width: 43, height: 32) }
            .buttonStyle(MenuActionStyle()).disabled(disabled || model.jobRunning || model.error || (sessions.isActive && sessions.deadline == nil))
    }
    private var moreMenu: some View {
        Button(action: openMain) { Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 28).foregroundStyle(MenuHUD.accent) }
            .buttonStyle(MenuActionStyle()).accessibilityLabel(L("打开主窗口"))
    }
    @ViewBuilder private var railCommands: some View {
        railButton("打开主窗口", icon: "arrow.up.right.square", action: openMain)
        railButton(model.helperStatus == .enabled ? "重新核验" : "启用服务", icon: "checkmark.shield") {
            if model.helperStatus == .enabled { Task { await model.refresh() } } else { model.enableHelper() }
        }.disabled(model.busy)
        if !model.workRequests.active.isEmpty {
            railButton("并行工作请求", icon: "list.bullet") { model.openWorkRequests(); closePopover?() }
        }
        ForEach(screenChoices.filter { model.allowsScreenChoice($0) }) { choice in
            railButton(choice.title, icon: choice.icon) { Task { await model.setWorkScreenBehavior(choice) } }.disabled(disabled || !model.verifiedWork)
        }
        if model.countdownText != nil { railButton("取消倒计时", icon: "xmark", action: model.cancelVisibleCountdown) }
        railButton("立即熄屏", icon: "display") { Task { await model.sleepDisplayNow() } }.disabled(disabled || !model.verifiedWork || model.otherTasksRequireDisplay)
        railButton("立即休眠", icon: "power") { Task { await model.choose(.normal, sleep: true) } }.disabled(model.busy)
        if model.pending != nil { railButton("打开系统设置", icon: "gearshape", action: model.openLockSettings) }
        railButton("退出 Orexin", icon: "power") { Task { await model.requestQuit() } }.disabled(model.busy)
    }
    private func railButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: icon).symbolRenderingMode(.monochrome).foregroundStyle(MenuHUD.ink); Text(L(title)) }.font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).frame(height: 32).foregroundStyle(MenuHUD.ink).background(MenuHUD.recess)
        }.buttonStyle(MenuActionStyle())
    }
    private func engage(_ minutes: Double?) {
        Task {
            if let minutes, sessions.isActive { _ = sessions.extend(minutes: minutes) }
            else { sessions.endCondition = minutes == nil ? .indefinite : .duration; if let minutes { sessions.durationMinutes = minutes }; await sessions.start() }
            model.onUpdate?()
        }
    }
    private func cycleMode() { Task { await model.selectWorkPreset(model.keepsAwake ? .normal : model.preferredAwakeMode) } }
    private func openMain() { model.openPreferences?(); if !standalone { closePopover?() } }
}

private enum MenuHUD {
    static var paper: Color { TerminalStyle.paper }
    static var surface: Color { TerminalStyle.surface }
    static var silver: Color { TerminalStyle.silver }
    static var recess: Color { TerminalStyle.recess }
    static var ink: Color { TerminalStyle.ink }
    static var muted: Color { TerminalStyle.muted }
    static var line: Color { TerminalStyle.line }
    static var accent: Color { TerminalStyle.accent }
    static var signal: Color { TerminalStyle.signal }
    static var amber: Color { TerminalStyle.amber }
    static var warning: Color { TerminalStyle.warning }
    static var secondary: Color { TerminalStyle.secondary }
    static var onAccent: Color { TerminalStyle.onAccent }
    static func mono(_ size: CGFloat) -> Font { .custom("IBMPlexMono", size: size) }
    static func serif(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT", size: size) }
    static func song(_ size: CGFloat) -> Font { .custom("STSongti-SC-Bold", size: size) }
}
private struct MenuLight: View {
    let color: Color
    var size: CGFloat = 5
    var body: some View { Circle().fill(color).frame(width: size, height: size).shadow(color: color.opacity(0.65), radius: 4) }
}
private struct MenuCutShape: Shape {
    var cut: CGFloat = 10
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut)); p.closeSubpath()
        }
    }
}
private struct MenuInterlockShape: Shape {
    var reverse = false
    func path(in r: CGRect) -> Path {
        let s: CGFloat = 10
        return Path { p in
            p.move(to: CGPoint(x: reverse ? 0 : s, y: 0)); p.addLine(to: CGPoint(x: reverse ? r.maxX - s : r.maxX, y: 0))
            p.addLine(to: CGPoint(x: reverse ? r.maxX : r.maxX - s, y: r.maxY)); p.addLine(to: CGPoint(x: reverse ? s : 0, y: r.maxY)); p.closeSubpath()
        }
    }
}
private struct MenuDeckSwitchStyle: ToggleStyle {
    let title: String
    let effective: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 5) {
                Text(effective ? "ACTIVE" : "STANDBY").font(MenuHUD.serif(9))
                    .frame(width: 54, height: 18).foregroundStyle(effective ? MenuHUD.onAccent : MenuHUD.muted)
                    .background(effective ? MenuHUD.accent : MenuHUD.line.opacity(0.7))
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Rectangle().fill(MenuHUD.recess)
                    Rectangle().fill(configuration.isOn ? MenuHUD.accent : MenuHUD.muted).frame(width: 15, height: 16).padding(3)
                        .shadow(color: configuration.isOn ? MenuHUD.accent.opacity(0.65) : .clear, radius: 5)
                }.frame(width: 43, height: 22)
            }.opacity(enabled ? 1 : 0.45)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: configuration.isOn)
        }.buttonStyle(MenuActionStyle()).accessibilityLabel(title).accessibilityValue(configuration.isOn ? "ON" : "OFF")
    }
}
private struct MenuDeckButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) { configuration.trigger() } label: {
            configuration.label.font(MenuHUD.song(12)).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 38)
                .foregroundStyle(prominent ? MenuHUD.onAccent : MenuHUD.ink)
                .background(prominent ? Color(red: 0.78, green: 0.04, blue: 0.07) : MenuHUD.silver, in: MenuCutShape(cut: 9)).opacity(enabled ? 1 : 0.4)
        }.buttonStyle(MenuActionStyle(cut: 9))
    }
}
private struct MenuBandSwitchStyle: ToggleStyle {
    let label: String
    let width: CGFloat
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                MenuLight(color: configuration.isOn ? MenuHUD.accent : MenuHUD.muted, size: 5)
                Text(label).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(configuration.isOn ? "ON" : "OFF").font(MenuHUD.mono(9)).foregroundStyle(configuration.isOn ? MenuHUD.ink : MenuHUD.muted)
                    .padding(.horizontal, 4).padding(.vertical, 2).background(MenuHUD.paper)
            }.frame(width: width, height: 32).background(MenuHUD.recess).opacity(enabled ? 1 : 0.4)
        }.buttonStyle(MenuActionStyle()).accessibilityLabel(label).accessibilityValue(configuration.isOn ? "ON" : "OFF")
    }
}
private struct MenuDeckGrid: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: CGFloat(10), through: size.width, by: 20) {
                for y in stride(from: CGFloat(10), through: size.height, by: 20) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(MenuHUD.accent.opacity(0.12)))
                }
            }
        }.allowsHitTesting(false)
    }
}
private struct MenuActionStyle: PrimitiveButtonStyle {
    var cut: CGFloat = 0
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role) { ControlAudio.shared.click(); configuration.trigger() } label: { configuration.label }
            .buttonStyle(MenuPressStyle(cut: cut))
    }
}
private struct MenuPressStyle: ButtonStyle {
    let cut: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.brightness(configuration.isPressed ? -0.16 : 0)
            .opacity(enabled ? 1 : 0.45)
            .clipShape(MenuCutShape(cut: cut)).contentShape(MenuCutShape(cut: cut))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
