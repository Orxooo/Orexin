// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import ServiceManagement
import SwiftUI
import WakeMacCore

struct PowerHomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sessions: SessionController
    var openSessions: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var working: Bool { model.active == .background || model.active == .desk || model.keepsAwake || model.runsWithLidClosed }
    private var statusColor: Color { model.error ? TerminalStyle.warning : model.verifiedWork ? TerminalStyle.signal : TerminalStyle.amber }
    private var status: String {
        if model.busy { return "正在切换" }
        if model.pending != nil { return "等待设置" }
        if model.error { return "需要处理" }
        if model.snapshot == nil || model.active == nil { return "等待核验" }
        return model.verifiedWork ? (model.active == .background && model.helperStatus == .enabled ? "保持唤醒已生效 · 合盖服务已授权" : "保持唤醒已生效") : "允许正常休眠"
    }
    private var detail: String {
        if model.busy || model.error || model.pending != nil { return model.headline }
        switch model.active {
        case .background: return "保持系统唤醒，合盖后继续工作。屏幕行为由下方设置控制。"
        case .desk: return "保持系统唤醒，合盖后允许休眠。适合桌面工作、演示与长时间任务。"
        case .normal: return "工作已收尾，释放 Orexin 的保活设置，让系统恢复自然休眠。"
        case nil: return "读取并核验系统状态后即可开始工作。"
        }
    }
    private var endSummary: String {
        if let countdown = model.countdownText { return countdown }
        if sessions.isActive { return sessions.status }
        if model.triggerOwnedMode != nil { return model.triggerSummary }
        return working ? "手动结束 · 无时间限制" : "尚未开始"
    }
    var body: some View {
        VStack(spacing: 16) {
            hero
            modes
            controls
            if model.pending != nil || model.error {
                WorkCard(title: "需要处理") {
                    WorkNote(text: model.message, icon: "exclamationmark.circle")
                    HStack {
                        if model.pending != nil { Button(L("打开锁屏设置"), action: model.openLockSettings).workKeyboardFocus(radius: 0) }
                        Button(L("重新检查")) { model.error = false; Task { await model.refresh() } }.workKeyboardFocus(radius: 0)
                    }
                }
            }
            OrbitalEventFeed(entries: model.history)
        }.buttonStyle(TerminalButtonStyle()).focusEffectDisabled()
    }
    private var systemUptime: String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("SESSION STATUS // 实时会话状态")).font(TerminalStyle.mono(10)).tracking(0.8).foregroundStyle(TerminalStyle.muted)
                    HStack(alignment: .center, spacing: 12) {
                        Text(L(model.active == .background ? "后台工作中" : model.active == .desk ? "桌面工作中" : model.active?.title ?? "等待核验"))
                            .font(TerminalStyle.display(32)).lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
                        HStack(spacing: 7) {
                            TerminalSignal(color: statusColor)
                            Text(L(status)).font(.system(size: 10, weight: .semibold)).foregroundStyle(statusColor)
                        }.padding(6).background(TerminalStyle.surface)
                        if model.busy { ProgressView().controlSize(.small) }
                    }
                    Text(L(detail)).font(.system(size: 12)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        OrbitalReadout(label: "THERMAL // 温度压力", value: model.thermalSummary, color: model.thermalProtectionRequired ? TerminalStyle.warning : TerminalStyle.signal)
                        OrbitalReadout(label: "ASSERTION // 系统断言", value: model.snapshot == nil ? "待核验" : model.keepsAwake ? "NoIdleSleep" : "None")
                        OrbitalReadout(label: "UPTIME // 系统运行", value: systemUptime, color: TerminalStyle.signal)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                OrbitalMoon(phase: model.active?.rawValue ?? "unknown").frame(width: 220, height: 205)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("结束条件 // TERMINATION")).font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                    Text(L(endSummary)).font(.system(size: 11)).lineLimit(2).help(endSummary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(L("设置结束条件"), action: openSessions).workKeyboardFocus(radius: 0)
                Button(L(working ? "结束工作" : "开始工作")) {
                    model.quitWhenReady = false
                    Task { if working { await model.choose(.normal) } else { await model.beginDefaultSession() } }
                }.buttonStyle(TerminalButtonStyle(prominent: true)).workKeyboardFocus(radius: 0).disabled(model.busy || sessions.isStarting)
            }.padding(12).background(TerminalStyle.surface)
        }.padding(18).background(TerminalStyle.recess).overlay(CRTLines()).terminalSurface()
    }
    private var modes: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(WorkMode.allCases.enumerated()), id: \.element) { index, mode in
                let selected = model.active == mode && model.pending == nil && !model.error
                Button {
                    model.quitWhenReady = false
                    Task { await model.selectWorkPreset(mode) }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("RACK \(String(format: "%02d", index + 1))").font(TerminalStyle.mono(9))
                            Spacer()
                            Rectangle().fill(selected ? TerminalStyle.signal : TerminalStyle.muted.opacity(0.5)).frame(width: 5, height: 5)
                        }.foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted)
                        HStack(spacing: 9) {
                            TerminalIcon(name: mode == .background ? "laptopcomputer" : mode == .desk ? "display" : "moon.zzz", size: 22).foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(TerminalStyle.ink)
                                Text(mode == .background ? "MODE 01 // CLAMSHELL" : mode == .desk ? "MODE 02 // PRESENTATION" : "MODE 03 // DEFAULT POWER")
                                    .font(TerminalStyle.mono(8)).foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted)
                            }
                        }
                        Text(L(mode == .background ? "合盖继续工作，允许屏幕自动关闭。" : mode == .desk ? "保持桌面工作，合盖后允许休眠。" : "释放保活，恢复系统自然休眠。"))
                            .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
                        Text(selected ? "CURRENT ACTIVE" : "SELECT MODE").font(TerminalStyle.mono(9)).foregroundStyle(selected ? TerminalStyle.signal : TerminalStyle.muted)
                    }.frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading).padding(13)
                        .background(selected ? TerminalStyle.surface : TerminalStyle.recess)
                        .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.65)))
                        .overlay(alignment: .top) { Rectangle().fill(selected ? TerminalStyle.accent : TerminalStyle.line).frame(height: 2) }
                }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                    .disabled(model.busy || (mode == .background && model.helperStatus != .enabled))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.active)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("CONTROL MATRIX // 策略调控")).font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted).padding(.top, 16).padding(.bottom, 12)
            PowerAssertionRows(model: model, sessions: sessions)
            rule
            HStack(spacing: 10) {
                TerminalIcon(name: model.helperStatus == .enabled ? "checkmark.shield" : "key", size: 21).frame(width: 25).foregroundStyle(TerminalStyle.signal)
                if model.helperStatus == .enabled { Text(L("合盖服务已授权")).font(.system(size: 11)) }
                else { Button(L(model.helperStatus == .requiresApproval ? "完成合盖服务授权…" : "启用合盖服务…"), action: model.enableHelper).workKeyboardFocus(radius: 0).disabled(model.busy) }
                Spacer()
                if sessions.deadline != nil { Button(L("+15 分钟")) { _ = sessions.extend(minutes: 15); model.onUpdate?() }.workKeyboardFocus(radius: 0).disabled(!model.verifiedWork) }
                Button(L("立即休眠")) { Task { await model.choose(.normal, sleep: true) } }.workKeyboardFocus(radius: 0).disabled(model.busy)
            }.padding(.vertical, 14)
            if model.helperStatus != .enabled && !model.helperMessage.isEmpty { Text(L(model.helperMessage)).font(WorkType.caption).foregroundStyle(TerminalStyle.muted).padding(.bottom, 12) }
        }.padding(.horizontal, 18).background(TerminalStyle.surface)
    }
    private var rule: some View { Rectangle().fill(TerminalStyle.line.opacity(0.6)).frame(height: 1) }
}

