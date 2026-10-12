// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import SwiftUI

struct ThermalProtectionView: View {
    @ObservedObject var model: AppModel
    let availableWidth: CGFloat
    private var state: ProcessInfo.ThermalState { model.thermalObservedState ?? model.thermalStateProvider() }
    private var level: Int? {
        switch state { case .nominal: 0; case .fair: 1; case .serious: 2; case .critical: 3; @unknown default: nil }
    }
    private var stateTitle: String {
        switch state { case .nominal: "正常"; case .fair: "轻度"; case .serious: "严重"; case .critical: "危急"; @unknown default: "未知" }
    }
    private var stateCode: String {
        switch state { case .nominal: "NOMINAL"; case .fair: "MODERATE"; case .serious: "HEAVY"; case .critical: "CRITICAL"; @unknown default: "UNKNOWN" }
    }
    private var pressureColor: Color { level.map { $0 < 2 ? TerminalStyle.accent : TerminalStyle.warning } ?? TerminalStyle.muted }
    private var safeguardCode: String {
        if model.thermalCleanupPending { return "CLEANUP PENDING" }
        if !model.thermalReleaseEnabled { return "DISARMED" }
        return model.thermalProtectionRequired ? "INTERCEPTED" : "ARMED"
    }
    private var safeguardTitle: String {
        if model.thermalCleanupPending { return "正在释放保活，等待系统确认" }
        if !model.thermalReleaseEnabled { return "温度紧急释放已关闭" }
        return model.thermalProtectionRequired ? "温度保护已触发" : "温度保护已就绪"
    }
    private var assertionState: String {
        guard let held = model.snapshot?.idleSleepPrevented else { return "UNKNOWN" }
        return held ? "ENGAGED" : "RELEASED"
    }
    private var lidState: String {
        guard let lease = model.snapshot?.backgroundLeaseActive, let disabled = model.snapshot?.sleepDisabled else { return "UNKNOWN" }
        if lease && disabled { return "ENGAGED" }
        return !lease && !disabled ? "RELEASED" : "UNVERIFIED"
    }
    private var thermalEntries: [HistoryEntry] { model.history.filter { $0.text.contains("温度") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            metadata
            pressurePanel
            safeguard
            historyFeed
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task { model.sampleThermalPressure() }
    }
    private var metadata: some View {
        HStack(spacing: 12) {
            Text("SYSTEM THERMAL TELEMETRY & SAFEGUARD").font(TerminalStyle.mono(9))
                .foregroundStyle(TerminalStyle.muted).lineLimit(2)
            Spacer(minLength: 8)
            metadataValue("PRESSURE", value: stateCode, color: pressureColor)
            metadataValue("TRIP THRESHOLD", value: model.thermalThreshold.code, color: TerminalStyle.secondary)
            metadataValue("AUTO RELEASE", value: model.thermalReleaseEnabled ? "ON" : "OFF",
                          color: model.thermalReleaseEnabled ? TerminalStyle.signal : TerminalStyle.muted)
        }
    }
    private func metadataValue(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            Text(value).font(TerminalStyle.mono(10)).foregroundStyle(color)
        }.padding(.horizontal, 10).padding(.vertical, 7).background(TerminalStyle.recess)
    }
    private var pressurePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                TerminalSignal(color: pressureColor)
                Text("SYSTEM THERMAL PRESSURE").font(TerminalStyle.mono(12)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("macOS // ProcessInfo").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
            }
            if availableWidth > 760 {
                HStack(alignment: .center, spacing: 24) {
                    pressureReadout.frame(maxWidth: .infinity, alignment: .leading)
                    moon.frame(width: min(290, availableWidth * 0.30), height: 260)
                }
            } else {
                pressureReadout
                moon.frame(height: 220)
            }
        }.padding(20).modifier(ThermalRackSurface())
    }
    private var pressureReadout: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                Text(L(stateTitle)).font(TerminalStyle.display(54)).foregroundStyle(pressureColor)
                    .shadow(color: pressureColor.opacity(0.18), radius: 7)
                VStack(alignment: .leading, spacing: 7) {
                    Text(stateCode).font(TerminalStyle.mono(13)).foregroundStyle(TerminalStyle.signal)
                    Text(L(model.thermalCleanupPending ? "正在重试释放" : model.thermalProtectionRequired ? "达到保护阈值" : "系统压力等级"))
                        .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                }
                Spacer(minLength: 0)
            }.accessibilityElement(children: .combine)
            Text(L("按 macOS 报告的温度压力等级执行保护。系统未提供摄氏温度读数。"))
                .font(.system(size: 12)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                pressureSegment(0, title: "正常", code: "NOMINAL")
                pressureSegment(1, title: "轻度", code: "MODERATE")
                pressureSegment(2, title: "严重", code: "HEAVY")
                pressureSegment(3, title: "危急", code: "CRITICAL")
            }.accessibilityElement(children: .ignore).accessibilityLabel(L("系统温度压力")).accessibilityValue(L(stateTitle))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { refreshButton; sampleInfo }
                VStack(alignment: .leading, spacing: 12) { refreshButton; sampleInfo }
            }
        }
    }
    private func pressureSegment(_ index: Int, title: String, code: String) -> some View {
        let color = index < 2 ? TerminalStyle.accent : TerminalStyle.warning
        let illuminated = level.map { index <= $0 } ?? false
        return VStack(alignment: .leading, spacing: 9) {
            Rectangle().fill(illuminated ? color : TerminalStyle.silver).frame(height: 9)
                .shadow(color: illuminated ? color.opacity(0.38) : .clear, radius: 5)
            Text(L(title)).font(.system(size: 11, weight: index == level ? .semibold : .regular))
            Text(code).font(TerminalStyle.mono(8)).lineLimit(1).minimumScaleFactor(0.75)
        }.foregroundStyle(index == level ? color : TerminalStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var refreshButton: some View {
        Button {
            Task { await model.refresh(); await model.protectFromThermalPressure() }
        } label: {
            HStack(spacing: 8) { TerminalIcon(name: "arrow.clockwise", size: 14); Text(L("刷新状态 // RE-SAMPLE")) }
        }.buttonStyle(TerminalButtonStyle()).disabled(model.busy)
            .accessibilityHint("重新读取系统状态并检查温度保护阈值")
    }
    private var sampleInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LAST SAMPLE").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            Text(model.thermalLastSampled?.formatted(date: .omitted, time: .standard) ?? L("等待采样"))
                .font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.ink)
        }
    }
    private var moon: some View {
        OrbitalMoon(phase: model.active?.rawValue ?? "unknown").padding(12).background(TerminalGrid())
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
    }
    private var safeguard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TerminalIcon(name: "checkmark.shield", size: 21).foregroundStyle(TerminalStyle.signal)
                Text(L("过热保护 // THERMAL SAFEGUARD")).font(TerminalStyle.display(19)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 14) {
                TerminalIcon(name: "checkmark.shield", size: 25)
                    .foregroundStyle(model.thermalReleaseEnabled ? TerminalStyle.signal : TerminalStyle.muted)
                    .padding(10).background(TerminalStyle.silver)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(L(safeguardTitle)).font(.system(size: 15, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(safeguardCode).font(TerminalStyle.mono(9))
                            .foregroundStyle(model.thermalCleanupPending ? TerminalStyle.warning : model.thermalReleaseEnabled ? TerminalStyle.signal : TerminalStyle.muted)
                    }
                    Text((model.thermalReleaseEnabled ? "" : L("启用后，")) + LF("达到%@温度压力时，释放 Orexin 的防休眠断言、合盖保活和会话效果，并取消自动休眠倒计时。", L(model.thermalThreshold.title)))
                    Text(L("正在执行的命令继续运行；不会强制休眠或关闭其他任务。降温后由你重新开启工作。"))
                }.font(.system(size: 12)).foregroundStyle(TerminalStyle.muted)
            }.padding(16).background(TerminalStyle.recess)
            if availableWidth > 640 {
                HStack(spacing: 12) { assertionRegister; lidRegister; commandRegister }
            } else {
                assertionRegister
                lidRegister
                commandRegister
            }
            if availableWidth > 760 {
                HStack(alignment: .top, spacing: 16) { thresholdPanel.frame(maxWidth: .infinity); switches.frame(maxWidth: .infinity) }
            } else {
                thresholdPanel
                switches
            }
        }.padding(18).modifier(ThermalRackSurface())
    }
    private var assertionRegister: some View {
        register("01", title: "SYSTEM ASSERTION", code: "闲置休眠断言", value: assertionState,
                 detail: model.snapshot?.idleSleepPrevented == nil ? "尚未核验" : model.keepsAwake ? "阻止闲置休眠" : "允许闲置休眠", color: TerminalStyle.accent)
    }
    private var lidRegister: some View {
        register("02", title: "CLAMSHELL LEASE", code: "合盖保活", value: lidState,
                 detail: lidState == "UNKNOWN" ? "尚未核验" : lidState == "UNVERIFIED" ? "状态未通过核验" : model.runsWithLidClosed ? "合盖继续运行" : "合盖保活未启用", color: TerminalStyle.accent)
    }
    private var commandRegister: some View {
        register("03", title: "COMMAND DELEGATE", code: "前台命令", value: model.jobRunning ? "RUNNING" : "IDLE",
                 detail: model.jobStatus, color: TerminalStyle.secondary)
    }
    private func register(_ number: String, title: String, code: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text("REGISTER " + number); Spacer(minLength: 0); Text(code) }
                .font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            Text(L(title)).font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.ink)
            Text(value).font(TerminalStyle.mono(16)).foregroundStyle(value == "UNKNOWN" || value == "UNVERIFIED" ? TerminalStyle.muted : color)
            Text(L(detail)).font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                .lineLimit(2).frame(minHeight: 25, alignment: .topLeading)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(TerminalStyle.recess).overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.5)))
    }
    private var thresholdPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PARAM // THRESHOLD LEVEL").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            Text(L("触发阈值 // TRIGGER POINT")).font(.system(size: 14, weight: .semibold))
            Text(L("达到所选等级时释放本应用保活。")).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
            HStack(spacing: 6) { thresholdChoice(.heavy); thresholdChoice(.critical) }
        }.padding(14).background(TerminalStyle.surface)
    }
    private func thresholdChoice(_ threshold: ThermalThreshold) -> some View {
        let selected = model.thermalThreshold == threshold
        return Button {
            Task { await model.setThermalThreshold(threshold) }
        } label: {
            VStack(spacing: 6) {
                Text(threshold.title).font(.system(size: 12, weight: .semibold))
                Text(threshold.code + (threshold == .critical ? " // " + L("默认") : "")).font(TerminalStyle.mono(8))
            }.frame(maxWidth: .infinity).frame(minHeight: 50)
                .foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted).background(TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
                .overlay(alignment: .top) {
                    Rectangle().fill(selected ? TerminalStyle.accent : .clear).frame(height: 2)
                        .shadow(color: selected ? TerminalStyle.accent.opacity(0.3) : .clear, radius: 4)
                }
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .accessibilityLabel(LF("温度保护阈值：%@", L(threshold.title))).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var switches: some View {
        VStack(alignment: .leading, spacing: 22) {
            WorkToggle(title: "超温时释放 Orexin 保活", detail: "EMERGENCY RELEASE // 依照所选阈值",
                       isOn: Binding(get: { model.thermalReleaseEnabled }, set: { value in Task { await model.setThermalReleaseEnabled(value) } }))
            WorkToggle(title: "温度超标时播放警报", detail: "ACOUSTIC CHIME // 每次超温触发一次",
                       isOn: Binding(get: { model.thermalAudibleAlertEnabled }, set: { model.setThermalAudibleAlertEnabled($0) }))
        }.padding(14).background(TerminalStyle.surface)
    }
    private var historyFeed: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TerminalIcon(name: "terminal", size: 14).foregroundStyle(TerminalStyle.accent)
                Text(L("温度保护记录 // THERMAL EVENT STREAM")).font(TerminalStyle.mono(11)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("LOCAL").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.signal)
            }.padding(11).background(TerminalStyle.surface)
            VStack(alignment: .leading, spacing: 11) {
                if thermalEntries.isEmpty {
                    Text(L("尚无温度保护记录。")).font(TerminalStyle.mono(11)).foregroundStyle(TerminalStyle.muted)
                }
                ForEach(thermalEntries.prefix(8)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 13) {
                        Text(entry.date.formatted(date: .omitted, time: .standard)).foregroundStyle(TerminalStyle.muted).fixedSize()
                        Text(L(entry.text)).foregroundStyle(TerminalStyle.ink).fixedSize(horizontal: false, vertical: true)
                    }.font(TerminalStyle.mono(10))
                }
            }.frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading).padding(12).background(TerminalStyle.recess)
            Text(LF("显示最近 %d 条 / 共 %d 条真实记录", min(8, thermalEntries.count), thermalEntries.count))
                .font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
        }.padding(16).modifier(ThermalRackSurface())
    }
}
private struct ThermalRackSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(TerminalStyle.surface).overlay(Rectangle().strokeBorder(TerminalStyle.line))
            .overlay(TerminalBrackets().stroke(TerminalStyle.steel.opacity(0.5)).padding(7))
    }
}
