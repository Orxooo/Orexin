// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation
import Combine
import WakeMacCore
import Darwin

enum TriggerKind: String, Codable, CaseIterable, Identifiable {
    case externalDisplay, displayMirroring, usbDevice, bluetoothDevice, appRunning, appFrontmost, processRunning, weeklySchedule
    case batteryCharging, batteryAbove, acConnected, acDisconnected, ipAddress, wifiSSID, ciscoVPN, dnsServer
    case headphones, audioOutput, mountedVolume, cpuAbove, idleAbove
    var id: String { rawValue }
    var title: String {
        switch self {
        case .externalDisplay: return L("连接外接显示器")
        case .displayMirroring: return L("显示器镜像")
        case .usbDevice: return L("连接 USB 设备")
        case .bluetoothDevice: return L("连接蓝牙设备")
        case .appRunning: return L("指定应用正在运行")
        case .appFrontmost: return L("指定应用位于前台")
        case .processRunning: return L("指定进程正在运行")
        case .weeklySchedule: return L("每周指定时间")
        case .batteryCharging: return L("电池正在充电")
        case .batteryAbove: return L("电量高于百分比")
        case .acConnected: return L("已连接电源")
        case .acDisconnected: return L("已断开电源")
        case .ipAddress: return L("拥有指定 IP 地址")
        case .wifiSSID: return L("连接指定 Wi-Fi")
        case .ciscoVPN: return L("系统可检测的 Cisco VPN 已连接")
        case .dnsServer: return L("使用指定 DNS 服务器")
        case .headphones: return L("使用耳机输出")
        case .audioOutput: return L("使用指定音频输出")
        case .mountedVolume: return L("已挂载指定磁盘")
        case .cpuAbove: return L("CPU 使用率高于百分比")
        case .idleAbove: return L("空闲时间超过秒数")
        }
    }
    var requiresValue: Bool {
        [.usbDevice, .bluetoothDevice, .appRunning, .appFrontmost, .processRunning, .batteryAbove, .ipAddress, .wifiSSID, .dnsServer, .audioOutput, .mountedVolume, .cpuAbove, .idleAbove].contains(self)
    }
    var hint: String {
        switch self {
        case .appRunning, .appFrontmost: return L("应用 Bundle ID，例如 com.apple.Safari")
        case .processRunning: return L("进程的完整可执行文件路径；匹配当前用户的所有运行实例")
        case .weeklySchedule: return L("按 Mac 当前时区的当地星期和时间匹配")
        case .usbDevice: return L("设备名称或 registry ID（见当前观测）")
        case .bluetoothDevice: return L("设备名称或蓝牙地址")
        case .batteryAbove, .cpuAbove: return L("0–100；必须严格高于此值")
        case .idleAbove: return L("1–86400 秒；必须严格超过此值")
        case .ipAddress, .dnsServer: return L("完整 IPv4 或 IPv6 地址")
        case .wifiSSID: return L("完整 Wi-Fi 网络名称（区分大小写）")
        case .audioOutput: return L("设备名称或 UID（见当前观测）")
        case .mountedVolume: return L("磁盘名称或完整挂载路径")
        default: return L("无需额外参数")
        }
    }
}

