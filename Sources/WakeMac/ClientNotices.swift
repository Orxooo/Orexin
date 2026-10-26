// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import WakeMacCore

enum ClientNoticeKind: String, Codable {
    case update, serviceFailure, serviceRecovery, serviceUpgradeRequired, leaseExpired, sessionEnding
    case thermal, thermalRecovery, activity, operationFailed, test
    var requiresPopup: Bool {
        switch self {
        case .update, .serviceFailure, .serviceUpgradeRequired, .leaseExpired, .thermal, .operationFailed, .test: true
        default: false
        }
    }
}

struct ClientNotice: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var date = Date()
    var kind: ClientNoticeKind
    var title: String
    var body: String
    var releaseURL: URL?
    var systemNotification = true
    var read = false
}
private struct NoticeArchive: Codable {
    var entries: [ClientNotice]
    var importedIDs: Set<String>
}

/// Each process has one writer. The GUI imports the service's immutable event IDs.
@MainActor final class ClientNoticeCenter: ObservableObject {
    @Published private(set) var entries: [ClientNotice]
    @Published private(set) var storageError = ""
    var onArrival: ((ClientNotice, Bool) -> Void)?
    private let url: URL?
    private let preferences: UserDefaults
    private var importedIDs: Set<String> = []
    var unreadCount: Int { entries.filter { !$0.read }.count }
    var popupEnabled: Bool {
        get { preferences.object(forKey: "orexin.notifications.popup") as? Bool ?? true }
        set { preferences.set(newValue, forKey: "orexin.notifications.popup"); objectWillChange.send() }
    }
    init(url: URL? = nil, preferences: UserDefaults = .standard) {
        self.url = url; self.preferences = preferences
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let archive = data.flatMap { try? JSONDecoder().decode(NoticeArchive.self, from: $0) }
        entries = archive?.entries ?? data.flatMap { try? JSONDecoder().decode([ClientNotice].self, from: $0) } ?? []
        importedIDs = archive?.importedIDs ?? []
        entries = Array(entries.prefix(100))
    }
    @discardableResult func post(_ kind: ClientNoticeKind, title: String, body: String,
                                 id: String = UUID().uuidString, at date: Date = Date(),
                                 releaseURL: URL? = nil, systemNotification: Bool = true) -> Bool {
        guard !entries.contains(where: { $0.id == id }) else { return false }
        let notice = ClientNotice(id: id, date: date, kind: kind, title: title,
                                  body: String(body.prefix(4000)), releaseURL: releaseURL,
                                  systemNotification: systemNotification)
        entries.insert(notice, at: 0); entries = Array(entries.prefix(100)); save()
        onArrival?(notice, true)
        return true
    }
    func ingest(_ remote: [ClientNotice]) {
        let known = Set(entries.map(\.id)).union(importedIDs)
        let incoming = remote.filter { !known.contains($0.id) }
        let currentRemoteIDs = Set(remote.prefix(100).map(\.id))
        let changed = currentRemoteIDs != importedIDs
        importedIDs = currentRemoteIDs
        guard !incoming.isEmpty else { if changed { save() }; return }
        entries = Array((entries + incoming).sorted { $0.date > $1.date }.prefix(100)); save()
        // The service already delivered external notifications. Only present the
        // most recent missed actionable incident, rather than a backlog of sheets.
        let latestPopup = incoming.filter { notice in
            guard !notice.read, notice.kind.requiresPopup else { return false }
            let recovery: ClientNoticeKind?
            switch notice.kind {
            case .thermal: recovery = .thermalRecovery
            case .serviceFailure, .serviceUpgradeRequired: recovery = .serviceRecovery
            default: recovery = nil
            }
            // The service exports newest first, including events within the same
            // ISO-8601 second. A later recovery supersedes a missed warning.
            return !remote.prefix(while: { $0.id != notice.id }).contains { $0.kind == recovery }
        }
            .max { $0.date < $1.date }?.id
        for notice in incoming where !notice.kind.requiresPopup || notice.id == latestPopup {
            onArrival?(notice, false)
        }
    }
    func acknowledge(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), !entries[index].read else { return }
        entries[index].read = true; save()
    }
    func acknowledgeAll() {
        entries = entries.map { var value = $0; value.read = true; return value }; save()
    }
    func controlPayload() -> Data? {
        // ControlReply has a 512 KiB frame shared with history and task status;
        // Data fields are then base64 encoded. Reserve at most 64 KiB for notices.
        var selected: [ClientNotice] = []
        var size = 2
        for notice in entries {
            guard let encoded = try? ControlCoding.encode(notice),
                  size + encoded.count + 1 <= 64 * 1024 else { break }
            selected.append(notice); size += encoded.count + 1
        }
        return try? ControlCoding.encode(selected)
    }
    private func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(NoticeArchive(entries: entries, importedIDs: importedIDs)).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            storageError = ""
        } catch { storageError = "消息记录保存失败：" + error.localizedDescription }
    }
}

extension AppModel {
    func reportPowerServiceFailure(_ reason: String) {
        guard !powerServiceIncident else { return }
        powerServiceIncident = true
        notices.post(.serviceFailure, title: "工作状态无法确认",
                     body: "保活或权限服务的状态读取失败，请检查当前工作模式。\n" + reason)
        // Retain the existing injected notification seam for standalone callers.
        if notices.onArrival == nil { notificationHandler?("工作状态无法确认：" + reason) }
    }
    func reportPowerServiceRecovery() {
        guard powerServiceIncident else { return }
        powerServiceIncident = false
        notices.post(.serviceRecovery, title: "状态读取已恢复", body: "已重新读取系统状态，请确认当前工作模式；不会自动重新开始已停止的工作。")
    }
    func checkSessionEndingNotice(now: Date) {
        // Service countdowns are announced by their owner, not again by the GUI.
        let dates = serviceSocket == nil ? [automation.nextDeadline, sessions.deadline] : [automation.deadline, sessions.deadline]
        guard let end = dates.compactMap({ $0 }).min(), end > now, end.timeIntervalSince(now) <= 300 else { return }
        notices.post(.sessionEnding, title: "工作会话即将结束",
                     body: "距离计划结束已不足 5 分钟，请保存工作或延长会话。",
                     id: "deadline.\(end.timeIntervalSince1970)", at: now)
    }
}
