// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import WakeMacCore

@MainActor final class UpdateMonitor: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var message = ""
    @Published private(set) var releaseURL: URL?
    @Published var automatic = true {
        didSet { preferences.set(automatic, forKey: "orexin.updates.automatic") }
    }
    private let preferences: UserDefaults
    private let notices: ClientNoticeCenter
    private let current: String
    private let previews: Bool
    private let loader: () async throws -> [GitHubRelease]
    init(notices: ClientNoticeCenter, preferences: UserDefaults = .standard,
         current: String = OrexinRelease.versionTag, previews: Bool = !OrexinRelease.channel.isEmpty,
         loader: @escaping () async throws -> [GitHubRelease] = UpdateMonitor.fetch) {
        self.notices = notices; self.preferences = preferences; self.current = current
        self.previews = previews; self.loader = loader
        automatic = preferences.object(forKey: "orexin.updates.automatic") as? Bool ?? true
        releaseURL = notices.entries.first { $0.kind == .update }?.releaseURL
    }
    func check(manual: Bool = false, now: Date = Date()) async {
        guard !checking else { return }
        if !manual {
            guard automatic else { return }
            if let last = preferences.object(forKey: "orexin.updates.lastAttempt") as? Date,
               now >= last, now.timeIntervalSince(last) < 6 * 3600 { return }
        }
        checking = true
        preferences.set(now, forKey: "orexin.updates.lastAttempt")
        defer { checking = false }
        do {
            guard let installed = ReleaseVersion(current) else { throw ModeError("无法读取当前版本。") }
            let releases = try await loader()
            guard let release = ReleaseCatalog.latest(in: releases, includePreviews: previews),
                  let latest = release.version, let url = release.url else {
                releaseURL = nil; message = "Orexin 仓库尚未发布可用版本。"; return
            }
            releaseURL = url
            if installed < latest {
                message = LF("发现新版本：%@", release.tagName)
                // Separate from bounded message retention: no repeat popup after
                // a restart or after 100 newer notices have displaced this one.
                if preferences.string(forKey: "orexin.updates.announcedTag") != release.tagName {
                    notices.post(.update, title: "Orexin 有新版本",
                                 body: LF("发现新版本：%@。可查看发布说明并下载更新。", release.tagName),
                                 id: "update.\(release.tagName)", at: now, releaseURL: url)
                    preferences.set(release.tagName, forKey: "orexin.updates.announcedTag")
                }
            } else {
                message = installed == latest ? LF("当前已是最新公开版本（%@）。", release.tagName)
                    : LF("当前版本高于最新公开版本（%@）。", release.tagName)
            }
        } catch {
            message = LF("暂时无法检查更新：%@", error.localizedDescription)
            if manual { notices.post(.activity, title: "更新检查未完成", body: message, at: now, systemNotification: false) }
        }
    }
    nonisolated static func fetch() async throws -> [GitHubRelease] {
        var request = URLRequest(url: ReleaseCatalog.apiURL)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Orexin/\(OrexinRelease.versionTag)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw ModeError("GitHub 暂时不可用，请稍后重试。")
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }
}
