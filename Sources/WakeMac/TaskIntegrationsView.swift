// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

struct TaskIntegrationsView: View {
    @ObservedObject var model: AppModel
    let availableWidth: CGFloat
    @State private var cliCopyMessage = ""
    @State private var scriptCopyMessage = ""
    private let sampleScript = "tell application \"Orexin\"\n    start session mode \"desktop\" for minutes 30\n    session status\n    -- end session\nend tell"
    private var cliExample: String {
        let bundle = Bundle.main.bundleURL
        let appPath = bundle.pathExtension == "app" ? bundle.path : "/Applications/Orexin.app"
        let path = (appPath + "/Contents/Helpers/orexin").replacingOccurrences(of: "'", with: "'\\''")
        return "orexin='\(path)'\n\"$orexin\" run --title Build -- make\n\"$orexin\" list --json"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                TerminalLabel("本地接入状态", systemImage: "terminal").font(.system(size: 13, weight: .semibold))
                Text(model.requestServiceMessage.isEmpty ? L("本地接口尚未就绪；请确认 Orexin 正在运行。") : model.requestServiceMessage)
                    .font(TerminalStyle.mono(10)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(TerminalStyle.muted)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
            if availableWidth > 900 {
                // Each pair shares its natural row height, including wrapped translations
                // and expanded details. The card backgrounds span the entire grid.
                Grid(alignment: .topLeading, horizontalSpacing: 48, verticalSpacing: 14) {
                    GridRow { cliHeader; scriptHeader }
                    GridRow { cliDescription; scriptDescription }
                    GridRow { codeExample(cliExample); codeExample(sampleScript) }
                    GridRow { cliCopy; scriptCopy }
                    GridRow { cliNote; scriptNote }
                    GridRow { cliDetails; scriptDetails }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        HStack(spacing: 16) {
                            Color.clear.frame(maxWidth: .infinity).terminalSurface()
                            Color.clear.frame(maxWidth: .infinity).terminalSurface()
                        }
                    }
            } else { cli; scripting }
        }
    }
    private var cli: some View {
        VStack(alignment: .leading, spacing: 14) {
            cliHeader
            cliDescription
            codeExample(cliExample)
            cliCopy
            cliNote
            cliDetails
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
    }
    private var scripting: some View {
        VStack(alignment: .leading, spacing: 14) {
            scriptHeader
            scriptDescription
            codeExample(sampleScript)
            scriptCopy
            scriptNote
            scriptDetails
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
    }
    private var cliHeader: some View {
        HStack {
            TerminalLabel("CLI 任务接入", systemImage: "terminal").font(WorkType.sectionTitle)
            Spacer(minLength: 0)
            Text("LOCAL CLI").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var cliDescription: some View {
        Text(L("适合构建、备份与脚本任务。每个请求独立保活，完成后释放自己的请求。"))
            .font(WorkType.caption).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
    }
    private func codeExample(_ text: String) -> some View {
        ScrollView(.horizontal) {
            Text(text).font(TerminalStyle.mono(10)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                .padding(12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TerminalStyle.recess).gridCellUnsizedAxes(.horizontal)
    }
    private var cliCopy: some View {
        HStack {
            if !cliCopyMessage.isEmpty { Text(L(cliCopyMessage)).font(WorkType.compactCaption).foregroundStyle(TerminalStyle.signal) }
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                cliCopyMessage = NSPasteboard.general.setString(cliExample, forType: .string) ? "示例已复制" : "复制失败，请选中文本复制"
            } label: { TerminalLabel("复制 CLI 示例", systemImage: "doc.on.doc").frame(width: 130) }.workKeyboardFocus(radius: 0)
        }
    }
    private var cliNote: some View {
        WorkNote(text: "示例使用应用内附带的 CLI，无需安装到 PATH。默认恢复原有状态；需要成功后休眠时添加 --after sleep。")
    }
    private var cliDetails: some View {
        DisclosureGroup(L("外部任务生命周期")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("register → heartbeat → complete / fail\nrelease · status · list · stop-all")
                    .font(TerminalStyle.mono(10)).textSelection(.enabled)
                Text(L("register 返回 ID:TOKEN；任务执行期间用 heartbeat 续约，结束后报告实际退出码。release 仅释放保活，不终止进程。"))
                    .font(WorkType.caption).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
                Text(L("使用 \"$orexin\" help 查看参数；所有命令支持 --json。"))
                    .font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
            }.padding(.top, 8)
        }.font(WorkType.caption)
    }
    private var scriptHeader: some View {
        HStack {
            TerminalLabel("AppleScript 外部总线", systemImage: "terminal")
                .font(WorkType.sectionTitle)
            Spacer(minLength: 0)
            Text("AUTOMATION API").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var scriptDescription: some View {
        Text(L("通过 AppleScript 控制工作会话与电源策略。"))
            .font(WorkType.caption).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
    }
    private var scriptCopy: some View {
        HStack {
            if !scriptCopyMessage.isEmpty {
                Text(L(scriptCopyMessage)).font(WorkType.compactCaption).foregroundStyle(TerminalStyle.signal)
            }
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                scriptCopyMessage = NSPasteboard.general.setString(sampleScript, forType: .string)
                    ? "脚本已复制" : "复制失败，请选中文本复制"
            } label: { TerminalLabel("复制脚本", systemImage: "doc.on.doc").frame(width: 130) }
                .workKeyboardFocus(radius: 0)
        }
    }
    private var scriptNote: some View {
        WorkNote(text: "支持会话启停、延长、剩余时间、显示器与屏保、合盖、触发器和磁盘保活控制。后台工作需要已批准的合盖服务；所有命令采用偏好设置中的锁屏策略。")
    }
    private var scriptDetails: some View {
        DisclosureGroup("更多脚本命令") {
            Text("session is active\nsession time remaining\nextend session for minutes 15\nprevent display sleep\nallow display sleep\nprevent screen saver\nallow screen saver\nenable closed display mode\ndisable closed display mode\ntriggers are enabled\nenable triggers\ndisable triggers\nenable drive alive\ndisable drive alive")
                .font(TerminalStyle.mono(10)).textSelection(.enabled).padding(.top, 8)
        }.font(WorkType.caption)
    }
}
