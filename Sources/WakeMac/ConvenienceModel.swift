// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import WakeMacCore

@MainActor enum AppPaths {
    // Orexin starts with its own local history and assets.
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Orexin", isDirectory: true)
}

extension AppModel {
    var countdownText: String? {
        guard let end = [automation.nextDeadline, sessions.deadline].compactMap({ $0 }).min() else { return nil }
        let seconds = max(0, Int(ceil(end.timeIntervalSince(now))))
        if automation.batterySleepAt == end { return String(format: L("低电量：%d 秒后休眠"), seconds) }
        if automation.jobSleepAt == end { return String(format: L("任务已完成：%d 秒后休眠"), seconds) }
        return String(format: L("%d 分钟后休眠并锁定"), max(1, Int(ceil(Double(seconds) / 60))))
    }
    var menuText: String {
        guard menuLabelEnabled else { return "" }
        if busy { return L("切换中") }
        if error || pending != nil { return L("待处理") }
        let name = active.map { $0 == .background ? L("后台") : $0 == .desk ? L("桌面") : L("正常") } ?? L("未知")
        guard let end = [automation.nextDeadline, sessions.deadline].compactMap({ $0 }).min() else { return name }
        if appearance.showEndTime {
            let formatter = DateFormatter(); formatter.locale = AppLanguage.selected.locale
            formatter.dateFormat = appearance.twentyFourHour ? "HH:mm" : "h:mm a"
            return name + " · " + formatter.string(from: end)
        }
        return name + " · \(max(1, Int(ceil(end.timeIntervalSince(now) / 60))))m"
    }
    func record(_ text: String, notify: Bool = false) {
        historyStore.append(text); history = historyStore.entries
        if notify { notificationHandler?(text) }
    }
    func scheduleRestore(at date: Date) {
        guard !busy, active == .desk || active == .background else {
            convenienceMessage = "请先选择后台工作或桌面工作。"; return
        }
        guard date > Date() else { convenienceMessage = "请选择未来的时间。"; return }
        automation.deadline = date
        convenienceMessage = "已设置定时休眠。"
        record("定时休眠：" + date.formatted(date: .abbreviated, time: .shortened))
        onUpdate?()
    }
    func cancelVisibleCountdown() {
        guard let next = [automation.nextDeadline, sessions.deadline].compactMap({ $0 }).min() else { return }
        if sessions.deadline == next { Task { await sessions.end() }; return }
        if automation.batterySleepAt == next {
            automaticSleepRevision += 1; automation.cancelBatterySleep(); record("已取消本次低电量休眠。")
        } else if automation.jobSleepAt == next {
            automaticSleepRevision += 1; automation.cancelJobSleep(); workRequests.cancelSleep()
            if requestCountdownMode != nil { requestCountdownMode = nil; Task { await reconcileWorkRequests() } }
            record("已取消任务完成后休眠。")
        } else { cancelTimer() }
        onUpdate?()
    }
    func cancelTimer() {
        automation.deadline = nil; record("已取消定时休眠。"); onUpdate?()
    }
    func cancelAutomaticSleep() {
        automaticSleepRevision += 1
        automation.cancelBatterySleep(); automation.cancelJobSleep()
        workRequests.cancelSleep()
        if requestCountdownMode != nil {
            requestCountdownMode = nil
            Task { await reconcileWorkRequests() }
        }
        convenienceMessage = "已取消自动休眠；正在运行的命令会继续。"
        record(convenienceMessage); onUpdate?()
    }
    func setBatteryProtection(enabled: Bool, threshold: Int) {
        automaticSleepRevision += 1
        automation.batteryEnabled = enabled
        automation.batteryThreshold = min(50, max(5, threshold))
        automation.resetBatterySession()
        preferences.set(enabled, forKey: "orexin.BatteryProtection")
        preferences.set(automation.batteryThreshold, forKey: "orexin.BatteryThreshold")
        record("低电量保护" + (enabled ? "：\(automation.batteryThreshold)%" : "已关闭"))
    }
    func setMenuLabel(_ enabled: Bool) {
        menuLabelEnabled = enabled; preferences.set(enabled, forKey: "orexin.MenuLabel"); onUpdate?()
    }
    func tick(now date: Date = Date(), battery reading: BatteryReading?) async {
        now = date
        if battery != reading { battery = reading }
        onUpdate?()
        if await protectFromThermalPressure() { return }
        await reapWorkRequests(now: date)
        guard !busy else { return }
        let actions = automation.evaluate(now: date, mode: active, battery: reading)
        for action in actions {
            switch action {
            case .sleepForTimer:
                record("定时到点，恢复正常模式并请求系统休眠。", notify: true)
                await choose(.normal, sleep: true, automatic: true)
            case .batteryWarning(let percent):
                record("电量 \(percent)%，低于 \(automation.batteryThreshold)% 时将倒计时休眠。", notify: true)
            case .batteryCountdown:
                record("低电量保护：60 秒后休眠，可在面板取消。", notify: true)
            case .sleepForBattery:
                record("低电量保护开始恢复正常模式并请求休眠。", notify: true)
                await choose(.normal, sleep: true, automatic: true, batterySleep: true)
            case .sleepForJob:
                guard workRequests.active.isEmpty else { continue }
                record("任务成功，开始恢复正常模式并请求休眠。", notify: true)
                await choose(.normal, sleep: true, automatic: true)
            }
        }
        await tickFeatures(now: date, battery: reading, thermalAlreadyChecked: true)
        tickBehavior(now: date)
    }
    func startJob(command: String, directory: String) async {
        if await protectFromThermalPressure() {
            convenienceMessage = "温度保护：请等待设备降温并恢复正常休眠后，再启动命令。"
            onUpdate?(); return
        }
        let path = (directory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            convenienceMessage = "请填写命令和有效工作目录。"; return
        }
        let handle: WorkRequestHandle
        do {
            let behavior = workScreen.behavior(for: legacyWorkMode ?? .desk)
            handle = try await registerWork(.init(title: "命令任务 " + Date().formatted(date: .omitted, time: .standard), source: "command",
                screen: behavior == .normalBrightness ? .awake : behavior == .dim ? .dim : .idle, teardown: .sleepOnSuccess))
        } catch { convenienceMessage = error.localizedDescription; onUpdate?(); return }
        let id = handle.id
        commandHandles[id] = handle; runningCommandIDs.insert(id); jobRunning = true
        let log = jobLogDirectory.appendingPathComponent("task-\(id.uuidString).log")
        commandLogs[id] = log; jobLogURL = log
        jobStatus = "命令运行中"; convenienceMessage = ""
        preferences.set(true, forKey: "orexin.JobWasRunning")
        record("命令任务已启动；独立保活，等待真实退出码。")
        do {
            try FileManager.default.createDirectory(at: jobLogDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let result = try await Task.detached(priority: .utility) {
                try CommandJob.run(command: command, directory: path, logURL: log)
            }.value
            try await completeWork(handle, exitCode: result.exitCode)
            jobStatus = result.exitCode == 0 ? "命令成功" : "命令失败（\(result.exitCode)）"
            if result.truncated { record("任务日志已达到 5 MB 上限，后续输出已丢弃。") }
        } catch {
            let teardown = try? workRequests.release(id: id, state: .failed, reason: error.localizedDescription, now: Date())
            saveWorkRequests(); await finishWorkMutation(teardown, now: Date())
            jobStatus = "命令启动或日志处理失败：" + error.localizedDescription
        }
        runningCommandIDs.remove(id); commandHandles.removeValue(forKey: id)
        jobRunning = !runningCommandIDs.isEmpty
        preferences.set(jobRunning, forKey: "orexin.JobWasRunning")
        record(jobStatus, notify: true); onUpdate?()
    }
    func completeJob(id: UUID, exitCode: Int32?, at date: Date) {
        jobRunning = false; preferences.set(false, forKey: "orexin.JobWasRunning")
        automation.finishJob(id: id, success: exitCode == 0, now: date)
        if exitCode == 0 {
            jobStatus = automation.jobSleepAt == nil ? "命令成功；自动休眠已取消" : "命令成功；60 秒后休眠"
        } else { jobStatus = LF("命令失败（%@），不会休眠", exitCode.map(String.init) ?? L("未获得退出码")) }
        record(jobStatus, notify: true); onUpdate?()
    }
    func observeDisplay(_ updated: DisplayState) {
        guard display != updated else { return }
        if let old = display.lidClosed, let value = updated.lidClosed, old != value { record(value ? "检测到合盖。" : "检测到开盖。") }
        if let old = display.builtInAsleep, let value = updated.builtInAsleep, old != value { record(value ? "检测到屏幕熄灭。" : "检测到屏幕亮起。") }
        display = updated
    }
}
