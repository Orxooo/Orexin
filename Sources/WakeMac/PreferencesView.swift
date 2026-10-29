// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI
import AppKit
import ServiceManagement
import WakeMacCore

private enum PreferencePage: String, CaseIterable {
    case power = "工作模式", sessions = "工作会话", triggers = "自动触发", automation = "自动收尾", command = "任务管理", settings = "偏好设置", thermal = "温度保护", advanced = "主题外观", notices = "消息提醒", history = "运行记录", about = "关于软件"
    var icon: String {
        switch self { case .power: "sun.max"; case .sessions: "hourglass"; case .triggers: "bolt.badge.clock"; case .automation: "timer"; case .command: "terminal"; case .settings: "slider.horizontal.3"; case .thermal: "thermometer"; case .advanced: "paintbrush.pointed"; case .notices: "bell"; case .history: "clock.arrow.circlepath"; case .about: "info.circle" }
    }
    var code: String {
        switch self { case .power: "MODES"; case .sessions: "SESS"; case .triggers: "TRIG"; case .automation: "TEAR"; case .command: "TASKS"; case .settings: "CONF"; case .thermal: "TEMP"; case .advanced: "STYLE"; case .notices: "ALERTS"; case .history: "LOGS"; case .about: "ABOUT" }
    }
    var number: String { String(format: "%02d", (Self.allCases.firstIndex(of: self) ?? 0) + 1) }
    var englishTitle: String {
        switch self {
        case .power: "POWER CONTROL SYSTEM"
        case .sessions: "SESSION TARGET CONTROL"
        case .triggers: "AUTO DISPATCH SYSTEM"
        case .automation: "AUTO TEARDOWN & POWER DEFENSE"
        case .command: "TASK MANAGEMENT"
        case .settings: "SYSTEM & DAEMON PREFERENCES"
        case .thermal: "THERMAL SAFEGUARD"
        case .advanced: "CONSOLE STYLE MATRIX"
        case .notices: "MESSAGES & NOTIFICATIONS"
        case .history: "SYSTEM AUDIT & EVENT LOGS"
        case .about: "ABOUT & UPDATES"
        }
    }
    var subtitle: String {
        switch self {
        case .power: "保持唤醒，合盖继续；工作结束后安心休眠。"
        case .sessions: "设置保持唤醒多久，或在应用退出、下载完成后自动结束。"
        case .triggers: "条件满足时自动开始，手动操作始终优先。"
        case .automation: "让工作按时结束，也照顾好电量。"
        case .command: "统一查看任务，独立保活，按结果收尾。"
        case .settings: "按你的习惯，安排每一次切换。"
        case .thermal: "监测系统温度压力，在过热时释放保活。"
        case .advanced: "调整主题、语言、菜单栏与声音。"
        case .notices: "更新、服务状态和保护事件，集中查看。"
        case .history: "模式切换与运行状态，都留在这里。"
        case .about: "了解 Orexin，查看更新与开源主页。"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hotkeys: GlobalHotKeys
    @ObservedObject var notifier: LocalNotifier
    @ObservedObject private var notices: ClientNoticeCenter
    @ObservedObject private var appearance: AppearanceController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("orexin.appearance.language") private var languageID = "zh-Hans"
    @State private var page = PreferencePage.power
    @State private var date = Date().addingTimeInterval(3600)
    @State private var teardownPreset = 60
    @State private var command = ""
    @State private var taskSection = TaskManagementSection.tasks
    @State private var directory = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var shortcutDraft = ShortcutBinding.defaults
    @State private var shortcutEnabled = true
    init(model: AppModel, hotkeys: GlobalHotKeys, notifier: LocalNotifier) {
        self.model = model; self.hotkeys = hotkeys; self.notifier = notifier; self.appearance = model.appearance; self.notices = model.notices
    }

    var body: some View {
        GeometryReader { window in
        VStack(spacing: 0) {
            consoleHeader
            HStack(spacing: 0) {
            sidebar.fixedSize(horizontal: true, vertical: false)
            contentPane(width: max(0, window.size.width - 206))
        }
        }.frame(width: window.size.width, height: window.size.height, alignment: .topLeading)
        }
        // Rebuild rendered controls when the palette changes. Page and command drafts
        // remain owned by PreferencesView; power/session state remains in controllers.
        .id(appearance.theme.rawValue + "/" + languageID)
        .environment(\.locale, (AppLanguage(rawValue: languageID) ?? .simplifiedChinese).locale)
        .frame(minWidth: 860, minHeight: 630)
        .background { TerminalStyle.paper; TerminalAtmosphere() }
        .overlay(CRTLines())
        .font(WorkType.body).foregroundStyle(TerminalStyle.ink).tint(TerminalStyle.accent)
        .buttonStyle(TerminalButtonStyle()).focusEffectDisabled().preferredColorScheme(appearance.theme.colorScheme)
        .onChange(of: model.requestedTaskPage) { _, _ in page = .command; taskSection = .tasks }
        .onChange(of: model.requestedNoticePage) { _, _ in page = .notices }
        .onAppear { shortcutDraft = hotkeys.bindings; shortcutEnabled = hotkeys.enabled }
        .onReceive(NotificationCenter.default.publisher(for: .wakeMacOpenTemperature)) { _ in page = .thermal }
        .onReceive(NotificationCenter.default.publisher(for: .wakeMacOpenCommandTask)) { _ in page = .command; taskSection = .run }
        .onReceive(NotificationCenter.default.publisher(for: .orexinOpenAbout)) { _ in page = .about }
    }

    private func contentPane(width: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(page.number) // \(page.code) · POWER TERMINAL").font(TerminalStyle.mono(10)).tracking(0.6).foregroundStyle(TerminalStyle.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(L(page.rawValue)).font(.system(size: 27, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        Text(page.englishTitle).font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                    }
                    if page != .power { Text(L(page.subtitle)).font(.system(size: 12)).foregroundStyle(TerminalStyle.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    if page == .settings { serviceHeaderStatus }
                    if page == .history { historyHeaderStatus }
                }.padding(.vertical, 18).padding(.horizontal, 22)
                    .overlay(alignment: .bottom) { Rectangle().fill(TerminalStyle.line.opacity(0.5)).frame(height: 1) }
                if notices.unreadCount > 0 && page != .notices {
                    HStack {
                        Text(LF("有 %d 条未读提醒", notices.unreadCount)).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Button(L("查看消息")) { page = .notices }
                    }.padding(.horizontal, 22).padding(.vertical, 10).background(TerminalStyle.recess)
                }
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("page-top")
                        ZStack(alignment: .topLeading) {
                            ForEach(PreferencePage.allCases, id: \.self) { item in
                                if page == item {
                                    VStack(alignment: .leading, spacing: 16) { pageContent(item, contentWidth: width) }
                                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                                        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 20)
                                        .transition(reduceMotion ? .identity : .asymmetric(
                                            insertion: .opacity.combined(with: .offset(y: 12)),
                                            removal: .opacity.combined(with: .offset(y: -6))))
                                }
                            }
                        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: page)
                }.frame(width: width)
                    .defaultScrollAnchor(.topLeading)
                    .onChange(of: page) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                    .onChange(of: taskSection) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
                }
            }.frame(width: width, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading).clipped()
    }

    @ViewBuilder private func pageContent(_ page: PreferencePage, contentWidth: CGFloat) -> some View {
        switch page {
        case .power: PowerHomeView(model: model, sessions: model.sessions) { self.page = .sessions }
        case .sessions: sessionsTab(contentWidth: contentWidth)
        case .triggers: TriggersView(controller: model.triggers)
        case .automation: AutoTeardownView(model: model, date: $date, preset: $teardownPreset, availableWidth: max(0, contentWidth - 40))
        case .command: CommandTasksView(model: model, command: $command, directory: $directory, availableWidth: max(0, contentWidth - 40), section: $taskSection)
        case .settings: settingsTab(contentWidth: contentWidth)
        case .thermal: ThermalProtectionView(model: model, availableWidth: max(0, contentWidth - 40))
        case .advanced: AdvancedView(appearance: model.appearance, notifier: notifier, availableWidth: max(0, contentWidth - 40))
        case .notices: ClientNoticesView(notices: notices, notifier: notifier, updates: model.updates, serviceNoticeSupport: model.serviceNoticeSupport)
        case .history: HistoryRecordsView(model: model, availableWidth: max(0, contentWidth - 40))
        case .about: AboutSoftwareView(updates: model.updates, availableWidth: max(0, contentWidth - 40))
        }
    }

    private var serviceHeaderStatus: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SM_SERVICE_STATE").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                Text(model.helperStatus == .enabled ? "AUTHORIZED" : model.helperStatus == .requiresApproval ? "AWAITING APPROVAL" : "NOT REGISTERED")
                    .font(TerminalStyle.mono(10)).foregroundStyle(model.helperStatus == .enabled ? TerminalStyle.signal : TerminalStyle.amber)
            }
            Rectangle().fill(TerminalStyle.line).frame(width: 1, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("POWER ASSERTION").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                Text(model.snapshot == nil ? "UNKNOWN" : model.keepsAwake ? "ENGAGED" : "RELEASED")
                    .font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.accent)
            }
        }.padding(10).background(TerminalStyle.recess).overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
    }

    private var historyHeaderStatus: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("RING_BUFFER_STATUS").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(model.history.count) / \(HistoryStore.maximumEntries)").font(TerminalStyle.mono(18))
                    Text("LOCAL").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.signal)
                        .padding(3).background(TerminalStyle.selection)
                }
            }
            TerminalIcon(name: "cpu", size: 22).foregroundStyle(TerminalStyle.accent).frame(width: 40, height: 40)
                .background(TerminalStyle.silver).accessibilityHidden(true)
        }.padding(12).background(TerminalStyle.surface).overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.7)))
    }

    private var consoleHeader: some View {
        HStack(spacing: 12) {
            ConsoleWindowControls()
            ApplicationBadge().frame(width: 26, height: 26)
            Text("OREXIN").font(TerminalStyle.mono(14)).tracking(1.5)
            Text("SYS // \(OrexinRelease.displayVersion)")
                .font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent).padding(.horizontal, 6).padding(.vertical, 3).background(TerminalStyle.silver)
            WindowDragRegion().frame(maxWidth: .infinity, maxHeight: .infinity)
            if let battery = model.battery {
                TerminalLabel("BAT: \(battery.percent)% · " + L(battery.onBattery ? "电池供电" : "已接电源"), systemImage: battery.onBattery ? "battery.75percent" : "battery.100percent.bolt")
                    .font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.signal)
            }
        }.padding(.horizontal, 18).frame(height: 50).background(TerminalStyle.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(TerminalStyle.line.opacity(0.6)).frame(height: 1) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AVIONICS CORE").font(TerminalStyle.mono(9)).tracking(1.1).foregroundStyle(TerminalStyle.muted)
                Text("SUBSYSTEM NAVIGATION").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.ink)
            }.padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 22)
            VStack(spacing: 5) {
                ForEach(PreferencePage.allCases, id: \.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { page = item }
                    } label: {
                        HStack(spacing: 10) {
                            Text(item.number + " //").font(TerminalStyle.mono(9)).opacity(0.75)
                            Text(L(item.rawValue)).font(.system(size: 12, weight: page == item ? .semibold : .regular))
                                .lineLimit(2).minimumScaleFactor(0.85).frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 0)
                            Text(item.code).font(TerminalStyle.mono(9)).opacity(0.7)
                        }.padding(.horizontal, 12).frame(height: 37)
                            .foregroundStyle(page == item ? TerminalStyle.accent : TerminalStyle.muted)
                            .background {
                                if page == item { TerminalStyle.selection }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                        .accessibilityAddTraits(page == item ? [.isSelected] : [])
                }
            }.overlay(alignment: .topLeading) {
                Rectangle().fill(TerminalStyle.accent).frame(height: 2)
                    .offset(y: CGFloat(PreferencePage.allCases.firstIndex(of: page) ?? 0) * 42)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: page)
                    .allowsHitTesting(false)
            }.padding(.horizontal, 10)
            Spacer(minLength: 18)
            VStack(alignment: .leading, spacing: 8) {
                Text("HARDWARE SECURITY").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                TerminalLabel(model.lockSummary, systemImage: model.requiresImmediateLock ? "checkmark.shield" : "gearshape")
                    .font(.system(size: 10)).foregroundStyle(TerminalStyle.accent).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(L("合盖服务")).font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                    Spacer()
                    Text(L(model.helperStatus == .enabled ? "已授权" : "未授权")).font(TerminalStyle.mono(9)).foregroundStyle(model.helperStatus == .enabled ? TerminalStyle.signal : TerminalStyle.amber)
                }
            }.padding(12).background(TerminalStyle.surface).padding(12)
        }.frame(width: 206).frame(maxHeight: .infinity).background(TerminalStyle.recess)
    }

    private func sessionsTab(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            orbitalColumns(contentWidth: contentWidth) {
                SessionsView(model: model, controller: model.sessions)
                IdleScreenConsoleView(controller: model.idlePolicy, immediateAuthentication: model.snapshot?.lockPolicy == .immediate)
            } trailing: {
                VStack(spacing: 16) {
                    VStack(spacing: 14) {
                        OrbitalMoon(phase: model.active?.rawValue ?? "unknown").frame(height: 210)
                        Rectangle().fill(TerminalStyle.line).frame(height: 1)
                        Text("REMAINING CYCLE").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                        Text(sessionRemaining).font(TerminalStyle.mono(28)).foregroundStyle(TerminalStyle.ink)
                        Button(L("+15 MIN // 延长")) { _ = model.sessions.extend(minutes: 15); model.onUpdate?() }
                            .disabled(!model.verifiedWork || model.sessions.deadline == nil)
                    }.padding(16).terminalSurface()
                    OrbitalEventFeed(entries: model.history, title: "会话记录")
                }
            }
        }
    }
    private var sessionRemaining: String {
        guard let deadline = model.sessions.deadline else { return model.sessions.isActive ? "∞" : "--:--:--" }
        let seconds = max(0, Int(deadline.timeIntervalSince(model.now)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func settingsTab(contentWidth: CGFloat) -> some View {
        Group {
            PreferencesConsoleRack(number: "01", title: "合盖运行特权服务", code: "SMAPPSERVICE CLAMSHELL DAEMON", metadata: "DAEMON CONTROL") {
                Text(L("合盖继续运行需要启用 Orexin 自带的系统服务，并在系统设置中批准一次。"))
                    .font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                PreferencesConsoleFooter(stacked: contentWidth < 760) {
                    HStack(spacing: 8) {
                        if model.helperStatus == .enabled {
                            PreferencesServiceReadyBadge()
                        } else {
                            Button(action: model.enableHelper) {
                                PreferencesTelemetryLabel(title: model.helperStatus == .requiresApproval ? "完成授权" : "启用合盖服务",
                                    code: model.helperStatus == .requiresApproval ? "AUTHORIZE" : "DAEMON_ENABLE", icon: "checkmark.shield")
                            }.workKeyboardFocus(radius: 0).disabled(model.busy)
                        }
                        Button { SMAppService.openSystemSettingsLoginItems() } label: {
                            PreferencesTelemetryLabel(title: "打开系统设置", code: "SYS_SETTINGS", icon: "arrow.up.right.square")
                        }.workKeyboardFocus(radius: 0)
                    }
                } action: {
                    Button(role: .destructive) { Task { await model.removeHelper() } } label: {
                        PreferencesTelemetryLabel(title: "移除服务", code: "PURGE", icon: "trash")
                    }.workKeyboardFocus(radius: 0).disabled(model.busy)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(model.helperStatus == .enabled ? TerminalStyle.signal : TerminalStyle.amber).frame(width: 7, height: 7).padding(.top, 4)
                        Text(L(model.helperStatus == .enabled ? "系统已批准辅助服务；实际连接会在启动相关功能时核验。" : model.helperMessage.isEmpty ? "合盖服务尚未授权。" : model.helperMessage))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(model.helperStatus == .enabled ? TerminalStyle.signal : TerminalStyle.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    WorkNote(text: "切换回正常模式或退出应用会恢复休眠；异常断线和心跳超时由服务自动恢复。")
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(TerminalStyle.recess)
                    .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.45)))
            }
            PreferencesConsoleRack(number: "02", title: "锁屏与密码策略", code: "SECURITY & PRIVACY GUARDS", accent: TerminalStyle.secondary, metadata: "AUTHENTICATION POLICY") {
                WorkToggle(title: "工作时保持未锁定", detail: "额外选项：熄屏或合盖返回时免输密码，每次新工作需账户密码。仅保持桌面可见无需开启，防熄屏与防屏保无需密码授权。", isOn: Binding(get: { model.unlockedWorkEnabled }, set: { enabled in Task { await model.setUnlockedWork(enabled) } }))
                    .disabled(model.busy || (!model.unlockedWorkEnabled && model.helperStatus != .enabled))
                    .padding(12).background(TerminalStyle.recess)
                WorkToggle(title: "要求即时密码保护", detail: "默认开启。关闭后跟随 macOS 的密码要求，可使用系统设置的延迟或不要求密码。", isOn: Binding(get: { model.requiresImmediateLock }, set: { enabled in Task { await model.setRequireImmediateLock(enabled) } }))
                    .disabled(model.busy || model.unlockedWorkEnabled).padding(12).background(TerminalStyle.recess)
                    .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.45)))
                PreferencesConsoleFooter(stacked: contentWidth < 760) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TerminalIcon(name: "info.circle", size: 13).foregroundStyle(TerminalStyle.signal)
                        Text(L(model.unlockedWorkEnabled ? "临时保持未锁定仅从即时密码策略开始；结束、退出或服务恢复后重新要求即时密码。不会解锁已经锁定的 Mac。" : "Orexin 不修改系统密码要求，也不解锁已锁定的 Mac。系统设为不要求密码时，熄屏后返回桌面也不再要求密码。"))
                            .font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } action: {
                    Button(action: model.openLockSettings) {
                        PreferencesTelemetryLabel(title: "打开系统锁屏设置", code: "LOCK_SETTINGS", icon: "shield")
                    }.workKeyboardFocus(radius: 0)
                }
            }
            PreferencesConsoleRack(number: "03", title: "日常使用偏好", code: "CONSOLE INTERACTION", accent: TerminalStyle.muted, metadata: "LOCAL PREFERENCES") {
                WorkToggle(title: "菜单栏显示模式和倒计时", detail: "在 macOS 状态栏显示当前模式，以及剩余时长或结束时间。", isOn: Binding(get: { model.menuLabelEnabled }, set: model.setMenuLabel)).padding(.vertical, 5)
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "登录时启动 // Launch at Login", detail: "登录后启动 Orexin 菜单栏应用；是否自动开始会话由下方默认会话设置控制。", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin)).padding(.vertical, 5)
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "低电量保护", detail: LF("电池供电且电量达到 %d%% 时，留出 60 秒取消后请求休眠。", model.automation.batteryThreshold), isOn: Binding(get: { model.automation.batteryEnabled }, set: { model.setBatteryProtection(enabled: $0, threshold: model.automation.batteryThreshold) })).padding(.vertical, 5)
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("系统通知")).font(WorkType.controlLabel)
                        Text(L(notifier.enabled ? "通知已开启" : "接收任务结果与电量提醒")).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    }
                    Spacer()
                    if notifier.enabled {
                        Button { notifier.send("Orexin 测试通知：通知通道已触发。") } label: {
                            PreferencesTelemetryLabel(title: "测试通知", code: "EMIT_PING", icon: "bell")
                        }.workKeyboardFocus(radius: 0)
                    }
                    Button(L(notifier.enabled ? "通知设置…" : "开启通知…")) {
                        if notifier.enabled { notifier.showSettings() }
                        else { Task { _ = await notifier.request() } }
                    }.workKeyboardFocus(radius: 0)
                }
                if !notifier.message.isEmpty { WorkNote(text: notifier.message) }
            }.toggleStyle(TerminalSwitchStyle()).controlSize(.small)
            settingsEventStream
            PreferencesAdditionalSettings {
                PreferencesConsoleRack(number: "04", title: "会话通知", code: "SESSION EVENT DELIVERY", accent: TerminalStyle.signal) {
                    Text(L("任务结果、低电量与错误提醒继续保留。"))
                        .font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                    WorkToggle(title: "工作会话开始", isOn: $notifier.sessionStart)
                    WorkToggle(title: "工作会话结束", isOn: $notifier.sessionEnd)
                    WorkToggle(title: "自动触发开始与结束", isOn: $notifier.triggerChange)
                    WorkToggle(title: "自动清理已显示的 Orexin 通知", isOn: $notifier.autoClear)
                }
                PreferencesConsoleRack(number: "05", title: "全局快捷键", code: "GLOBAL KEY BINDINGS") {
                    WorkToggle(title: "启用快捷键", isOn: $shortcutEnabled)
                    ForEach(shortcutDraft.indices, id: \.self) { index in
                        HStack {
                            Text(L(shortcutDraft[index].title)).font(WorkType.controlLabel)
                            Spacer()
                            Toggle("启用" + shortcutDraft[index].title, isOn: $shortcutDraft[index].enabled)
                                .labelsHidden().toggleStyle(TerminalSwitchStyle()).controlSize(.small)
                            TerminalPicker("修饰键", selection: $shortcutDraft[index].modifiers, choices: GlobalHotKeys.modifiers.map { TerminalChoice($0.0, $0.1) }).labelsHidden().frame(width: 108)
                            TerminalPicker("按键", selection: $shortcutDraft[index].key, choices: GlobalHotKeys.keys.map { TerminalChoice($0.0, $0.1) }).labelsHidden().frame(width: 66)
                        }
                    }
                    HStack {
                        Text(L(hotkeys.message.isEmpty ? "模式默认使用 ⌃⌥ + 1 / 2 / 3；其他操作按需开启。" : hotkeys.message))
                            .font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                        Spacer()
                        Button(L("保存快捷键")) { hotkeys.apply(shortcutDraft, enabled: shortcutEnabled) }.workKeyboardFocus(radius: 0)
                    }
                }
                BehaviorSettingsView(behavior: model.behavior)
            }
            HStack {
                WorkNote(text: "退出前会恢复正常休眠。", icon: "power")
                Spacer()
                Button(L("提交问题")) { NSWorkspace.shared.open(OrexinRelease.issuesURL) }.workKeyboardFocus(radius: 0)
                Button(L("退出 Orexin")) { Task { await model.requestQuit() } }.workKeyboardFocus(radius: 0).disabled(model.busy)
            }
            if model.jobRunning { WorkNote(text: "命令仍在运行，退出时会等待任务结束。") }
        }
    }

    private var settingsEventStream: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TerminalIcon(name: "terminal", size: 13).foregroundStyle(TerminalStyle.accent)
                Text("DAEMON / SYSTEM EVENT STREAM").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 0)
                Text("LOCAL RECORDS").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.signal)
            }
            Rectangle().fill(TerminalStyle.line.opacity(0.5)).frame(height: 1)
            if model.history.isEmpty {
                Text(L("尚无运行记录")).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
            }
            ForEach(model.history.prefix(4)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("[" + entry.date.formatted(date: .omitted, time: .standard) + "]").foregroundStyle(TerminalStyle.muted)
                    Text(L(entry.text)).foregroundStyle(TerminalStyle.accent).fixedSize(horizontal: false, vertical: true)
                }.font(TerminalStyle.mono(9))
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(TerminalStyle.recess)
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.55)))
    }

    @ViewBuilder private func orbitalColumns<Leading: View, Trailing: View>(contentWidth: CGFloat, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) -> some View {
        if contentWidth > 760 {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) { leading() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 16) { trailing() }
                    .frame(width: min(280, (contentWidth - 56) * 0.27))
            }
        } else {
            VStack(alignment: .leading, spacing: 16) { leading(); trailing() }
        }
    }

    @ViewBuilder private var feedback: some View {
        if !model.convenienceMessage.isEmpty { WorkNote(text: model.convenienceMessage) }
    }
}
