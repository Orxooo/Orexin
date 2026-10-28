// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI

struct IdlePolicyView: View {
    @ObservedObject var controller: IdlePolicyController
    var immediateAuthentication = true
    var body: some View {
        WorkCard(title: "闲置后的屏幕", subtitle: "工作继续运行；屏保的密码要求跟随系统设置。") {
            WorkToggle(title: "闲置后熄屏锁定", detail: "显示器保活期间暂停；允许熄屏且 macOS 立即要求密码时执行。", isOn: $controller.lockEnabled).disabled(!immediateAuthentication)
            HStack { Text(L("锁定等待")).font(WorkType.controlLabel); Spacer(); TerminalStepper(value: $controller.lockMinutes, in: 1...240) { Text(LF("%d 分钟", Int(controller.lockMinutes))).monospacedDigit() }.fixedSize().accessibilityLabel("闲置锁定等待时间") }
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            WorkToggle(title: "闲置后启动系统屏保", detail: "启用“防止闲时屏保”时此项暂停。", isOn: $controller.screenSaverEnabled)
            HStack { Text(L("屏保等待")).font(WorkType.controlLabel); Spacer(); TerminalStepper(value: $controller.screenSaverMinutes, in: 1...240) { Text(LF("%d 分钟", Int(controller.screenSaverMinutes))).monospacedDigit() }.fixedSize().accessibilityLabel("屏保等待时间") }
            WorkNote(text: controller.status)
        }
    }
}
