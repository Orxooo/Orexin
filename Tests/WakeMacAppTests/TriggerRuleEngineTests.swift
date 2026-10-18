// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor private final class RuleEngineSource: TriggerObservationSource {
    var externalDisplay: Bool? = true
    var acConnected: Bool? = true
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
        var value = TriggerSnapshot()
        value.externalDisplay = externalDisplay; value.acConnected = acConnected
        return value
    }
}

@MainActor final class TriggerRuleEngineTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)
    private func rule(id: String = "00000000-0000-0000-0000-000000000001", mode: WorkMode = .desk, priority: Int = 0, sustained: Double = 0, cooldown: Double = 0) -> TriggerRule {
        TriggerRule(id: UUID(uuidString: id)!, name: id, mode: mode, enabled: true, conditions: [TriggerCondition()], priority: priority, sustainedMatchSeconds: sustained, cooldownSeconds: cooldown)
    }
    private func observations(_ rules: [TriggerRule], state: TriggerMatchState = .matched) -> [UUID: TriggerConditionResult] {
        Dictionary(rules.flatMap(\.allConditions).map { ($0.id, TriggerConditionResult(state: state, detail: "fixture")) }, uniquingKeysWith: { a, _ in a })
    }
    private func prefs() -> UserDefaults { UserDefaults(suiteName: "RuleEngineTests." + UUID().uuidString)! }

    func testNestedThreeValuedTruthTablesNeverNegateUnknownIntoMatch() {
        let a = TriggerCondition(), b = TriggerCondition()
        let allStates: [TriggerMatchState] = [.matched, .unmatched, .unknown]
        for x in allStates { for y in allStates {
            let readings = [a.id: TriggerConditionResult(state: x, detail: ""), b.id: TriggerConditionResult(state: y, detail: "")]
            let all: TriggerExpression = .all([.condition(a), .condition(b)])
            let any: TriggerExpression = .any([.condition(a), .condition(b)])
            let expectedAll: TriggerMatchState = x == .unmatched || y == .unmatched ? .unmatched : x == .unknown || y == .unknown ? .unknown : .matched
            let expectedAny: TriggerMatchState = x == .matched || y == .matched ? .matched : x == .unknown || y == .unknown ? .unknown : .unmatched
            XCTAssertEqual(all.evaluate(readings), expectedAll)
            XCTAssertEqual(any.evaluate(readings), expectedAny)
            XCTAssertEqual(TriggerExpression.not(.not(all)).evaluate(readings), expectedAll)
        } }
        XCTAssertEqual(TriggerExpression.not(.condition(a)).evaluate([:]), .unknown)
        let nested: TriggerExpression = .all([.condition(a), .not(.any([.condition(b)]))])
        XCTAssertEqual(nested.evaluate([a.id: .init(state: .matched, detail: ""), b.id: .init(state: .unmatched, detail: "")]), .matched)
    }
    func testSustainedMatchRequiresBoundaryAndUnknownResetsIt() {
        var engine = TriggerRuleEngine()
        let rule = rule(sustained: 10), yes = observations([rule])
        func read(_ offset: Double, _ input: [UUID: TriggerConditionResult]) -> TriggerRuleEvaluation {
            engine.evaluate(rules: [rule], observations: input, now: epoch.addingTimeInterval(offset)).rules[0]
        }
        XCTAssertEqual(read(0, yes).state, .sustaining)
        XCTAssertEqual(read(9.9, yes).state, .sustaining)
        XCTAssertEqual(read(10, yes).state, .matched)
        XCTAssertEqual(read(11, [:]).state, .unknown)
        XCTAssertEqual(read(12, yes).remainingSeconds, 10)
        XCTAssertEqual(read(21.9, yes).state, .sustaining)
        XCTAssertEqual(read(22, yes).state, .matched)
    }
    func testCooldownStartsAtQualifiedMatchEndAndDoesNotExtendOnRepeatedFalse() {
        var engine = TriggerRuleEngine()
        let rule = rule(sustained: 5, cooldown: 20), yes = observations([rule]), no = observations([rule], state: .unmatched)
        func read(_ offset: Double, _ input: [UUID: TriggerConditionResult]) -> TriggerRuleEvaluation {
            engine.evaluate(rules: [rule], observations: input, now: epoch.addingTimeInterval(offset)).rules[0]
        }
        XCTAssertEqual(read(0, yes).state, .sustaining)
        XCTAssertEqual(read(2, no).state, .unmatched)
        XCTAssertEqual(read(3, yes).state, .sustaining) // Unqualified flicker did not start cooldown.
        XCTAssertEqual(read(8, yes).state, .matched)
        XCTAssertEqual(read(10, no).state, .unmatched)
        XCTAssertEqual(read(15, no).state, .unmatched)
        XCTAssertEqual(read(16, yes).remainingSeconds, 14)
        XCTAssertEqual(read(29.99, yes).state, .coolingDown)
        XCTAssertEqual(read(30, yes).state, .matched)
        XCTAssertEqual(read(31, [:]).state, .unknown)
        XCTAssertEqual(read(32, yes).state, .coolingDown)
    }
    func testBackwardClockResetsSustainedWindowAndPreservesRemainingCooldown() {
        var engine = TriggerRuleEngine()
        let rule = rule(sustained: 10, cooldown: 20), yes = observations([rule]), no = observations([rule], state: .unmatched)
        _ = engine.evaluate(rules: [rule], observations: yes, now: epoch)
        let rewound = engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(-60))
        XCTAssertEqual(rewound.rules[0].remainingSeconds, 10)
        _ = engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(-50))
        _ = engine.evaluate(rules: [rule], observations: no, now: epoch.addingTimeInterval(-49))
        let cooling = engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(-100))
        XCTAssertEqual(cooling.rules[0].state, .coolingDown)
        XCTAssertEqual(cooling.rules[0].remainingSeconds, 20)
    }
    func testLongObservationGapsBreakSustainedMatchButNormalSamplesAccumulate() {
        var engine = TriggerRuleEngine()
        let rule = rule(sustained: 20), yes = observations([rule])
        func read(_ offset: Double) -> TriggerRuleEvaluation {
            engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(offset)).rules[0]
        }
        XCTAssertEqual(read(0).state, .sustaining)
        XCTAssertEqual(read(10).remainingSeconds, 10)
        XCTAssertEqual(read(20).state, .matched)
        XCTAssertEqual(read(40).remainingSeconds, 20)
        XCTAssertEqual(read(50).state, .sustaining)
        XCTAssertEqual(read(60).state, .matched)
        // The 15-second boundary is still contiguous; greater gaps are not.
        XCTAssertEqual(read(75).state, .matched)
        XCTAssertEqual(read(90.01).state, .sustaining)
    }
    func testStaleQualifiedMatchCooldownElapsesFromContinuityLossBoundary() {
        var engine = TriggerRuleEngine()
        let rule = rule(cooldown: 20), yes = observations([rule])
        _ = engine.evaluate(rules: [rule], observations: yes, now: epoch)
        let resumed = engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(30))
        XCTAssertEqual(resumed.rules[0].state, .coolingDown)
        XCTAssertEqual(resumed.rules[0].remainingSeconds, 5) // last sample + 15 + 20
        XCTAssertEqual(engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(35)).rules[0].state, .matched)
        // Another long gap cannot restart cooldown at the resume time.
        XCTAssertEqual(engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(100)).rules[0].state, .matched)
    }
    func testPriorityAndStableTieBreakIgnoreInputOrder() {
        let desk = rule(priority: 10)
        let background = rule(id: "00000000-0000-0000-0000-000000000002", mode: .background, priority: 0)
        let rules = [desk, background]
        var engine = TriggerRuleEngine()
        XCTAssertEqual(engine.evaluate(rules: rules.reversed(), observations: observations(rules), now: epoch).winnerID, desk.id)
        var samePriority = desk; samePriority.priority = 0
        XCTAssertEqual(engine.evaluate(rules: [samePriority, background], observations: observations(rules), now: epoch).winnerID, background.id)
        var equalMode = background; equalMode.mode = .desk
        let ties = [samePriority, equalMode]
        XCTAssertEqual(engine.evaluate(rules: ties.reversed(), observations: observations(ties), now: epoch).winnerID, samePriority.id)
        XCTAssertEqual(engine.evaluate(rules: ties, observations: observations(ties), now: epoch).winnerID, samePriority.id)
    }
    func testDryRunExplainsSuppressionSessionManualSafetyAndLowerPriority() {
        let first = rule(priority: 2), second = rule(id: "00000000-0000-0000-0000-000000000002")
        let rules = [first, second], yes = observations(rules), engine = TriggerRuleEngine()
        let ordinary = engine.preview(rules: rules, observations: yes, now: epoch, context: .init())
        XCTAssertEqual(ordinary.rules.map(\.state), [.matched, .overridden])
        let suppressed = engine.preview(rules: rules, observations: yes, now: epoch, context: .init(suppressedRuleIDs: [first.id]))
        XCTAssertEqual(suppressed.rules.map(\.state), [.suppressed, .matched])
        for context in [TriggerArbitrationContext(sessionActive: true), TriggerArbitrationContext(manualWorkActive: true)] {
            let report = engine.preview(rules: rules, observations: yes, now: epoch, context: context)
            XCTAssertNil(report.winnerID); XCTAssertTrue(report.rules.allSatisfy { $0.state == .overridden })
        }
        let blocked = engine.preview(rules: rules, observations: yes, now: epoch, context: .init(safetyBlockReason: "thermal"))
        XCTAssertNil(blocked.winnerID); XCTAssertTrue(blocked.rules.allSatisfy { $0.state == .suppressed && $0.detail.contains("thermal") })
        let paused = engine.preview(rules: rules, observations: yes, now: epoch, context: .init(masterEnabled: false))
        XCTAssertNil(paused.winnerID); XCTAssertTrue(paused.rules.allSatisfy { $0.state == .suppressed })
    }
    func testPreviewDoesNotStartAdvanceOrResetLiveTimers() {
        var engine = TriggerRuleEngine()
        let rule = rule(sustained: 10), yes = observations([rule])
        _ = engine.preview(rules: [rule], observations: yes, now: epoch, context: .init())
        XCTAssertEqual(engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(20)).rules[0].state, .sustaining)
        _ = engine.preview(rules: [rule], observations: [:], now: epoch.addingTimeInterval(25), context: .init())
        XCTAssertEqual(engine.evaluate(rules: [rule], observations: yes, now: epoch.addingTimeInterval(30)).rules[0].state, .matched)
    }
    func testControllerDryRunLeavesPreferencesDiagnosticsAndLiveTimerUntouched() async throws {
        let preferences = prefs(), source = RuleEngineSource(), controller = TriggerController(preferences: preferences, source: source)
        let rule = rule(sustained: 10)
        XCTAssertNil(controller.save(rule))
        let before = preferences.dictionaryRepresentation() as NSDictionary
        let report = await controller.dryRun(now: epoch)
        XCTAssertEqual(report.rules[0].state, .sustaining)
        XCTAssertTrue(controller.observations.isEmpty); XCTAssertNil(controller.lastObservedAt); XCTAssertNil(controller.evaluationReport)
        XCTAssertEqual(before, preferences.dictionaryRepresentation() as NSDictionary)
        let firstReal = await controller.matchingRules(now: epoch.addingTimeInterval(20), battery: nil)
        XCTAssertTrue(firstReal.isEmpty)
        let diagnosticsBefore = controller.evaluationReport, observedBefore = controller.lastObservedAt
        source.externalDisplay = nil
        _ = await controller.dryRun(now: epoch.addingTimeInterval(25))
        XCTAssertEqual(controller.evaluationReport, diagnosticsBefore); XCTAssertEqual(controller.lastObservedAt, observedBefore)
        source.externalDisplay = true
        let qualified = await controller.matchingRules(now: epoch.addingTimeInterval(30), battery: nil)
        XCTAssertEqual(qualified.map(\.id), [rule.id])
        let encoded = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(TriggerEvaluationReport.self, from: encoded), report)
    }
    func testDraftDryRunDiscardsTimersForChangedExpression() async {
        let controller = TriggerController(preferences: prefs(), source: RuleEngineSource())
        var rule = rule(sustained: 10)
        XCTAssertNil(controller.save(rule))
        _ = await controller.matchingRules(now: epoch, battery: nil)
        rule.expression = .all([.condition(TriggerCondition(kind: .acConnected))])
        let preview = await controller.dryRun(rule, now: epoch.addingTimeInterval(100))
        XCTAssertEqual(preview.rules[0].state, .sustaining)
        XCTAssertNil(controller.rules[0].expression)
    }
    func testLegacyDecodeAndNestedRoundTripKeepDefaultsAndValidate() throws {
        let original = rule(), encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for field in ["expression", "priority", "sustainedMatchSeconds", "cooldownSeconds"] { legacy[field] = nil }
        let decoded = try JSONDecoder().decode(TriggerRule.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded, original)
        var nested = decoded
        nested.expression = .not(.any([.condition(TriggerCondition(kind: .acDisconnected)), .all([.condition(TriggerCondition(kind: .headphones))])]))
        nested.priority = 5; nested.sustainedMatchSeconds = 20; nested.cooldownSeconds = 30
        XCTAssertNil(nested.validationError)
        XCTAssertEqual(try JSONDecoder().decode(TriggerRule.self, from: JSONEncoder().encode(nested)), nested)
        // Native tree JSON needs no legacy flat fields.
        var treeOnly = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(nested)) as? [String: Any])
        treeOnly["conditions"] = nil; treeOnly["combination"] = nil
        XCTAssertEqual(try JSONDecoder().decode(TriggerRule.self, from: JSONSerialization.data(withJSONObject: treeOnly)).effectiveExpression, nested.effectiveExpression)
    }
    func testWeeklyScheduleEncodingIsStableAcrossTwentyRetainedRoundTrips() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let schedule = TriggerWeeklySchedule(weekdays: Set(1...7), startMinute: 540, endMinute: 1020)
        let original = try encoder.encode(schedule)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        XCTAssertEqual(object["weekdays"] as? [Int], Array(1...7))
        // Retain independently decoded Sets: their per-instance hash seeds can
        // differ even within one process, unlike reuse of one temporary buffer.
        let copies = try (0..<20).map { _ in try JSONDecoder().decode(TriggerWeeklySchedule.self, from: original) }
        for copy in copies {
            XCTAssertEqual(copy, schedule)
            XCTAssertEqual(try encoder.encode(copy), original)
        }
    }
    func testInvalidTreesAndTimeValuesCannotReplaceSavedRules() {
        let controller = TriggerController(preferences: prefs(), source: RuleEngineSource()), good = rule()
        XCTAssertNil(controller.save(good))
        var empty = good; empty.expression = .all([])
        var duplicate = good; duplicate.expression = .any([.condition(good.conditions[0]), .condition(good.conditions[0])])
        var deep = good; deep.expression = (0..<8).reduce(TriggerExpression.condition(TriggerCondition())) { value, _ in .not(value) }
        var negative = good; negative.sustainedMatchSeconds = -1
        var infinite = good; infinite.cooldownSeconds = .infinity
        var priority = good; priority.priority = 1001
        var count = good; count.expression = .all((0..<65).map { _ in .condition(TriggerCondition()) })
        for bad in [empty, duplicate, deep, negative, infinite, priority, count] {
            XCTAssertNotNil(controller.replaceAllRules([bad])); XCTAssertEqual(controller.rules, [good])
        }
        XCTAssertNotNil(controller.replaceAllRules([good, good])); XCTAssertEqual(controller.rules, [good])
        var conflicting = good; conflicting.id = UUID(); conflicting.conditions[0].kind = .headphones
        XCTAssertNotNil(controller.replaceAllRules([good, conflicting]))
        XCTAssertNil(controller.replaceAllRules([])); XCTAssertTrue(controller.rules.isEmpty)
    }
    func testCoordinatorSelectsHigherPriorityAndKeepsManualVetoThroughUnknown() async {
        let source = RuleEngineSource(), model = AppModel(backend: AutomationBackend(), preferences: prefs(), triggerSource: source)
        let high = rule(priority: 10), low = rule(id: "00000000-0000-0000-0000-000000000002", mode: .background)
        XCTAssertNil(model.triggers.replaceAllRules([low, high]))
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: epoch, battery: nil)
        XCTAssertEqual(model.active, .desk); XCTAssertEqual(model.triggerOwnedRuleID, high.id)
        await model.choose(.normal)
        source.externalDisplay = nil
        await model.tickFeatures(now: epoch.addingTimeInterval(6), battery: nil)
        source.externalDisplay = true
        await model.tickFeatures(now: epoch.addingTimeInterval(12), battery: nil)
        XCTAssertEqual(model.active, .normal)
        source.externalDisplay = false
        await model.tickFeatures(now: epoch.addingTimeInterval(18), battery: nil)
        source.externalDisplay = true
        await model.tickFeatures(now: epoch.addingTimeInterval(24), battery: nil)
        XCTAssertEqual(model.active, .desk)
        await model.choose(.normal)
    }
    func testSameModeRuleHandoffNaturalEndAndManualSuppressionKeepHistoryIDs() async {
        let source = RuleEngineSource(), model = AppModel(backend: AutomationBackend(), preferences: prefs(), triggerSource: source)
        source.acConnected = false
        let low = rule(priority: 0)
        var high = rule(id: "00000000-0000-0000-0000-000000000002", priority: 10)
        high.conditions = [TriggerCondition(kind: .acConnected)]
        XCTAssertNil(model.triggers.replaceAllRules([low, high]))
        await model.choose(.normal, automatic: true, startupRecovery: true)
        await model.tickFeatures(now: epoch, battery: nil)
        XCTAssertEqual(model.active, .desk); XCTAssertEqual(model.triggerOwnedRuleID, low.id)
        XCTAssertEqual(model.history.filter { $0.context?.kind == .rule && $0.text.hasPrefix("自动触发：") }.map { $0.context?.ruleID }, [low.id])

        source.acConnected = true
        await model.tickFeatures(now: epoch.addingTimeInterval(6), battery: nil)
        XCTAssertEqual(model.active, .desk); XCTAssertEqual(model.triggerOwnedRuleID, high.id)
        let handoffs = model.history.filter { $0.context?.kind == .rule && $0.text.hasPrefix("自动规则接管：") }
        XCTAssertEqual(handoffs.map { $0.context?.ruleID }, [high.id])
        XCTAssertEqual(handoffs.first?.context?.mode, WorkMode.desk.rawValue)
        await model.tickFeatures(now: epoch.addingTimeInterval(12), battery: nil)
        XCTAssertEqual(model.history.filter { $0.text.hasPrefix("自动规则接管：") }.count, 1)

        source.externalDisplay = false; source.acConnected = false
        await model.tickFeatures(now: epoch.addingTimeInterval(18), battery: nil)
        XCTAssertEqual(model.active, .normal); XCTAssertNil(model.triggerOwnedRuleID)
        let ends = model.history.filter { $0.context?.kind == .rule && $0.text.hasPrefix("自动规则结束：") }
        XCTAssertEqual(ends.map { $0.context?.ruleID }, [high.id])
        XCTAssertEqual(ends.first?.context?.mode, WorkMode.normal.rawValue)

        source.externalDisplay = true
        await model.tickFeatures(now: epoch.addingTimeInterval(24), battery: nil)
        XCTAssertEqual(model.triggerOwnedRuleID, low.id)
        await model.choose(.normal)
        let suppressed = model.history.filter { $0.context?.kind == .rule && $0.text.hasPrefix("自动规则已抑制：") }
        XCTAssertEqual(suppressed.map { $0.context?.ruleID }, [low.id])
        await model.choose(.normal)
        XCTAssertEqual(model.history.filter { $0.text.hasPrefix("自动规则已抑制：") }.count, 1)
    }

}
