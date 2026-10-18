// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation
import WakeMacCore

/// Strong Kleene logic: NOT unknown stays unknown; a known false resolves ALL,
/// and a known true resolves ANY. Empty groups are invalid, never vacuously true.
indirect enum TriggerExpression: Codable, Equatable {
    case condition(TriggerCondition)
    case all([TriggerExpression])
    case any([TriggerExpression])
    case not(TriggerExpression)

    private enum CodingKeys: String, CodingKey { case type, condition, children }
    enum Kind: String, Codable, CaseIterable { case condition, all, any, not }
    var kind: Kind {
        switch self { case .condition: return .condition; case .all: return .all; case .any: return .any; case .not: return .not }
    }
    var children: [TriggerExpression] {
        switch self { case .condition: return []; case .all(let items), .any(let items): return items; case .not(let item): return [item] }
    }
    var conditions: [TriggerCondition] {
        switch self { case .condition(let condition): return [condition]; default: return children.flatMap(\.conditions) }
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try fields.decode(Kind.self, forKey: .type)
        if kind == .condition { self = .condition(try fields.decode(TriggerCondition.self, forKey: .condition)); return }
        let children = try fields.decode([TriggerExpression].self, forKey: .children)
        switch kind {
        case .all: self = .all(children)
        case .any: self = .any(children)
        case .not:
            guard children.count == 1 else { throw DecodingError.dataCorruptedError(forKey: .children, in: fields, debugDescription: "NOT requires exactly one child") }
            self = .not(children[0])
        case .condition: fatalError("Handled above")
        }
    }
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(kind, forKey: .type)
        if case .condition(let condition) = self { try fields.encode(condition, forKey: .condition) }
        else { try fields.encode(children, forKey: .children) }
    }
    func validationError(depth: Int = 0) -> String? {
        guard depth < 8 else { return "条件最多嵌套 8 层。" }
        if case .condition(let condition) = self { return condition.validationError }
        guard !children.isEmpty else { return "条件组至少需要一个条件。" }
        return children.compactMap { $0.validationError(depth: depth + 1) }.first
    }
    func evaluate(_ results: [UUID: TriggerConditionResult]) -> TriggerMatchState {
        switch self {
        case .condition(let condition): return results[condition.id]?.state ?? .unknown
        case .not(let child):
            switch child.evaluate(results) { case .matched: return .unmatched; case .unmatched: return .matched; case .unknown: return .unknown }
        case .all(let children):
            guard !children.isEmpty else { return .unknown }
            let values = children.map { $0.evaluate(results) }
            return values.contains(.unmatched) ? .unmatched : values.contains(.unknown) ? .unknown : .matched
        case .any(let children):
            guard !children.isEmpty else { return .unknown }
            let values = children.map { $0.evaluate(results) }
            return values.contains(.matched) ? .matched : values.contains(.unknown) ? .unknown : .unmatched
        }
    }
    var summary: String {
        switch self {
        case .condition(let condition):
            return condition.kind.title + (condition.kind == .weeklySchedule ? " · " + (condition.schedule?.summary ?? L("尚未设置")) : condition.value.isEmpty ? "" : " · " + condition.value)
        case .all(let children): return L("全部") + " (" + children.map(\.summary).joined(separator: "; ") + ")"
        case .any(let children): return L("任一") + " (" + children.map(\.summary).joined(separator: "; ") + ")"
        case .not(let child): return L("非") + " (" + child.summary + ")"
        }
    }
}

struct TriggerArbitrationContext: Equatable {
    var masterEnabled = true
    var suppressedRuleIDs: Set<UUID> = []
    var sessionActive = false
    var manualWorkActive = false
    var safetyBlockReason: String?
}

enum TriggerEvaluationState: String, Codable {
    case matched, unmatched, unknown, sustaining, coolingDown, suppressed, overridden
    var title: String {
        switch self {
        case .matched: return "满足 · 排序胜出"
        case .unmatched: return "未满足"
        case .unknown: return "未知"
        case .sustaining: return "等待持续满足"
        case .coolingDown: return "冷却中"
        case .suppressed: return "已抑制"
        case .overridden: return "被覆盖"
        }
    }
}

struct TriggerRuleEvaluation: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var conditionState: TriggerMatchState
    var state: TriggerEvaluationState
    var detail: String
    var remainingSeconds: TimeInterval? = nil
}

struct TriggerEvaluationReport: Codable, Equatable {
    var evaluatedAt: Date
    var rules: [TriggerRuleEvaluation]
    var winnerID: UUID?
    var conditions: [UUID: TriggerConditionResult]
}