/// Both window surfaces use the same labels, state, actions and feedback.
struct PowerAssertionRows: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sessions: SessionController
    @ObservedObject private var screen: WorkScreenPolicy
    var compact = false
    init(model: AppModel, sessions: SessionController, compact: Bool = false) {
        self.model = model; self.sessions = sessions; self.screen = model.workScreen; self.compact = compact
    }
    private var controlsDisabled: Bool { model.busy || model.snapshot == nil || model.pending != nil }
    var body: some View {
        VStack(spacing: 0) {
            TerminalPowerToggle(title: "保持唤醒", detail: "阻止闲置休眠，屏幕仍可自动关闭", icon: "sun.max", code: "KEEP_AWAKE",
                                isOn: Binding(get: { model.keepsAwake }, set: { value in Task { await model.setKeepsAwake(value) } }), compact: compact)
                .disabled(controlsDisabled)
            divider
            TerminalPowerToggle(title: "合盖继续运行", detail: "开启时同时保持唤醒", icon: "laptopcomputer", code: "CLAMSHELL",
                                isOn: Binding(get: { model.runsWithLidClosed }, set: { value in Task { await model.changeSessionLidMode(value) } }), compact: compact)
                .disabled(controlsDisabled || model.helperStatus != .enabled)
            divider
            ForEach(WorkScreenBehavior.choices(for: model.active ?? .desk)) { behavior in
                TerminalPowerToggle(title: behavior.title, detail: behavior.detail, icon: behavior.icon, code: behavior.code,
                                    isOn: Binding(get: { screen.behavior(for: model.active ?? .desk) == behavior }, set: { enabled in
                    let fallback: WorkScreenBehavior = behavior == .systemIdle
                        ? (model.active == .background ? .dim : .normalBrightness) : .systemIdle
                    Task { await model.setWorkScreenBehavior(enabled ? behavior : fallback) }
                }), compact: compact)
                    .disabled(controlsDisabled || !model.verifiedWork || sessions.isStarting)
                divider
            }
            Text(L(screen.status)).font(.system(size: 10))
                .foregroundStyle(screen.status.hasPrefix("屏幕策略未核验：") ? TerminalStyle.warning : TerminalStyle.muted)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).frame(height: 26, alignment: .topLeading)
                .padding(.top, 7).padding(.leading, 9).help(L(screen.status))
            if model.active == .desk {
                WorkToggle(title: "Esc / 亮度键恢复", detail: "屏幕最暗时恢复原亮度，保留桌面工作会话。",
                           isOn: $screen.restoreDesktopBrightnessOnKey)
                if screen.dimExitNeedsInputAccess {
                    Button(L("跨应用恢复需要输入监控权限")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }.font(.system(size: 10)).padding(.vertical, 4)
                }
            }
            HStack {
                Text(L("只关闭显示器，唤醒后继续原屏幕策略"))
                    .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(L("立即熄屏")) { Task { await model.sleepDisplayNow() } }
                    .workKeyboardFocus(radius: 0)
                    .disabled(controlsDisabled || !model.verifiedWork || sessions.isStarting)
            }.padding(.top, 8)
        }
    }
    private var divider: some View { Rectangle().fill(TerminalStyle.line.opacity(0.6)).frame(height: 1) }
}

struct TerminalPowerToggle: View {
    let title: String
    let detail: String
    let icon: String
    let code: String
    @Binding var isOn: Bool
    var compact = false
    var body: some View {
        HStack(spacing: 12) {
            TerminalIcon(name: icon, size: 21).foregroundStyle(TerminalStyle.accent).frame(width: 32, height: 32)
                .background(TerminalStyle.recess).overlay(Rectangle().strokeBorder(TerminalStyle.line))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(L(title)).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(code).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.signal)
                }.frame(height: 32, alignment: .leading)
                Text(L(detail)).font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                    .lineLimit(2).frame(height: 26, alignment: .topLeading).help(L(detail))
            }
            Spacer(minLength: 10)
            Toggle(L(title), isOn: $isOn).labelsHidden().toggleStyle(TerminalSwitchStyle())
        }.padding(.vertical, compact ? 6 : 13)
            .padding(.leading, 9)
            .overlay(alignment: .leading) { Rectangle().fill(TerminalStyle.accent).frame(width: 2).padding(.vertical, compact ? 6 : 13) }
            .clipShape(Rectangle())
    }
}
