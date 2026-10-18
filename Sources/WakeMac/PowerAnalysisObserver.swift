// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import Combine
import Darwin
import IOKit.pwr_mgt
import WakeMacCore

enum PowerAssertionSource {
    static func read() -> PowerAssertionSnapshot {
        var processes: Unmanaged<CFDictionary>?
        var status: Unmanaged<CFDictionary>?
        let processResult = IOPMCopyAssertionsByProcess(&processes)
        let statusResult = IOPMCopyAssertionsStatus(&status)
        let processValues = processes?.takeRetainedValue() as? [AnyHashable: Any]
        let statusValues = status?.takeRetainedValue() as? [String: Any]
        return PowerAssertionParser.parse(byProcess: processResult == kIOReturnSuccess ? processValues : nil,
            systemStatus: statusResult == kIOReturnSuccess ? statusValues : nil, ownPID: getpid(),
            applicationName: { pid in
                // proc_name returns the executable name only; never request arguments or command output.
                var bytes = [CChar](repeating: 0, count: 256)
                guard proc_name(pid, &bytes, UInt32(bytes.count)) > 0 else { return nil }
                return String(cString: bytes)
            })
    }
}

@MainActor final class PowerAnalysisObserver: ObservableObject {
    static let sampleInterval: TimeInterval = 30
    @Published private(set) var snapshot: PowerAssertionSnapshot?
    @Published private(set) var refreshing = false
    var onChange: ((String) -> Void)?
    private let read: @Sendable () -> PowerAssertionSnapshot
    private var tracker = PowerAssertionChangeTracker()
    private var lastAttempt: Date?

    init(read: @escaping @Sendable () -> PowerAssertionSnapshot = { PowerAssertionSource.read() }) { self.read = read }

    /// Call from the existing app tick. No additional timer or unbounded background log stream.
    func refresh(force: Bool = false, now: Date = Date()) async {
        guard !refreshing, force || lastAttempt.map({ now.timeIntervalSince($0) >= Self.sampleInterval }) ?? true else { return }
        refreshing = true; lastAttempt = now
        let read = self.read
        let updated = await Task.detached(priority: .utility) { read() }.value
        snapshot = updated; refreshing = false
        if tracker.accept(updated) { onChange?(Self.historyText(updated)) }
    }

    static func historyText(_ snapshot: PowerAssertionSnapshot) -> String {
        guard snapshot.processesReadable || snapshot.statusReadable else {
            return "电源断言暂无法读取；保持唤醒或休眠的原因未知。"
        }
        let status = snapshot.processesReadable
            ? "电源断言变化：Orexin \(snapshot.ownCount) 项，其他进程 \(snapshot.externalCount) 项。"
            : "电源断言变化：进程列表无法读取，Orexin 与外部来源数量未知。"
        let sources = snapshot.assertions.prefix(8).map { row in
            "\(row.applicationName ?? "未知应用") · PID \(row.processID) · \(row.kind.rawValue) ×\(row.count)"
        }.joined(separator: "；")
        let extra = snapshot.assertions.count > 8 ? "；另有 \(snapshot.assertions.count - 8) 组来源未写入此条记录" : ""
        let unknown = !snapshot.processesReadable || !snapshot.statusReadable || snapshot.incomplete || !snapshot.unattributedTypes.isEmpty
        return status + sources + extra + (unknown ? "；部分系统状态或来源未知。" : "")
    }
}

enum HistoryEventKind: String, Codable, CaseIterable {
    case app, request, rule, mode, sleepWake, display, lid, powerSource, powerAssertion, protection

    /// For legacy call sites this labels the event only; it never infers what caused sleep or wake.
    static func inferred(from text: String) -> Self {
        if text.contains("电源断言") { return .powerAssertion }
        if text.contains("温度保护") || text.contains("低电量") { return .protection }
        if text.contains("工作请求") || text.contains("命令任务") || text.contains("任务成功") { return .request }
        if text.contains("自动触发") || text.contains("自动规则") { return .rule }
        if text.contains("系统即将休眠") || text.contains("系统已唤醒") || text.contains("休眠请求") { return .sleepWake }
        if text.contains("检测到合盖") || text.contains("检测到开盖") { return .lid }
        if text.contains("显示器") || text.contains("屏幕") { return .display }
        if text.contains("电源") || text.contains("电量") { return .powerSource }
        if text.contains("模式") || text.contains("切换") { return .mode }
        return .app
    }
}

struct HistoryContext: Codable, Equatable {
    var kind: HistoryEventKind
    var requestIDs: [UUID] = []
    var ruleID: UUID? = nil
    var mode: String? = nil

    var searchable: String {
        ([kind.rawValue, mode ?? "", ruleID?.uuidString ?? ""] + requestIDs.map(\.uuidString)).joined(separator: " ")
    }
}
