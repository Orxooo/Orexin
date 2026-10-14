// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryRecordsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var presentation: RecordPresentation
    @State private var search = ""
    @State private var filter = Category.all
    @State private var operationMessage = ""
    @State private var operationFailed = false
    @State private var showingClearConfirmation = false
    let availableWidth: CGFloat
    @FocusState private var searchFocused: Bool

    init(model: AppModel, availableWidth: CGFloat) {
        self.model = model; self.availableWidth = availableWidth
        _presentation = StateObject(wrappedValue: RecordPresentation(history: model.history,
            url: model.historyStore.url, twentyFourHour: model.appearance.twentyFourHour))
    }

    private enum Category: String, CaseIterable {
        case all = "全部", mode = "模式切换", screen = "显示器 / 电源", helper = "守护进程", alert = "异常告警"
        var token: String {
            switch self { case .all: "EVENT"; case .mode: "MODES"; case .screen: "HARDWARE"; case .helper: "DAEMON"; case .alert: "ALERTS" }
        }
        var color: Color {
            switch self { case .all: TerminalStyle.accent; case .mode: TerminalStyle.secondary; case .screen: TerminalStyle.accent; case .helper: TerminalStyle.signal; case .alert: TerminalStyle.warning }
        }
    }
    private struct StateTag {
        let title: String
        let color: Color
    }
    private struct PresentedEntry: Identifiable {
        let entry: HistoryEntry
        let category: Category
        let state: StateTag
        let descriptor: String
        let subsystem: String
        let searchable: String
        let time: String
        let date: String
        var id: UUID { entry.id }
    }
    @MainActor private final class RecordPresentation: ObservableObject {
        @Published private(set) var entries: [PresentedEntry] = []
        @Published private(set) var metadata: (size: String, modified: String) = ("", "")
        private var history: [HistoryEntry]
        private var presented: [PresentedEntry] = []
        private let url: URL?
        private let timeFormatter = DateFormatter()
        private var twentyFourHour: Bool
        private var query = ""
        private var filter = Category.all
        private var fileSize: NSNumber?
        private var fileModified: Date?
        private var storageFallback = (size: "未知", modified: "未知")

        init(history: [HistoryEntry], url: URL?, twentyFourHour: Bool) {
            self.history = history; self.url = url; self.twentyFourHour = twentyFourHour
            configureFormatter()
            rebuildEntries()
            refreshStorageMetadata()
        }
        func update(history updated: [HistoryEntry]) {
            guard history.count != updated.count || !zip(history, updated).allSatisfy({ pair in
                pair.0.id == pair.1.id && pair.0.date == pair.1.date && pair.0.text == pair.1.text
            }) else { return }
            history = updated
            rebuildEntries()
            refreshStorageMetadata()
        }
        func update(twentyFourHour updated: Bool) {
            guard twentyFourHour != updated else { return }
            twentyFourHour = updated
            configureFormatter()
            rebuildEntries()
        }
        func updateFormatting() {
            configureFormatter()
            rebuildEntries()
            formatStorageMetadata()
        }
        func refilter(search: String, category: Category) {
            query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            filter = category
            entries = presented.filter {
                (filter == .all || $0.category == filter) && (query.isEmpty || $0.searchable.localizedCaseInsensitiveContains(query))
            }
        }
        private func configureFormatter() {
            timeFormatter.locale = AppLanguage.selected.locale
            timeFormatter.timeZone = .current
            timeFormatter.dateFormat = twentyFourHour ? "HH:mm:ss" : "h:mm:ss a"
        }
        private func rebuildEntries() {
            presented = history.map { entry in
                let category = HistoryRecordsView.category(entry.text)
                let state = HistoryRecordsView.stateTag(entry.text)
                let descriptor = HistoryRecordsView.descriptor(entry.text)
                let subsystem = HistoryRecordsView.subsystem(entry.text)
                let searchable = entry.text + " " + L(entry.text) + " " + L(category.rawValue) + " " + category.token + " " + state.title + " " + descriptor + " " + subsystem + " " + entry.id.uuidString
                return PresentedEntry(entry: entry, category: category, state: state, descriptor: descriptor,
                    subsystem: subsystem, searchable: searchable, time: timeFormatter.string(from: entry.date),
                    date: entry.date.formatted(.dateTime.locale(AppLanguage.selected.locale).year().month(.abbreviated).day()))
            }
            refilter(search: query, category: filter)
        }
        private func refreshStorageMetadata() {
            fileSize = nil; fileModified = nil
            guard let url else {
                storageFallback = ("仅内存", "未配置本机文件")
                formatStorageMetadata(); return
            }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                storageFallback = FileManager.default.fileExists(atPath: url.path) ? ("暂无法读取", "暂无法读取") : ("尚未写入", "尚未写入文件")
                formatStorageMetadata(); return
            }
            storageFallback = ("未知", "未知")
            fileSize = attributes[.size] as? NSNumber
            fileModified = attributes[.modificationDate] as? Date
            formatStorageMetadata()
        }
        private func formatStorageMetadata() {
            metadata = (fileSize.map { ByteCountFormatter.string(fromByteCount: $0.int64Value, countStyle: .file) } ?? storageFallback.size,
                fileModified.map { $0.formatted(date: .abbreviated, time: .standard) } ?? storageFallback.modified)
        }
    }
    private static func category(_ text: String) -> Category {
        if ["失败", "温度保护触发", "温度保护已结束保活", "低于", "未确认", "无法", "错误", "异常"].contains(where: text.contains) { return .alert }
        if ["合盖", "开盖", "服务", "授权", "守护"].contains(where: text.contains) { return .helper }
        if ["显示器", "屏幕", "电量", "电源", "温度保护", "休眠请求", "系统即将休眠", "系统已唤醒"].contains(where: text.contains) { return .screen }
        if ["模式", "切换", "会话", "定时"].contains(where: text.contains) { return .mode }
        return .all
    }
    private static func stateTag(_ text: String) -> StateTag {
        if Self.category(text) == .alert { return StateTag(title: "WARNING", color: TerminalStyle.warning) }
        if text.contains("已取消") { return StateTag(title: "CANCELLED", color: TerminalStyle.muted) }
        if ["等待", "正在", "倒计时"].contains(where: text.contains) { return StateTag(title: "WAITING", color: TerminalStyle.amber) }
        if text.contains("已核验") { return StateTag(title: "VERIFIED", color: TerminalStyle.signal) }
        return StateTag(title: "RECORDED", color: TerminalStyle.muted)
    }
    private static func descriptor(_ text: String) -> String {
        if text.contains("温度") { return "THERMAL_GUARD" }
        if text.contains("电量") { return "BATTERY_EVENT" }
        if text.contains("命令") { return "COMMAND_TASK" }
        if text.contains("应用启动") { return "SYS_BOOT" }
        if text.contains("系统已唤醒") || text.contains("显示器已唤醒") { return "DISPLAY_WAKE" }
        if text.contains("系统即将休眠") || text.contains("显示器已休眠") { return "DISPLAY_SLEEP" }
        if text.contains("已核验") { return "MODE_VERIFY" }
        if text.contains("自动切换") || text.contains("自动触发") { return "AUTO_SWITCH" }
        if text.contains("切换") { return "MODE_SWITCH" }
        if text.contains("会话") { return "SESSION_EVENT" }
        switch Self.category(text) {
        case .helper: return "DAEMON_EVENT"
        case .screen: return "POWER_EVENT"
        case .alert: return "ALERT_EVENT"
        case .mode: return "MODE_EVENT"
        case .all: return "APP_EVENT"
        }
    }
    private static func subsystem(_ text: String) -> String {
        if text.contains("命令") { return "COMMAND_RUNNER" }
        if text.contains("温度") { return "THERMAL_GUARD" }
        if text.contains("电量") { return "POWER_DEFENSE" }
        switch Self.category(text) {
        case .mode: return "MODE_CONTROL"
        case .screen: return "POWER_EVENT"
        case .helper: return "DAEMON_SERVICE"
        case .alert: return "SAFETY_ALERT"
        case .all: return "APP_EVENT"
        }
    }
    private var timestampWidth: CGFloat { min(130, max(94, (availableWidth - 62) * 0.15)) }
    private var descriptorWidth: CGFloat { min(232, max(132, (availableWidth - 62) * 0.25)) }
    private var subsystemWidth: CGFloat { min(166, max(104, (availableWidth - 62) * 0.2)) }

    var body: some View {
        let metadata = presentation.metadata
        return VStack(alignment: .leading, spacing: 20) {
            toolbar
            auditFeed(fileSize: metadata.size)
            HStack(spacing: 12) {
                TerminalIcon(name: "terminal", size: 14).foregroundStyle(WorkStyle.ink)
                Text("LOCAL EVENT STREAM // JSON · UTF-8").font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
                Spacer(minLength: 0)
                Text(L("文件更新：") + metadata.modified).font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
            }.padding(.horizontal, 6)
        }
        .onReceive(model.$history) { presentation.update(history: $0) }
        .onReceive(model.appearance.$twentyFourHour) { presentation.update(twentyFourHour: $0) }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in presentation.updateFormatting() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in presentation.updateFormatting() }
        .onChange(of: search) { _, value in presentation.refilter(search: value, category: filter) }
        .onChange(of: filter) { _, value in presentation.refilter(search: search, category: value) }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                TerminalIcon(name: "internaldrive", size: 18)
                    .frame(width: 29, height: 29).background(TerminalStyle.silver)
                    .overlay(Rectangle().strokeBorder(WorkStyle.line))
                Text(L("仅保存在这台 Mac")).font(.system(size: 12, weight: .semibold)).fixedSize()
                Text("// " + (model.historyStore.url?.path ?? L("未配置本机日志文件")))
                    .font(TerminalStyle.mono(10)).foregroundStyle(WorkStyle.muted)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 0)
                Button(action: export) {
                    TerminalLabel("导出记录 // JSON", systemImage: "square.and.arrow.down").font(.system(size: 11))
                }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                Button(role: .destructive) {
                    showingClearConfirmation = true
                    operationMessage = ""
                } label: {
                    TerminalLabel("清空日志 // CLEAR", systemImage: "trash").font(.system(size: 11))
                }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                    .disabled(model.history.isEmpty || model.historyStore.url == nil)
            }
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            if showingClearConfirmation { clearConfirmation }
            HStack(spacing: 2) {
                ForEach(Category.allCases, id: \.self) { category in
                    categoryButton(category)
                }
            }.padding(3).background(TerminalStyle.recess)
                .overlay(Rectangle().strokeBorder(WorkStyle.line))
            HStack(spacing: 9) {
                TerminalIcon(name: "magnifyingglass", size: 14).foregroundStyle(WorkStyle.muted)
                TextField(L("搜索事件、类别、状态或 ID…"), text: $search).textFieldStyle(.plain)
                    .font(WorkType.body).focused($searchFocused).accessibilityLabel("搜索运行记录")
                if !search.isEmpty {
                    Button { search = "" } label: { TerminalIcon(name: "xmark", size: 11) }
                        .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                        .accessibilityLabel("清除搜索")
                }
                Button { searchFocused = true } label: {
                    Text("⌘ K").font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
                        .padding(3).background(TerminalStyle.silver)
                }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                    .keyboardShortcut("k", modifiers: .command).accessibilityLabel("聚焦日志搜索")
            }.padding(.horizontal, 12).frame(width: min(325, max(240, availableWidth - 34)), height: 38)
                .background(TerminalStyle.recess).overlay(Rectangle().strokeBorder(WorkStyle.line))
            if !operationMessage.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    TerminalIcon(name: operationFailed ? "exclamationmark.triangle" : "info.circle", size: 13)
                    Text(L(operationMessage)).fixedSize(horizontal: false, vertical: true)
                }.font(WorkType.caption).foregroundStyle(operationFailed ? TerminalStyle.warning : WorkStyle.muted)
            }
        }.padding(16).background(TerminalStyle.recess)
            .overlay(Rectangle().strokeBorder(WorkStyle.line.opacity(0.75)))
    }

    private var clearConfirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("清空运行记录？")).font(.system(size: 15, weight: .semibold))
                Text(LF("将从本机日志文件中移除全部 %d 条记录；此操作无法撤销。可先导出 JSON 留存。", model.history.count))
                .font(WorkType.body).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("取消")) { showingClearConfirmation = false }
                    .buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                Button(L("确认清空"), role: .destructive, action: clear)
                    .buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkStyle.surface).overlay(Rectangle().strokeBorder(TerminalStyle.warning.opacity(0.7)))
    }

    private func categoryButton(_ category: Category) -> some View {
        let selected = filter == category
        return TerminalSelectionButton(selected: selected, action: { filter = category }) {
            HStack(spacing: 5) {
                Rectangle().fill(category.color).frame(width: 6, height: 6)
                Text(L(category.rawValue)).font(.system(size: 10, weight: selected ? .semibold : .regular))
                Text("// " + (category == .all ? "ALL (\(model.history.count))" : category.token)).font(TerminalStyle.mono(8))
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
        }.accessibilityLabel(category.rawValue)
    }

    private func auditFeed(fileSize: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Rectangle().fill(TerminalStyle.accent).frame(width: 9, height: 9)
                    .shadow(color: TerminalStyle.accent.opacity(0.5), radius: 5)
                Text("AVIONICS AUDIT FEED").foregroundStyle(TerminalStyle.accent)
                Rectangle().fill(WorkStyle.line).frame(width: 1, height: 18)
                Text("LOCAL EVENT OBSERVER").foregroundStyle(WorkStyle.muted).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("ENCODING: UTF-8").foregroundStyle(WorkStyle.muted)
                HStack(spacing: 5) {
                    Rectangle().fill(TerminalStyle.signal).frame(width: 6, height: 6)
                    Text("LOCAL RECORDS").foregroundStyle(TerminalStyle.signal)
                }
            }.font(TerminalStyle.mono(9)).padding(.horizontal, 16).frame(height: 45)
                .background(WorkStyle.surface)
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            tableHeader
            if presentation.entries.isEmpty {
                Text(L(model.history.isEmpty ? "还没有运行记录；切换模式后会显示在这里。" : "没有匹配的运行记录。"))
                    .font(WorkType.body).foregroundStyle(WorkStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(30)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(presentation.entries) { entry in
                    historyRow(entry)
                    Rectangle().fill(WorkStyle.line.opacity(0.5)).frame(height: 1)
                }
            }
            HStack(spacing: 10) {
                Text("LOG JOURNAL: \(HistoryStore.maximumEntries) ENTRIES MAX")
                Spacer(minLength: 0)
                Text(LF("显示 %d / %d", presentation.entries.count, model.history.count))
                Text("// STORAGE: " + fileSize).foregroundStyle(TerminalStyle.accent)
            }.font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
                .padding(.horizontal, 16).frame(height: 38).background(WorkStyle.surface)
        }.background(TerminalStyle.recess)
            .overlay(Rectangle().strokeBorder(WorkStyle.line))
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text("TIMESTAMP").frame(width: timestampWidth, alignment: .leading)
            Text("EVENT DESCRIPTOR").frame(width: descriptorWidth, alignment: .leading)
            Text("PAYLOAD & RUNTIME STATE").frame(maxWidth: .infinity, alignment: .leading)
            Text("SUBSYSTEM TOKEN").frame(width: subsystemWidth, alignment: .trailing)
        }.font(TerminalStyle.mono(8)).foregroundStyle(WorkStyle.muted).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 16).frame(height: 29).background(WorkStyle.surface.opacity(0.65))
            .overlay(alignment: .bottom) { Rectangle().fill(WorkStyle.line).frame(height: 1) }
    }

    private func historyRow(_ row: PresentedEntry) -> some View {
        let entry = row.entry
        let category = row.category
        let state = row.state
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(row.time).font(TerminalStyle.mono(15)).fontWeight(.semibold)
                    .foregroundStyle(category == .alert ? TerminalStyle.warning : WorkStyle.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(row.date)
                    .font(TerminalStyle.mono(9)).foregroundStyle(WorkStyle.muted)
            }.frame(width: timestampWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Rectangle().fill(category.color).frame(width: 6, height: 6)
                    Text(row.descriptor).font(TerminalStyle.mono(9)).foregroundStyle(category.color)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }.padding(.horizontal, 5).padding(.vertical, 3).background(TerminalStyle.silver)
                Text("ID: " + entry.id.uuidString.prefix(8)).font(TerminalStyle.mono(8)).foregroundStyle(WorkStyle.muted)
                    .textSelection(.enabled)
            }.frame(width: descriptorWidth, alignment: .leading)
                .accessibilityLabel(LF("根据记录内容分类的事件：%@", row.descriptor))
            Text(L(entry.text)).font(.system(size: 12)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 7) {
                Text(row.subsystem).font(TerminalStyle.mono(8)).foregroundStyle(category.color)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(TerminalStyle.silver)
                    .overlay(alignment: .leading) { Rectangle().fill(category.color).frame(width: 2) }
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(state.title).font(TerminalStyle.mono(8)).foregroundStyle(state.color)
            }.frame(width: subsystemWidth, alignment: .trailing)
                .accessibilityLabel(LF("根据记录内容分类的状态：%@", state.title))
        }.padding(.horizontal, 16).padding(.vertical, 16)
    }

    private func clear() {
        do {
            try model.clearHistoryRecords()
            showingClearConfirmation = false
            operationFailed = false
            operationMessage = "已清空本机运行记录。"
        } catch {
            operationFailed = true
            operationMessage = "清空失败，现有记录已保留：" + error.localizedDescription
        }
    }
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Orexin-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(model.history).write(to: url, options: .atomic)
            operationFailed = false
            operationMessage = LF("已导出全部 %d 条运行记录。", model.history.count)
        } catch {
            operationFailed = true
            operationMessage = "导出失败：" + error.localizedDescription
        }
    }
}

extension AppModel {
    func clearHistoryRecords() throws {
        try historyStore.clear()
        history = historyStore.entries
    }
}
