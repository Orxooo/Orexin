// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

struct ClientNoticesView: View {
    @ObservedObject var notices: ClientNoticeCenter
    @ObservedObject var notifier: LocalNotifier
    @ObservedObject var updates: UpdateMonitor
    var serviceNoticeSupport: Bool?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("提醒设置")).font(.system(size: 16, weight: .semibold))
                Text(L(serviceNoticeSupport == true ? "后台事件提醒已启用" : serviceNoticeSupport == false ? "后台提醒尚未完整启用" : "等待连接后台服务"))
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                WorkToggle(title: "自动检查新版本", detail: "启动后及每 6 小时检查一次；同一版本只主动提醒一次。",
                           compact: true, isOn: $updates.automatic)
                WorkToggle(title: "重要事件弹窗", detail: "新版、服务中断、租约到期和温度保护触发时提醒。",
                           compact: true, isOn: Binding(get: { notices.popupEnabled }, set: { notices.popupEnabled = $0 }))
                HStack {
                    Text(L(notifier.enabled ? "系统通知已开启" : "系统通知未开启")).font(.system(size: 12))
                    Spacer()
                    Button(L(notifier.enabled ? "通知设置" : "开启系统通知")) {
                        if notifier.enabled { notifier.showSettings() }
                        else { Task { await notifier.request() } }
                    }
                    Button(L("发送测试提醒")) {
                        notices.post(.test, title: "通知测试", body: "这是一条测试提醒，不会改变工作模式、电源或温度保护。")
                    }
                }
                if !notifier.message.isEmpty { Text(L(notifier.message)).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted) }
                Text(L("关闭窗口后仍可在菜单栏检查更新；完全退出 Orexin 后停止检查。系统通知展示受通知权限与专注模式控制。"))
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
            }.padding(18).terminalSurface()
            HStack {
                Text(LF("消息记录 · %d 条未读", notices.unreadCount)).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(L("全部标为已读")) { notices.acknowledgeAll() }.disabled(notices.unreadCount == 0)
            }
            if !notices.storageError.isEmpty { Text(L(notices.storageError)).foregroundStyle(TerminalStyle.warning) }
            if notices.entries.isEmpty {
                Text(L("暂无提醒。新版、服务状态和保护事件会保留在这里。"))
                    .font(.system(size: 12)).foregroundStyle(TerminalStyle.muted).padding(18)
            }
            ForEach(notices.entries) { notice in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if !notice.read { Circle().fill(TerminalStyle.accent).frame(width: 6, height: 6) }
                        Text(L(notice.title)).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(notice.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                    }
                    Text(L(notice.body)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let url = notice.releaseURL { Button(L("查看发布页")) { NSWorkspace.shared.open(url) } }
                        Spacer()
                        if !notice.read { Button(L("标为已读")) { notices.acknowledge(notice.id) } }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
            }
        }
    }
}