/// Runtime is deliberately separate from the portable rules. Timers are reset on
/// edits/replacement/restart. A cooldown starts when a qualified match ends,
/// including when an observation becomes unknown. Samples normally arrive every
/// 5 seconds; a gap over 15 seconds loses continuity at lastSample + 15 seconds.
/// Existing cooldown deadlines still elapse in wall time during such gaps.
struct TriggerRuleEngine {
    static let maximumObservationGap: TimeInterval = 15
    private struct Runtime {
        var matchingSince: Date?
        var cooldownUntil: Date?
        var qualified = false
        var lastEvaluatedAt: Date?
    }
    private var runtime: [UUID: Runtime] = [:]
    mutating func reset(_ id: UUID? = nil) {
        if let id { runtime[id] = nil } else { runtime = [:] }
    }
    static func precedes(_ lhs: TriggerRule, _ rhs: TriggerRule) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.mode != rhs.mode { return lhs.mode == .background }
        return lhs.id.uuidString < rhs.id.uuidString
    }
    func preview(rules: [TriggerRule], observations: [UUID: TriggerConditionResult], now: Date, context: TriggerArbitrationContext) -> TriggerEvaluationReport {
        var copy = self
        return copy.evaluate(rules: rules, observations: observations, now: now, context: context)
    }
    mutating func evaluate(rules: [TriggerRule], observations: [UUID: TriggerConditionResult], now: Date, context: TriggerArbitrationContext = .init()) -> TriggerEvaluationReport {
        runtime = runtime.filter { id, _ in rules.contains { $0.id == id } }
        var results: [TriggerRuleEvaluation] = []
        var eligible: [TriggerRule] = []
        for rule in rules {
            let raw = rule.validationError == nil ? rule.effectiveExpression.evaluate(observations) : .unknown
            var result = TriggerRuleEvaluation(id: rule.id, name: rule.name, conditionState: raw, state: .unknown, detail: "")
            guard rule.enabled, context.masterEnabled, rule.validationError == nil else {
                runtime[rule.id] = nil
                result.state = .suppressed
                result.detail = rule.validationError ?? (!context.masterEnabled ? "自动触发总开关已暂停。" : "规则已停用。")
                results.append(result); continue
            }
            var state = runtime[rule.id] ?? Runtime()
            // A backward wall-clock correction must not manufacture elapsed time.
            if let previous = state.lastEvaluatedAt, now < previous {
                let remaining = state.cooldownUntil.map { max(0, $0.timeIntervalSince(previous)) } ?? 0
                state.matchingSince = nil
                state.cooldownUntil = remaining > 0 ? now.addingTimeInterval(min(remaining, rule.cooldownSeconds)) : nil
                state.qualified = false
            } else if let previous = state.lastEvaluatedAt, now.timeIntervalSince(previous) > Self.maximumObservationGap {
                state.matchingSince = nil
                if state.qualified && rule.cooldownSeconds > 0 {
                    state.cooldownUntil = previous.addingTimeInterval(Self.maximumObservationGap + rule.cooldownSeconds)
                }
                state.qualified = false
            }
            state.lastEvaluatedAt = now
            if raw != .matched {
                if state.qualified && rule.cooldownSeconds > 0 { state.cooldownUntil = now.addingTimeInterval(rule.cooldownSeconds) }
                state.qualified = false; state.matchingSince = nil
                result.state = raw == .unknown ? .unknown : .unmatched
                result.detail = raw == .unknown ? "观测不足，无法判定；持续匹配计时已重置。" : "条件未满足；持续匹配计时已重置。"
            } else {
                if state.matchingSince == nil { state.matchingSince = now }
                let cooldown = max(0, state.cooldownUntil?.timeIntervalSince(now) ?? 0)
                let sustained = max(0, rule.sustainedMatchSeconds - now.timeIntervalSince(state.matchingSince!))
                if cooldown > 0 {
                    result.state = .coolingDown; result.remainingSeconds = cooldown
                    result.detail = "上次有效匹配结束后冷却，剩余 \(Int(ceil(cooldown))) 秒。"
                } else if sustained > 0 {
                    result.state = .sustaining; result.remainingSeconds = sustained
                    result.detail = "条件需要持续满足 \(rule.sustainedMatchSeconds.formatted()) 秒，还需 \(Int(ceil(sustained))) 秒。"
                } else {
                    state.qualified = true; state.cooldownUntil = nil
                    result.state = .matched; result.detail = "条件及时间要求均满足。"
                    eligible.append(rule)
                }
            }
            runtime[rule.id] = state
            results.append(result)
        }
        var winner: TriggerRule?
        for rule in eligible.sorted(by: Self.precedes) {
            guard let index = results.firstIndex(where: { $0.id == rule.id }) else { continue }
            if let reason = context.safetyBlockReason {
                results[index].state = .suppressed; results[index].detail = "安全策略优先：" + reason
            } else if context.sessionActive {
                results[index].state = .overridden; results[index].detail = "当前工作会话优先于自动规则。"
            } else if context.manualWorkActive {
                results[index].state = .overridden; results[index].detail = "当前手动工作模式优先于自动规则。"
            } else if context.suppressedRuleIDs.contains(rule.id) {
                results[index].state = .suppressed; results[index].detail = "手动操作已抑制此规则；条件明确解除后才可再次触发。"
            } else if let winner {
                results[index].state = .overridden
                results[index].detail = "由「\(winner.name)」接管。排序：优先级高者优先，同级后台优先，再按规则 ID 升序。"
            } else {
                winner = rule
                results[index].detail = "排序胜出：优先级 \(rule.priority)。同级后台优先，再按规则 ID 升序。"
            }
        }
        return TriggerEvaluationReport(evaluatedAt: now, rules: results, winnerID: winner?.id, conditions: observations)
    }
}
