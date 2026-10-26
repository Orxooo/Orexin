// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI

struct AboutSoftwareView: View {
    @ObservedObject var updates: UpdateMonitor
    let availableWidth: CGFloat
    private var checking: Bool { updates.checking }
    private var updateMessage: String { updates.message }
    private var releaseURL: URL? { updates.releaseURL }

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

            updateSection
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

    private var updateSection: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TerminalLabel("软件更新", systemImage: "arrow.clockwise").font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("GITHUB RELEASES").font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                }
                Text(L("启动后及每 6 小时自动检查更新，也可手动检查。Preview 版本会检查预发布更新。"))
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                HStack(spacing: 10) {
                    Button(L(checking ? "检查中…" : "检查更新")) { Task { await updates.check(manual: true) } }
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

}
