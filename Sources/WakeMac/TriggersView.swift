// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WakeMacCore

struct TriggersView: View {
    @ObservedObject var controller: TriggerController
    @State private var editing: TriggerRule?
    @State private var diagnostics = TriggerSnapshot()
    @State private var refreshing = false
    @State private var showingMore = false
    private let ruleColumns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let primaryKinds: Set<TriggerKind> = [.acConnected, .batteryCharging, .batteryAbove, .cpuAbove, .ciscoVPN, .audioOutput, .headphones]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            masterBus.terminalPopup(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), width: 650) {
                if let rule = editing {
                    TriggerRuleEditor(rule: rule, controller: controller) { editing = nil }.id(rule.id)
                }
            }
            HStack {
                Text(L("REG BAY // 规则机架")).font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted)
                Spacer()
                Text(controller.rules.isEmpty ? "DRAFT TEMPLATES · " + L("尚未配置规则") : "\(controller.rules.count) CONFIGURED PROFILES")
                    .font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
            }
            LazyVGrid(columns: ruleColumns, alignment: .leading, spacing: 14) {
                if controller.rules.isEmpty {
                    ForEach(Array(RuleTemplate.allCases.enumerated()), id: \.element) { index, template in
                        templateCard(template, number: index + 1)
                    }
                } else {
                    ForEach(Array(controller.rules.enumerated()), id: \.element.id) { index, rule in
                        ruleCard(rule, number: index + 1)
                    }
                }
            }
            telemetry
        }
            .task { await refreshTelemetry() }
            .onReceive(NotificationCenter.default.publisher(for: NativeTriggerObservations.permissionChanged)) { _ in
                Task { await refreshTelemetry() }
            }
            .onChange(of: showingMore) { _, expanded in
                if expanded { Task { await refreshTelemetry() } }
            }
    }

    private var masterBus: some View {
        HStack(alignment: .center, spacing: 14) {
            TerminalIcon(name: "bolt.fill", size: 25).foregroundStyle(TerminalStyle.accent)
                .frame(width: 42, height: 48).background(TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(TerminalStyle.line))
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(L("启用自动触发")).font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(controller.enabled ? "BUS::ARMED" : "BUS::PAUSED").font(TerminalStyle.mono(9)).foregroundStyle(controller.enabled ? TerminalStyle.signal : TerminalStyle.muted)
                }
                Text(L("暂停时保留规则配置，停止自动匹配；手动操作优先。"))
                    .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
                Text(LF("%d 条启用 · %d 条暂停", controller.rules.filter(\.enabled).count, controller.rules.filter { !$0.enabled }.count))
                    .font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.signal)
            }
            Spacer(minLength: 0)
            VStack(spacing: 3) {
                Text("MASTER_BUS").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                Toggle(L("启用自动触发"), isOn: $controller.enabled).labelsHidden().toggleStyle(TerminalSwitchStyle())
            }
            Button { editing = TriggerRule() } label: { TerminalLabel("新建规则", systemImage: "plus") }
                .workKeyboardFocus(radius: 0)
        }.padding(16).modifier(TriggerRackSurface(active: controller.enabled))
    }

    private func ruleCard(_ rule: TriggerRule, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeading(name: rule.name, icon: icon(for: rule.allConditions.first?.kind), number: number,
                        identifier: "RULE_ID :: " + String(rule.id.uuidString.prefix(8)),
                        status: ruleStatus(rule), color: ruleStatusColor(rule))
            ruleDefinition(rule)
            ruleControls(rule)
            ruleObservations(rule)
        }.padding(14).modifier(TriggerRackSurface(active: rule.enabled && controller.enabled))
    }

    private func ruleDefinition(_ rule: TriggerRule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rackRow("COND // 条件", rule.effectiveExpression.summary)
            rackRow("ACTION // 执行", L(rule.mode == .background ? "后台工作" : "桌面工作") + " · " + L("保持唤醒"), color: TerminalStyle.accent)
            rackRow("LID // 合盖策略", rule.mode == .background ? "允许合盖继续运行" : "合盖后允许休眠", color: TerminalStyle.signal)
            rackRow("PRIORITY // 优先级", "\(rule.priority) · 持续 \(rule.sustainedMatchSeconds.formatted()) 秒 · 冷却 \(rule.cooldownSeconds.formatted()) 秒")
            rackRow("FALLBACK // 收尾", "条件解除后恢复正常模式")
        }.padding(10).background(TerminalStyle.recess)
    }

    private func ruleControls(_ rule: TriggerRule) -> some View {
        HStack(spacing: 7) {
            Text(displayBehavior(rule)).font(.system(size: 9)).foregroundStyle(TerminalStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { editing = rule } label: { TerminalIcon(name: "slider.horizontal.3", size: 16).frame(width: 26, height: 30) }
                .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).accessibilityLabel(LF("编辑 %@", rule.name))
            Button(role: .destructive) { controller.remove(rule.id) } label: { TerminalIcon(name: "trash", size: 14).frame(width: 24, height: 30) }
                .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).foregroundStyle(TerminalStyle.warning).accessibilityLabel(LF("删除 %@", rule.name))
            Toggle(rule.name, isOn: Binding(get: { rule.enabled }, set: { controller.setEnabled(rule.id, $0) }))
                .labelsHidden().toggleStyle(TerminalSwitchStyle())
        }.padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(TerminalStyle.line.opacity(0.5)).frame(height: 1) }
    }

    private func ruleObservations(_ rule: TriggerRule) -> some View {
        DisclosureGroup(L("条件观测与判定")) {
            if let evaluation = controller.evaluationReport?.rules.first(where: { $0.id == rule.id }) {
                Text(L(evaluation.state.title) + " · " + L(evaluation.detail)).font(.system(size: 11)).foregroundStyle(TerminalStyle.accent)
            }
            ForEach(rule.allConditions) { condition in
                Text(observationText(condition))
                    .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            Text(L("收尾策略在规则接管工作模式时生效；手动操作和当前会话优先。"))
                .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted).padding(.top, 4)
        }.font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
    }

    private func observationText(_ condition: TriggerCondition) -> String {
        let title = conditionTitle(condition)
        guard let reading = controller.observations[condition.id] else {
            return title + ": " + L("尚未观测")
        }
        let state = L(stateTitle(reading.state))
        let detail = L(reading.detail)
        return "\(title): \(state) · \(detail)"
    }

    private func templateCard(_ template: RuleTemplate, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeading(name: template.title, icon: icon(for: template.kind), number: number,
                        identifier: "DRAFT TEMPLATE // 未保存", status: "OFF · 未配置", color: TerminalStyle.muted)
            VStack(alignment: .leading, spacing: 8) {
                rackRow("COND // 条件", template.condition)
                rackRow("ACTION // 执行", "选择桌面工作或后台工作")
                rackRow("LID // 合盖策略", "跟随所选工作模式")
                rackRow("FALLBACK // 收尾", "条件解除后恢复正常模式")
            }.padding(10).background(TerminalStyle.recess)
            HStack {
                Text(L("未配置 · 不会自动执行")).font(.system(size: 9)).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 0)
                Button(L("配置模板")) { editing = template.draft() }.font(.system(size: 10)).workKeyboardFocus(radius: 0)
                Toggle(L("模板尚未启用"), isOn: .constant(false)).labelsHidden().toggleStyle(TerminalSwitchStyle()).disabled(true)
            }.padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(TerminalStyle.line.opacity(0.5)).frame(height: 1) }
        }.padding(14).modifier(TriggerRackSurface(active: false))
    }

    private func cardHeading(name: String, icon: String, number: Int, identifier: String, status: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            TerminalIcon(name: icon, size: 19).foregroundStyle(TerminalStyle.accent).frame(width: 28, height: 31)
                .background(TerminalStyle.recess).overlay(Rectangle().strokeBorder(TerminalStyle.line))
            VStack(alignment: .leading, spacing: 5) {
                Text(L(name)).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.85).frame(height: 32, alignment: .topLeading)
                Text(L(identifier)).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text(String(format: "RACK_%02d", number)).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.accent)
                Text(L(status)).font(.system(size: 9)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rackRow(_ label: String, _ value: String, color: Color = TerminalStyle.ink) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(L(label)).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted).frame(width: 96, alignment: .leading)
            Text(L(value)).font(.system(size: 10)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(2).minimumScaleFactor(0.85)
        }.frame(minHeight: 26, alignment: .top)
    }

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(L("当前观测")).font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        Text("HARDWARE TELEMETRY").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent)
                    }
                    Text(L("只读诊断不会切换模式；CPU 首次采样不可判定，再次刷新后显示采样间使用率。"))
                        .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { Task { await refreshTelemetry(refreshRules: true) } } label: { TerminalLabel("刷新观测", systemImage: "arrow.clockwise") }
                    .workKeyboardFocus(radius: 0).disabled(refreshing)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { telemetryCards }.frame(minWidth: 700)
                LazyVGrid(columns: ruleColumns, alignment: .leading, spacing: 10) { telemetryCards }
            }
            if let date = diagnostics.observedAt {
                Text("OBSERVED // " + date.formatted(date: .omitted, time: .standard)).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            }
            WorkNote(text: "VPN 条件只检测 macOS 网络设置中名称含 Cisco、AnyConnect 或 Secure Client 的服务。客户端没有向系统公开连接状态时显示未知，规则不会匹配。耳机条件读取内置输出标识；USB 或蓝牙耳机请使用指定音频输出规则。")
                .padding(10).background(TerminalStyle.recess)
            DisclosureGroup("更多观测与权限", isExpanded: $showingMore) {
                additionalObservations.padding(.top, 10)
            }.font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
        }.padding(16).modifier(TriggerRackSurface(active: false))
    }

    @ViewBuilder private var telemetryCards: some View {
        telemetryCard("电源输入 // POWER", icon: "bolt.fill", value: diagnostics.acConnected.map { $0 ? "已连接电源" : "电池供电" } ?? "未知",
                      detail: diagnostics.batteryPercent.map { LF("电池剩余 %d%%", $0) } ?? diagnostics.unavailable[.acConnected] ?? "系统未提供电池读数",
                      indicator: diagnostics.batteryPercent.map { Double($0) / 100 }, available: diagnostics.acConnected != nil)
        telemetryCard("CPU 采样 // LOAD", icon: "cpu", value: diagnostics.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "待采样",
                      detail: diagnostics.cpuPercent == nil ? diagnostics.unavailable[.cpuAbove] ?? "需要两次有效采样" : "两次采样间的实际使用率",
                      indicator: diagnostics.cpuPercent.map { $0 / 100 }, available: diagnostics.cpuPercent != nil)
        telemetryCard("VPN 状态 // TUNNEL", icon: "key", value: diagnostics.ciscoVPN.map { $0 ? "已连接" : "未连接" } ?? "未知",
                      detail: diagnostics.unavailable[.ciscoVPN] ?? "系统 Cisco VPN 服务状态", available: diagnostics.ciscoVPN != nil)
        telemetryCard("音频输出 // SINK", icon: "headphones", value: diagnostics.audioOutput?.name ?? "未知",
                      detail: diagnostics.audioOutput.map { "UID: " + $0.id } ?? diagnostics.unavailable[.audioOutput] ?? "系统未提供当前输出",
                      available: diagnostics.audioOutput != nil)
    }

    private func telemetryCard(_ title: String, icon: String, value: String, detail: String, indicator: Double? = nil, available: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                TerminalIcon(name: icon, size: 12)
                Text(L(title)).font(TerminalStyle.mono(8))
                Spacer(minLength: 0)
                Circle().fill(available ? TerminalStyle.signal : TerminalStyle.amber).frame(width: 4, height: 4)
            }.foregroundStyle(TerminalStyle.muted)
            Text(L(value)).font(.system(size: 17, weight: .semibold, design: .monospaced)).lineLimit(2)
                .minimumScaleFactor(0.75).foregroundStyle(available ? TerminalStyle.ink : TerminalStyle.muted)
            Text(L(detail)).font(.system(size: 9)).foregroundStyle(TerminalStyle.muted).lineLimit(3).help(detail).textSelection(.enabled)
            Spacer(minLength: 0)
            if let indicator, indicator.isFinite {
                GeometryReader { geometry in
                    Rectangle().fill(TerminalStyle.recess)
                        .overlay(alignment: .leading) { Rectangle().fill(TerminalStyle.signal).frame(width: geometry.size.width * min(1, max(0, indicator))) }
                }.frame(height: 3).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 116).padding(12)
            .background(TerminalStyle.surface).overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.7)))
    }

    private var additionalObservations: some View {
        VStack(alignment: .leading, spacing: 12) {
            rackRow("DISPLAY", diagnostics.externalDisplay.map { $0 ? "已连接外接显示器" : "无外接显示器" } ?? "未知")
            rackRow("MIRROR", diagnostics.displayMirroring.map { $0 ? "正在镜像" : "未镜像" } ?? "未知")
            rackRow("WI-FI", diagnostics.wifiSSID ?? diagnostics.unavailable[.wifiSSID] ?? "未知")
            rackRow("IP", diagnostics.ipAddresses.map { $0.sorted().joined(separator: "、") } ?? "未知")
            rackRow("DNS", diagnostics.dnsServers.map { $0.sorted().joined(separator: "、") } ?? "未知")
            rackRow("USB", describe(diagnostics.usbDevices))
            rackRow("BLUETOOTH", describe(diagnostics.bluetoothDevices))
            rackRow("APPS", describe(diagnostics.runningAppChoices))
            rackRow("FRONTMOST", diagnostics.frontmostApp ?? "未知")
            rackRow("PROCESSES", describe(diagnostics.processes))
            rackRow("VOLUMES", describe(diagnostics.mountedVolumes))
            rackRow("IDLE", diagnostics.idleSeconds.map { LF("%.0f 秒", $0) } ?? "未知")
            permissionRow(kind: .wifiSSID, title: "Wi-Fi 网络名称", explanation: diagnostics.unavailable[.wifiSSID] ?? "macOS 需要定位权限才会提供网络名称。拒绝或未授权时不会匹配。")
            WorkNote(text: "Wi-Fi 名称受 macOS 定位权限保护。开源自行构建版本若缺少定位授权声明或有效签名，系统可能不显示授权弹窗；此时 Wi-Fi 规则不会匹配。请在系统设置 → 隐私与安全性 → 定位服务检查 Orexin 的权限。")
            permissionRow(kind: .bluetoothDevice, title: "蓝牙设备", explanation: diagnostics.unavailable[.bluetoothDevice] ?? "仅读取已配对且当前连接的设备。需要蓝牙权限。")
        }
    }

    private func refreshTelemetry(refreshRules: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if refreshRules { await controller.refreshDiagnostics() }
        let kinds = showingMore ? Set(TriggerKind.allCases) : primaryKinds
        diagnostics = await controller.preview(kinds: kinds)
    }

    private func describe(_ devices: [TriggerDevice]?) -> String {
        guard let devices else { return "未知" }
        return devices.isEmpty ? "未发现设备或应用" : devices.map { $0.name + " [" + $0.id + "]" }.joined(separator: "、")
    }
    private func icon(for kind: TriggerKind?) -> String {
        switch kind {
        case .weeklySchedule: return "clock"
        case .acConnected, .acDisconnected, .batteryCharging, .batteryAbove: return "bolt.fill"
        case .wifiSSID, .ipAddress, .dnsServer: return "wifi"
        case .appRunning, .appFrontmost, .processRunning: return "terminal"
        default: return "bolt.badge.clock"
        }
    }
    private func ruleStatus(_ rule: TriggerRule) -> String {
        if !rule.enabled { return "PAUSED · 已暂停" }
        if !controller.enabled { return "BUS PAUSED" }
        return controller.evaluationReport?.rules.first(where: { $0.id == rule.id })?.state.title ?? "等待观测"
    }
    private func ruleStatusColor(_ rule: TriggerRule) -> Color {
        guard rule.enabled, controller.enabled else { return TerminalStyle.muted }
        switch controller.evaluationReport?.rules.first(where: { $0.id == rule.id })?.state {
        case .matched: return TerminalStyle.signal
        case .unknown, .sustaining, .coolingDown: return TerminalStyle.amber
        default: return TerminalStyle.muted
        }
    }
    private func stateTitle(_ state: TriggerMatchState) -> String {
        switch state { case .matched: return "满足"; case .unmatched: return "未满足"; case .unknown: return "未知" }
    }
    private func displayBehavior(_ rule: TriggerRule) -> String {
        let display = rule.preventDisplaySleep.map { $0 ? "保持亮屏" : "允许熄屏" } ?? "显示器跟随全局"
        let saver = rule.preventScreenSaver.map { $0 ? "暂停屏保" : "允许屏保" } ?? "屏保跟随全局"
        return L(display) + " · " + L(saver)
    }
    private func conditionTitle(_ condition: TriggerCondition) -> String {
        if condition.kind == .weeklySchedule { return condition.kind.title + ": " + (condition.schedule?.summary ?? L("尚未设置")) }
        if condition.kind == .externalDisplay && !condition.ignoreBuiltInDisplay { return L("连接显示器（包括内建）") }
        if condition.kind == .processRunning { return condition.kind.title + "：" + URL(fileURLWithPath: condition.value).lastPathComponent }
        guard condition.kind.requiresValue else { return condition.kind.title }
        if (condition.kind == .appRunning || condition.kind == .appFrontmost),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: condition.value) {
            return condition.kind.title + "：" + FileManager.default.displayName(atPath: url.path)
        }
        return condition.kind.title + "：" + condition.value
    }
    private func permissionRow(kind: TriggerKind, title: String, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(title)).font(WorkType.controlLabel)
            Text(L(explanation)).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
            HStack {
                Button(L("请求授权")) { controller.requestPermission(for: kind); Task { await refreshTelemetry() } }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                Button(L("打开权限设置")) { controller.openPermissionSettings(for: kind) }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
        }
    }
}

