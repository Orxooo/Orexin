// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI

struct PreferencesConsoleRack<Content: View>: View {
    let number: String
    let title: String
    let code: String
    var accent: Color = TerminalStyle.accent
    var metadata = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("RACK." + number + " //").font(TerminalStyle.mono(10)).foregroundStyle(accent)
                Text(L(title)).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Text("[" + code + "]").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                if !metadata.isEmpty {
                    Text(metadata).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                        .lineLimit(1).minimumScaleFactor(0.65)
                }
            }
            Rectangle().fill(TerminalStyle.line.opacity(0.55)).frame(height: 1)
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(TerminalStyle.paper.opacity(0.8))
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
            .overlay(TerminalBrackets().stroke(accent.opacity(0.8), lineWidth: 1.4).allowsHitTesting(false))
    }
}

struct PreferencesTelemetryLabel: View {
    let title: String
    let code: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .regular))
                .frame(width: 15).accessibilityHidden(true)
            Text(L(title) + " // " + code).font(TerminalStyle.mono(10)).tracking(0.3)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
    }
}

/// An authorized service is a status readout, not a disabled action.
struct PreferencesServiceReadyBadge: View {
    var body: some View {
        PreferencesTelemetryLabel(title: "合盖服务已安装", code: "DAEMON_READY", icon: "checkmark.shield")
            .padding(.horizontal, 15).frame(height: 36)
            .foregroundStyle(TerminalStyle.accent).background(TerminalStyle.selection.opacity(0.45))
            .overlay(Rectangle().strokeBorder(TerminalStyle.accent.opacity(0.75)))
            .shadow(color: TerminalStyle.accent.opacity(0.15), radius: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("合盖服务已安装并已授权")
            .accessibilityValue("DAEMON_READY")
            .accessibilityAddTraits(.isStaticText)
    }
}

struct PreferencesConsoleFooter<Note: View, Action: View>: View {
    var stacked: Bool
    @ViewBuilder var note: Note
    @ViewBuilder var action: Action

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 12) {
                note
                action.frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(alignment: .center, spacing: 16) {
                note.frame(maxWidth: .infinity, alignment: .leading)
                action.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

struct PreferencesAdditionalSettings<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    TerminalIcon(name: "chevron.right", size: 13)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(L("附加设置")).font(.system(size: 13, weight: .semibold))
                    Text("// NOTIFICATIONS · SHORTCUTS · SESSION BEHAVIOR")
                        .font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                    Text(L(expanded ? "收起" : "展开")).font(TerminalStyle.mono(9))
                }.foregroundStyle(TerminalStyle.accent).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TerminalStyle.paper.opacity(0.8))
                    .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
            }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                .accessibilityLabel("附加设置：会话通知、全局快捷键和会话行为")
                .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                content.transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: -8)))
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: expanded)
    }
}

/// The existing idle-policy controls in the session's instrument-row composition.
struct IdleScreenConsoleView: View {
    @ObservedObject var controller: IdlePolicyController
    var immediateAuthentication: Bool

    var body: some View {
        PreferencesConsoleRack(number: "03", title: "闲置后的屏幕", code: "IDLE DISPLAY & SESSION GUARD", accent: TerminalStyle.secondary) {
            Text(L("工作继续运行；熄屏锁定需要即时密码保护，屏保的密码要求跟随系统设置。"))
                .font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
            policyRow(number: "01", title: "闲置后熄屏锁定", code: "DISPLAY LOCK", detail: "仅在 macOS 立即要求密码时执行；其他策略下暂停。") {
                Toggle(L("闲置后熄屏锁定"), isOn: $controller.lockEnabled).labelsHidden().toggleStyle(TerminalSwitchStyle())
                    .disabled(!immediateAuthentication)
                    .accessibilityLabel("闲置后熄屏锁定")
            } timing: {
                timingControl("锁定等待", value: $controller.lockMinutes, accessibility: "闲置锁定等待时间")
            }
            policyRow(number: "02", title: "闲置后启动系统屏保", code: "SCREEN SAVER", detail: "启用「防止闲时屏保」时暂停；不会结束工作。") {
                Toggle(L("闲置后启动系统屏保"), isOn: $controller.screenSaverEnabled).labelsHidden().toggleStyle(TerminalSwitchStyle())
                    .accessibilityLabel("闲置后启动系统屏保")
            } timing: {
                timingControl("屏保等待", value: $controller.screenSaverMinutes, accessibility: "屏保等待时间")
            }
            HStack(alignment: .top, spacing: 8) {
                TerminalIcon(name: "info.circle", size: 13).foregroundStyle(TerminalStyle.signal)
                Text(L(controller.status)).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func policyRow<Control: View, Timing: View>(number: String, title: String, code: String, detail: String,
                                                       @ViewBuilder control: () -> Control, @ViewBuilder timing: () -> Timing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("[" + number + "]").font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(L(title)).font(.system(size: 13, weight: .semibold))
                        Text(code).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                            .padding(.horizontal, 4).padding(.vertical, 2).background(TerminalStyle.silver)
                    }
                    Text(L(detail)).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                control()
            }
            Rectangle().fill(TerminalStyle.line.opacity(0.4)).frame(height: 1)
            timing()
        }.padding(12).background(TerminalStyle.recess)
    }

    private func timingControl(_ title: String, value: Binding<Double>, accessibility: String) -> some View {
        HStack {
            Text(L(title)).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
            Text("// WAIT INTERVAL").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            Spacer(minLength: 0)
            TerminalStepper(value: value, in: 1...240) {
                Text(LF("%d 分钟", Int(value.wrappedValue))).font(TerminalStyle.mono(12)).foregroundStyle(TerminalStyle.ink)
            }.fixedSize().accessibilityLabel(accessibility)
        }
    }
}
