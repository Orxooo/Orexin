// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import SwiftUI

struct AutoTeardownView: View {
    @ObservedObject var model: AppModel
    @Binding var date: Date
    @Binding var preset: Int
    let availableWidth: CGFloat
    private var canSchedule: Bool { !model.busy && model.verifiedWork }
    private var sideWidth: CGFloat { min(340, availableWidth * 0.32) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if availableWidth >= 920 {
                HStack(alignment: .top, spacing: 18) {
                    primary.frame(width: availableWidth - sideWidth - 18)
                    side.frame(width: sideWidth)
                }
            } else {
                primary
                side
            }
            OrbitalEventFeed(entries: model.history, title: "自动收尾记录")
        }.buttonStyle(TerminalButtonStyle())
    }

    private var primary: some View {
        VStack(spacing: 18) {
            WorkCard(title: "定时休眠 // TIMED SLEEP", subtitle: "到点中断工作，恢复正常模式，并向 macOS 请求休眠与锁定。") {
                HStack(spacing: 10) {
                    ForEach([30, 60, 120], id: \.self) { minutes in durationCard(minutes) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        scheduleField
                        Spacer(minLength: 12)
                        scheduleButton
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        scheduleField
                        scheduleButton.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(12).background(TerminalStyle.recess)
                    .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.5)))
                if let end = model.automation.deadline {
                    HStack(spacing: 12) {
                        Text(end.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.selected.locale)) + L(" 请求休眠并锁定"))
                            .font(.system(size: 11)).foregroundStyle(TerminalStyle.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(L("取消定时"), action: model.cancelTimer)
                    }.padding(10).background(TerminalStyle.selection.opacity(0.3))
                } else if !canSchedule {
                    WorkNote(text: "先在工作模式页开启保持唤醒，再设置恢复时间。")
                }
                if canSchedule && date <= model.now { WorkNote(text: "所选时间已过去，请重新选择时长或钟点。") }
            }
            batteryPanel
        }
    }

    private func durationCard(_ minutes: Int) -> some View {
        let selected = preset == minutes
        return Button {
            preset = minutes
            date = Date().addingTimeInterval(Double(minutes * 60))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SLOT::0\(minutes == 30 ? 1 : minutes == 60 ? 2 : 3)").font(TerminalStyle.mono(9))
                    Spacer(minLength: 0)
                    TerminalSignal(color: selected ? TerminalStyle.accent : TerminalStyle.line)
                }.foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(minutes == 30 ? "30" : "\(minutes / 60)").font(TerminalStyle.mono(29))
                    Text(L(minutes == 30 ? "分钟后" : "小时后")).font(.system(size: 11))
                }.foregroundStyle(TerminalStyle.ink)
                Rectangle().fill(selected ? TerminalStyle.accent.opacity(0.5) : TerminalStyle.line).frame(height: 1)
                HStack {
                    Text("TGT_SPAN")
                    Spacer(minLength: 0)
                    Text(minutes == 30 ? "+30M" : "+\(minutes / 60).0H")
                }.font(TerminalStyle.mono(8)).foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted)
            }.frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).padding(12)
                .background(selected ? TerminalStyle.selection.opacity(0.4) : TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(selected ? TerminalStyle.accent : TerminalStyle.line, lineWidth: selected ? 2 : 1))
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .accessibilityLabel(LF("%d 分钟后休眠并锁定", minutes))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var scheduleField: some View {
        HStack(spacing: 10) {
            Text(L("结束时间")).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
            SchedulePicker(selection: Binding(get: { date }, set: { date = $0; preset = 0 }))
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var scheduleButton: some View {
        Button { model.scheduleRestore(at: date) } label: { TerminalLabel("设置定时", systemImage: "arrow.right") }
            .buttonStyle(TerminalButtonStyle(prominent: true)).workKeyboardFocus(radius: 0)
            .disabled(!canSchedule || date <= model.now)
    }

    private var batteryPanel: some View {
        WorkCard(title: "低电量保护 // BATTERY SAFEGUARD") {
            WorkToggle(title: "电池供电时自动保护", detail: "脱离外接电源时，防止唤醒状态耗尽电池。", icon: "bolt.fill",
                       isOn: Binding(get: { model.automation.batteryEnabled }, set: { model.setBatteryProtection(enabled: $0, threshold: model.automation.batteryThreshold) }))
                .padding(12).background(TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.5)))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("休眠电量阈值 // CRITICAL THRESHOLD")).font(.system(size: 12, weight: .semibold))
                    Text(L("达到阈值后留出 60 秒取消")).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                }
                Spacer(minLength: 0)
                TerminalStepper(value: Binding(get: { model.automation.batteryThreshold }, set: { model.setBatteryProtection(enabled: model.automation.batteryEnabled, threshold: $0) }), in: 5...50, step: 5) {
                    Text("\(model.automation.batteryThreshold)%").font(TerminalStyle.mono(27)).foregroundStyle(TerminalStyle.signal)
                }.fixedSize().accessibilityLabel("休眠电量")
            }.padding(12).background(TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.5)))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TerminalLabel("低电量休眠倒计时", systemImage: "checkmark.shield")
                    Spacer(minLength: 0)
                    Text(L("60 秒内可取消")).font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent)
                }
                Text(L("倒计时期间可以取消。接上电源自动撤销本次休眠；计时结束后恢复正常模式，再向系统请求休眠。"))
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    ForEach(0..<10) { index in
                        Rectangle().fill(index * 10 < (model.battery?.percent ?? 0) ? TerminalStyle.signal : TerminalStyle.line).frame(height: 5)
                    }
                }
                HStack {
                    Text(LF("当前电池 %@", model.battery.map { String($0.percent) + "%" } ?? L("未知")))
                    Spacer(minLength: 0)
                    Text(L(model.battery.map { $0.onBattery ? "电池供电" : "已接电源" } ?? "电源未知"))
                }.font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted)
            }.padding(12).background(TerminalStyle.recess.opacity(0.5))
                .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
            Text(L("提前 5% 提醒；取消后本次工作模式不重复触发，重新选择工作模式即可恢复保护。"))
                .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            if model.automation.batterySleepAt != nil || model.automation.jobSleepAt != nil {
                Button(L("取消自动休眠"), action: model.cancelAutomaticSleep)
            }
        }
    }

    private var side: some View {
        VStack(spacing: 18) {
            OrbitalMoon(phase: model.active?.rawValue ?? "unknown").frame(height: 280).padding(16).terminalSurface()
            WorkCard(title: "保护状态 // DEFENSE") {
                HStack(spacing: 8) {
                    TerminalIcon(name: "checkmark.shield", size: 18).foregroundStyle(TerminalStyle.signal)
                    Text(model.thermalProtectionRequired ? L("温度保护已触发") : LF("系统温度压力：%@", L(model.thermalSummary)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.thermalProtectionRequired ? TerminalStyle.warning : TerminalStyle.signal)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(TerminalStyle.recess)
                if let countdown = model.countdownText { Text(countdown).font(TerminalStyle.mono(12)).foregroundStyle(TerminalStyle.accent) }
                HStack(spacing: 8) {
                    TerminalSignal(color: model.verifiedWork ? TerminalStyle.signal : TerminalStyle.line)
                    Text(model.verifiedWork ? "WORK ENGAGED" : "STANDBY").font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.accent)
                    Spacer(minLength: 8)
                    Button(L("温度保护")) { NotificationCenter.default.post(name: .wakeMacOpenTemperature, object: nil) }
                        .buttonStyle(TerminalButtonStyle()).workKeyboardFocus(radius: 0)
                }.frame(minHeight: 36)
            }
        }
    }
}
