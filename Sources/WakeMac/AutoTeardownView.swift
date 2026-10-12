// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import SwiftUI

struct AutoTeardownView: View {
    @ObservedObject var model: AppModel
    @Binding var date: Date
    @Binding var preset: Int
    let availableWidth: CGFloat
    private var canSchedule: Bool { !model.busy && model.verifiedWork }
    var body: some View {
        VStack(spacing: 16) {
            if availableWidth > 760 {
                HStack(alignment: .top, spacing: 16) {
                    primary.frame(width: (availableWidth - 16) * 0.68)
                    side.frame(width: (availableWidth - 16) * 0.32)
                }
            } else { primary; side }
            OrbitalEventFeed(entries: model.history, title: "自动收尾记录")
        }
    }
    private var primary: some View {
        VStack(spacing: 16) {
            WorkCard(title: "定时休眠 // TIMED SLEEP", subtitle: "到点中断工作，恢复正常模式，并向 macOS 请求休眠与锁定。") {
                HStack(spacing: 10) {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        Button { preset = minutes; date = Date().addingTimeInterval(Double(minutes * 60)) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text("SLOT::0\(minutes == 30 ? 1 : minutes == 60 ? 2 : 3)").font(TerminalStyle.mono(9)); Spacer(); if preset == minutes { TerminalSignal(color: TerminalStyle.accent) } }
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(minutes == 30 ? "30" : "\(minutes / 60)").font(TerminalStyle.mono(29))
                                    Text(L(minutes == 30 ? "分钟后" : "小时后")).font(.system(size: 11))
                                }
                                Rectangle().fill(TerminalStyle.line).frame(height: 1)
                                Text("TGT_SPAN  +\(minutes)M").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(TerminalStyle.recess)
                                .overlay(Rectangle().strokeBorder(TerminalStyle.line))
                                .overlay(alignment: .top) { Rectangle().fill(preset == minutes ? TerminalStyle.accent : .clear).frame(height: 3) }
                        }.buttonStyle(TerminalPlainButtonStyle()).accessibilityLabel(LF("%d 分钟后休眠并锁定", minutes))
                    }
                }
                HStack(spacing: 10) {
                    TerminalIcon(name: "calendar", size: 18).foregroundStyle(TerminalStyle.muted)
                    SchedulePicker(selection: Binding(get: { date }, set: { date = $0; preset = 0 }))
                    Spacer(minLength: 0)
                    Button { model.scheduleRestore(at: date) } label: { TerminalLabel("设置定时 // ENGAGE", systemImage: "arrow.right") }
                        .buttonStyle(TerminalButtonStyle(prominent: true)).disabled(!canSchedule || date <= model.now)
                }.padding(12).background(TerminalStyle.recess)
                if let end = model.automation.deadline {
                    HStack {
                        Text(end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.selected.locale)) + L(" 请求休眠并锁定")).foregroundStyle(TerminalStyle.accent)
                        Spacer(); Button(L("取消定时"), action: model.cancelTimer)
                    }
                } else if !canSchedule || date > model.now {
                    WorkNote(text: canSchedule ? "选择时长或指定钟点，再设置定时。" : "先在工作模式页开启保持唤醒，再设置恢复时间。")
                }
                if canSchedule && date <= model.now {
                    WorkNote(text: "所选时间已过去，请重新选择时长或钟点。")
                }
            }
            WorkCard(title: "低电量保护 // BATTERY SAFEGUARD") {
                WorkToggle(title: "电池供电时自动保护", detail: "脱离外接电源时，防止后台工作耗尽电池。", isOn: Binding(get: { model.automation.batteryEnabled }, set: { model.setBatteryProtection(enabled: $0, threshold: model.automation.batteryThreshold) }))
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("休眠电量阈值 // CRITICAL THRESHOLD")).font(.system(size: 12, weight: .semibold))
                        Text(L("达到阈值后留出 60 秒取消")).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                    }
                    Spacer(minLength: 10)
                    TerminalStepper(value: Binding(get: { model.automation.batteryThreshold }, set: { model.setBatteryProtection(enabled: model.automation.batteryEnabled, threshold: $0) }), in: 5...50, step: 5) {
                        Text("\(model.automation.batteryThreshold)%").font(TerminalStyle.mono(27)).foregroundStyle(TerminalStyle.signal)
                    }.fixedSize().accessibilityLabel("休眠电量")
                }.padding(12).background(TerminalStyle.recess)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { TerminalLabel("低电量休眠倒计时", systemImage: "checkmark.shield"); Spacer(); Text(L("60 秒内可取消")).font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent) }
                    Text(L("倒计时期间可以取消。接上电源自动撤销本次休眠；计时结束后恢复正常模式，再向系统请求休眠。"))
                        .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        ForEach(0..<10) { index in
                            Rectangle().fill(index * 10 < (model.battery?.percent ?? 0) ? TerminalStyle.signal : TerminalStyle.line).frame(height: 5)
                        }
                    }
                    HStack {
                        Text(LF("当前电池 %@", model.battery.map { String($0.percent) + "%" } ?? L("未知")))
                        Spacer(); Text(L(model.battery.map { $0.onBattery ? "电池供电" : "已接电源" } ?? "电源未知"))
                    }.font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted)
                }.padding(12).overlay(Rectangle().strokeBorder(TerminalStyle.line))
                DisclosureGroup("保护规则") {
                    Text(L("提前 5% 提醒；取消后本次工作模式不重复触发，重新选择工作模式即可恢复保护。"))
                        .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted).padding(.top, 6)
                }
                if model.automation.batterySleepAt != nil || model.automation.jobSleepAt != nil { Button(L("取消自动休眠"), action: model.cancelAutomaticSleep) }
            }
        }
    }
    private var side: some View {
        VStack(spacing: 16) {
            OrbitalMoon(phase: model.active?.rawValue ?? "unknown").frame(height: 240).padding(16).terminalSurface()
            WorkCard(title: "保护状态 // DEFENSE") {
                Text(model.thermalProtectionRequired ? L("温度保护已触发") : LF("系统温度压力：%@", L(model.thermalSummary))).foregroundStyle(model.thermalProtectionRequired ? TerminalStyle.warning : TerminalStyle.signal)
                Text(L("温度监测与过热保护在独立的「温度保护」模块中。"))
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let countdown = model.countdownText { Text(countdown).font(TerminalStyle.mono(12)).foregroundStyle(TerminalStyle.accent) }
                HStack { TerminalCursor(); Text(model.verifiedWork ? "WORK ENGAGED" : "STANDBY").font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.accent) }
            }
        }
    }
}
