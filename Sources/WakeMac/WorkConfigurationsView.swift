// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WakeMacCore

struct WorkProfilePicker: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: WorkProfileStore
    var body: some View {
        TerminalPicker("工作配置", selection: $model.selectedWorkProfileID,
            choices: [TerminalChoice(L("默认命令收尾"), UUID?.none)]
                + store.profiles.map { TerminalChoice($0.name, Optional($0.id)) }, localizeChoices: false)
        .onChange(of: store.profiles) { _, profiles in
            if let id = model.selectedWorkProfileID, !profiles.contains(where: { $0.id == id }) { model.selectedWorkProfileID = nil }
        }
    }
}

struct WorkConfigurationsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: WorkProfileStore
    @State private var editing: WorkProfile?
    @State private var preview: ConfigurationPreview?
    @State private var importMode = ConfigurationImportMode.merge
    @State private var message = ""
    @State private var previewAfter = true
    @State private var inspectedScript: String?
    init(model: AppModel) { self.model = model; store = model.profiles }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TerminalLabel("工作配置 // WORK POLICIES", systemImage: "slider.horizontal.3").font(TerminalStyle.mono(13))
                    Spacer()
                    Button(L("新建配置")) { editing = WorkProfile(name: L("新工作配置")) }
                }
                Text(L("复用工作模式、屏幕需求、期限与成功 / 失败 / 超时收尾。选择配置后，任务仍使用同一套保活协调与保护规则。"))
                    .font(WorkType.caption).foregroundStyle(TerminalStyle.secondary)
                if store.profiles.isEmpty { Text(L("尚无工作配置。新建一个，或导入可版本管理的 JSON 文件。")).foregroundStyle(TerminalStyle.muted) }
                ForEach(store.profiles) { profile in profileRow(profile) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
            VStack(alignment: .leading, spacing: 12) {
                TerminalLabel("可移植配置 // PORTABLE CONFIGURATION", systemImage: "doc.text").font(TerminalStyle.mono(13))
                Text(L("导出规则与工作配置，不含任务、进程、凭据或授权。导入先预览；同一 UUID 按导入版本更新。导入规则保持关闭，脚本需要在本机重新启用。"))
                    .font(WorkType.caption).foregroundStyle(TerminalStyle.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { configurationActions }
                    VStack(alignment: .leading, spacing: 12) { configurationActions }
                }
                if !message.isEmpty { Text(L(message)).font(WorkType.caption).foregroundStyle(TerminalStyle.amber).textSelection(.enabled) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
        }.frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $editing) { profile in
            WorkProfileEditor(profile: profile) { profile in
                do { try store.save(profile); editing = nil; message = "配置已保存；任务开始时采用配置快照。" }
                catch { message = error.localizedDescription }
            }
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("导入预览")).font(TerminalStyle.mono(13))
                    ForEach(preview.changes, id: \.self) { Text(L($0)).font(WorkType.caption).textSelection(.enabled) }
                    TerminalSegmentedPicker(title: "配置内容", selection: $previewAfter,
                        choices: [TerminalChoice("导入前", false), TerminalChoice("应用后", true)])
                    ScrollView([.vertical, .horizontal]) {
                        Text(previewAfter ? preview.afterJSON : preview.beforeJSON).font(TerminalStyle.mono(11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 330).padding(10).background(TerminalStyle.recess)
                    HStack {
                        Button(L("取消")) { self.preview = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(L("应用此配置")) {
                            do { try model.applyWorkConfiguration(preview); message = "已导入。请到自动规则启用所需规则；脚本授权单独确认。"; self.preview = nil }
                            catch { message = error.localizedDescription; self.preview = nil }
                        }
                    }
                }.padding(24).frame(width: 720).background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle())
            }
        }
        .sheet(isPresented: Binding(get: { inspectedScript != nil }, set: { if !$0 { inspectedScript = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("脚本内容（只读）")).font(TerminalStyle.mono(13))
                ScrollView([.vertical, .horizontal]) { Text(inspectedScript ?? "").font(TerminalStyle.mono(11)).textSelection(.enabled) }.frame(height: 420)
                Button(L("关闭")) { inspectedScript = nil }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 700).background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink)
        }
    }
    @ViewBuilder private var configurationActions: some View {
        Button(action: exportFile) { Text(L("导出 JSON…")).frame(width: 150) }
        TerminalPicker("导入方式", selection: $importMode,
            choices: [TerminalChoice("合并", .merge), TerminalChoice("替换全部", .replace)], controlHeight: 36)
            .frame(width: 180)
        Button(action: importFile) { Text(L("选择文件并预览…")).frame(width: 150) }
    }
    private func profileRow(_ profile: WorkProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.name).font(TerminalStyle.mono(13))
                Spacer()
                Text("\(profile.mode.rawValue) / \(profile.screen.rawValue)").font(TerminalStyle.mono(11)).foregroundStyle(TerminalStyle.accent)
                Button(L("编辑")) { editing = profile }
                Button(L("删除")) {
                    do { try store.replace(store.profiles.filter { $0.id != profile.id }, revoke: [profile.id]) }
                    catch { message = error.localizedDescription }
                }
            }
            Text(profile.id.uuidString).font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted).textSelection(.enabled)
            Text(LF("成功：%@ · 失败 / 超时：释放保活 · 期限：%@", L(profile.success.teardown == .sleepOnSuccess ? "全部成功后倒计时休眠" : "释放保活"), profile.timeoutSeconds.map { LF("%.0f 秒", $0.rounded(.towardZero)) } ?? L("不限")))
                .font(WorkType.caption).foregroundStyle(TerminalStyle.secondary)
            if !profile.scriptPaths.isEmpty {
                ForEach(profile.scriptPaths, id: \.self) { path in
                    HStack { Text(path).textSelection(.enabled); Spacer(); Button(L("查看脚本")) {
                        do {
                            _ = try store.fingerprint(profile)
                            inspectedScript = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
                        } catch { message = error.localizedDescription }
                    } }
                        .font(TerminalStyle.mono(10))
                }
                HStack {
                    Text(L("允许此配置在本机执行上述脚本（内容变化后需重新启用）")).font(WorkType.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Toggle(L("允许此配置在本机执行上述脚本（内容变化后需重新启用）"), isOn: Binding(get: { store.hooksEnabled(profile) }, set: { enabled in
                        do { try store.setHooksEnabled(enabled, profile: profile); message = enabled ? "已启用本机结果脚本。" : "脚本已停用。" }
                        catch { message = error.localizedDescription }
                    })).toggleStyle(TerminalSwitchStyle())
                }
            }
        }.padding(12).background(TerminalStyle.recess)
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "orexin-work.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportWorkConfiguration().write(to: url, options: .atomic); message = L("已导出：") + url.path }
        catch { message = error.localizedDescription }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { preview = try model.previewWorkConfiguration(Data(contentsOf: url), mode: importMode) }
        catch { message = L("导入未应用：") + error.localizedDescription }
    }
}