/// Weekdays use Gregorian numbering: Sunday 1 through Saturday 7.
/// Wall-clock intervals repeat in local time, including both occurrences of a
/// repeated DST hour. Nonexistent spring-forward minutes are never sampled.
struct TriggerWeeklySchedule: Codable, Equatable {
    var weekdays: Set<Int> = Set(2...6)
    var startMinute = 9 * 60
    var endMinute = 17 * 60
    var allDay = false
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
    var validationError: String? {
        guard !weekdays.isEmpty, weekdays.allSatisfy({ (1...7).contains($0) }) else { return "请至少选择一个有效的星期。" }
        guard (0..<1440).contains(startMinute), (0..<1440).contains(endMinute) else { return "时间必须在 00:00 至 23:59 之间。" }
        if !allDay && startMinute == endMinute { return "开始和结束时间不能相同；如需全天，请启用全天。" }
        return nil
    }
    func matches(at date: Date, calendar: Calendar = Self.localCalendar) -> Bool? {
        guard validationError == nil else { return nil }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let day = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return nil }
        if allDay { return weekdays.contains(day) }
        let clock = hour * 60 + minute
        if startMinute < endMinute { return weekdays.contains(day) && clock >= startMinute && clock < endMinute }
        // An overnight interval belongs to its starting weekday.
        if clock >= startMinute { return weekdays.contains(day) }
        if clock < endMinute { return weekdays.contains(day == 1 ? 7 : day - 1) }
        return false
    }
    private enum CodingKeys: String, CodingKey { case weekdays, startMinute, endMinute, allDay }
    /// Set iteration order is not canonical. Stable arrays are required for
    /// portable-config preview tokens and reproducible versioned exports.
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(weekdays.sorted(), forKey: .weekdays)
        try fields.encode(startMinute, forKey: .startMinute)
        try fields.encode(endMinute, forKey: .endMinute)
        try fields.encode(allDay, forKey: .allDay)
    }
    var summary: String {
        let labels = [1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"]
        let days = [2, 3, 4, 5, 6, 7, 1].filter { weekdays.contains($0) }.map { L(labels[$0]!) }.joined(separator: ", ")
        if allDay { return days + " · " + L("全天") }
        let start = String(format: "%02d:%02d", startMinute / 60, startMinute % 60)
        let end = String(format: "%02d:%02d", endMinute / 60, endMinute % 60)
        return days + " · " + start + "–" + end + (startMinute > endMinute ? " " + L("（次日）") : "")
    }
}

struct TriggerCondition: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TriggerKind = .externalDisplay
    var value = ""
    var schedule: TriggerWeeklySchedule? = nil
    var ignoreBuiltInDisplay = true
    enum CodingKeys: String, CodingKey { case id, kind, value, schedule, ignoreBuiltInDisplay }
    var validationError: String? {
        if kind == .weeklySchedule { return schedule?.validationError ?? (schedule == nil ? "请设置每周时间条件。" : nil) }
        guard kind.requiresValue else { return nil }
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return LF("请填写%@。", L(kind.hint)) }
        switch kind {
        case .batteryAbove, .cpuAbove:
            guard let number = Double(input), number.isFinite, number >= 0, number < 100 else { return "百分比必须在 0（含）至 100（不含）之间。" }
        case .idleAbove:
            guard let number = Double(input), number.isFinite, number >= 1, number <= 86400 else { return "空闲秒数必须在 1–86400 之间。" }
        case .ipAddress, .dnsServer:
            guard Self.isIPAddress(input) else { return "请输入完整的 IPv4 或 IPv6 地址。" }
        case .processRunning:
            guard input.hasPrefix("/"), input != "/", !input.contains("\0"), URL(fileURLWithPath: input).lastPathComponent != "" else { return "请选择正在运行的进程，或输入完整的可执行文件路径。" }
        case .appRunning, .appFrontmost:
            guard input.contains("."), !input.contains(where: { $0.isWhitespace }), !input.contains("/") else { return "请使用应用的 Bundle ID，不能使用进程名或路径。" }
        default: break
        }
        return nil
    }
    static func isIPAddress(_ input: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return input.withCString { inet_pton(AF_INET, $0, &v4) == 1 || inet_pton(AF_INET6, $0, &v6) == 1 }
    }
}

extension TriggerCondition {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(UUID.self, forKey: .id)
        kind = try fields.decode(TriggerKind.self, forKey: .kind)
        value = try fields.decodeIfPresent(String.self, forKey: .value) ?? ""
        schedule = try fields.decodeIfPresent(TriggerWeeklySchedule.self, forKey: .schedule)
        ignoreBuiltInDisplay = try fields.decodeIfPresent(Bool.self, forKey: .ignoreBuiltInDisplay) ?? true
    }
}

