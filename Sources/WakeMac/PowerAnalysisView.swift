// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import SwiftUI
import WakeMacCore

struct PowerAnalysisView: View {
    @ObservedObject var observer: PowerAnalysisObserver
    @State private var expanded = false
    @State private var source = Source.all

    private enum Source: String, CaseIterable {
        case all = "全部来源", orexin = "Orexin", external = "其他进程"
    }
    private var rows: [PowerAssertionRecord] {
        (observer.snapshot?.assertions ?? []).filter {
            source == .all || (source == .orexin ? $0.isOrexin : !$0.isOrexin)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TerminalIcon(name: "bolt", size: 18).foregroundStyle(TerminalStyle.accent)
                Text(L("电源分析")).font(.system(size: 15, weight: .semibold))
                Text("POWER OBSERVER").font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
                Spacer(minLength: 8)
                Button {
                    Task { await observer.refresh(force: true) }
                } label: {
                    TerminalLabel(observer.refreshing ? "读取中…" : "刷新断言", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0).disabled(observer.refreshing)
            }
            if let snapshot = observer.snapshot {
                HStack(spacing: 0) {
                    metric("Orexin", value: snapshot.processesReadable ? String(snapshot.ownCount) : "—", detail: "本进程持有的断言")
                    Rectangle().fill(WorkStyle.line).frame(width: 1)
                    metric("其他进程", value: snapshot.processesReadable ? String(snapshot.externalCount) : "—", detail: "系统返回的外部来源")
                    Rectangle().fill(WorkStyle.line).frame(width: 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("最近观察")).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                        Text(snapshot.sampledAt, style: .time).font(TerminalStyle.mono(15))
                        Text(L("应用运行时，每 30 秒采样")).font(.system(size: 10)).foregroundStyle(WorkStyle.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
                }.fixedSize(horizontal: false, vertical: true).padding(14).background(TerminalStyle.recess)

                Text(L(observationSummary(snapshot))).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(snapshot.processesReadable && snapshot.statusReadable ? WorkStyle.ink : TerminalStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("断言表示进程正在请求某种电源行为，不证明 Mac 实际未休眠。系统唤醒原因未由此接口提供；未归因的原因显示为未知。"))
                    .font(WorkType.caption).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(L("断言来源"), selection: $source) {
                            ForEach(Source.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                        }.pickerStyle(.segmented).frame(maxWidth: 340)
                        if rows.isEmpty {
                            Text(L(snapshot.processesReadable ? "当前没有匹配的活动断言。" : "系统未返回进程列表，来源未知。"))
                                .font(WorkType.caption).foregroundStyle(WorkStyle.muted).padding(.vertical, 8)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(rows) { row in
                                        assertionRow(row)
                                        Rectangle().fill(WorkStyle.line.opacity(0.5)).frame(height: 1)
                                    }
                                }
                            }.frame(maxHeight: 256)
                        }
                        if snapshot.statusReadable {
                            Text(L("系统汇总：") + (snapshot.activeSystemTypes.isEmpty ? L("未报告活动断言") : snapshot.activeSystemTypes.map { L($0.title) }.joined(separator: " · ")))
                                .font(WorkType.caption).foregroundStyle(WorkStyle.muted).textSelection(.enabled)
                        }
                        if !snapshot.unattributedTypes.isEmpty {
                            Text(L("来源未知：") + snapshot.unattributedTypes.map { L($0.title) }.joined(separator: " · "))
                                .font(WorkType.caption).foregroundStyle(TerminalStyle.warning)
                        }
                        if snapshot.incomplete {
                            Text(L("部分记录不可解析或超过本次采样上限，数量可能不完整。"))
                                .font(WorkType.caption).foregroundStyle(TerminalStyle.warning)
                        }
                        Text(L("仅读取 PID、进程名称和断言类型；不读取命令参数、断言描述或系统私有日志。"))
                            .font(.system(size: 10)).foregroundStyle(WorkStyle.muted)
                    }.padding(.top, 12)
                } label: {
                    Text(L("查看系统断言与来源")).font(.system(size: 12, weight: .medium))
                }
            } else {
                Text(L("尚未读取系统电源断言。来源与原因未知。"))
                    .font(WorkType.body).foregroundStyle(WorkStyle.muted)
            }
        }.padding(16).background(WorkStyle.surface).overlay(Rectangle().strokeBorder(WorkStyle.line))
            .task { await observer.refresh() }
    }

    private func metric(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L(title)).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
            Text(value).font(TerminalStyle.mono(22)).foregroundStyle(title == "Orexin" ? TerminalStyle.accent : WorkStyle.ink)
            Text(L(detail)).font(.system(size: 10)).foregroundStyle(WorkStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
    }
    private func assertionRow(_ row: PowerAssertionRecord) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle().fill(row.isOrexin ? TerminalStyle.accent : TerminalStyle.steel).frame(width: 3, height: 25)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.applicationName ?? L("未知应用")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("PID \(row.processID) · " + L(row.isOrexin ? "Orexin 本进程" : "其他进程"))
                    .font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(L(row.kind.title)).font(.system(size: 11)).foregroundStyle(WorkStyle.ink)
                Text(row.kind.rawValue).font(TerminalStyle.mono(8)).foregroundStyle(WorkStyle.muted)
            }.frame(maxWidth: .infinity, alignment: .trailing)
            Text("×\(row.count)").font(TerminalStyle.mono(11)).frame(width: 32, alignment: .trailing)
        }.textSelection(.enabled).padding(.vertical, 10)
    }
    private func observationSummary(_ snapshot: PowerAssertionSnapshot) -> String {
        guard snapshot.processesReadable || snapshot.statusReadable else { return "系统电源信息暂不可用；当前来源未知。" }
        guard snapshot.processesReadable && snapshot.statusReadable else { return "系统仅返回部分信息；无法完整判断当前保活来源。" }
        if snapshot.activeSystemTypes.contains(where: \.preventsIdleSleep) || snapshot.assertions.contains(where: { $0.kind.preventsIdleSleep }) {
            return "观察到阻止系统闲置休眠的请求。展开查看 Orexin 与其他进程的来源。"
        }
        if snapshot.activeSystemTypes.contains(where: \.keepsDisplayAwake) || snapshot.assertions.contains(where: { $0.kind.keepsDisplayAwake }) {
            return "观察到保持显示器唤醒的请求。其他电源行为仍由 macOS 决定。"
        }
        if snapshot.incomplete || snapshot.activeSystemTypes.contains(.other) || snapshot.assertions.contains(where: { $0.kind == .other }) {
            return "部分断言类型或来源未知；无法完整判断当前保活请求。"
        }
        return "未观察到阻止闲置休眠的断言；这不保证 Mac 会立即休眠。"
    }
}

extension PowerAssertionKind {
    var title: String {
        switch self {
        case .idleSystem: "防止系统闲置休眠"
        case .idleDisplay: "防止显示器闲置休眠"
        case .system: "系统休眠限制"
        case .disk: "保持磁盘活动"
        case .network: "网络客户端活动"
        case .userActivity: "用户活动"
        case .background: "后台任务"
        case .media: "外接媒体活动"
        case .display: "显示器活动"
        case .other: "其他系统断言"
        }
    }
}
