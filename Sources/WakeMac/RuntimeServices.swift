// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import IOKit.ps
import UserNotifications
import Combine
import WakeMacCore

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
}
@MainActor final class HistoryStore {
    static let maximumEntries = 200
    let url: URL?
    var entries: [HistoryEntry]
    init(url: URL?) {
        self.url = url
        entries = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
    }
    func append(_ text: String) {
        entries.insert(HistoryEntry(text: text), at: 0)
        entries = Array(entries.prefix(Self.maximumEntries))
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Commit only this store's empty JSON before changing the visible history.
    func clear() throws {
        guard let url else { throw ClearError.storageUnavailable }
        let data = try JSONEncoder().encode([HistoryEntry]())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        entries.removeAll()
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private enum ClearError: LocalizedError {
        case storageUnavailable
        var errorDescription: String? { "未配置本机日志文件，无法保存清空结果。" }
    }
}
struct BatterySource {
    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  raw[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = raw[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = raw[kIOPSMaxCapacityKey] as? Int, maximum > 0,
                  let state = raw[kIOPSPowerSourceStateKey] as? String,
                  state == kIOPSBatteryPowerValue || state == kIOPSACPowerValue else { continue }
            return BatteryReading(percent: Int(Double(current) / Double(maximum) * 100), onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}
enum FeatureNotification: String { case sessionStart, sessionEnd, triggerChange, sessionExtended }
@MainActor final class LocalNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var enabled = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var message = ""
    @Published var sessionStart = true { didSet { preferences.set(sessionStart, forKey: "orexin.notifications.sessionStart") } }
    @Published var sessionEnd = true { didSet { preferences.set(sessionEnd, forKey: "orexin.notifications.sessionEnd") } }
    @Published var triggerChange = true { didSet { preferences.set(triggerChange, forKey: "orexin.notifications.triggerChange") } }
    @Published var autoClear = false { didSet { preferences.set(autoClear, forKey: "orexin.notifications.autoClear") } }
    @Published var notificationSound = true { didSet { preferences.set(notificationSound, forKey: "orexin.notifications.sound") } }
    @Published var lifecycleSound = false { didSet { preferences.set(lifecycleSound, forKey: "orexin.notifications.lifecycleSound") } }
    @Published var extensionSound = false { didSet { preferences.set(extensionSound, forKey: "orexin.notifications.extensionSound") } }
    private var eventSound: NSSound?
    private let preferences: UserDefaults
    private let readAuthorization: () async -> UNAuthorizationStatus
    private let askAuthorization: () async throws -> Bool
    private let openSettings: (URL) -> Bool
    init(readAuthorization: @escaping () async -> UNAuthorizationStatus = { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
         askAuthorization: @escaping () async throws -> Bool = { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) },
         openSettings: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.readAuthorization = readAuthorization; self.askAuthorization = askAuthorization; self.openSettings = openSettings
        sessionStart = preferences.object(forKey: "orexin.notifications.sessionStart") as? Bool ?? true
        sessionEnd = preferences.object(forKey: "orexin.notifications.sessionEnd") as? Bool ?? true
        triggerChange = preferences.object(forKey: "orexin.notifications.triggerChange") as? Bool ?? true
        autoClear = preferences.bool(forKey: "orexin.notifications.autoClear")
        notificationSound = preferences.object(forKey: "orexin.notifications.sound") as? Bool ?? true
        lifecycleSound = preferences.bool(forKey: "orexin.notifications.lifecycleSound")
        extensionSound = preferences.bool(forKey: "orexin.notifications.extensionSound")
        super.init()
    }
    static var settingsURL: URL {
        var url = URLComponents(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        url.queryItems = [URLQueryItem(name: "id", value: Bundle.main.bundleIdentifier ?? "com.orxooo.Orexin")]
        return url.url!
    }
    func refresh() async {
        authorizationStatus = await readAuthorization()
        enabled = authorizationStatus == .authorized || authorizationStatus == .provisional
    }
    func configure() {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        Task { await refresh() }
    }
    func request() async -> Bool {
        await refresh()
        if authorizationStatus == .notDetermined {
            do { _ = try await askAuthorization(); await refresh() }
            catch { message = "通知授权请求失败：" + error.localizedDescription; return false }
        }
        if !enabled {
            let opened = openSettings(Self.settingsURL)
            message = opened ? "已打开通知设置，请选择 Orexin 并允许通知。" : "无法打开通知设置，请在系统设置 → 通知中允许 Orexin。"
        } else { message = "通知已开启。" }
        return enabled
    }
    func showSettings() {
        message = openSettings(Self.settingsURL) ? "已打开通知设置。" : "请打开系统设置 → 通知 → Orexin。"
    }
    func send(_ text: String, sound: Bool? = nil) {
        guard enabled else { return }
        let content = UNMutableNotificationContent(); content.title = "Orexin"; content.body = text
        let name = UserDefaults.standard.string(forKey: "orexin.appearance.sound") ?? ""
        content.sound = (sound ?? notificationSound) ? (name.isEmpty ? .default : UNNotificationSound(named: UNNotificationSoundName(rawValue: name))) : nil
        if autoClear { UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    func allows(_ event: FeatureNotification) -> Bool {
        switch event { case .sessionStart: sessionStart; case .sessionEnd: sessionEnd; case .triggerChange: triggerChange; case .sessionExtended: false }
    }
    func send(_ text: String, event: FeatureNotification) {
        let standaloneSound = (lifecycleSound && (event == .sessionStart || event == .sessionEnd)) || (extensionSound && event == .sessionExtended)
        if standaloneSound {
            let name = preferences.string(forKey: "orexin.appearance.sound") ?? ""
            eventSound = name.isEmpty ? NSSound(named: NSSound.Name("Glass")) : NSSound(contentsOfFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds/" + name).path, byReference: true)
            eventSound?.play()
        }
        guard allows(event) else { return }; send(text, sound: standaloneSound ? false : nil)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
