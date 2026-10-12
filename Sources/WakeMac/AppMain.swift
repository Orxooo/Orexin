// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import SwiftUI
import ServiceManagement
import WakeMacCore
import WakeMacPower

extension WorkMode {
    var recordTitle: String { switch self { case .background: "后台工作"; case .desk: "桌面工作"; case .normal: "正常休眠" } }
    var title: String { switch self { case .background: L("后台工作"); case .desk: L("桌面工作"); case .normal: L("正常休眠") } }
    var icon: String { switch self { case .background: "moon.stars"; case .desk: "laptopcomputer"; case .normal: "lock.shield" } }
    var detail: String {
        switch self {
        case .background: L("合盖继续运行，允许屏幕自动关闭")
        case .desk: L("保持运行，允许闲时熄屏")
        case .normal: L("恢复闲置与合盖休眠")
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    let backend: any ModeBackend
    let preferences: UserDefaults
    let triggerSource: (any TriggerObservationSource)?
    let sessionEffects: (any SessionEffectManaging)?
    init(backend: any ModeBackend = MacBackend(), preferences: UserDefaults = .standard, historyURL: URL? = nil, jobLogDirectory: URL? = nil,
         triggerSource: (any TriggerObservationSource)? = nil, sessionEffects: (any SessionEffectManaging)? = nil) {
        self.backend = backend; self.preferences = preferences
        self.triggerSource = triggerSource; self.sessionEffects = sessionEffects
        self.historyStore = HistoryStore(url: historyURL)
        self.history = historyStore.entries
        self.jobLogDirectory = jobLogDirectory ?? AppPaths.root.appendingPathComponent("Task Logs")
        thermalThreshold = ThermalThreshold(rawValue: preferences.string(forKey: "orexin.thermal.threshold") ?? "") ?? .critical
        thermalReleaseEnabled = preferences.object(forKey: "orexin.thermal.releaseEnabled") as? Bool ?? true
        thermalAudibleAlertEnabled = preferences.object(forKey: "orexin.thermal.audibleAlert") as? Bool ?? true
        automation.batteryEnabled = preferences.object(forKey: "orexin.BatteryProtection") as? Bool ?? true
        automation.batteryThreshold = min(50, max(5, preferences.object(forKey: "orexin.BatteryThreshold") as? Int ?? 20))
        menuLabelEnabled = preferences.object(forKey: "orexin.MenuLabel") as? Bool ?? true
        requiresImmediateLock = preferences.object(forKey: "orexin.RequireImmediateLock") as? Bool ?? true
        unlockedWorkEnabled = preferences.bool(forKey: "orexin.work.keepUnlocked")
        if preferences.bool(forKey: "orexin.JobWasRunning") {
            record("上次退出时命令尚未确认结束；未重新运行命令，也未安排休眠。")
            preferences.set(false, forKey: "orexin.JobWasRunning")
        }
    }
    let historyStore: HistoryStore
    let jobLogDirectory: URL
    @Published var history: [HistoryEntry] = []
    @Published var automation = AutomationPolicy()
    @Published var now = Date()
    @Published var battery: BatteryReading?
    @Published var menuLabelEnabled = true
    @Published private(set) var requiresImmediateLock = true
    @Published private(set) var unlockedWorkEnabled = false
    var lockRequirement: LockRequirement { unlockedWorkEnabled ? .unlockedWork : requiresImmediateLock ? .immediate : .system }
    var lockSummary: String { unlockedWorkEnabled ? "工作时保持未锁定" : requiresImmediateLock ? "要求即时密码保护" : "跟随系统锁屏设置" }
    func setUnlockedWork(_ enabled: Bool) async {
        guard !busy else { return }
        if active != .normal { await choose(.normal) }
        guard !error else { return }
        unlockedWorkEnabled = enabled
        preferences.set(enabled, forKey: "orexin.work.keepUnlocked")
        onUpdate?()
    }
    func setRequireImmediateLock(_ enabled: Bool) async {
        guard !busy else { return }
        requiresImmediateLock = enabled
        preferences.set(enabled, forKey: "orexin.RequireImmediateLock")
        generation += 1; refreshID = nil
        await refresh()
    }
    @Published var convenienceMessage = ""
    @Published var helperMessage = ""
    @Published var triggerSummary = "自动触发尚未接管运行模式"
    lazy var triggers = TriggerController(preferences: preferences, source: triggerSource)
    lazy var sessions = makeSessionController()
    lazy var behavior = BehaviorPreferences(preferences: preferences)
    lazy var idlePolicy: IdlePolicyController = {
        let controller = IdlePolicyController(preferences: preferences)
        controller.workingProvider = { [weak self] in self?.verifiedWork == true }
        controller.immediateAuthentication = { [weak self] in self?.snapshot?.lockPolicy == .immediate }
        controller.allowsScreenSaver = { [weak self] in self?.sessions.effectivePreventScreenSaver != true && self?.sessions.screenSaverExceptionActive != true }
        controller.preflight = { [weak self] in
            guard let self, !self.busy else { return false }
            let revision = self.generation
            guard let current = try? await self.backend.snapshot() else { return false }
            guard self.generation == revision, !self.busy else { return false }
            self.snapshot = current
            return self.lockRequirement.accepts(current.lockPolicy) && current.idleSleepPrevented == true
        }
        return controller
    }()
    lazy var appearance: AppearanceController = {
        let controller = AppearanceController(preferences: preferences)
        controller.onUpdate = { [weak self] in self?.onUpdate?() }
        return controller
    }()
    var triggerOwnedMode: WorkMode?
    var triggerOwnedRuleID: UUID?
    var appliedTriggerBehavior: SessionBehaviorOverride?
    var triggerRuntimeMode: WorkMode?
    var suppressedTriggerIDs: Set<UUID> = []
    var lastFeatureSample = Date.distantPast
    var featureTickRunning = false
    @Published var jobRunning = false
    @Published var jobStatus = "尚未启动命令"
    @Published var jobLogURL: URL?
    var automaticSleepRevision = 0
    var thermalStateProvider: () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    @Published var thermalThreshold: ThermalThreshold
    @Published var thermalReleaseEnabled: Bool
    @Published var thermalAudibleAlertEnabled: Bool
    @Published var thermalCleanupPending = false
    @Published var thermalObservedState: ProcessInfo.ThermalState?
    @Published var thermalLastSampled: Date?
    var thermalIncidentNotified = false
    var thermalNotificationHandler: ((String, Bool) -> Void)?
    var finalBatteryReading: (() -> BatteryReading?)?
    var notificationHandler: ((String) -> Void)?
    var featureNotificationHandler: ((String, FeatureNotification) -> Void)?
    var openPreferences: (() -> Void)?
    var openMenu: (() -> Void)?
    lazy var coordinator = ModeCoordinator(backend: backend)
    @Published var snapshot: Snapshot?
    @Published var display = DisplayState.read()
    lazy var workScreen = WorkScreenPolicy(preferences: preferences, runtimeEnabled: backend is MacBackend)
    @Published var active: WorkMode?
    @Published var pending: WorkMode?
    @Published var busy = false
    private var queuedAutomaticSleep: (battery: Bool, revision: Int)?
    @Published var message = "读取当前状态…"
    @Published var error = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    private var refreshID: UUID?
    var generation = 0
    var quitWhenReady = false
    var onUpdate: (() -> Void)?
    var showPanel: (() -> Void)?
    var quitApplication: (() -> Void)?
    var lockInstruction: String {
        return "当前要求即时密码保护。请在系统设置 → 锁定屏幕中，将显示器关闭或屏保启动后的密码要求设为「立即」；也可在 Orexin 偏好设置中选择跟随系统设置。"
    }
    var headline: String {
        if busy { return "正在切换…" }
        if let pending { return LF("%@ · 等待系统设置", pending.title) }
        if error { return "需要处理" }
        return active.map { LF("%@ · 已核验", $0.title) } ?? "尚未选择模式"
    }
    @Published private(set) var helperStatus = SMAppService.daemon(plistName: PowerService.plistName).status
    func refreshHelperStatus() {
        let observed = SMAppService.daemon(plistName: PowerService.plistName).status
        if helperStatus != observed { helperStatus = observed }
    }
    var keepsAwake: Bool { snapshot?.idleSleepPrevented == true }
    var runsWithLidClosed: Bool { snapshot?.backgroundLeaseActive == true && snapshot?.sleepDisabled == true }
    func setKeepsAwake(_ enabled: Bool) async {
        quitWhenReady = false
        await choose(enabled ? (runsWithLidClosed ? .background : .desk) : .normal)
    }
    func setRunsWithLidClosed(_ enabled: Bool) async {
        quitWhenReady = false
        await choose(enabled ? .background : (keepsAwake ? .desk : .normal))
    }
    func enableHelper() {
        defer { refreshHelperStatus() }
        let service = SMAppService.daemon(plistName: PowerService.plistName)
        if service.status == .requiresApproval {
            helperMessage = "请在登录项与扩展中批准 Orexin 的后台服务。"
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            _ = try PowerService.peerRequirement(identifier: PowerService.identifier)
            try service.register()
            helperMessage = "服务已登记，请在登录项与扩展中批准 Orexin。"
            SMAppService.openSystemSettingsLoginItems()
        } catch {
            if service.status == .requiresApproval {
                helperMessage = "请在登录项与扩展中批准 Orexin 的后台服务。"
                SMAppService.openSystemSettingsLoginItems()
            } else { helperMessage = error.localizedDescription }
        }
    }
    func removeHelper() async {
        defer { refreshHelperStatus() }
        await choose(.normal)
        guard active == .normal, !error, !busy else {
            helperMessage = "请先成功恢复正常休眠，再移除服务。"; return
        }
        do {
            try await SMAppService.daemon(plistName: PowerService.plistName).unregister()
            helperMessage = "合盖服务已移除。桌面工作仍可使用。"
        } catch { helperMessage = error.localizedDescription }
    }
    func refresh() async {
        guard !busy && refreshID == nil else { return }
        refreshHelperStatus()
        let id = UUID(), version = generation
        refreshID = id
        defer { if refreshID == id { refreshID = nil; onUpdate?() } }
        do {
            let current = try await backend.snapshot()
            guard generation == version, !busy, refreshID == id else { return }
            snapshot = current; observeDisplay(DisplayState.read())
            if !lockRequirement.accepts(current.lockPolicy) && current.idleSleepPrevented == true {
                refreshID = nil
                await choose(.normal, automatic: true)
                return
            }
            active = WorkMode.allCases.first { current.matches($0, lockRequirement: lockRequirement) }
            if let target = pending, lockRequirement.accepts(current.lockPolicy) {
                refreshID = nil
                await choose(target)
                return
            }
            if pending == nil && !error { message = active == nil ? "选择一个工作模式。现有电源状态尚未由本应用接管。" : "系统状态已回读确认。" }
        } catch {
            guard generation == version, !busy, refreshID == id else { return }
            snapshot = nil; active = nil
            let reason = error.localizedDescription
            if !self.error || message != reason { record("状态读取失败：" + reason) }
            self.error = true; message = reason
        }
    }
    func choose(_ mode: WorkMode, sleep: Bool = false, automatic: Bool = false, batterySleep: Bool = false, startupRecovery: Bool = false) async {
        guard !busy else {
            if mode == .normal, sleep, automatic {
                if queuedAutomaticSleep == nil || !batterySleep {
                    queuedAutomaticSleep = (batterySleep, automaticSleepRevision)
                }
                UnlockedWorkAuthorization.cancelPending()
            }
            return
        }
        if mode != .normal, thermalProtectionRequired || thermalCleanupPending {
            await protectFromThermalPressure()
            error = true
            message = "温度保护：请等待设备降温并恢复正常休眠后，再开启工作。"
            record(message); onUpdate?()
            return
        }
        let sleepIdlePeriod = sleep ? workScreen.currentIdlePeriod() : nil
        let previousMode = active
        if !automatic || mode == .normal {
            sessions.effectOverrides = nil
            sessions.manualModeChanged()
            if !startupRecovery { suppressCurrentTriggers() }
        }
        if !automatic { automaticSleepRevision += 1; automation.cancelJobSleep(); automation.resetBatterySession() }
        if mode == .normal { automation.deadline = nil; automation.cancelJobSleep(); automation.cancelBatterySleep() }
        record((automatic ? "自动切换：" : "切换模式：") + mode.recordTitle)
        generation += 1; refreshID = nil
        // Persist intent before the first side effect, including an interrupted first attempt.
        preferences.set(true, forKey: "orexin.HasConfiguredMode")
        busy = true; error = false; pending = nil; active = nil
        snapshot = nil
        if mode == .normal {
            sessions.screenPolicyPreventsSleep = nil
            do { try workScreen.restore() }
            catch { record("屏幕亮度恢复失败：" + error.localizedDescription) }
        } else { workScreen.runtimeBehavior = nil }
        message = LF("正在应用并核验「%@」…", mode.title); onUpdate?()
        let revision = automaticSleepRevision
        let result = sleep ? await coordinator.sleep(lockRequirement: lockRequirement) { [weak self] in
            guard let self else { return false }
            return await MainActor.run {
                guard !automatic || self.automaticSleepRevision == revision else { return false }
                guard !automatic || (!self.thermalProtectionRequired && !self.thermalCleanupPending) else { return false }
                if batterySleep {
                    let fresh = self.finalBatteryReading != nil ? self.finalBatteryReading?() : self.battery
                    guard self.automation.batteryEnabled,
                          let reading = fresh,
                          reading.onBattery, (0...self.automation.batteryThreshold).contains(reading.percent) else { return false }
                }
                return true
            }
        } : await coordinator.select(mode, lockRequirement: lockRequirement)
        switch result {
        case .active(let verified):
            if verified == .normal, let sleepIdlePeriod { workScreen.didRequestSystemSleep(in: sleepIdlePeriod) }
            do {
                let current = try await backend.snapshot()
                snapshot = current; observeDisplay(DisplayState.read())
                guard current.matches(verified, lockRequirement: lockRequirement) else { throw ModeError("切换后状态发生变化：\n" + current.diagnostic) }
                active = verified
                message = sleep ? "已向系统发送休眠请求。" : "系统状态已回读确认。"
            } catch { self.error = true; message = error.localizedDescription }
        case .sleepCancelled:
            do {
                let current = try await backend.snapshot()
                guard current.matches(.normal, lockRequirement: lockRequirement) else { throw ModeError("取消休眠后正常模式未通过核验。") }
                active = .normal; snapshot = current
                message = "自动休眠已取消，当前为正常模式。"
            } catch { self.error = true; message = error.localizedDescription }
        case .needsLockPolicy(let target):
            pending = target; message = lockInstruction
            if sleep { message += "\n设置完成后请再次点「立即休眠」，不会自动打断当前工作。" }
            showPanel?()
        case .failed(let reason):
            error = true; message = reason; showPanel?()
        }
        busy = false
        if let queued = queuedAutomaticSleep {
            queuedAutomaticSleep = nil
            if queued.revision == automaticSleepRevision {
                await choose(.normal, sleep: true, automatic: true, batterySleep: queued.battery)
                return
            }
        }
        if mode != .normal, thermalProtectionRequired || thermalCleanupPending {
            // A failed readback/rollback may have hidden an acquired inhibitor.
            thermalCleanupPending = true
            await protectFromThermalPressure()
            return
        }
        if error {
            record((thermalCleanupPending ? "温度保护释放失败：" : "切换失败：") + message, notify: !thermalCleanupPending)
        }
        else if pending != nil { record("等待恢复立即锁屏保护。", notify: !thermalCleanupPending) }
        else { record(result == .sleepCancelled ? message : (sleep ? "已发送系统休眠请求。" : "模式已核验：" + mode.recordTitle)) }
        if verifiedWork { await applyWorkScreenPolicy(now: Date()) }
        if !automatic, !error, pending == nil, active == mode, previousMode != mode {
            if mode != .normal { featureNotificationHandler?("工作已开始：" + mode.title, .sessionStart) }
            else if previousMode == .desk || previousMode == .background { featureNotificationHandler?("工作已结束，已恢复正常休眠。", .sessionEnd) }
        }
        onUpdate?()
        if quitWhenReady {
            if active == .normal && pending == nil && !error { sessions.shutdown(); behavior.saveStatistics(); quitApplication?() }
            else if mode != .normal { await choose(.normal) }
            else if error { quitWhenReady = false }
        }
    }
    func openLockSettings() {
        Task { await backend.requestLockPolicy(.immediate) }
    }
    func requestQuit() async {
        if jobRunning {
            automation.cancelJobSleep()
            convenienceMessage = "命令仍在运行。已取消完成后休眠；请等待命令结束后退出。"
            record(convenienceMessage); openPreferences?(); return
        }
        quitWhenReady = true
        if !busy { await choose(.normal) }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { message = "请在系统设置 → 通用 → 登录项中允许 Orexin。" }
        } catch { self.error = true; message = "登录启动设置失败：" + error.localizedDescription }
        onUpdate?()
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel(historyURL: AppPaths.root.appendingPathComponent("history.json"))
    var item: NSStatusItem!
    var panel: NSWindow!
    var quickPanel: ConsoleMenuPanel!
    var timer: Timer?
    var allowExit = false
    var preferencesWindow: NSWindow?
    var automationTimer: Timer?
    var observers: [NSObjectProtocol] = []
    let hotkeys = GlobalHotKeys()
    let notifier = LocalNotifier()
    private var thermalAlertSound: NSSound?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = model.appearance.theme.appearance
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureApplicationMenu()
        let quickHeight = min(650, max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
        quickPanel = ConsoleMenuPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: quickHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        quickPanel.title = "Orexin · 菜单控制"; quickPanel.level = .popUpMenu
        quickPanel.hidesOnDeactivate = true; quickPanel.isReleasedWhenClosed = false
        quickPanel.delegate = self
        let menuHost = NSHostingView(rootView: ControlPanel(model: model, height: quickHeight, closePopover: { [weak self] in self?.quickPanel.orderOut(nil) }))
        menuHost.sizingOptions = []
        quickPanel.contentView = menuHost
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        panel = ConsoleWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: quickHeight), styleMask: [.borderless, .closable, .miniaturizable], backing: .buffered, defer: false)
        panel.delegate = self
        panel.backgroundColor = .windowBackgroundColor
        panel.title = "Orexin · 快捷面板"
        panel.isReleasedWhenClosed = false
        let panelHost = NSHostingView(rootView: ControlPanel(model: model, standalone: true, height: quickHeight))
        panelHost.sizingOptions = [.minSize, .intrinsicContentSize]
        panel.contentView = panelHost
        panel.center()
        model.onUpdate = { [weak self] in self?.updateMenu() }
        model.showPanel = { [weak self] in self?.showPanel() }
        model.quitApplication = { [weak self] in self?.allowExit = true; NSApp.terminate(nil) }
        model.openPreferences = { [weak self] in self?.showPreferences() }
        model.openMenu = { [weak self] in self?.togglePopover() }
        model.finalBatteryReading = { BatterySource.read() }
        notifier.configure()
        ScriptBridge.model = model
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.model.refreshHelperStatus()
                await self?.notifier.refresh()
            }
        })
        model.notificationHandler = { [weak self] text in self?.notifier.send(text) }
        model.thermalNotificationHandler = { [weak self] text, audible in
            guard let self else { return }
            self.notifier.send(text, sound: false)
            guard audible else { return }
            let name = self.model.appearance.soundName
            let custom = name.isEmpty ? nil : NSSound(contentsOfFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds/" + name).path, byReference: true)
            self.thermalAlertSound = custom ?? NSSound(named: NSSound.Name("Basso"))
            self.thermalAlertSound?.play()
        }
        model.featureNotificationHandler = { [weak self] text, event in self?.notifier.send(text, event: event) }
        hotkeys.handler = { [weak self] id in
            guard let self else { return }
            self.model.quitWhenReady = false
            Task { await self.model.performShortcut(id) }
        }
        hotkeys.start()
        if !hotkeys.message.isEmpty { model.record(hotkeys.message) }
        let center = NSWorkspace.shared.notificationCenter
        for (name, text) in [(NSWorkspace.willSleepNotification, "系统即将休眠。"), (NSWorkspace.didWakeNotification, "系统已唤醒。"), (NSWorkspace.screensDidSleepNotification, "系统显示器已休眠。"), (NSWorkspace.screensDidWakeNotification, "系统显示器已唤醒。")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.model.record(text)
                    if name == NSWorkspace.screensDidWakeNotification {
                        self.model.workScreen.resumeAfterDisplayWake()
                        await self.model.applyWorkScreenPolicy(now: Date())
                    }
                    if name == NSWorkspace.willSleepNotification { await self.model.handleSystemWillSleep() }
                    if name == NSWorkspace.didWakeNotification, self.model.behavior.startAfterWake {
                        await self.model.refresh()
                        await self.model.beginDefaultSession()
                    }
                }
            })
        }
        automationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.tick(battery: BatterySource.read()) }
        }
        model.record("应用启动；恢复正常模式，不重放命令或定时任务。")
        updateMenu()
        if !UserDefaults.standard.bool(forKey: "orexin.HasConfiguredMode") { showPreferences() }
        Task {
            if UserDefaults.standard.bool(forKey: "orexin.HasConfiguredMode") { await model.choose(.normal, automatic: true, startupRecovery: true) }
            else { await model.refresh() }
            if model.behavior.startAtLaunch { await model.beginDefaultSession() }
        }
        timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        // Keep readback fresh while controls track. The backend's independent
        // loop renews its lease even when a readback command or UI is delayed.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPreferences(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowExit { return .terminateNow }
        // Cancel this termination attempt; issue a fresh one only after cleanup succeeds.
        Task { await model.requestQuit() }
        return .terminateCancel
    }
    @objc func showPanel() {
        NSApp.setActivationPolicy(.regular)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = WorkMode(rawValue: raw) else { return }
        model.quitWhenReady = false
        Task { await model.choose(mode) }
    }
    @objc func sleepNow() { Task { await model.choose(.normal, sleep: true) } }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func togglePopover() {
        guard let button = item.button, let statusWindow = button.window else { return }
        if quickPanel.isVisible { quickPanel.orderOut(nil); return }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = statusWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.maxX - quickPanel.frame.width, screen.minX + 8), screen.maxX - quickPanel.frame.width - 8)
        let y = max(screen.minY + 8, anchor.minY - quickPanel.frame.height - 6)
        quickPanel.setFrameOrigin(NSPoint(x: x, y: y))
        quickPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await model.refresh() }
    }
    func showPreferences() {
        NSApp.setActivationPolicy(.regular)
        if preferencesWindow == nil {
            // A landscape starting size leaves room for the sidebar and control rows.
            // AppKit owns resizing; content must not replace the initial window size.
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
            let size = NSSize(width: min(1280, visible.width - 48), height: min(780, visible.height - 64))
            let window = ConsoleWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.contentMinSize = NSSize(width: 860, height: 630)
            window.title = "Orexin"; window.isReleasedWhenClosed = false
            window.appearance = model.appearance.theme.appearance
            window.delegate = self
            window.backgroundColor = .windowBackgroundColor
            let host = NSHostingView(rootView: PreferencesView(model: model, hotkeys: hotkeys, notifier: notifier))
            host.sizingOptions = []
            window.contentView = host
            window.setContentSize(size)
            window.center(); preferencesWindow = window
        }
        quickPanel.orderOut(nil)
        preferencesWindow?.makeKeyAndOrderFront(nil)
        preferencesWindow?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === quickPanel, quickPanel.childWindows?.contains(where: { $0.isVisible }) != true { quickPanel.orderOut(nil) }
    }
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let anotherVisible = [preferencesWindow, panel].compactMap { $0 }.contains { $0 !== closing && $0.isVisible }
        if !anotherVisible { NSApp.setActivationPolicy(.accessory) }
    }
    func updateMenu() {
        let appearance = model.appearance.theme.appearance
        if NSApp.appearance != appearance { NSApp.appearance = appearance }
        for window in [preferencesWindow, panel, quickPanel].compactMap({ $0 }) where window.appearance != appearance {
            window.appearance = appearance
        }
        let image = model.appearance.menuImage()
        if item.button?.image !== image { item.button?.image = image }
        let title = model.menuText.isEmpty ? "" : " " + model.menuText
        if item.button?.title != title { item.button?.title = title }
        if item.button?.font?.pointSize != 11 { item.button?.font = .systemFont(ofSize: 11, weight: .medium) }
        let toolTip = "Orexin · " + model.headline
        if item.button?.toolTip != toolTip { item.button?.toolTip = toolTip }
    }
}

@main struct WakeMacMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        TerminalStyle.registerFonts()
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
