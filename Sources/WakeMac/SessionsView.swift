// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI
import WakeMacCore

struct SessionsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: SessionController
    @State private var extensionMinutes: Double = 15
    @State private var processSearch = ""
    @State private var showingSaverOptions = false
    @State private var showingCursorOptions = false
    @State private var showingDriveOptions = false

    private var configurationLocked: Bool { controller.isActive || controller.isStarting }
    private var displayedProcesses: [DiscoveredProcess] {
        let search = processSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return controller.processChoices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.executablePath.localizedCaseInsensitiveContains(search) || String($0.identity.pid).contains(search) }
    }
    private var displayPrevention: Binding<Bool> {
        Binding(get: { controller.effectivePreventDisplaySleep }, set: { value in
            Task { await model.changeDisplayPrevention(value) }
        })
    }
    private var saverPrevention: Binding<Bool> {
        Binding(get: { controller.effectivePreventScreenSaver }, set: { value in
            Task { await model.changeScreenSaverPrevention(value) }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsPanel
            effectsPanel
        }
        .task { controller.refreshCursorAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshCursorAccess()
        }
    }

    private var settingsPanel: some View {
        sessionPanel(number: "01", title: "会话设置", subtitle: "TARGET PRESETS", signal: TerminalStyle.accent) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldHeading("开始时使用", subtitle: "INITIAL WORK MODE")
                    HStack(spacing: 6) {
                        modeCard(.desk, title: "桌面工作", detail: "屏幕与屏保由会话效果控制", icon: "display")
                        modeCard(.background, title: "后台工作", detail: "合盖保活", icon: "laptopcomputer")
                    }.padding(5).background(TerminalStyle.recess)
                }.disabled(configurationLocked)

                VStack(alignment: .leading, spacing: 8) {
                    fieldHeading("结束条件", subtitle: "TERMINATION TRIGGER")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        conditionCard(.indefinite, title: "手动结束", detail: "保持至手动切换", index: "01")
                        conditionCard(.duration, title: "定时持续", detail: "到时恢复正常休眠", index: "02")
                        conditionCard(.application, title: "应用退出", detail: "监测所选应用退出", index: "03")
                        conditionCard(.download, title: "下载完成", detail: "观察文件增长与稳定", index: "04")
                    }
                    HStack(spacing: 10) {
                        Text(L("其他结束条件")).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                        Spacer(minLength: 8)
                        TerminalActionMenu(
                            title: controller.endCondition == .untilDate || controller.endCondition == .process ? controller.endCondition.title : "指定时间 / 单个进程",
                            titles: [SessionEndCondition.untilDate.title, SessionEndCondition.process.title]
                        ) { index in
                            controller.endCondition = index == 0 ? .untilDate : .process
                        }.frame(width: 205)
                    }
                }.disabled(configurationLocked)

                if controller.endCondition == .indefinite || controller.endCondition == .duration {
                    durationPresets.disabled(configurationLocked)
                }
                conditionFields.disabled(configurationLocked)
                if controller.isActive, let deadline = controller.deadline {
                    extensionControls(deadline: deadline)
                }
                sessionAction
            }
        }
    }

    private var durationPresets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("快速持续时间设定")).font(WorkType.controlLabel)
                Spacer(minLength: 8)
                Text(controller.endCondition == .indefinite ? L("∞  无限") : LF("%@ 分钟", controller.durationMinutes.formatted(.number.locale(AppLanguage.selected.locale).precision(.fractionLength(0...2)))))
                    .font(TerminalStyle.mono(11)).foregroundStyle(WorkStyle.ink)
            }
            HStack(spacing: 7) {
                durationButton("15m", minutes: 15)
                durationButton("30m", minutes: 30)
                durationButton("1h", minutes: 60)
                durationButton("2h", minutes: 120)
                durationButton("4h", minutes: 240)
                Button {
                    controller.endCondition = .indefinite
                } label: {
                    Text(L("∞ 无限")).font(TerminalStyle.mono(11))
                        .frame(minWidth: 58, minHeight: 30)
                        .foregroundStyle(WorkStyle.ink)
                        .background(controller.endCondition == .indefinite ? TerminalStyle.silver : WorkStyle.surface)
                        .overlay(alignment: .top) { selectionBar(controller.endCondition == .indefinite) }
                        .contentShape(Rectangle())
                }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                    .accessibilityLabel("不限时，手动结束")
                    .accessibilityAddTraits(controller.endCondition == .indefinite ? [.isSelected] : [])
                Spacer(minLength: 0)
            }
            if controller.endCondition == .duration {
                HStack(spacing: 10) {
                    Text(L("自定义时长")).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                    TextField(L("分钟"), value: $controller.durationMinutes, format: .number)
                        .textFieldStyle(TerminalTextFieldStyle()).frame(width: 90)
                        .accessibilityLabel("会话时长，分钟")
                    Text(L("分钟")).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                    Spacer(minLength: 0)
                }
            } else {
                effectText("保持工作状态，直到你结束会话或手动切换模式。")
            }
        }.padding(12).background(TerminalStyle.recess)
    }

    private func durationButton(_ title: String, minutes: Double) -> some View {
        let selected = controller.endCondition == .duration && controller.durationMinutes == minutes
        return Button {
            controller.durationMinutes = minutes
            controller.endCondition = .duration
        } label: {
            Text(L(title)).font(TerminalStyle.mono(11)).frame(width: 40, height: 30)
                .foregroundStyle(WorkStyle.ink)
                .background(selected ? TerminalStyle.silver : WorkStyle.surface)
                .overlay(alignment: .top) { selectionBar(selected) }
                .contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .accessibilityLabel(LF("持续 %@ 分钟", minutes.formatted()))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var sessionAction: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(alignment: .top, spacing: 8) {
                TerminalIcon(name: "info.circle", size: 15)
                    .foregroundStyle(controller.isActive ? TerminalStyle.signal : WorkStyle.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("当前会话状态")).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                    Text(L(controller.status)).font(WorkType.body).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(LF("会话状态：%@", L(controller.status)))
                }
            }
            Spacer(minLength: 0)
            Button {
                Task {
                    if controller.isActive { await controller.end() }
                    else { await controller.start() }
                }
            } label: {
                HStack(spacing: 10) {
                    TerminalIcon(name: controller.isActive ? "stop.fill" : "play", size: 15)
                    Text(L(controller.isStarting ? "正在核验…" : controller.isActive ? "结束会话" : "开始会话"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(controller.isActive ? "END_SESSION" : "ENGAGE_SESSION").font(TerminalStyle.mono(11))
                }.frame(minWidth: 230, minHeight: 42)
            }.buttonStyle(WorkButtonStyle(prominent: true)).workKeyboardFocus(radius: 0)
                .disabled(controller.isStarting)
        }
    }

    private func extensionControls(deadline: Date) -> some View {
        HStack(spacing: 10) {
            Text(LF("结束：%@", deadline.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.selected.locale))))
                .font(WorkType.caption).foregroundStyle(WorkStyle.muted)
            Spacer(minLength: 8)
            TextField(L("分钟"), value: $extensionMinutes, format: .number)
                .textFieldStyle(TerminalTextFieldStyle()).frame(width: 65)
                .accessibilityLabel("延长会话的分钟数")
            Button(L("延长会话")) { controller.extend(minutes: extensionMinutes) }
                .buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
        }
    }

    private var effectsPanel: some View {
        sessionPanel(number: "02", title: "会话效果", subtitle: "HARDWARE ASSERTION MATRIX", signal: TerminalStyle.signal) {
            effectText("保持桌面可见需同时开启防熄屏与防屏保；无需开启「工作时保持未锁定」。")
            VStack(alignment: .leading, spacing: 12) {
                effectText("开关可预先设置；进入桌面或后台工作后生效，恢复正常休眠后停止。")
                if model.screenEffectsControlledByOtherTasks {
                    WorkNote(text: "当前仅有其他任务在运行；请先启动工作会话再调整显示器和屏保。")
                }
                if !controller.screenSaverControlAvailable {
                    WorkNote(text: "当前后台服务不支持独立屏保控制，请完成任务后重启后台服务。")
                }
                effectRow(code: "DISPLAY", descriptor: "IDLE DISPLAY", title: "防止显示器闲时休眠", detail: "不会改变锁屏或密码设置；锁定后暂停。", isOn: displayPrevention, report: controller.effectReport.display, enabled: !model.screenEffectsControlledByOtherTasks) { EmptyView() }
                effectRow(code: "SAVER", descriptor: "USER ACTIVITY", title: "防止闲时屏保", detail: "开启时也会保持显示器唤醒；锁定后暂停。", isOn: saverPrevention, report: controller.effectReport.screenSaver, enabled: controller.screenSaverControlAvailable && !model.screenEffectsControlledByOtherTasks,
                          actionTitle: L("例外应用") + (controller.screenSaverExceptionBundleIDs.isEmpty ? "" : " · \(controller.screenSaverExceptionBundleIDs.count)"), action: { showingSaverOptions.toggle() }) {
                    if showingSaverOptions {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(controller.screenSaverExceptionBundleIDs, id: \.self) { identifier in
                                HStack {
                                    Text(controller.screenSaverExceptionName(identifier)).font(WorkType.caption)
                                    Spacer()
                                    Button { controller.screenSaverExceptionBundleIDs.removeAll { $0 == identifier } } label: { TerminalIcon(name: "minus.circle") }
                                        .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                                        .accessibilityLabel(LF("移除屏保例外 %@", controller.screenSaverExceptionName(identifier)))
                                }
                            }
                            Button(L("添加屏保例外应用")) { controller.chooseScreenSaverException() }
                                .buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                            WorkNote(text: "例外应用运行时暂停自动启动屏保；工作中的开关修改仅影响本次，正常模式下保存为默认。")
                        }
                    }
                }
                effectRow(code: "CURSOR", descriptor: "1 PX / INTERVAL", title: "轻微移动鼠标", detail: "按间隔移动 1 像素并移回；仅在已解锁时运行。", isOn: $controller.moveCursor, report: controller.effectReport.cursor,
                          actionTitle: controller.moveCursor ? "参数与授权" : nil, action: { showingCursorOptions.toggle() }) {
                    if controller.moveCursor, showingCursorOptions {
                        VStack(alignment: .leading, spacing: 12) {
                            secondsField("移动间隔", value: $controller.mouseMovementIntervalSeconds)
                            WorkToggle(title: "仅在闲置时移动", detail: "没有键盘或鼠标输入达到所设时长后才移动；屏保运行时暂停。", isOn: $controller.mouseOnlyWhenIdle)
                            if controller.mouseOnlyWhenIdle { secondsField("闲置多久后开始移动", value: $controller.mouseIdleThresholdSeconds) }
                            WorkToggle(title: "长期闲置后停止移动", detail: "达到停止时长后暂停；再次使用电脑会重新计时。", isOn: Binding(get: { controller.mouseStopAfterIdleSeconds != nil }, set: { controller.mouseStopAfterIdleSeconds = $0 ? 3600 : nil }))
                            if controller.mouseStopAfterIdleSeconds != nil {
                                secondsField("闲置多久后停止移动", value: Binding(get: { controller.mouseStopAfterIdleSeconds ?? 3600 }, set: { controller.mouseStopAfterIdleSeconds = $0 }))
                            }
                            WorkNote(text: "保留系统闲置计时；显示器和屏保由各自开关控制。")
                            Text(L(controller.cursorAccessStatus)).font(WorkType.caption)
                                .foregroundStyle(controller.cursorAccessGranted ? TerminalStyle.signal : WorkStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(L(controller.cursorAccessGranted ? "辅助功能已授权" : "授权辅助功能")) { controller.requestCursorAccess() }
                                .buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                                .disabled(controller.cursorAccessGranted)
                        }
                    }
                }
                effectRow(code: "DISK", descriptor: "DIRECTORY ACCESS", title: "定期访问磁盘", detail: "仅访问所选目录；不阻止手动弹出，部分磁盘仍可能自行休眠。", isOn: $controller.driveAlive,
                          report: controller.driveDirectories.isEmpty ? "未选择磁盘目录" : LF("已选择 %d 个目录", controller.driveDirectories.count),
                          actionTitle: "目录与间隔", action: { showingDriveOptions.toggle() }) {
                    if showingDriveOptions {
                        VStack(alignment: .leading, spacing: 12) {
                            if controller.driveAlive { secondsField("磁盘访问间隔", value: $controller.diskAccessIntervalSeconds) }
                            ForEach(controller.driveDirectories, id: \.path) { directory in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(directory.path).font(TerminalStyle.mono(10)).lineLimit(2)
                                        if let message = controller.effectReport.drives[directory.path] { effectText(message) }
                                    }
                                    Spacer()
                                    Button { controller.driveDirectories.removeAll { $0 == directory } } label: { TerminalIcon(name: "minus.circle") }
                                        .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                                        .accessibilityLabel(LF("移除目录 %@", directory.lastPathComponent))
                                }
                            }
                            Button(L("添加磁盘目录")) { controller.chooseDriveDirectory() }
                                .buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                        }
                    }
                }
            }
        }
    }

    private func effectRow<Content: View>(code: String, descriptor: String, title: String, detail: String, isOn: Binding<Bool>, report: String,
                                          enabled: Bool = true,
                                          actionTitle: String? = nil, action: (() -> Void)? = nil,
                                          @ViewBuilder controls: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text("[" + code + "]").font(TerminalStyle.mono(9))
                    .foregroundStyle(isOn.wrappedValue ? TerminalStyle.accent : WorkStyle.muted)
                    .frame(width: 63, alignment: .leading).padding(.top, 4)
                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) {
                            Text(L(title)).font(.system(size: 13, weight: .semibold))
                            Text(descriptor).font(TerminalStyle.mono(8)).foregroundStyle(WorkStyle.muted)
                        }
                        Text(L(title)).font(.system(size: 13, weight: .semibold))
                    }
                    Text(L(detail)).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 5) {
                        Text("↳").font(TerminalStyle.mono(10)).foregroundStyle(WorkStyle.muted)
                        Text(L(report)).font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityLabel(LF("运行反馈：%@", L(report)))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle(L(title), isOn: isOn).labelsHidden().toggleStyle(TerminalSwitchStyle())
                            .disabled(!enabled)
                        .accessibilityLabel(title).accessibilityHint(detail)
                    if let actionTitle, let action {
                        Button(L(actionTitle), action: action).font(WorkType.caption)
                            .buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                    }
                }
            }
            controls()
        }.padding(12).background(TerminalStyle.recess)
            .overlay(Rectangle().strokeBorder(WorkStyle.line.opacity(0.3)))
    }

    private func modeCard(_ mode: WorkMode, title: String, detail: String, icon: String) -> some View {
        let selected = controller.defaultMode == mode
        return Button { controller.defaultMode = mode } label: {
            HStack(spacing: 12) {
                TerminalIcon(name: icon, size: 19)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L(title)).font(.system(size: 14, weight: .semibold))
                    Text(L(detail)).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                }
            }.frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(selected ? WorkStyle.ink : WorkStyle.muted)
                .background(selected ? TerminalStyle.silver : TerminalStyle.recess)
                .overlay(alignment: .top) { selectionBar(selected) }
                .contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .accessibilityLabel(title + "，" + detail)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func conditionCard(_ condition: SessionEndCondition, title: String, detail: String, index: String) -> some View {
        let selected = controller.endCondition == condition
        return Button { controller.endCondition = condition } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("COND " + index).font(TerminalStyle.mono(10)).foregroundStyle(WorkStyle.muted)
                Text(L(title)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    .minimumScaleFactor(0.85).frame(height: 34, alignment: .topLeading)
                Text(L(detail)).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                    .lineLimit(3).minimumScaleFactor(0.85).frame(height: 40, alignment: .topLeading)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                .foregroundStyle(WorkStyle.ink)
                .background(selected ? TerminalStyle.silver : TerminalStyle.recess)
                .overlay(alignment: .top) { selectionBar(selected) }
                .contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .accessibilityLabel(title + "，" + detail)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func selectionBar(_ selected: Bool) -> some View {
        Rectangle().fill(TerminalStyle.accent).frame(height: 2).opacity(selected ? 1 : 0).allowsHitTesting(false)
    }

    private func fieldHeading(_ title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Text(L(title)).font(WorkType.controlLabel)
            Text("// " + subtitle).font(TerminalStyle.mono(10)).foregroundStyle(WorkStyle.muted)
        }
    }

    private func sessionPanel<Content: View>(number: String, title: String, subtitle: String, signal: Color, @ViewBuilder content: () -> Content) -> some View {
        PreferencesConsoleRack(number: number, title: title, code: subtitle, accent: signal) {
            content()
        }
    }

    @ViewBuilder private var conditionFields: some View {
        switch controller.endCondition {
        case .indefinite, .duration:
            EmptyView()
        case .untilDate:
            HStack { Text(L("结束时间")).font(WorkType.controlLabel); Spacer(); SchedulePicker(selection: $controller.endDate) }
        case .application:
            HStack {
                Text(controller.applicationURL?.deletingPathExtension().lastPathComponent ?? L("未选择应用"))
                    .font(WorkType.body).foregroundStyle(WorkStyle.muted)
                Spacer()
                Button(L("选择正在运行的应用")) { controller.chooseApplication() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
            WorkNote(text: "核验应用包身份及实际运行进程；全部匹配实例退出后结束。无法核验时继续等待。")
        case .process:
            if !controller.processChoices.isEmpty {
                TextField(L("搜索进程名称、路径或 PID"), text: $processSearch).textFieldStyle(TerminalTextFieldStyle()).font(WorkType.body)
            }
            HStack {
                TerminalActionMenu(title: controller.selectedProcess.map { "\($0.name) · PID \($0.identity.pid)" } ?? "选择进程", titles: displayedProcesses.map { "\($0.name) · PID \($0.identity.pid)" }) { index in
                    if displayedProcesses.indices.contains(index) { controller.selectedProcess = displayedProcesses[index] }
                }.frame(width: 260).disabled(displayedProcesses.isEmpty)
                Spacer()
                Button(L("刷新进程")) { controller.refreshProcesses() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
            if let process = controller.selectedProcess { effectText(process.executablePath) }
            WorkNote(text: L(controller.processDiscoveryStatus) + " · " + L("仅监测所选的这次运行；同名进程重启不会延续会话。"))
        case .download:
            HStack {
                Text(controller.downloadURL?.lastPathComponent ?? L("未选择文件")).font(WorkType.body).foregroundStyle(WorkStyle.muted).lineLimit(2)
                Spacer()
                Button(L("选择下载文件")) { controller.chooseDownload() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
            if let percent = controller.downloadProgressPercent {
                ProgressView(value: percent, total: 100)
                effectText(LF("系统报告下载进度：%@%%", percent.formatted(.number.precision(.fractionLength(0)))))
            } else { effectText("未获得系统发布的下载百分比；仍按文件增长与稳定时长监测。") }
            secondsField("下载稳定时长", value: $controller.downloadStabilitySeconds)
            WorkNote(text: "用于大文件下载：下载期间保持唤醒，完成后结束本次会话并恢复正常休眠。先观察文件增长，再等待完成重命名和稳定；网络暂停可能被视为稳定，重要下载请手动结束。")
        }
    }

    private func secondsField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(L(title)).font(WorkType.controlLabel)
            Spacer()
            TextField(L("秒"), value: value, format: .number).textFieldStyle(TerminalTextFieldStyle()).frame(width: 75).accessibilityLabel(title + "，秒")
            Text(L("秒")).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
        }
    }
    private func effectText(_ text: String) -> some View {
        Text(L(text)).font(WorkType.caption).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true)
    }
}
