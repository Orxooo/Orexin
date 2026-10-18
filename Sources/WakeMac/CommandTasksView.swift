// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import SwiftUI
import WakeMacCore

enum TaskManagementSection: String, CaseIterable {
    case tasks = "任务列表", run = "运行命令", configurations = "工作配置", integrations = "外部接入"
    var code: String { switch self { case .tasks: "TASKS"; case .run: "RUN"; case .configurations: "POLICIES"; case .integrations: "CONNECT" } }
}

struct CommandTasksView: View {
    @ObservedObject var model: AppModel
    @Binding var command: String
    @Binding var directory: String
    @Binding var section: TaskManagementSection
    let availableWidth: CGFloat
    @State private var preflightBusy = false
    @State private var preflightPassed: Bool?
    @State private var preflightMessage = ""
    @State private var logTail = ""
    @State private var logError = ""
    @State private var mounted = false
    @State private var windowVisible = false
    @State private var directoryValid = false
    @State private var selectedLogURL: URL?
    @State private var showTaskLog = false

    init(model: AppModel, command: Binding<String>, directory: Binding<String>, availableWidth: CGFloat,
         section: Binding<TaskManagementSection>) {
        self.model = model; _command = command; _directory = directory; self.availableWidth = availableWidth; _section = section
    }
    private var hasCommand: Bool { !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func refreshDirectoryValidity() {
        var folder: ObjCBool = false
        directoryValid = FileManager.default.fileExists(atPath: (directory as NSString).expandingTildeInPath, isDirectory: &folder) && folder.boolValue
    }
    private var canRun: Bool { hasCommand && directoryValid && !model.busy && !preflightBusy }
    private var showsLog: Bool { section == .run || showTaskLog }
    private var isVisible: Bool { mounted && windowVisible && showsLog }
    private var currentLogURL: URL? { showTaskLog ? selectedLogURL : model.jobLogURL }
    private var logRequest: WorkRequestRecord? {
        guard let url = currentLogURL else { return nil }
        return model.workRequests.records.first { model.commandLogs[$0.id] == url }
    }
    private var logRunning: Bool { logRequest.map { model.runningCommandIDs.contains($0.id) } ?? false }
    private var logRefreshID: LogRefreshID { .init(path: currentLogURL?.path, running: logRunning, visible: isVisible, displayed: showsLog) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionNavigation
            switch section {
            case .tasks:
                WorkRequestsView(model: model, onShowLog: { url in
                    selectedLogURL = url; logTail = ""; logError = ""; showTaskLog = true
                }, onRunCommand: { section = .run }, onConnect: { section = .integrations })
            case .run:
                if availableWidth > 840 {
                    HStack(alignment: .top, spacing: 16) {
                        executionColumn.frame(width: (availableWidth - 16) * 0.64)
                        observationColumn.frame(width: (availableWidth - 16) * 0.36)
                    }
                } else {
                    executionColumn
                    observationColumn
                }
            case .integrations:
                TaskIntegrationsView(model: model, availableWidth: availableWidth)
            case .configurations:
                WorkConfigurationsView(model: model)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(CommandWindowVisibilityProbe { windowVisible = $0 }.frame(width: 0, height: 0))
            .sheet(isPresented: $showTaskLog) {
                VStack(alignment: .leading, spacing: 16) {
                    observationColumn
                    HStack { Spacer(); Button(L("关闭")) { showTaskLog = false }.keyboardShortcut(.cancelAction) }
                }.padding(24).frame(width: 640).background(TerminalStyle.paper)
                    .foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle())
            }
            .onAppear { mounted = true; refreshDirectoryValidity() }
            .onDisappear { mounted = false }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshDirectoryValidity() }
            .onChange(of: windowVisible) { _, visible in if visible { refreshDirectoryValidity() } }
            .onChange(of: command) { _, _ in resetPreflight() }
            .onChange(of: directory) { _, _ in resetPreflight(); refreshDirectoryValidity() }
            .task(id: logRefreshID) {
                guard showsLog else { return }
                // Load once on selection even before macOS delivers window visibility.
                // Ongoing polling remains limited to a visible log workspace.
                await refreshLog()
                while logRunning && isVisible && !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard logRunning, isVisible, !Task.isCancelled else { return }
                    await refreshLog()
                }
            }
    }
    private var sectionNavigation: some View {
        HStack(spacing: 2) {
            ForEach(TaskManagementSection.allCases, id: \.self) { item in
                TerminalSelectionButton(selected: section == item, action: { section = item }) {
                    HStack(spacing: 5) {
                        Text(L(item.rawValue)).font(.system(size: 12, weight: section == item ? .semibold : .regular))
                        if availableWidth >= 760 {
                            Text("// " + item.code).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                                .accessibilityHidden(true)
                        }
                    }
                }.accessibilityLabel(L(item.rawValue))
            }
        }.padding(3).background(TerminalStyle.recess)
            .overlay(Rectangle().strokeBorder(WorkStyle.line))
    }
    private var executionColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            executionProtocol
            console
            WorkNote(text: "支持多个前台命令并行执行；外部任务通过 CLI 明确报告完成，不推测其他应用的任务状态。")
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
            DisclosureGroup("运行前须知与休眠规则") {
                Text(L("使用非交互的前台命令，不支持密码输入或 & / nohup 后台任务。所有重叠请求成功且没有其他保活来源时，倒计时 60 秒；失败、取消、失联或到期时只释放保活。日志保存 stdout 和 stderr 的前 5 MB。"))
                    .font(WorkType.caption).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }.font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
            if !model.convenienceMessage.isEmpty { WorkNote(text: model.convenienceMessage) }
        }
    }
    private var executionProtocol: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                TerminalLabel("运行一次，完成后休眠", systemImage: "terminal").font(WorkType.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("EXECUTE AND REST").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
            }
            Text(L("每个命令独立保活并记录退出码；全部成功后才按收尾策略处理，手动模式与会话继续保留。")).font(WorkType.caption)
                .foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(model.selectedWorkProfileID == nil ? "SUCCESS: 60s" : "PROFILE POLICY").foregroundStyle(TerminalStyle.accent)
                Text(L("FAIL: 不休眠")).foregroundStyle(TerminalStyle.secondary)
                Text(L("STDIN: 非交互")).foregroundStyle(TerminalStyle.muted)
            }.font(TerminalStyle.mono(9))
            WorkProfilePicker(model: model, store: model.profiles)
            HStack {
                TerminalLabel("工作目录 // WORKING DIRECTORY", systemImage: "folder").font(WorkType.compactCaption).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 0)
                Text(L(directoryValid ? "PATH VALID" : "请选择有效目录")).font(.system(size: 9))
                    .foregroundStyle(directoryValid ? TerminalStyle.signal : TerminalStyle.amber)
            }
            HStack(spacing: 8) {
                Text("$").font(TerminalStyle.mono(14)).foregroundStyle(TerminalStyle.muted).accessibilityHidden(true)
                TextField(L("工作目录"), text: $directory).textFieldStyle(.plain).font(TerminalStyle.mono(12))
                    .accessibilityLabel(L("命令工作目录"))
                Button(L("选择目录…")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { directory = url.path; refreshDirectoryValidity() }
                }.workKeyboardFocus(radius: 0)
            }.padding(10).background(TerminalStyle.recess)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
    }
    private var console: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TerminalIcon(name: "terminal", size: 13).foregroundStyle(TerminalStyle.accent)
                Text("/bin/zsh -l").font(TerminalStyle.mono(10))
                Text(directory).font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Text("COMMAND DRAFT").font(TerminalStyle.mono(9))
                    .foregroundStyle(model.jobRunning ? TerminalStyle.signal : TerminalStyle.muted)
            }.padding(12).background(TerminalStyle.silver.opacity(0.3))
            Rectangle().fill(TerminalStyle.line).frame(height: 1)
            ZStack(alignment: .topLeading) {
                CommandSourceEditor(text: $command, editable: true).frame(height: 230).clipped()
                if command.isEmpty {
                    Text(L("# 输入多行 zsh 命令\n# 成功后倒计时休眠；失败时保留现场"))
                        .font(TerminalStyle.mono(12)).foregroundStyle(TerminalStyle.steel).padding(.leading, 47).padding(.top, 16)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }.overlay(CRTLines())
            HStack(spacing: 8) {
                Text("❯").font(TerminalStyle.mono(13)).foregroundStyle(TerminalStyle.accent)
                TerminalCursor().frame(width: 8, height: 15).allowsHitTesting(false).accessibilityHidden(true)
                Text(L("在上方输入命令，点击下方运行")).font(WorkType.compactCaption).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 0)
            }.padding(.horizontal, 15).padding(.vertical, 10).background(TerminalStyle.recess)
            HStack {
                Text("LINES: \(command.components(separatedBy: "\n").count)").font(TerminalStyle.mono(8))
                Spacer(minLength: 0)
                Text(L(preflightPassed == true ? "ZSH SYNTAX: 已通过" : "ZSH · 非交互执行")).font(TerminalStyle.mono(8))
            }.foregroundStyle(TerminalStyle.muted).padding(12).background(TerminalStyle.recess)
            if !preflightMessage.isEmpty {
                Text(L(preflightMessage)).font(TerminalStyle.mono(10)).foregroundStyle(preflightPassed == true ? TerminalStyle.signal : TerminalStyle.warning)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).padding(12).background(TerminalStyle.recess)
            }
            Rectangle().fill(TerminalStyle.line).frame(height: 1)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Circle().fill(model.jobRunning ? TerminalStyle.signal : TerminalStyle.amber).frame(width: 5, height: 5)
                        Text(L(model.jobStatus)).font(.system(size: 11, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L(model.jobRunning ? "任务继续运行" : "等待手动运行")).font(.system(size: 9)).foregroundStyle(TerminalStyle.muted)
                }
                Spacer(minLength: 0)
                Button(L(preflightBusy ? "检查中…" : "语法预检")) { Task { await preflight() } }
                    .workKeyboardFocus(radius: 0).disabled(preflightBusy || !hasCommand)
                    .help("只运行 zsh -n，不执行命令，不检查依赖或登录环境。")
                Button {
                    let submitted = command, folder = directory
                    Task { await model.startJob(command: submitted, directory: folder) }
                } label: {
                    TerminalLabel("运行，成功后休眠", systemImage: "play.fill").font(.system(size: 12, weight: .semibold))
                }.buttonStyle(TerminalButtonStyle(prominent: true)).workKeyboardFocus(radius: 0).disabled(!canRun)
            }.padding(12).background(TerminalStyle.surface)
            if model.jobRunning || model.automation.jobSleepAt != nil {
                Button(L("取消完成后休眠，命令继续"), action: model.cancelAutomaticSleep).workKeyboardFocus(radius: 0).padding(12)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
    }
    private var observationColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TerminalLabel("任务执行日志", systemImage: "doc.text").font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("STDOUT / STDERR").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                }
                if let request = logRequest {
                    Text(request.spec.title).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(L(logRunning ? "命令运行中" : request.state.displayTitle))
                        Spacer()
                        if let code = request.exitCode { Text("EXIT \(code)") }
                    }.font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(logText).font(TerminalStyle.mono(10)).foregroundStyle(logError.isEmpty ? TerminalStyle.ink : TerminalStyle.warning)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            Color.clear.frame(height: 1).id("log-end")
                        }.padding(10)
                    }.frame(height: 268).background(TerminalStyle.recess)
                        .onChange(of: logTail) { _, _ in if logRunning { proxy.scrollTo("log-end", anchor: .bottom) } }
                }
                Text(L("最多显示末尾 16 KiB / 80 行")).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                if let url = currentLogURL {
                    Button(L("在 Finder 查看完整日志")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }.workKeyboardFocus(radius: 0)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).terminalSurface()
        }
    }
    private var logText: String {
        if !logError.isEmpty { return L(logError) }
        if !logTail.isEmpty { return logTail }
        return L(logRunning ? "命令运行中，等待标准输出或错误输出。" : currentLogURL == nil ? "尚未启动命令。任务输出会在运行后显示。" : "日志没有输出内容。")
    }
    private func resetPreflight() {
        if preflightPassed != nil { preflightPassed = nil }
        if !preflightMessage.isEmpty { preflightMessage = "" }
    }
    private func preflight() async {
        guard !preflightBusy else { return }
        let submitted = command, folder = directory
        preflightBusy = true
        defer { preflightBusy = false }
        let diagnostic = await Task.detached(priority: .utility) { () -> String? in
            do { try CommandSyntaxPreflight.check(command: submitted, directory: folder); return nil }
            catch { return error.localizedDescription }
        }.value
        guard command == submitted, directory == folder else { return }
        preflightPassed = diagnostic == nil
        preflightMessage = diagnostic.map { LF("语法检查未通过：\n%@", $0) } ?? "zsh -n 语法检查通过；未执行命令。依赖、路径参数和运行结果仍需实际运行验证。"
    }
    private func refreshLog() async {
        guard let url = currentLogURL else { logTail = ""; logError = ""; return }
        let result = await Task.detached(priority: .utility) { () -> (String, String) in
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let end = try handle.seekToEnd(), limit: UInt64 = 16_384
                let offset = end > limit ? end - limit : 0
                try handle.seek(toOffset: offset)
                let data = try handle.read(upToCount: Int(limit)) ?? Data()
                var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
                if offset > 0, !lines.isEmpty { lines.removeFirst() }
                return (lines.suffix(80).joined(separator: "\n"), "")
            } catch { return ("", LF("暂时无法读取日志：%@", error.localizedDescription)) }
        }.value
        guard !Task.isCancelled, currentLogURL == url else { return }
        logTail = result.0; logError = result.1
    }
    private struct LogRefreshID: Equatable { var path: String?; var running: Bool; var visible: Bool; var displayed: Bool }
}

