// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import Foundation

enum ThermalThreshold: String, CaseIterable, Identifiable {
    case heavy, critical
    var id: String { rawValue }
    var title: String { self == .heavy ? L("严重") : L("危急") }
    var code: String { rawValue.uppercased() }
    func reached(by state: ProcessInfo.ThermalState) -> Bool {
        switch state {
        case .nominal, .fair: return false
        case .serious: return self == .heavy
        case .critical: return true
        @unknown default: return true
        }
    }
}

extension AppModel {
    var thermalProtectionRequired: Bool {
        thermalReleaseEnabled && thermalThreshold.reached(by: thermalStateProvider())
    }

    func sampleThermalPressure(at date: Date = Date()) {
        let reading = thermalStateProvider()
        if thermalObservedState != reading { thermalObservedState = reading }
        thermalLastSampled = date
    }

    func setThermalThreshold(_ threshold: ThermalThreshold) async {
        guard thermalThreshold != threshold else { return }
        thermalThreshold = threshold
        preferences.set(threshold.rawValue, forKey: "orexin.thermal.threshold")
        record("温度保护阈值：" + threshold.title + " // " + threshold.code)
        onUpdate?()
        await protectFromThermalPressure()
    }

    func setThermalReleaseEnabled(_ enabled: Bool) async {
        guard thermalReleaseEnabled != enabled else { return }
        thermalReleaseEnabled = enabled
        preferences.set(enabled, forKey: "orexin.thermal.releaseEnabled")
        record("温度保护紧急释放" + (enabled ? "已开启。" : "已关闭；已触发的释放仍会完成。"))
        onUpdate?()
        await protectFromThermalPressure()
    }

    func setThermalAudibleAlertEnabled(_ enabled: Bool) {
        guard thermalAudibleAlertEnabled != enabled else { return }
        thermalAudibleAlertEnabled = enabled
        preferences.set(enabled, forKey: "orexin.thermal.audibleAlert")
        record("温度保护声音警报" + (enabled ? "已开启。" : "已关闭。"))
        onUpdate?()
    }

    private func notifyThermalIncident(releasing: Bool) {
        guard !thermalIncidentNotified else { return }
        thermalIncidentNotified = true
        let text = "温度保护触发：系统温度压力达到" + thermalSummary
            + (releasing ? "，暂停保活并取消自动休眠；正在执行的命令继续运行。" : "；紧急释放已关闭，保活状态保持不变。")
        record(text)
        if let thermalNotificationHandler { thermalNotificationHandler(text, thermalAudibleAlertEnabled) }
        else { notificationHandler?(text) }
    }

    /// Release our inhibitors; do not terminate a command or force system sleep.
    /// A failed cleanup is retried even if the next reading is cooler.
    @discardableResult func protectFromThermalPressure() async -> Bool {
        sampleThermalPressure()
        let aboveThreshold = thermalObservedState.map { thermalThreshold.reached(by: $0) } == true
        let required = thermalReleaseEnabled && aboveThreshold
        if aboveThreshold || thermalCleanupPending { notifyThermalIncident(releasing: required || thermalCleanupPending) }
        guard required || thermalCleanupPending else {
            if !aboveThreshold { thermalIncidentNotified = false }
            return false
        }
        suppressCurrentTriggers()
        automaticSleepRevision += 1
        automation.deadline = nil
        automation.cancelJobSleep(); automation.cancelBatterySleep()
        guard !busy else { thermalCleanupPending = true; return true }
        let needsCleanup = thermalCleanupPending || keepsAwake || runsWithLidClosed
            || active == .desk || active == .background || pending != nil
            || sessions.isActive
        // Normal's authentication handoff follows successful power release.
        // Let refresh finish that handoff without repeatedly opening settings.
        if pending == .normal { sessions.manualModeChanged(); return true }
        // Failed effect releases retain their assertion IDs for the next retry.
        guard needsCleanup else { sessions.manualModeChanged(); return true }
        thermalCleanupPending = true
        await choose(.normal, automatic: true)
        guard active == .normal, !error, pending == nil else { return true }
        thermalCleanupPending = false
        message = "温度保护已结束保活，恢复正常休眠。降温后可重新开启工作。"
        convenienceMessage = message
        record(message); onUpdate?()
        return true
    }
}
