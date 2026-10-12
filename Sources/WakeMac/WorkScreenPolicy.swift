// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import CoreGraphics
import Darwin
import WakeMacCore

enum WorkScreenBehavior: String, CaseIterable, Identifiable {
    case dim, normalBrightness, immediateSleep, systemIdle
    var id: String { rawValue }
    var keepsDisplayActive: Bool { self == .dim || self == .normalBrightness }
    var title: String {
        let key = switch self {
        case .dim: "屏幕最暗"
        case .normalBrightness: "正常亮度"
        case .immediateSleep: "立即熄屏"
        case .systemIdle: "按系统时间熄屏"
        }
        return L(key)
    }
    var detail: String {
        switch self {
        case .dim: "亮度设为 0，保留屏幕会话与自动化操作"
        case .normalBrightness: "恢复原亮度，保留屏幕会话与自动化操作"
        case .immediateSleep: "立即关闭显示器，纯后台任务继续运行"
        case .systemIdle: "按系统闲置时间关闭显示器，纯后台任务继续运行"
        }
    }
    var icon: String { self == .dim ? "sun.min" : self == .normalBrightness ? "sun.max" : "display" }
    var code: String {
        switch self {
        case .dim: "ZERO_BRIGHTNESS"
        case .normalBrightness: "NORMAL_BRIGHTNESS"
        case .immediateSleep: "DISPLAY_SLEEP_NOW"
        case .systemIdle: "DISPLAY_IDLE"
        }
    }
    static func choices(for mode: WorkMode) -> [Self] {
        [.dim, .normalBrightness, .systemIdle]
    }
}

/// On Apple Silicon, brightness control is supplied by DisplayServices. Resolve
/// optional system symbols at runtime; unavailable control fails visibly.
enum BuiltInBrightness {
    private typealias Read = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Write = @convention(c) (UInt32, Float) -> Int32
    private static let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
    private static var display: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16), count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
    static func read() throws -> Float {
        guard let framework, let symbol = dlsym(framework, "DisplayServicesGetBrightness"), let display else {
            throw ModeError("当前 Mac 无法读取内置屏幕亮度。")
        }
        var value: Float = 0
        guard unsafeBitCast(symbol, to: Read.self)(display, &value) == 0, value.isFinite, (0...1).contains(value) else {
            throw ModeError("当前 Mac 无法读取内置屏幕亮度。")
        }
        return value
    }
    static func write(_ value: Float) throws {
        guard value.isFinite, (0...1).contains(value), let framework,
              let symbol = dlsym(framework, "DisplayServicesSetBrightness"), let display,
              unsafeBitCast(symbol, to: Write.self)(display, value) == 0 else {
            throw ModeError("当前 Mac 无法设置内置屏幕亮度。")
        }
        guard abs(try read() - value) < (value == 0 ? 0.001 : 0.03) else { throw ModeError("屏幕亮度未通过系统回读核验。") }
    }
}