private struct TriggerRackSurface: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).background(TerminalStyle.surface)
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.7)))
            .overlay(alignment: .top) { Rectangle().fill(active ? TerminalStyle.accent : .clear).frame(height: 2) }
            .overlay(TerminalBrackets().stroke(TerminalStyle.line, lineWidth: 0.7).padding(5).allowsHitTesting(false))
    }
}

private enum RuleTemplate: CaseIterable, Hashable {
    case power, application, schedule, wifi
    var title: String {
        switch self { case .power: return "外接电源连接"; case .application: return "应用 / 进程守护"; case .schedule: return "工作日时间表"; case .wifi: return "指定 Wi-Fi 网络" }
    }
    var kind: TriggerKind {
        switch self { case .power: return .acConnected; case .application: return .appRunning; case .schedule: return .weeklySchedule; case .wifi: return .wifiSSID }
    }
    var condition: String {
        switch self { case .power: return "连接外部电源时"; case .application: return "选择应用或进程后配置"; case .schedule: return "周一至周五 · 09:00–17:00，可编辑"; case .wifi: return "填写目标 Wi-Fi 名称后配置" }
    }
    func draft() -> TriggerRule {
        TriggerRule(name: title, enabled: false,
                    conditions: [TriggerCondition(kind: kind, schedule: self == .schedule ? TriggerWeeklySchedule() : nil)])
    }
}

