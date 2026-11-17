// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import SwiftUI
import AppKit
import ApplicationServices

extension Notification.Name {
    static let orexinOpenCorePreferences = Notification.Name("Orexin.OpenCorePreferences")
}

struct CoreRuntimePreferencesView: View {
    @ObservedObject var model: AppModel
    private var working: Bool {
        model.busy || model.legacyWorkMode != nil || model.sessions.isActive || model.sessions.isStarting
        || !model.workRequests.active.isEmpty || !model.runningCommandIDs.isEmpty
        || model.servicePlans.contains { !$0.state.terminal }
    }
    var body: some View {
        PreferencesConsoleRack(number: "01", title: "后台核心", code: "RUNTIME CORE") {
            Text(L("会话、自动规则和任务由后台核心管理，退出界面后继续运行。"))
                .font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
            HStack(spacing: 12) {
                Circle().fill(model.serviceInfo != nil && !model.serviceConnectionFailed ? TerminalStyle.signal : TerminalStyle.amber)
                    .frame(width: 7, height: 7)
                Text(L(model.serviceInfo == nil ? "核心未连接" : "核心已连接"))
                    .font(WorkType.controlLabel)
                if let info = model.serviceInfo {
                    Text("PID \(info.pid)").font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted)
                }
                Spacer(minLength: 0)
                Button(L(model.serviceInfo == nil ? "启动核心" : "重新连接")) {
                    Task { await model.connectTaskService() }
                }.disabled(model.busy)
                if model.coreUpgradeRequired {
                    Button(L("重启并升级核心")) { Task { await model.restartCoreService() } }.disabled(working)
                }
                Button(L("停止核心")) { Task { await model.stopCoreService() } }
                    .disabled(working || model.serviceInfo == nil)
            }.padding(12).background(TerminalStyle.recess)
            if model.serviceConnectionFailed || model.error {
                Text(L(model.message)).font(WorkType.caption).foregroundStyle(TerminalStyle.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RememberAccountPasswordView: View {
    @ObservedObject var credentials: UnlockedWorkCredentials
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkToggle(title: "记住账户密码，自动授权",
                detail: "将 Mac 账户密码保存到本机钥匙串，用于自动授权“工作时保持未锁定”。关闭后删除保存的密码。",
                isOn: Binding(get: { credentials.enabled }, set: { enabled in
                    Task { do { try await credentials.setEnabled(enabled) } catch { /* The controller presents the failure. */ } }
                }))
                .disabled(credentials.busy)
            if let message = credentials.message {
                Text(L(message)).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(TerminalStyle.recess)
    }
}

struct CorePermissionPreferencesView: View {
    @ObservedObject var model: AppModel
    @State private var input = false
    @State private var accessibility = false
    @State private var location = false
    @State private var bluetooth = false

    var body: some View {
        PreferencesConsoleRack(number: "04", title: "系统权限", code: "PERMISSION ACCESS") {
            permission("输入监控", detail: "用于 Esc 和亮度按键恢复屏幕亮度。", granted: input) {
                if input { openPrivacy("Privacy_ListenEvent") }
                else { _ = CGRequestListenEventAccess() }
            }
            permission("辅助功能", detail: "用于工作期间的自动移动指针。", granted: accessibility) {
                if accessibility { openPrivacy("Privacy_Accessibility") }
                else { model.sessions.requestCursorAccess() }
            }
            permission("定位服务", detail: "用于 Wi-Fi 网络名称触发条件。", granted: location) {
                if location { model.triggers.openPermissionSettings(for: .wifiSSID) }
                else { model.triggers.requestPermission(for: .wifiSSID) }
            }
            permission("蓝牙", detail: "用于已连接蓝牙设备触发条件。", granted: bluetooth) {
                if bluetooth { model.triggers.openPermissionSettings(for: .bluetoothDevice) }
                else { model.triggers.requestPermission(for: .bluetoothDevice) }
            }
        }.onAppear(perform: refresh)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NativeTriggerObservations.permissionChanged)) { _ in refresh() }
    }
    private func permission(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L(title)).font(WorkType.controlLabel)
                Text(L(detail)).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(L(granted ? "已授权" : "未授权")).font(WorkType.caption)
                .foregroundStyle(granted ? TerminalStyle.signal : TerminalStyle.amber)
            Button(L(granted ? "打开权限设置" : "请求授权")) { action(); refresh() }
        }.padding(12).background(TerminalStyle.recess)
    }
    private func refresh() {
        input = CGPreflightListenEventAccess()
        accessibility = AXIsProcessTrusted()
        location = model.triggers.permissionState(for: .wifiSSID) == .authorized
        bluetooth = model.triggers.permissionState(for: .bluetoothDevice) == .authorized
        model.refreshHelperStatus()
    }
    private func openPrivacy(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) else { return }
        NSWorkspace.shared.open(url)
    }
}
