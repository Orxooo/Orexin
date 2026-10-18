// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI
import WakeMacCore

extension RequestState {
    var displayTitle: String {
        switch self {
        case .active: "保活中"
        case .succeeded: "已成功"
        case .failed: "已失败"
        case .cancelled: "已释放"
        case .lost: "已失联"
        case .expired: "已到期"
        case .overridden: "已被停止"
        case .rejected: "未获准"
        }
    }
}

struct WorkRequestsView: View {
    @ObservedObject var model: AppModel
    var onShowLog: (URL) -> Void
    var onRunCommand: () -> Void
    var onConnect: () -> Void
    @State private var showHistory = false
    private let actionWidth: CGFloat = 128
    private let actionSpacing: CGFloat = 8
    private var visible: [WorkRequestRecord] {
        let records = model.workRequests.records.reversed()
        return Array(records.filter { showHistory || $0.state == .active || model.runningCommandIDs.contains($0.id) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    TerminalLabel("并行工作请求", systemImage: "doc.text").font(WorkType.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(LF("%d 项保活请求 · %d 条命令运行中", model.workRequests.active.count, model.runningCommandIDs.count))
                        .font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                }
                Spacer(minLength: 12)
                actionButton("全部停止保活", role: .destructive) { Task { await model.choose(.normal) } }
                    .disabled(model.busy || !model.verifiedWork)
            }
            Text(L("每项任务独立释放保活；释放不会终止命令。全部停止同时结束会话与规则保活。"))
                .font(WorkType.caption).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            WorkToggle(title: "显示最近结束的请求", compact: true, isOn: $showHistory)
                .padding(12).background(TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(WorkStyle.line.opacity(0.3)))
            if visible.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L(showHistory ? "暂无工作请求" : "当前没有活跃任务")).font(WorkType.controlLabel.weight(.semibold))
                    Text(L("运行一条命令，或让外部工具通过 CLI 登记任务。"))
                        .font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                    HStack(spacing: 10) {
                        Button(L("运行命令"), action: onRunCommand).buttonStyle(TerminalButtonStyle(prominent: true))
                        Button(L("外部接入"), action: onConnect).buttonStyle(WorkButtonStyle())
                    }.workKeyboardFocus(radius: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(TerminalStyle.recess)
            }
            LazyVStack(spacing: 10) {
                ForEach(visible) { request in requestRow(request) }
            }
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            ExecutionPlansView(model: model, onShowLog: onShowLog)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
    }
    private func requestRow(_ request: WorkRequestRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(request.spec.title).font(WorkType.controlLabel.weight(.semibold)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L(request.state.displayTitle)).font(TerminalStyle.mono(10))
                            .foregroundStyle(stateColor(request)).fixedSize()
                    }
                    Text("\(L(request.spec.mode == .background ? "后台工作" : "桌面工作")) · \(L(screenTitle(request.spec.screen)))")
                        .font(WorkType.caption).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(request.spec.source.uppercased()).font(TerminalStyle.mono(9))
                            .lineLimit(1).truncationMode(.middle).help(request.spec.source)
                        Text("//").font(TerminalStyle.mono(9)).accessibilityHidden(true)
                        requestID(request)
                    }.foregroundStyle(WorkStyle.muted)
                    if request.state == .active {
                        HStack(alignment: .top, spacing: 5) {
                            Text("↳").font(TerminalStyle.mono(10)).foregroundStyle(WorkStyle.muted)
                            Text(L(model.requestSatisfied(request.spec) ? "保活需求已核验" : "需求暂未满足；请检查电源或屏幕状态"))
                                .font(WorkType.caption).foregroundStyle(model.requestSatisfied(request.spec) ? TerminalStyle.signal : TerminalStyle.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: actionSpacing) {
                    if let log = model.commandLogs[request.id] {
                        actionButton("查看日志") { onShowLog(log) }
                    } else { emptyActionSlot }
                    if request.state == .active {
                        actionButton("释放此请求") { Task { await model.releaseWork(id: request.id) } }
                            .disabled(model.busy)
                    } else { emptyActionSlot }
                }.frame(width: actionWidth * 2 + actionSpacing, alignment: .trailing)
            }
            if let code = request.exitCode {
                Text("EXIT \(code)").font(TerminalStyle.mono(9)).foregroundStyle(stateColor(request))
            }
            if let expires = [request.leaseExpiresAt, request.spec.deadline].compactMap({ $0 }).min(), request.state == .active {
                Text(L("到期时间") + " · " + expires.formatted(date: .abbreviated, time: .shortened))
                    .font(WorkType.compactCaption).foregroundStyle(WorkStyle.muted)
            }
            if model.runningCommandIDs.contains(request.id) && request.state != .active {
                Text(L("保活已释放；命令仍在运行")).font(WorkType.caption).foregroundStyle(TerminalStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = request.reason {
                Text(reason).font(WorkType.compactCaption).foregroundStyle(WorkStyle.muted).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).background(TerminalStyle.recess)
            .overlay(Rectangle().strokeBorder(WorkStyle.line.opacity(0.3)))
    }
    private func actionButton(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            // WorkButtonStyle adds 15 pt on each side and a 36 pt minimum height.
            Text(L(title)).lineLimit(2).minimumScaleFactor(0.75)
                .multilineTextAlignment(.center).frame(width: actionWidth - 30, height: 30)
        }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
    }
    private var emptyActionSlot: some View {
        Color.clear.frame(width: actionWidth, height: 36).allowsHitTesting(false).accessibilityHidden(true)
    }
    private func requestID(_ request: WorkRequestRecord) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            _ = NSPasteboard.general.setString(request.id.uuidString, forType: .string)
        } label: {
            HStack(spacing: 5) {
                Text(String(request.id.uuidString.prefix(8))).font(TerminalStyle.mono(9))
                TerminalIcon(name: "doc.on.doc", size: 10)
            }
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).fixedSize()
            .help(L("复制完整请求 ID") + "\n" + request.id.uuidString).accessibilityLabel(L("复制完整请求 ID"))
    }
    private func stateColor(_ request: WorkRequestRecord) -> Color {
        switch request.state {
        case .active: model.requestSatisfied(request.spec) ? TerminalStyle.signal : TerminalStyle.warning
        case .succeeded: TerminalStyle.signal
        case .failed, .lost, .rejected: TerminalStyle.warning
        default: TerminalStyle.muted
        }
    }
    private func screenTitle(_ screen: RequestScreen) -> String {
        switch screen { case .idle: "允许屏幕休眠"; case .dim: "屏幕调暗"; case .awake: "屏幕常亮" }
    }
}