/// Native scrolling keeps logical line numbers aligned with wrapped editor text.
private struct CommandSourceEditor: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: proposal.height ?? 330)
    }
    func makeNSView(context: Context) -> NSScrollView {
        // The ruler uses TextKit 1. Construct that stack directly instead of
        // forcing a factory-created TextKit 2 view into compatibility mode while drawing.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 330), textContainer: container)
        let scroll = NSScrollView()
        scroll.clipsToBounds = true
        scroll.documentView = editor
        scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        scroll.drawsBackground = true; scroll.backgroundColor = NSColor(TerminalStyle.recess)
        editor.isRichText = false; editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: 330); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 8, height: 16)
        editor.font = NSFont(name: "IBMPlexMono", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isAutomaticSpellingCorrectionEnabled = false
        editor.allowsUndo = true; editor.focusRingType = .none; editor.delegate = context.coordinator
        editor.setAccessibilityLabel("要运行的 zsh 命令")
        let ruler = CommandLineRuler(editor: editor, scroll: scroll)
        scroll.verticalRulerView = ruler; scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak ruler] _ in ruler?.needsDisplay = true }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            editor.string = text
            (scroll.verticalRulerView as? CommandLineRuler)?.sourceChanged()
        }
        if editor.isEditable != editable { editor.isEditable = editable }
        let appearance = scroll.window?.effectiveAppearance ?? NSApp.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let ink = NSColor(TerminalStyle.ink).usingColorSpace(.deviceRGB) ?? .textColor
            let background = NSColor(TerminalStyle.recess).usingColorSpace(.deviceRGB) ?? .textBackgroundColor
            let caret = NSColor(TerminalStyle.accent).usingColorSpace(.deviceRGB) ?? .textColor
            if editor.textColor != ink { editor.textColor = ink }
            if editor.backgroundColor != background { editor.backgroundColor = background; scroll.backgroundColor = background }
            if editor.insertionPointColor != caret { editor.insertionPointColor = caret }
        }
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.scrollObserver { NotificationCenter.default.removeObserver(observer) }
        coordinator.scrollObserver = nil; (scroll.documentView as? NSTextView)?.delegate = nil
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var scrollObserver: NSObjectProtocol?
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
            (editor.enclosingScrollView?.verticalRulerView as? CommandLineRuler)?.sourceChanged()
        }
    }
}
private final class CommandLineRuler: NSRulerView {
    weak var editor: NSTextView?
    private var lineStarts = [0]
    override var isFlipped: Bool { true }
    init(editor: NSTextView, scroll: NSScrollView) {
        self.editor = editor; super.init(scrollView: scroll, orientation: .verticalRuler); ruleThickness = 34
        clipsToBounds = true
    }
    required init(coder: NSCoder) { fatalError("Not used") }
    func sourceChanged() {
        lineStarts = [0]
        if let source = editor?.string as NSString? {
            var index = 0
            while index < source.length {
                index = NSMaxRange(source.lineRange(for: NSRange(location: index, length: 0)))
                if index < source.length || (index == source.length && editor?.string.hasSuffix("\n") == true) { lineStarts.append(index) }
            }
        }
        needsDisplay = true
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        // Recent AppKit versions can pass a dirty rect extending beyond this
        // ruler. Clip explicitly so its background cannot cover the editor.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        NSColor(TerminalStyle.recess).setFill(); bounds.fill()
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        let visible = editor.visibleRect.offsetBy(dx: -editor.textContainerInset.width, dy: -editor.textContainerInset.height)
        layout.ensureLayout(forBoundingRect: visible, in: container)
        let visibleGlyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let source = editor.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor(TerminalStyle.muted)]
        let firstCharacter = visibleGlyphs.length > 0 ? layout.characterIndexForGlyph(at: visibleGlyphs.location) : 0
        var lower = 0, upper = lineStarts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= firstCharacter { lower = middle + 1 } else { upper = middle }
        }
        var line = max(0, lower - 1)
        while line < lineStarts.count, lineStarts[line] < source.length {
            let index = lineStarts[line]
            let glyph = layout.glyphIndexForCharacter(at: index)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = convert(NSPoint(x: 0, y: fragment.minY + editor.textContainerInset.height), from: editor).y
            if y > bounds.maxY { break }
            if y + fragment.height >= bounds.minY { draw(line + 1, y: y, attributes: attributes) }
            line += 1
        }
        if source.length == 0 || editor.string.hasSuffix("\n") {
            let y = convert(NSPoint(x: 0, y: layout.extraLineFragmentRect.minY + editor.textContainerInset.height), from: editor).y
            draw(lineStarts.count, y: y, attributes: attributes)
        }
    }
    private func draw(_ number: Int, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let label = String(format: "%02d", number) as NSString
        label.draw(at: NSPoint(x: ruleThickness - label.size(withAttributes: attributes).width - 7, y: y), withAttributes: attributes)
    }
}

/// Pause log polling when this page's window is hidden, minimized, or covered.
private struct CommandWindowVisibilityProbe: NSViewRepresentable {
    var report: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { let view = VisibilityView(); view.report = report; return view }
    func updateNSView(_ view: VisibilityView, context: Context) { view.report = report }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stopObserving(); view.report = nil }
    final class VisibilityView: NSView {
        var report: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stopObserving()
            guard let window else { report?(false); return }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reportVisibility() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.report?(false) }
            })
            Task { @MainActor [weak self] in self?.reportVisibility() }
        }
        private func reportVisibility() { report?(window?.isVisible == true && window?.occlusionState.contains(.visible) == true) }
        func stopObserving() { for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers = [] }
    }
}