enum TriggerCombination: String, Codable, CaseIterable { case all, any }
struct TriggerRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新触发规则"
    var mode: WorkMode = .desk
    var enabled = false
    var combination: TriggerCombination = .all
    var conditions = [TriggerCondition()]
    var preventDisplaySleep: Bool? = nil
    var preventScreenSaver: Bool? = nil
    var expression: TriggerExpression? = nil
    var priority = 0
    var sustainedMatchSeconds: TimeInterval = 0
    var cooldownSeconds: TimeInterval = 0
    var effectiveExpression: TriggerExpression {
        expression ?? (combination == .all ? .all(conditions.map(TriggerExpression.condition)) : .any(conditions.map(TriggerExpression.condition)))
    }
    var allConditions: [TriggerCondition] { effectiveExpression.conditions }
    enum CodingKeys: String, CodingKey { case id, name, mode, enabled, combination, conditions, preventDisplaySleep, preventScreenSaver, expression, priority, sustainedMatchSeconds, cooldownSeconds }
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写规则名称。" }
        if mode == .normal { return "触发规则只能选择桌面工作或后台工作。" }
        guard (-1000...1000).contains(priority) else { return "优先级必须在 -1000 至 1000 之间。" }
        guard sustainedMatchSeconds.isFinite, (0...86400).contains(sustainedMatchSeconds), cooldownSeconds.isFinite, (0...86400).contains(cooldownSeconds) else { return "持续匹配和冷却时间必须为 0–86400 秒。" }
        if let error = effectiveExpression.validationError() { return error }
        let leaves = allConditions
        if leaves.count > 64 { return "每条规则最多 64 个条件。" }
        if Set(leaves.map(\.id)).count != leaves.count { return "条件标识重复，请重新添加条件。" }
        return nil
    }
    func matches(_ results: [UUID: TriggerConditionResult]) -> Bool {
        guard enabled, validationError == nil else { return false }
        return effectiveExpression.evaluate(results) == .matched
    }
}

extension TriggerRule {
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decode(UUID.self, forKey: .id)
        name = try fields.decode(String.self, forKey: .name)
        mode = try fields.decode(WorkMode.self, forKey: .mode)
        enabled = try fields.decode(Bool.self, forKey: .enabled)
        combination = try fields.decodeIfPresent(TriggerCombination.self, forKey: .combination) ?? .all
        conditions = try fields.decodeIfPresent([TriggerCondition].self, forKey: .conditions) ?? []
        expression = try fields.decodeIfPresent(TriggerExpression.self, forKey: .expression)
        priority = try fields.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        sustainedMatchSeconds = try fields.decodeIfPresent(TimeInterval.self, forKey: .sustainedMatchSeconds) ?? 0
        cooldownSeconds = try fields.decodeIfPresent(TimeInterval.self, forKey: .cooldownSeconds) ?? 0
        preventDisplaySleep = try fields.decodeIfPresent(Bool.self, forKey: .preventDisplaySleep)
        preventScreenSaver = try fields.decodeIfPresent(Bool.self, forKey: .preventScreenSaver)
    }
}

enum TriggerMatchState: String, Codable {
    case matched, unmatched, unknown
    var title: String {
        switch self { case .matched: return "满足"; case .unmatched: return "未满足"; case .unknown: return "未知" }
    }
}
struct TriggerConditionResult: Codable, Equatable {
    var state: TriggerMatchState
    var detail: String
}