struct TriggerRuleEditor: View {
    @State var rule: TriggerRule
    @ObservedObject var controller: TriggerController
    let finish: () -> Void
    @State private var error: String?
    @State private var preview = TriggerSnapshot()
    @State private var trial: TriggerEvaluationReport?
    @State private var trying = false
    private var expression: Binding<TriggerExpression> {
        Binding(get: { rule.effectiveExpression }, set: { rule.expression = $0; trial = nil })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("编辑触发规则")).font(WorkType.dialogTitle).accessibilityAddTraits(.isHeader)
            TextField(L("规则名称"), text: $rule.name).textFieldStyle(TerminalTextFieldStyle())
            HStack {
                TerminalPicker("进入模式", selection: $rule.mode, choices: [TerminalChoice("桌面工作", .desk), TerminalChoice("后台工作", .background)])
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("优先级（-1000 至 1000）")).font(.system(size: 10))
                    TextField(L("优先级"), value: $rule.priority, format: .number).frame(width: 160)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("持续满足（秒）")).font(.system(size: 10))
                    TextField(L("持续满足秒数"), value: $rule.sustainedMatchSeconds, format: .number)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("匹配结束后冷却（秒）")).font(.system(size: 10))
                    TextField(L("冷却秒数"), value: $rule.cooldownSeconds, format: .number)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    WorkNote(text: "高优先级先执行；同级后台优先，再按规则 ID 升序。未知不会被取反成满足，并会中断持续计时。冷却从已满足时间要求的匹配解除时开始；每约 5 秒采样，超过 15 秒未采样会中断持续计时。")
                    TriggerExpressionEditor(expression: expression, depth: 0) { condition in
                        AnyView(conditionFields(condition))
                    }
                    if let error = rule.validationError { Text(L(error)).foregroundStyle(.red) }
                }
            }.frame(minHeight: 160, maxHeight: 300)
            HStack {
                Button(L("只读试运行")) {
                    Task {
                        trying = true
                        let original = rule
                        var candidate = original; candidate.enabled = true
                        let result = await controller.dryRun(candidate)
                        if rule == original { trial = result }
                        trying = false
                    }
                }.disabled(trying || rule.validationError != nil).workKeyboardFocus(radius: 0)
                Text(L("按启用此规则预览；不保存、不切换模式、不推进计时。")).font(.system(size: 10)).foregroundStyle(WorkStyle.muted)
            }
            if let trial, let result = trial.rules.first(where: { $0.id == rule.id }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L(result.state.title)).font(WorkType.controlLabel)
                    Text(L(result.detail)).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup(L("查看条件和竞争规则")) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(rule.allConditions) { condition in
                                    if let value = trial.conditions[condition.id] {
                                        Text(condition.kind.title + ": " + L(value.state.title) + " · " + L(value.detail)).font(.system(size: 10))
                                    }
                                }
                                ForEach(trial.rules.filter { $0.id != rule.id }) { other in
                                    Text(other.name + ": " + L(other.state.title) + " · " + L(other.detail)).font(.system(size: 10))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }
                }.padding(10).background(WorkStyle.canvas)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("规则生效时的显示行为")).font(WorkType.controlLabel)
                HStack {
                    TerminalPicker("显示器", selection: $rule.preventDisplaySleep, choices: [TerminalChoice("使用全局设置", nil), TerminalChoice("保持亮屏", true), TerminalChoice("允许闲时息屏", false)])
                    TerminalPicker("屏幕保护", selection: $rule.preventScreenSaver, choices: [TerminalChoice("使用全局设置", nil), TerminalChoice("暂停屏保", true), TerminalChoice("允许屏保", false)])
                }
                WorkNote(text: "覆盖仅在本规则控制工作模式时生效；系统锁定后亮屏与屏保保活会暂停，密码要求由所选锁屏策略决定。")
            }
            WorkToggle(title: "启用这条规则", detail: "启用后会开始自动匹配条件。", isOn: $rule.enabled)
            if let error { Text(L(error)).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L("取消"), action: finish).buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                Button(L("保存")) {
                    error = controller.save(rule)
                    if error == nil { finish() }
                }.buttonStyle(WorkButtonStyle(prominent: true)).workKeyboardFocus(radius: 0)
            }
        }.padding(26).frame(width: 650).background(WorkStyle.canvas).foregroundStyle(WorkStyle.ink)
            .font(.system(size: 12)).tint(WorkStyle.blue)
            .buttonStyle(WorkButtonStyle()).focusEffectDisabled().textFieldStyle(TerminalTextFieldStyle())
            .task(id: rule.allConditions.map(\.kind)) { await refreshPreview() }
            .onChange(of: rule) { _, _ in trial = nil }
    }
    private func conditionFields(_ condition: Binding<TriggerCondition>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            TerminalPicker("条件", selection: condition.kind, choices: TriggerKind.allCases.map { TerminalChoice($0.title, $0) })
            if condition.wrappedValue.kind == .weeklySchedule { scheduleInput(condition) }
            if condition.wrappedValue.kind == .externalDisplay {
                WorkToggle(title: "忽略内建显示器", detail: "只把外接显示器作为匹配条件。", isOn: condition.ignoreBuiltInDisplay)
            }
            if condition.wrappedValue.kind.requiresValue {
                conditionInput(condition)
                if condition.wrappedValue.kind != .appRunning && condition.wrappedValue.kind != .appFrontmost {
                    Text(L(condition.wrappedValue.kind.hint)).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                }
            }
            if let validation = condition.wrappedValue.validationError { Text(L(validation)).font(.system(size: 11)).foregroundStyle(.red) }
        }.onChange(of: condition.wrappedValue.kind) { _, kind in
            if kind == .weeklySchedule && condition.wrappedValue.schedule == nil { condition.wrappedValue.schedule = TriggerWeeklySchedule() }
        }
    }
    @ViewBuilder private func conditionInput(_ condition: Binding<TriggerCondition>) -> some View {
        let kind = condition.wrappedValue.kind
        let suggestions = preview.suggestions(for: kind)
        VStack(alignment: .leading, spacing: 8) {
            if kind == .appRunning || kind == .appFrontmost {
                HStack {
                    Button(L("选择应用…")) { chooseApplication(condition) }.workKeyboardFocus(radius: 0)
                    if !suggestions.isEmpty { suggestionMenu(suggestions, condition: condition, title: "选择运行中的应用") }
                }
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: condition.wrappedValue.value) {
                    Text(FileManager.default.displayName(atPath: appURL.path)).foregroundStyle(WorkStyle.ink)
                }
                DisclosureGroup("应用标识（高级）") {
                    TextField(L("应用 Bundle ID"), text: condition.value).padding(.top, 5)
                }
            } else {
                if !suggestions.isEmpty {
                    HStack {
                        suggestionMenu(suggestions, condition: condition, title: kind == .mountedVolume ? "选择已挂载磁盘" : kind == .processRunning ? "选择运行中的进程" : "选择当前观测")
                        Button(L("刷新")) { Task { await refreshPreview() } }.workKeyboardFocus(radius: 0)
                    }
                } else if [.usbDevice, .bluetoothDevice, .audioOutput, .mountedVolume, .processRunning].contains(kind) {
                    HStack {
                    Text(L(preview.unavailable[kind] ?? "没有可选设备，连接后可刷新。")).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                        Button(L("刷新")) { Task { await refreshPreview() } }.workKeyboardFocus(radius: 0)
                    }
                }
                TextField(L(kind.hint), text: condition.value)
            }
        }
    }
    private func scheduleInput(_ condition: Binding<TriggerCondition>) -> some View {
        let schedule = Binding<TriggerWeeklySchedule>(get: { condition.wrappedValue.schedule ?? TriggerWeeklySchedule() }, set: { condition.wrappedValue.schedule = $0 })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    let selected = schedule.wrappedValue.weekdays.contains(day)
                    Button {
                        if selected { schedule.wrappedValue.weekdays.remove(day) }
                        else { schedule.wrappedValue.weekdays.insert(day) }
                    } label: {
                        Text(L([1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"][day]!))
                    }.buttonStyle(WorkButtonStyle(prominent: selected)).workKeyboardFocus(radius: 0)
                        .accessibilityValue(L(selected ? "已选择" : "未选择"))
                }
            }
            WorkToggle(title: "全天", detail: "按所选星期从当地 00:00 到次日 00:00。", isOn: schedule.allDay)
            if !schedule.wrappedValue.allDay {
                HStack {
                    scheduleTimePicker("开始", minute: schedule.startMinute)
                    scheduleTimePicker("结束", minute: schedule.endMinute)
                }
            }
            WorkNote(text: "使用 Mac 当前时区的当地时间，开始包含、结束不包含。结束早于开始时跨至次日，归属开始的星期。夏令时跳过的时间不匹配，重复小时两次均按当地时间匹配。")
        }
    }
    private func scheduleTimePicker(_ label: String, minute: Binding<Int>) -> some View {
        // A weekly wall-clock time is not an absolute Date. Native NSDatePicker's
        // AX value can apply the system timezone even when its visual timezone
        // is UTC, so represent hours/minutes directly for both display and AX.
        let hour = Binding<Int>(get: { minute.wrappedValue / 60 }, set: { minute.wrappedValue = min(max($0, 0), 23) * 60 + minute.wrappedValue % 60 })
        let fraction = Binding<Int>(get: { minute.wrappedValue % 60 }, set: { minute.wrappedValue = (minute.wrappedValue / 60) * 60 + min(max($0, 0), 59) })
        return HStack(spacing: 5) {
            Text(L(label)).font(WorkType.controlLabel)
            TextField(L("小时"), value: hour, format: .number.precision(.integerLength(2))).frame(width: 46).accessibilityLabel(L(label) + " · " + L("小时"))
            Text(":").foregroundStyle(WorkStyle.muted)
            TextField(L("分钟"), value: fraction, format: .number.precision(.integerLength(2))).frame(width: 46).accessibilityLabel(L(label) + " · " + L("分钟"))
        }.textFieldStyle(TerminalTextFieldStyle()).font(WorkType.body).monospacedDigit()
    }
    private func suggestionMenu(_ suggestions: [TriggerSuggestion], condition: Binding<TriggerCondition>, title: String) -> some View {
        TerminalActionMenu(title: title, titles: suggestions.map(\.title)) { index in
            if suggestions.indices.contains(index) { condition.wrappedValue.value = suggestions[index].value }
        }.frame(width: 250)
    }
    private func refreshPreview() async {
        let kinds = Set(rule.allConditions.map(\.kind))
        let updated = await controller.preview(kinds: kinds)
        guard kinds == Set(rule.allConditions.map(\.kind)) else { return }
        preview = updated
    }
    private func chooseApplication(_ condition: Binding<TriggerCondition>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择应用"; panel.message = "选择应用后自动保存它的标识，用于判断正在运行或位于前台。"
        guard let owner = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: owner) { response in
            guard response == .OK, let url = panel.url else { return }
            guard let id = TriggerController.applicationBundleIdentifier(at: url) else { error = "所选应用没有有效的应用标识，请选择另一个应用。"; return }
            condition.wrappedValue.value = id
            error = nil
        }
    }
}

