// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI

struct QuickSessionControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sessions: SessionController
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack {
                Text(L("会话")).font(WorkType.controlLabel)
                Spacer()
                Button(L(model.verifiedWork ? "结束" : "开始默认会话")) { Task { await model.performShortcut(4) } }.workKeyboardFocus(radius: 0)
                    .disabled(model.busy || sessions.isStarting)
            }
            WorkToggle(title: "阻止显示器休眠", detail: model.otherTasksRequireDisplay ? "其他任务仍要求屏幕保持工作。" : "", compact: compact, isOn: Binding(get: { sessions.effectivePreventDisplaySleep }, set: { value in Task { await model.changeDisplayPrevention(value) } }))
                .disabled(model.otherTasksRequireDisplay && sessions.effectivePreventDisplaySleep)
            WorkToggle(title: "阻止闲时屏保", detail: model.otherTasksRequireScreenSaverPrevention ? "其他任务仍要求暂停屏保。" : "", compact: compact, isOn: Binding(get: { sessions.effectivePreventScreenSaver }, set: { value in Task { await model.changeScreenSaverPrevention(value) } }))
                .disabled(model.otherTasksRequireScreenSaverPrevention && sessions.effectivePreventScreenSaver)
            if sessions.deadline != nil {
                HStack {
                    Text(L("延长会话")).font(compact ? WorkType.compactLabel : WorkType.controlLabel)
                    Spacer()
                    Button(L("+15 分钟")) { _ = sessions.extend(minutes: 15); model.onUpdate?() }.workKeyboardFocus(radius: 0).disabled(!model.verifiedWork)
                }
            }
        }.font(WorkType.body).buttonStyle(WorkButtonStyle()).focusEffectDisabled().disabled(model.busy)
    }
}