@MainActor final class TriggerController: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            preferences.set(enabled, forKey: Self.enabledStorageKey)
            revision += 1
            engine.reset(); evaluationReport = nil
            if !enabled { observations = [:]; status = "自动触发已暂停。" }
            else { status = "自动触发已启用，等待匹配条件。" }
        }
    }
    @Published private(set) var rules: [TriggerRule]
    @Published private(set) var observations: [UUID: TriggerConditionResult] = [:]
    @Published private(set) var status = "尚未启用自动触发规则。"
    @Published private(set) var snapshot = TriggerSnapshot()
    @Published private(set) var lastObservedAt: Date?
    private let preferences: UserDefaults
    private let source: any TriggerObservationSource
    private var revision = 0
    private var engine = TriggerRuleEngine()
    @Published private(set) var evaluationReport: TriggerEvaluationReport?
    var arbitrationContextProvider: (() -> TriggerArbitrationContext)?
    var arbitrationContext = TriggerArbitrationContext()
    /// Unknown observations do not establish that a manually suppressed rule cleared.
    var assertedRuleIDs: Set<UUID> {
        let enabledIDs = Set(rules.filter(\.enabled).map(\.id))
        return Set(evaluationReport?.rules.filter { enabledIDs.contains($0.id) && $0.conditionState != .unmatched }.map(\.id) ?? [])
    }
    private static let enabledStorageKey = "orexin.NativeTriggersEnabled.v1"
    private static let storageKey = "orexin.NativeTriggerRules.v1"
    init(preferences: UserDefaults, source: (any TriggerObservationSource)? = nil) {
        self.preferences = preferences
        self.source = source ?? NativeTriggerObservations()
        enabled = preferences.object(forKey: Self.enabledStorageKey) as? Bool ?? true
        rules = preferences.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([TriggerRule].self, from: $0) } ?? []
    }
    func reload() {
        let values = preferences.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([TriggerRule].self, from: $0) } ?? []
        if values != rules { rules = values; engine.reset(); evaluationReport = nil; revision += 1 }
        let master = preferences.object(forKey: Self.enabledStorageKey) as? Bool ?? true
        if enabled != master { enabled = master }
    }
    @discardableResult func save(_ rule: TriggerRule) -> String? {
        if let error = Self.validateRules(rules.filter { $0.id != rule.id } + [rule]) { return error }
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule }
        else { rules.append(rule) }
        engine.reset(rule.id); evaluationReport = nil
        persist(); return nil
    }
    nonisolated static func validateRules(_ rules: [TriggerRule]) -> String? {
        if rules.count > 128 { return "最多可配置 128 条规则。" }
        if Set(rules.map(\.id)).count != rules.count { return "规则标识重复。" }
        // Condition IDs are scoped to a rule. Reusing an ID across different
        // rules is allowed only when it represents the identical condition.
        var conditions: [UUID: TriggerCondition] = [:]
        for rule in rules {
            if let error = rule.validationError { return rule.name + ": " + error }
            for condition in rule.allConditions {
                if let previous = conditions[condition.id], previous != condition { return "不同条件不能共用同一标识。" }
                conditions[condition.id] = condition
            }
        }
        return nil
    }
    @discardableResult func replaceAllRules(_ replacement: [TriggerRule]) -> String? {
        if let error = Self.validateRules(replacement) { return error }
        rules = replacement; engine.reset(); evaluationReport = nil; observations = [:]
        persist(); return nil
    }
    func remove(_ id: UUID) { rules.removeAll { $0.id == id }; engine.reset(id); evaluationReport = nil; persist() }
    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        guard !enabled || rules[index].validationError == nil else { return }
        rules[index].enabled = enabled; engine.reset(id); evaluationReport = nil; persist()
    }
    private func persist() {
        revision += 1
        if let data = try? JSONEncoder().encode(rules) { preferences.set(data, forKey: Self.storageKey) }
        if !enabled { status = "自动触发已暂停。"; observations = [:] }
        else if !rules.contains(where: \.enabled) { status = "尚未启用自动触发规则。"; observations = [:] }
    }
    func matchingRules(now: Date, battery: BatteryReading?) async -> [TriggerRule] {
        guard self.enabled else { observations = [:]; status = "自动触发已暂停。"; return [] }
        let enabledRules = rules.filter { $0.enabled && $0.validationError == nil }
        guard !enabledRules.isEmpty else { observations = [:]; status = "尚未启用自动触发规则。"; return [] }
        let observedRevision = revision
        let read = await readObservations(rules: enabledRules, now: now, battery: battery)
        guard revision == observedRevision else { observations = [:]; return [] }
        snapshot = read.snapshot; observations = read.results; lastObservedAt = now
        // Preserve every eligible rule here. The coordinator applies suppression,
        // manual/session priority and safety before using the deterministic order.
        let report = engine.evaluate(rules: rules, observations: observations, now: now)
        evaluationReport = report
        let qualified = Set(report.rules.filter { $0.state == .matched || $0.state == .overridden }.map(\.id))
        let matches = enabledRules.filter { qualified.contains($0.id) }.sorted(by: TriggerRuleEngine.precedes)
        status = matches.isEmpty ? "没有规则满足条件及时间要求。" : LF("满足条件：%@", matches.map(\.name).joined(separator: ", "))
        return matches
    }
    func updateArbitration(_ context: TriggerArbitrationContext) {
        arbitrationContext = context
        guard let current = evaluationReport else { return }
        evaluationReport = engine.preview(rules: rules, observations: observations, now: current.evaluatedAt, context: context)
    }
    func refreshDiagnostics() async {
        let now = Date(), currentRevision = revision
        let read = await readObservations(rules: rules, now: now, battery: nil)
        guard currentRevision == revision else { return }
        snapshot = read.snapshot; observations = read.results; lastObservedAt = now
        var context = arbitrationContextProvider?() ?? arbitrationContext; context.masterEnabled = enabled
        evaluationReport = engine.preview(rules: rules, observations: read.results, now: now, context: context)
    }
    /// Dry-run reads current observations into local values and evaluates a copy
    /// of runtime. It never persists, advances timers, publishes diagnostics, or
    /// calls the coordinator. A draft replaces its saved counterpart for ranking.
    func dryRun(_ draft: TriggerRule? = nil, now: Date = Date(), battery: BatteryReading? = nil) async -> TriggerEvaluationReport {
        var candidates = rules
        if let draft {
            candidates.removeAll { $0.id == draft.id }; candidates.append(draft)
        }
        let currentEngine = engine
        let read = await readObservations(rules: candidates, now: now, battery: battery)
        var context = arbitrationContextProvider?() ?? arbitrationContext; context.masterEnabled = enabled
        var previewEngine = currentEngine
        if let draft, rules.first(where: { $0.id == draft.id }) != draft { previewEngine.reset(draft.id) }
        return previewEngine.preview(rules: candidates, observations: read.results, now: now, context: context)
    }
    private func readObservations(rules: [TriggerRule], now: Date, battery: BatteryReading?) async -> (snapshot: TriggerSnapshot, results: [UUID: TriggerConditionResult]) {
        let conditions = rules.flatMap(\.allConditions)
        var snapshot = await source.read(kinds: Set(conditions.map(\.kind)), now: now)
        if let battery {
            snapshot.batteryPercent = (0...100).contains(battery.percent) ? battery.percent : nil
            snapshot.acConnected = !battery.onBattery
        }
        var results: [UUID: TriggerConditionResult] = [:]
        for condition in conditions { results[condition.id] = snapshot.evaluate(condition, now: now) }
        return (snapshot, results)
    }
    /// Editor preview is read-only and never saves or evaluates an unsaved rule.
    func preview(kinds: Set<TriggerKind>) async -> TriggerSnapshot { await source.read(kinds: kinds, now: Date()) }
    static func applicationBundleIdentifier(at url: URL) -> String? {
        guard url.pathExtension.lowercased() == "app", let id = Bundle(url: url)?.bundleIdentifier,
              TriggerCondition(kind: .appRunning, value: id).validationError == nil else { return nil }
        return id
    }
    func openPermissionSettings(for kind: TriggerKind) { source.openPermissionSettings(for: kind) }
    func requestPermission(for kind: TriggerKind) { source.requestPermission(for: kind) }
}
