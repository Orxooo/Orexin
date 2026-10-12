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
    var standalone = false
    var height: CGFloat = 650
    var closePopover: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("orexin.appearance.language") private var languageID = "zh-Hans"

    init(model: AppModel, standalone: Bool = false, height: CGFloat = 650, closePopover: (() -> Void)? = nil) {
        self.model = model; self.sessions = model.sessions; self.appearance = model.appearance
        self.standalone = standalone; self.height = height; self.closePopover = closePopover
    }

    private var protected: Bool { model.snapshot?.lockPolicy == .immediate }
    private var statusColor: Color {
        model.error || model.pending != nil ? TerminalStyle.warning : TerminalStyle.signal
    }
    private var title: String {
        model.busy ? "正在切换" : model.pending != nil ? "等待确认" : model.error ? "需要检查" : model.active?.title ?? "等待核验"
    }
    private var sessionSummary: String {
        if let countdown = model.countdownText { return countdown }
        if sessions.isActive { return sessions.status }
        if model.triggerOwnedMode != nil { return model.triggerSummary }
        return model.verifiedWork ? "手动结束" : "尚未开始会话"
    }
    private var durationUnavailable: Bool {
        model.busy || sessions.isStarting || model.jobRunning || model.snapshot == nil || model.pending != nil || model.error || (sessions.isActive && sessions.deadline == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TerminalSignal(color: TerminalStyle.accent)
                        Text("TLM // LOCAL").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent)
                        Spacer()
                        Text("CPU: \(ProcessInfo.processInfo.activeProcessorCount) CORE").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                        Text(model.snapshot == nil ? "READING" : "IOPM READY").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.signal)
                    }
                    status
                    HStack { TerminalSignal(color: TerminalStyle.accent); Text(L("执行模式 // SELECT POWER VECTOR")).font(TerminalStyle.mono(9)); Spacer() }.foregroundStyle(TerminalStyle.muted)
                    modes
                    matrix
                    quickActions
                    if model.pending != nil || model.error { feedback }
                }.padding(12)
            }.frame(maxWidth: .infinity)
            footer
        }.id(appearance.theme.rawValue + "/" + languageID).frame(width: 500, height: height)
            .environment(\.locale, (AppLanguage(rawValue: languageID) ?? .simplifiedChinese).locale)
            .background { TerminalStyle.paper; TerminalAtmosphere() }
            .foregroundStyle(TerminalStyle.ink).tint(TerminalStyle.accent)
            .buttonStyle(TerminalButtonStyle()).focusEffectDisabled().preferredColorScheme(appearance.theme.colorScheme)
            .onExitCommand { if !standalone { closePopover?() } }
    }

    private var header: some View {
        HStack(spacing: 9) {
            if standalone { ConsoleWindowControls() }
            ApplicationBadge().frame(width: 22, height: 22)
            Text("OREXIN").font(TerminalStyle.mono(14)).tracking(1).shadow(color: TerminalStyle.accent.opacity(0.5), radius: 4)
            Text(OrexinRelease.displayVersion)
                .font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent).padding(5).overlay(Rectangle().strokeBorder(TerminalStyle.accent.opacity(0.4)))
            if standalone { WindowDragRegion().frame(maxWidth: .infinity, maxHeight: .infinity) } else { Spacer(minLength: 0) }
            if let battery = model.battery {
                Text("\(battery.percent)%").font(TerminalStyle.mono(11)).foregroundStyle(TerminalStyle.signal)
                    .help(battery.onBattery ? "电池供电" : "已接电源")
            }
            Button { openMain() } label: {
                TerminalIcon(name: "arrow.up.right.square", size: 15).frame(width: 24, height: 24)
            }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                .accessibilityLabel("打开主窗口").help("打开 Orexin 主窗口")
        }.padding(.horizontal, 14).frame(height: 38).background(TerminalStyle.surface)
            .overlay(alignment: .bottom) { rule }
    }

    private var status: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TerminalCursor()
                    Text("ACTIVE VECTOR // \(model.active == .background ? "01" : model.active == .desk ? "02" : model.active == .normal ? "03" : "UNKNOWN")").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent)
                    if model.snapshot != nil && model.active != nil && !model.busy && !model.error && model.pending == nil {
                        Text(L("已核验")).font(.system(size: 9)).foregroundStyle(TerminalStyle.signal).padding(3).background(TerminalStyle.selection)
                    }
                }
                HStack(spacing: 8) {
                    Text(L(title)).font(.system(size: 23, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).accessibilityAddTraits(.isHeader)
                    if model.busy { ProgressView().controlSize(.small) }
                }
                Text(L(model.active == .normal ? "闲置与合盖时恢复系统自然休眠，释放 Orexin 的保活设置。" : model.active == .background ? "保持唤醒，合盖后继续运行后台任务。" : model.active == .desk ? "保持桌面工作，合盖后允许休眠。" : "当前电源状态尚未匹配工作模式，请等待核验或重新检查。"))
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if sessions.isActive || model.triggerOwnedMode != nil {
                    Text(L(sessionSummary)).font(.system(size: 10)).foregroundStyle(TerminalStyle.accent).lineLimit(1)
                }
                HStack(spacing: 7) {
                    OrbitalReadout(label: "THERMAL", value: model.thermalSummary, color: TerminalStyle.signal, compact: true)
                    OrbitalReadout(label: "IOPM ASSERT", value: model.keepsAwake ? "NoIdleSleep" : model.snapshot == nil ? "UNKNOWN" : "None", compact: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            OrbitalMoon(phase: model.active?.rawValue ?? "unknown", labels: false).frame(width: 104, height: 104)
        }.padding(10).background(TerminalGrid()).terminalSurface()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: title)
    }

    private var modes: some View {
        HStack(spacing: 9) {
            ForEach(Array(WorkMode.allCases.enumerated()), id: \.element) { index, mode in
                modeButton(mode, number: index + 1)
            }
        }
    }

    private func modeButton(_ mode: WorkMode, number: Int) -> some View {
        let selected = model.active == mode && model.pending == nil && !model.error
        let code = mode == .background ? "CLAMSHELL" : mode == .desk ? "PRESENTATION" : "DEFAULT"
        return Button {
            model.quitWhenReady = false
            Task { await model.selectWorkPreset(mode) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("RACK_0\(number)").font(TerminalStyle.mono(9))
                    Spacer(minLength: 0)
                    Rectangle().fill(selected ? TerminalStyle.signal : TerminalStyle.muted).frame(width: 5, height: 5)
                }
                HStack(spacing: 7) {
                    TerminalIcon(name: mode == .background ? "laptopcomputer" : mode == .desk ? "display" : "moon", size: 19)
                    Text(mode.title).font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                }.frame(height: 34, alignment: .leading)
                Text(code).font(TerminalStyle.mono(8)).lineLimit(1).minimumScaleFactor(0.7)
                rule
                Text(selected ? "ACTIVE" : "STANDBY").font(TerminalStyle.mono(9))
            }.foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted)
                .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? TerminalStyle.selection : TerminalStyle.surface)
                .overlay(Rectangle().strokeBorder(TerminalStyle.line, lineWidth: 0.6))
                .overlay(alignment: .top) { Rectangle().fill(selected ? TerminalStyle.accent : .clear).frame(height: 2) }
                .contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .disabled(model.busy || sessions.isStarting || (mode == .background && model.helperStatus != .enabled))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var matrix: some View {
        VStack(alignment: .leading, spacing: 0) {
            PowerAssertionRows(model: model, sessions: sessions, compact: true)
            rule
            HStack(spacing: 8) {
                TerminalIcon(name: "checkmark.shield", size: 14).foregroundStyle(TerminalStyle.signal)
                Text(L(model.helperStatus == .enabled ? "特权守护进程已就绪" : "合盖服务需要授权")).font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                Spacer()
                if model.helperStatus == .enabled {
                    Button(L("重新核验")) { Task { await model.refresh() } }.buttonStyle(TerminalPlainButtonStyle()).foregroundStyle(TerminalStyle.accent).disabled(model.busy)
                } else {
                    Button(L("启用服务"), action: model.enableHelper).buttonStyle(TerminalPlainButtonStyle()).foregroundStyle(TerminalStyle.accent).disabled(model.busy)
                }
            }.padding(.vertical, 8)
        }.padding(.horizontal, 12).terminalSurface()
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                durationButton("+15m", minutes: 15)
                durationButton("+30m", minutes: 30)
                durationButton("+1.0h", minutes: 60)
                durationButton("+2.0h", minutes: 120)
                Button { openMain(); NotificationCenter.default.post(name: .wakeMacOpenCommandTask, object: nil) } label: {
                    Text(L("编译后")).font(.system(size: 10)).frame(maxWidth: .infinity)
                }.workKeyboardFocus(radius: 0)
            }.frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                if let countdown = model.countdownText {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(countdown).font(.system(size: 10)).foregroundStyle(TerminalStyle.warning)
                        Button(L("取消倒计时"), action: model.cancelVisibleCountdown).buttonStyle(TerminalPlainButtonStyle()).font(.system(size: 10)).foregroundStyle(TerminalStyle.accent)
                    }
                } else {
                    Text(L(sessions.isActive && sessions.deadline != nil ? "快捷延长当前定时会话" : sessions.isActive ? "当前会话按任务条件结束" : "快捷开始定时会话"))
                        .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                }
                Spacer(minLength: 0)
                Button { Task { await model.choose(.normal, sleep: true) } } label: {
                    TerminalLabel("立即休眠", systemImage: "power").font(.system(size: 12, weight: .semibold))
                }.buttonStyle(TerminalButtonStyle(prominent: true)).workKeyboardFocus(radius: 0).disabled(model.busy)
            }
        }
    }

    private func durationButton(_ label: String, minutes: Double) -> some View {
        Button {
            Task {
                if sessions.isActive { _ = sessions.extend(minutes: minutes) }
                else {
                    sessions.endCondition = .duration
                    sessions.durationMinutes = minutes
                    await sessions.start()
                }
                model.onUpdate?()
            }
        } label: { Text(L(label)).font(TerminalStyle.mono(10)).frame(maxWidth: .infinity) }
            .workKeyboardFocus(radius: 0).disabled(durationUnavailable)
            .help(sessions.isActive ? "延长当前定时会话" : "按默认工作模式启动定时会话")
    }

    private func openMain() { model.openPreferences?(); if !standalone { closePopover?() } }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkNote(text: model.message, icon: "exclamationmark.circle")
            HStack {
                if model.pending != nil { Button(L("打开系统设置"), action: model.openLockSettings).workKeyboardFocus(radius: 0) }
                Button(L("重新检查")) { model.error = false; Task { await model.refresh() } }.workKeyboardFocus(radius: 0)
            }
        }.padding(12).background(TerminalStyle.surface)
            .overlay(Rectangle().strokeBorder(TerminalStyle.warning.opacity(0.5)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TerminalIcon(name: protected ? "lock.shield" : "lock.trianglebadge.exclamationmark", size: 12)
            Text(L(model.lockSummary)).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(model.display.lidClosed.map { $0 ? "LID::CLOSED" : "LID::OPEN" } ?? "LID::UNKNOWN")
                .font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent)
        }.foregroundStyle(protected ? TerminalStyle.signal : TerminalStyle.muted)
            .padding(.horizontal, 16).frame(height: 32).background(TerminalStyle.surface)
            .overlay(alignment: .top) { rule }
    }
    private var rule: some View { Rectangle().fill(TerminalStyle.line.opacity(0.6)).frame(height: 1) }
}