@MainActor final class WorkScreenPolicy: ObservableObject {
    @Published private(set) var background: WorkScreenBehavior
    @Published private(set) var desktop: WorkScreenBehavior
    @Published private(set) var status = "跟随系统屏幕设置"
    @Published var runtimeBehavior: WorkScreenBehavior? {
        didSet {
            guard runtimeBehavior != oldValue else { return }
            if runtimeBehavior == .immediateSleep { behaviorBeforeSleep = oldValue }
            else { behaviorBeforeSleep = nil }
            observedImmediateSleep = false
            revision += 1; appliedBehavior = nil
        }
    }
    private var behaviorBeforeSleep: WorkScreenBehavior?
    private var observedImmediateSleep = false
    private let preferences: UserDefaults
    private let runtimeEnabled: Bool
    private var appliedBehavior: WorkScreenBehavior?
    private var appliedMode: WorkMode?
    private var originalBrightness: Float?
    private var idleTimeout: TimeInterval?
    private var timeoutSource: Bool?
    private var timeoutSample = Date.distantPast
    private var lastSleepRequest = Date.distantPast
    private var lastDimCheck = Date.distantPast
    private var requestInFlight = false
    private var normalSleepIdlePeriod: TimeInterval?
    private var revision = 0
    var monotonicTime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var readBrightness: () throws -> Float = BuiltInBrightness.read
    var writeBrightness: (Float) throws -> Void = BuiltInBrightness.write
    var idleSeconds: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
    }
    var readTimeout: (Bool) async throws -> TimeInterval = { onBattery in
        let text = try await Task.detached(priority: .utility) {
            try CommandRunner.run("/usr/bin/pmset", ["-g", "custom"], timeout: 3)
        }.value
        guard let minutes = displayTimeoutMinutes(text, onBattery: onBattery) else {
            throw ModeError("无法读取系统熄屏时间。")
        }
        return minutes == 0 ? .infinity : TimeInterval(minutes * 60)
    }
    var requestSleep: () async throws -> Void = {
        _ = try await Task.detached(priority: .userInitiated) {
            try CommandRunner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 2)
        }.value
    }
    init(preferences: UserDefaults, runtimeEnabled: Bool = true) {
        self.preferences = preferences
        self.runtimeEnabled = runtimeEnabled
        background = WorkScreenBehavior(rawValue: preferences.string(forKey: "orexin.screen.background") ?? "") ?? .dim
        desktop = WorkScreenBehavior(rawValue: preferences.string(forKey: "orexin.screen.desktop") ?? "") ?? .normalBrightness
        if !WorkScreenBehavior.choices(for: .background).contains(background) { background = .systemIdle }
        if !WorkScreenBehavior.choices(for: .desk).contains(desktop) { desktop = .systemIdle }
        originalBrightness = (preferences.object(forKey: "orexin.screen.restoreBrightness") as? NSNumber).map { $0.floatValue }
    }
    func behavior(for mode: WorkMode) -> WorkScreenBehavior {
        runtimeBehavior ?? (mode == .background ? background : desktop)
    }
    func resumeAfterDisplayWake() {
        guard runtimeBehavior == .immediateSleep else { return }
        runtimeBehavior = behaviorBeforeSleep
    }
    func select(_ behavior: WorkScreenBehavior, for mode: WorkMode) {
        guard mode != .normal, WorkScreenBehavior.choices(for: mode).contains(behavior) else { return }
        if mode == .background { background = behavior } else { desktop = behavior }
        preferences.set(behavior.rawValue, forKey: mode == .background ? "orexin.screen.background" : "orexin.screen.desktop")
        runtimeBehavior = nil; revision += 1; appliedBehavior = nil
    }
    func restore() throws {
        revision += 1; appliedBehavior = nil; appliedMode = nil; runtimeBehavior = nil
        idleTimeout = nil; timeoutSource = nil
        if let originalBrightness {
            try writeBrightness(originalBrightness)
            self.originalBrightness = nil
            preferences.removeObject(forKey: "orexin.screen.restoreBrightness")
        }
        setStatus("跟随系统屏幕设置")
    }
    private func setStatus(_ message: String) { if status != message { status = message } }
    func currentIdlePeriod() -> TimeInterval { monotonicTime() - idleSeconds() }
    func didRequestSystemSleep(in idlePeriod: TimeInterval) {
        // Commit the input epoch captured before the asynchronous request.
        // Input received while that request runs belongs to a new idle period.
        if idlePeriod.isFinite { normalSleepIdlePeriod = idlePeriod }
    }
    func normalSleepIsDue(state: DisplayState, onBattery: Bool, now: Date) async -> Bool {
        // Display sleep/locking may precede this tick. Normal mode must still
        // request system sleep once; this does not unlock or weaken protection.
        guard runtimeEnabled else { return false }
        do {
            if timeoutSource != onBattery || now.timeIntervalSince(timeoutSample) >= 60 {
                idleTimeout = try await readTimeout(onBattery)
                timeoutSource = onBattery; timeoutSample = now
            }
            guard let idleTimeout, idleTimeout.isFinite else { return false }
            let idle = idleSeconds(), idlePeriod = monotonicTime() - idle
            // Allow for small differences between the clock and input samples.
            if let consumed = normalSleepIdlePeriod, idlePeriod > consumed + 0.25 {
                normalSleepIdlePeriod = nil
            }
            guard idle >= idleTimeout, normalSleepIdlePeriod == nil else { return false }
            normalSleepIdlePeriod = idlePeriod
            return true
        } catch { setStatus("屏幕策略未核验：" + error.localizedDescription); return false }
    }
    func tick(mode: WorkMode?, working: Bool, state: DisplayState, onBattery: Bool, now: Date) async {
        guard runtimeEnabled, working, let mode, mode != .normal else { return }
        if runtimeBehavior == .immediateSleep {
            if state.builtInAsleep == true { observedImmediateSleep = true }
            else if state.builtInAsleep == false, observedImmediateSleep { resumeAfterDisplayWake() }
        }
        normalSleepIdlePeriod = nil
        let behavior = behavior(for: mode), version = revision
        let changed = appliedBehavior != behavior || appliedMode != mode
        do {
            if behavior == .dim {
                if originalBrightness == nil {
                    let original = try readBrightness()
                    originalBrightness = original
                    preferences.set(original, forKey: "orexin.screen.restoreBrightness")
                }
                if changed || now.timeIntervalSince(lastDimCheck) >= 5 {
                    lastDimCheck = now
                    if try readBrightness() >= 0.001 { try writeBrightness(0) }
                }
                setStatus("亮度 0% · 显示器会话保留")
            } else if behavior != .immediateSleep, let originalBrightness {
                try writeBrightness(originalBrightness)
                self.originalBrightness = nil; preferences.removeObject(forKey: "orexin.screen.restoreBrightness")
            }
            if behavior == .systemIdle, timeoutSource != onBattery || now.timeIntervalSince(timeoutSample) >= 60 {
                let timeout = try await readTimeout(onBattery)
                guard version == revision else { return }
                idleTimeout = timeout; timeoutSource = onBattery; timeoutSample = now
            }
            guard version == revision else { return }
            appliedBehavior = behavior; appliedMode = mode
            switch behavior {
            case .dim: break
            case .normalBrightness: setStatus("正常亮度 · 显示器会话保留")
            case .immediateSleep: setStatus(state.builtInAsleep == true ? "显示器已熄灭 · 后台任务继续" : "正在请求显示器立即熄灭")
            case .systemIdle:
                if let idleTimeout { setStatus(idleTimeout.isInfinite ? "系统设置为不自动熄屏" : LF("按系统设置闲置 %d 分钟后熄屏", Int(idleTimeout / 60))) }
            }
            // The action suspends display effects until wake without changing
            // the preset's saved policy or repeatedly sleeping a closed display.
            let sleepDue = behavior == .immediateSleep && changed
                || behavior == .systemIdle && idleTimeout.map { idleSeconds() >= $0 } == true
            if sleepDue, state.builtInAsleep != true, !requestInFlight,
               changed || now.timeIntervalSince(lastSleepRequest) >= 3 {
                requestInFlight = true; lastSleepRequest = now
                defer { requestInFlight = false }
                try await requestSleep()
            }
        } catch {
            guard version == revision else { return }
            if behavior == .immediateSleep { resumeAfterDisplayWake() }
            setStatus("屏幕策略未核验：" + error.localizedDescription)
        }
    }
}

func displayTimeoutMinutes(_ text: String, onBattery: Bool) -> Int? {
    var profileMatches = false
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "Battery Power:" || trimmed == "AC Power:" || trimmed == "UPS Power:" {
            profileMatches = trimmed == (onBattery ? "Battery Power:" : "AC Power:")
        } else if profileMatches {
            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            if parts.first == "displaysleep", parts.count > 1, let value = Int(parts[1]), (0...1440).contains(value) { return value }
        }
    }
    return nil
}
