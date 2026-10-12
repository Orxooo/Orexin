// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

struct AboutSoftwareView: View {
    let availableWidth: CGFloat
    @State private var checking = false
    @State private var updateMessage = ""
    @State private var releaseURL: URL?

    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if availableWidth > 850 {
                HStack(alignment: .top, spacing: 16) {
                    appInformation.frame(width: (availableWidth - 16) * 0.42)
                    communityInformation.frame(width: (availableWidth - 16) * 0.58)
                }
            } else {
                appInformation
                communityInformation
            }

            updates
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appInformation: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ApplicationBadge().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Orexin").font(.system(size: 28, weight: .semibold))
                        Text("POWER TERMINAL // macOS").font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.accent)
                        Text("\(OrexinRelease.displayVersion) · #\(build)").font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted)
                    }
                }
                Text(L("Orexin 在工作时保持 Mac 唤醒，并在会话或任务结束后恢复休眠。"))
                    .font(.system(size: 12)).foregroundStyle(TerminalStyle.muted)
                Text(L("开源软件 · GPL-3.0-only · © 2026 Orxooo"))
                    .font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.signal)
                HStack(spacing: 10) {
                    Button(L("GitHub 主页")) { NSWorkspace.shared.open(OrexinRelease.repositoryURL) }
                    Button(L("复制仓库地址")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(OrexinRelease.repositoryURL.absoluteString, forType: .string)
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading).padding(18).terminalSurface()
    }

    private var communityInformation: some View {
        VStack(alignment: .leading, spacing: 18) {
            TerminalLabel("项目与反馈", systemImage: "globe").font(.system(size: 16, weight: .semibold))
            Rectangle().fill(TerminalStyle.line.opacity(0.6)).frame(height: 1)
            communityLink("版本下载", code: "RELEASES", url: OrexinRelease.releasesURL)
            communityLink("提交问题", code: "ISSUES", url: OrexinRelease.issuesURL)
        }.frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading).padding(18).terminalSurface()
    }

    private func communityLink(_ title: String, code: String, url: URL) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L(title)).font(.system(size: 13, weight: .semibold))
                Text(code).font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.accent)
            }
            Spacer(minLength: 0)
            Button(L(title)) { NSWorkspace.shared.open(url) }
                .font(.system(size: 11))
        }.padding(12).background(TerminalStyle.recess)
    }

    private var updates: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TerminalLabel("软件更新", systemImage: "arrow.clockwise").font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("GITHUB RELEASES").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                }
                Text(L("手动检查 GitHub 发布版本。Preview 版本也会检查预发布更新。"))
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                HStack(spacing: 10) {
                    Button(L(checking ? "检查中…" : "检查更新")) { Task { await checkForUpdates() } }
                        .disabled(checking)
                    if let releaseURL { Button(L("查看发布页")) { NSWorkspace.shared.open(releaseURL) } }
                    Spacer(minLength: 0)
                }
                if !updateMessage.isEmpty {
                    Text(L(updateMessage)).font(.system(size: 11)).foregroundStyle(TerminalStyle.signal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(18).terminalSurface()
    }

    @MainActor private func checkForUpdates() async {
        checking = true
        defer { checking = false }
        releaseURL = nil
        do {
            var request = URLRequest(url: ReleaseCatalog.apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Orexin/\(OrexinRelease.versionTag)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                updateMessage = "无法读取 GitHub 的响应。"; return
            }
            if response.statusCode == 404 {
                updateMessage = "Orexin 仓库尚未发布版本。"; return
            }
            guard response.statusCode == 200 else {
                updateMessage = LF("检查失败：GitHub 返回 HTTP %d。", response.statusCode); return
            }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard let release = ReleaseCatalog.latest(in: releases, includePreviews: !OrexinRelease.channel.isEmpty),
                  let latest = release.version, let current = ReleaseVersion(OrexinRelease.versionTag) else {
                updateMessage = "Orexin 仓库尚未发布版本。"; return
            }
            releaseURL = release.url
            updateMessage = current < latest
                ? LF("发现新版本：%@", release.tagName) : LF("当前已是最新公开版本（%@）。", release.tagName)
        } catch {
            updateMessage = LF("暂时无法连接 GitHub：%@", error.localizedDescription)
        }
    }
}