/// Recursive, native controls preserve every branch when changing operators.
/// Each NOT has exactly one child; switching a multi-child group to NOT wraps it.
private struct TriggerExpressionEditor: View {
    @Binding var expression: TriggerExpression
    let depth: Int
    let conditionFields: (Binding<TriggerCondition>) -> AnyView
    private var operatorBinding: Binding<TriggerExpression.Kind> {
        Binding(get: { expression.kind }, set: { kind in
            let children = expression.children
            switch kind {
            case .all: expression = .all(children)
            case .any: expression = .any(children)
            case .not: expression = .not(children.count == 1 ? children[0] : expression)
            case .condition: break
            }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if case .condition(let item) = expression {
                conditionFields(Binding(get: {
                    if case .condition(let current) = expression { return current }; return item
                }, set: { expression = .condition($0) }))
                HStack {
                    Button(L("取反 NOT")) { expression = .not(expression) }.disabled(depth >= 7)
                    Button(L("扩展为条件组")) { expression = .all([expression, .condition(TriggerCondition())]) }.disabled(depth >= 7)
                }.font(.system(size: 10))
            } else {
                TerminalPicker("逻辑组合", selection: operatorBinding, choices: [TerminalChoice("全部满足 ALL", .all), TerminalChoice("任一满足 ANY", .any), TerminalChoice("不满足 NOT", .not)])
                ForEach(Array(expression.children.indices), id: \.self) { index in
                    HStack(alignment: .top, spacing: 5) {
                        AnyView(TriggerExpressionEditor(expression: childBinding(index), depth: depth + 1, conditionFields: conditionFields))
                        if expression.kind != .not {
                            Button { removeChild(index) } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel(L("移除此条件或分组"))
                        }
                    }
                }
                if expression.children.count == 1 {
                    Button(L("移除这层逻辑")) { expression = expression.children[0] }.font(.system(size: 10))
                }
                if expression.kind != .not {
                    HStack {
                        Button(L("添加条件")) { append(.condition(TriggerCondition())) }.disabled(depth >= 7)
                        Button(L("添加分组")) { append(.any([.condition(TriggerCondition())])) }.disabled(depth >= 6)
                    }.font(.system(size: 10))
                }
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().strokeBorder(WorkStyle.muted.opacity(0.25)))
    }
    private func childBinding(_ index: Int) -> Binding<TriggerExpression> {
        Binding(get: { expression.children.indices.contains(index) ? expression.children[index] : .all([]) }, set: { value in
            var children = expression.children
            guard children.indices.contains(index) else { return }
            children[index] = value; replaceChildren(children)
        })
    }
    private func replaceChildren(_ children: [TriggerExpression]) {
        switch expression {
        case .all: expression = .all(children)
        case .any: expression = .any(children)
        case .not: if let child = children.first { expression = .not(child) }
        case .condition: break
        }
    }
    private func append(_ child: TriggerExpression) { replaceChildren(expression.children + [child]) }
    private func removeChild(_ index: Int) {
        var children = expression.children
        guard children.indices.contains(index) else { return }
        children.remove(at: index); replaceChildren(children)
    }
}