struct WorkProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: WorkProfile
    var save: (WorkProfile) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("工作配置")).font(TerminalStyle.mono(13))
            TextField(L("名称"), text: $profile.name).textFieldStyle(TerminalTextFieldStyle())
            HStack {
                TerminalPicker("工作模式", selection: $profile.mode,
                    choices: [TerminalChoice("桌面工作", .desk), TerminalChoice("后台工作", .background)])
                TerminalPicker("屏幕", selection: $profile.screen,
                    choices: [TerminalChoice("系统闲置", .idle), TerminalChoice("最低亮度", .dim), TerminalChoice("保持亮起", .awake)])
            }
            HStack {
                Text(L("设置任务期限")); Spacer()
                Toggle(L("设置任务期限"), isOn: Binding(get: { profile.timeoutSeconds != nil }, set: { profile.timeoutSeconds = $0 ? 3600 : nil }))
                    .toggleStyle(TerminalSwitchStyle())
            }
            if profile.timeoutSeconds != nil {
                HStack { Text(L("秒（1–604800）")); TextField(L("秒"), value: Binding(get: { profile.timeoutSeconds ?? 3600 }, set: { profile.timeoutSeconds = $0 }), format: .number).textFieldStyle(TerminalTextFieldStyle()) }
            }
            outcomeEditor("成功", outcome: $profile.success, allowsSleep: true)
            outcomeEditor("失败", outcome: $profile.failure, allowsSleep: false)
            outcomeEditor("超时", outcome: $profile.timeout, allowsSleep: false)
            Text(L("脚本使用 /bin/zsh -f 执行，最多 30 秒；不接收终端输入，不保存输出。保护或全局停止会终止结果脚本，原工作命令继续。保存后须回到列表明确启用脚本。"))
                .font(WorkType.caption).foregroundStyle(TerminalStyle.secondary)
            if let error = profile.validationError { Text(L(error)).foregroundStyle(TerminalStyle.amber).font(WorkType.caption) }
            HStack { Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L("保存")) { save(profile) }.disabled(profile.validationError != nil) }
        }.padding(24).frame(width: 650).background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle())
    }
    private func outcomeEditor(_ title: String, outcome: Binding<WorkOutcome>, allowsSleep: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L(title)).font(TerminalStyle.mono(13))
                if allowsSleep {
                    TerminalPicker("收尾", selection: outcome.teardown,
                        choices: [TerminalChoice("释放保活", .restore), TerminalChoice("全部成功后休眠", .sleepOnSuccess)])
                } else { Text(L("释放保活")).font(WorkType.caption) }
                Text(L("通知")).font(WorkType.caption)
                Toggle(L("通知"), isOn: outcome.notify).toggleStyle(TerminalSwitchStyle())
            }
            HStack {
                TextField(L("可选本地 zsh 脚本的绝对路径"), text: Binding(get: { outcome.wrappedValue.scriptPath ?? "" }, set: { outcome.wrappedValue.scriptPath = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(TerminalTextFieldStyle())
                Button(L("选择…")) {
                    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK { outcome.wrappedValue.scriptPath = panel.url?.path }
                }
            }
        }.padding(12).background(TerminalStyle.recess)
    }
}
