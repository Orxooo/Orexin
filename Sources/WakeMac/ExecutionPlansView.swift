// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WakeMacCore

private func planStateTitle(_ state: String) -> String {
    L(["pending": "等待执行", "running": "运行中", "cancelling": "正在取消", "succeeded": "已成功",
       "failed": "已失败", "cancelled": "已取消", "skipped": "已跳过", "lost": "已失联"][state] ?? state)
}

struct ExecutionPlansView: View {
    @ObservedObject var model: AppModel
    var onShowLog: (URL) -> Void
    @State private var draft: ExecutionPlan?
    @State private var selected: PlanRun?
    @State private var message = ""
    @State private var submitting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TerminalLabel("任务组与执行计划", systemImage: "doc.text").font(WorkType.sectionTitle)
                Spacer()
                Button(L("导入计划"), action: importPlan).buttonStyle(WorkButtonStyle())
            }
            Text(L("串行或并行运行一组命令，按依赖条件推进。退出界面后，后台服务继续管理。"))
                .font(WorkType.caption).foregroundStyle(WorkStyle.muted)
            if !model.requestServiceMessage.isEmpty { Text(model.requestServiceMessage).font(WorkType.compactCaption).textSelection(.enabled) }
            if let draft {
                VStack(alignment: .leading, spacing: 10) {
                    Text(draft.title).font(WorkType.controlLabel.weight(.semibold))
                    Text(LF("%d 条命令 · 最多 %d 条同时运行", draft.tasks.count, draft.maxConcurrent)).font(WorkType.caption)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(draft.tasks) { task in
                                Text("\(task.id) · \(task.condition.rawValue) [\(task.dependencies.joined(separator: ", "))]\n\(task.directory)\n\(task.command)")
                                    .font(TerminalStyle.mono(11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: 240)
                    Text(L("运行会执行以上命令。取消计划只跳过尚未启动的命令；已启动的命令会继续。"))
                        .font(WorkType.caption).foregroundStyle(TerminalStyle.warning)
                    HStack {
                        Button(L("运行计划")) { Task { await submit(draft) } }.buttonStyle(TerminalButtonStyle(prominent: true)).disabled(submitting)
                        Button(L("取消")) { self.draft = nil }.buttonStyle(WorkButtonStyle()).disabled(submitting)
                    }
                }.padding(12).background(TerminalStyle.recess)
            }
            if !message.isEmpty { Text(message).font(WorkType.caption).foregroundStyle(TerminalStyle.warning).textSelection(.enabled) }
            ForEach(model.servicePlans) { plan in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(plan.title).font(WorkType.controlLabel)
                        Text("\(planStateTitle(plan.state.rawValue)) · \(plan.finished)/\(plan.total)").font(TerminalStyle.mono(10)).foregroundStyle(WorkStyle.muted)
                    }
                    Spacer()
                    Button(L("查看详情")) { Task { await inspect(plan.id) } }.buttonStyle(WorkButtonStyle())
                    if !plan.state.terminal {
                        Button(L("取消计划")) { Task { await cancel(plan.id) } }.buttonStyle(WorkButtonStyle())
                    }
                }.padding(12).background(TerminalStyle.recess)
            }
            if let selected {
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Text(selected.plan.title).font(WorkType.controlLabel.weight(.semibold)); Spacer(); Button(L("关闭")) { self.selected = nil }.buttonStyle(WorkButtonStyle()) }
                    ForEach(selected.tasks) { task in
                        HStack {
                            Text("\(task.id) · \(planStateTitle(task.state.rawValue))" + (task.exitCode.map { " · EXIT \($0)" } ?? "")).font(TerminalStyle.mono(11))
                            Spacer()
                            if task.startedAt != nil {
                                Button(L("查看日志")) { onShowLog(model.planLogURL(runID: selected.id, taskID: task.id)) }.buttonStyle(WorkButtonStyle())
                            }
                        }
                        if let detail = task.detail { Text(detail).font(WorkType.compactCaption).foregroundStyle(WorkStyle.muted) }
                    }
                }.padding(12).background(TerminalStyle.recess)
            }
        }.onChange(of: model.servicePlans.map { "\($0.id):\($0.state):\($0.finished):\($0.running)" }) { _, _ in
            if let id = selected?.id { Task { await inspect(id) } }
        }
    }
    private func importPlan() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            let data = try file.read(upToCount: 32 * 1024 + 1) ?? Data()
            guard data.count <= 32 * 1024 else { throw ModeError("Execution plan exceeds 32 KiB") }
            draft = try ControlCoding.decode(ExecutionPlan.self, from: data).validated(); message = ""
        } catch { message = error.localizedDescription }
    }
    private func submit(_ plan: ExecutionPlan) async {
        submitting = true; defer { submitting = false }
        do {
            var request = ControlMessage("plan-run", id: UUID()); request.document = try ControlCoding.encode(plan)
            let reply = try await model.serviceCall(request); model.adoptServiceReply(reply)
            if let data = reply.document { selected = try ControlCoding.decode(PlanRun.self, from: data) }
            draft = nil; message = ""
        } catch { message = error.localizedDescription }
    }
    private func inspect(_ id: UUID) async {
        do { if let data = try await model.serviceCall(.init("plan-status", id: id)).document { selected = try ControlCoding.decode(PlanRun.self, from: data) } }
        catch { message = error.localizedDescription }
    }
    private func cancel(_ id: UUID) async {
        do { model.adoptServiceReply(try await model.serviceCall(.init("plan-cancel", id: id))); await inspect(id) }
        catch { message = error.localizedDescription }
    }
}
