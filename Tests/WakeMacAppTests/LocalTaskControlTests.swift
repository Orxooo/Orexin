import XCTest
import AppKit
import CoreText
import SwiftUI
@testable import WakeMac
import WakeMacCore

@MainActor final class LocalTaskControlTests: XCTestCase {
    private final class NoEffects: SessionEffectManaging {
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport { .init(displayAssertionActive: working && choices.preventDisplaySleep) }
        func release() {}
    }
    private func fixture(backend: any ModeBackend = AutomationBackend()) async throws -> (AppModel, LocalControlServer, String, URL) {
        let directory = URL(fileURLWithPath: "/tmp/orx-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let model = AppModel(backend: backend, preferences: UserDefaults(suiteName: "LocalAPI." + UUID().uuidString)!, sessionEffects: NoEffects())
        model.thermalStateProvider = { .nominal }
        await model.choose(.normal)
        let path = directory.appendingPathComponent("control.sock").path
        let server = try LocalControlServer(path: path) { request in await model.handleTaskControl(request) }
        return (model, server, path, directory)
    }
    private func call(_ message: ControlMessage, path: String) async throws -> ControlReply {
        try await Task.detached { try LocalControlSocket.call(message, path: path) }.value
    }
    private func launchCLI(_ arguments: [String], socket: String) throws -> (Process, Pipe) {
        let binary = ProcessInfo.processInfo.environment["OREXIN_CLI_BINARY"].map { URL(fileURLWithPath: $0) }
            ?? Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("orexin")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("Build orexin before local CLI integration: \(binary.path)") }
        let process = Process(), output = Pipe()
        process.executableURL = binary; process.arguments = arguments + ["--socket", socket]
        var environment = ProcessInfo.processInfo.environment; environment["OREXIN_SOCKET"] = socket
        process.environment = environment
        // For run, the explicit --socket would be passed to the child after --.
        if arguments.first == "run" { process.arguments = arguments }
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        return (process, output)
    }
    private func result(_ launched: (Process, Pipe)) async throws -> (Int32, ControlReply) {
        let deadline = Date().addingTimeInterval(15)
        while launched.0.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        if launched.0.isRunning { launched.0.terminate(); XCTFail("CLI timed out") }
        launched.0.waitUntilExit()
        let data = launched.1.fileHandleForReading.readDataToEndOfFile()
        return (launched.0.terminationStatus, try ControlCoding.decode(ControlReply.self, from: data))
    }
    private func waitForRequest(_ model: AppModel, process: Process) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.workRequests.active.isEmpty && process.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard !model.workRequests.active.isEmpty else { throw ModeError("CLI did not register an active request (exit \(process.isRunning ? -999 : process.terminationStatus))") }
    }
    func testRealCLIOverlapFailureAndFinalTeardownAcrossSocket() async throws {
        let (model, server, path, directory) = try await fixture()
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        let a = try launchCLI(["run", "--json", "--title", "first", "--screen", "awake", "--", "/bin/sleep", "0.4"], socket: path)
        try await waitForRequest(model, process: a.0)
        let b = try launchCLI(["run", "--json", "--title", "second", "--", "/bin/sh", "-c", "sleep 1; exit 7"], socket: path)
        let first = try await result(a)
        XCTAssertEqual(first.0, 0); XCTAssertEqual(first.1.tasks.first?.request.state, .succeeded)
        XCTAssertEqual(model.workRequests.active.count, 1); XCTAssertTrue(model.verifiedWork)
        let second = try await result(b)
        XCTAssertEqual(second.0, 7); XCTAssertEqual(second.1.tasks.first?.request.state, .failed)
        XCTAssertTrue(model.workRequests.active.isEmpty); XCTAssertEqual(model.active, .normal)
        XCTAssertNil(model.automation.jobSleepAt)
    }
    func testExternalRegistrationHeartbeatOwnershipReleaseAndStructuredErrors() async throws {
        let (model, server, path, directory) = try await fixture()
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        let registration = try await result(launchCLI(["register", "--json", "--lease", "5", "--title", "external"], socket: path))
        let handle = try XCTUnwrap(registration.1.handle), text = "\(handle.id.uuidString):\(handle.token.uuidString)"
        let heartbeat = try await result(launchCLI(["heartbeat", text, "--json"], socket: path))
        XCTAssertTrue(heartbeat.1.ok)
        let wrong = try await call(.init("complete", handle: .init(id: handle.id), exitCode: 0), path: path)
        XCTAssertFalse(wrong.ok); XCTAssertEqual(model.workRequests.active.count, 1)
        let listed = try await result(launchCLI(["list", "--json"], socket: path))
        XCTAssertNil(listed.1.handle); XCTAssertTrue(listed.1.tasks[0].satisfied)
        let released = try await result(launchCLI(["release", text, "--json"], socket: path))
        XCTAssertEqual(released.1.tasks[0].request.state, .cancelled); XCTAssertEqual(model.active, .normal)
        let late = try await result(launchCLI(["heartbeat", text, "--json"], socket: path))
        XCTAssertEqual(late.0, 1); XCTAssertFalse(late.1.ok)
        let malformed = try await result(launchCLI(["register", "--lease", "nan", "--json"], socket: path))
        XCTAssertEqual(malformed.0, 1)
    }
    func testWrapperSignalAndProcessLossAreNotSuccessfulCompletion() async throws {
        let (model, server, path, directory) = try await fixture()
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        let cancelled = try launchCLI(["run", "--json", "--", "/bin/sleep", "5"], socket: path)
        try await waitForRequest(model, process: cancelled.0)
        try await Task.sleep(for: .milliseconds(150))
        cancelled.0.terminate()
        let cancellation = try await result(cancelled)
        XCTAssertEqual(cancellation.0, 143); XCTAssertEqual(cancellation.1.tasks.first?.request.state, .cancelled)
        let lost = try launchCLI(["run", "--json", "--", "/bin/sleep", "0.8"], socket: path)
        try await waitForRequest(model, process: lost.0)
        kill(lost.0.processIdentifier, SIGKILL)
        while lost.0.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        await model.reapWorkRequests(now: Date())
        XCTAssertEqual(model.workRequests.records.last?.state, .lost)
        XCTAssertEqual(model.active, .normal); XCTAssertNil(model.automation.jobSleepAt)
    }
    func testServerOwnershipAndUnknownRequestsFailClosed() async throws {
        let (_, server, path, directory) = try await fixture()
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try LocalControlServer(path: path) { _ in .init() })
        var unsupported = ControlMessage("list"); unsupported.version = 2
        let version = try await call(unsupported, path: path)
        XCTAssertFalse(version.ok)
        let unknown = try await call(.init("status", id: UUID()), path: path)
        XCTAssertFalse(unknown.ok)
        let malformedDirectory = directory.appendingPathComponent("public")
        try FileManager.default.createDirectory(at: malformedDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        XCTAssertThrowsError(try LocalControlServer(path: malformedDirectory.appendingPathComponent("s").path) { _ in .init() })
    }
    func testCLIReportsFinalCleanupFailureWithoutLosingActualExitCode() async throws {
        let backend = CleanupFailureBackend()
        let (model, server, path, directory) = try await fixture(backend: backend)
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        let process = try launchCLI(["run", "--json", "--", "/bin/sleep", "0.3"], socket: path)
        try await waitForRequest(model, process: process.0)
        await backend.rejectCleanup()
        let response = try await result(process)
        XCTAssertEqual(response.0, 75); XCTAssertFalse(response.1.ok)
        XCTAssertEqual(response.1.tasks.first?.request.state, .succeeded)
        XCTAssertEqual(response.1.tasks.first?.request.exitCode, 0)
    }
    func testOptionalInteractiveTaskPanel() async throws {
        guard ProcessInfo.processInfo.environment["OREXIN_UI_PREVIEW"] == "1" else { throw XCTSkip("Interactive UI preview is opt-in; no system power transitions") }
        let (model, server, path, directory) = try await fixture()
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        model.requestServiceMessage = "CLI READY · " + path
        let a = try await model.registerWork(.init(title: "Build · UI verification", screen: .awake))
        _ = try await model.registerWork(.init(title: "Backup · independent lifecycle", mode: .background, screen: .idle))
        if ProcessInfo.processInfo.environment["OREXIN_UI_SNAPSHOTS"] == "1" {
            try await captureTaskManagement(model: model, directory: directory)
            return
        }
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        TerminalStyle.registerFonts()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1120, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Orexin · Isolated CLI/UI Verification"
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: ScrollView { CommandTasksView(model: model, command: .constant("printf 'safe local task\\n'"), directory: .constant("/tmp"), availableWidth: 1060, section: .constant(.tasks)).padding(20) }
            .background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()))
        window.contentView = view; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
        let evidence = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OREXIN_UI_OUTPUT"] ?? "/tmp/orexin-ui-preview")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try Data("\(getpid())\n\(path)\n\(a.id.uuidString)\n".utf8).write(to: evidence.appendingPathComponent("ui-ready.txt"))
        for _ in 0..<1800 {
            if FileManager.default.fileExists(atPath: evidence.appendingPathComponent("ui-finish").path) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: evidence.appendingPathComponent("task-panel.png"))
        }
        window.orderOut(nil); window.close()
    }
    private func captureTaskManagement(model: AppModel, directory: URL) async throws {
        let evidence = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OREXIN_UI_OUTPUT"] ?? "/tmp/orexin-ui-preview")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        TerminalStyle.registerFonts()
        // The XCTest runner has no app resources; register the shipped font for faithful snapshots.
        let font = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets/Fonts/IBMPlexMono-Regular.ttf")
        CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        XCTAssertNotNil(NSFont(name: "IBMPlexMono", size: 10))
        let log = directory.appendingPathComponent("build.log")
        try Data("[Build] Preparing workspace…\n[Build] Compiling 24 sources\n[Build] Linking Orexin\nBuild complete.\n".utf8).write(to: log)
        let commandID = try XCTUnwrap(model.workRequests.active.first?.id)
        model.commandLogs[commandID] = log; model.jobLogURL = log
        model.runningCommandIDs.insert(commandID); model.jobRunning = true; model.jobStatus = "命令运行中"
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Orexin · Isolated task management preview"
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.close() }
        func capture<V: View>(_ root: V, size: CGSize, name: String, selectTaskPage: Bool = false) async throws {
            window.setContentSize(size)
            let host = NSHostingView(rootView: root)
            window.contentView = host; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(350))
            if selectTaskPage {
                model.requestedTaskPage = UUID()
                try await Task.sleep(for: .milliseconds(350))
            }
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: evidence.appendingPathComponent(name + ".png"))
        }
        let prefs = UserDefaults(suiteName: "TaskUIPreview." + UUID().uuidString)!
        model.appearance.theme = .light
        for size in [CGSize(width: 1280, height: 800), CGSize(width: 860, height: 630)] {
            try await capture(PreferencesView(model: model, hotkeys: GlobalHotKeys(preferences: prefs), notifier: LocalNotifier(preferences: prefs)),
                              size: size, name: "window-tasks-\(Int(size.width))", selectTaskPage: true)
        }
        for section in TaskManagementSection.allCases {
            for width in [CGFloat(1034), CGFloat(614)] {
                let root = ScrollView {
                    CommandTasksView(model: model, command: .constant("printf 'Build started\\n'\n/usr/bin/make"), directory: .constant("/tmp"), availableWidth: width, section: .constant(section)).padding(20)
                }.background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle())
                    .preferredColorScheme(.light)
                try await capture(root, size: CGSize(width: width + 40, height: 960), name: "\(section.code.lowercased())-\(Int(width))")
            }
        }
        try await capture(ScrollView { AutoTeardownView(model: model, date: .constant(Date().addingTimeInterval(3600)), preset: .constant(60), availableWidth: 1034).padding(20) }
            .background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()).preferredColorScheme(.light),
                          size: CGSize(width: 1074, height: 960), name: "reference-existing-teardown")
        model.appearance.theme = .dark
        try await capture(PreferencesView(model: model, hotkeys: GlobalHotKeys(preferences: prefs), notifier: LocalNotifier(preferences: prefs)),
                          size: CGSize(width: 1280, height: 800), name: "window-tasks-dark", selectTaskPage: true)
        await model.choose(.normal)
        model.runningCommandIDs.removeAll(); model.jobRunning = false
        try await capture(ScrollView { CommandTasksView(model: model, command: .constant(""), directory: .constant("/tmp"), availableWidth: 614, section: .constant(.tasks)).padding(20) }
            .background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()).preferredColorScheme(.light),
                          size: CGSize(width: 654, height: 430), name: "tasks-empty")
    }

}

private actor CleanupFailureBackend: ModeBackend {
    var mode: WorkMode = .normal
    var fails = false
    func rejectCleanup() { fails = true }
    func snapshot() async throws -> Snapshot {
        .init(sleepDisabled: mode == .background, lockPolicy: .immediate, idleSleepPrevented: mode != .normal, displaySleepAllowed: true, backgroundLeaseActive: mode == .background)
    }
    func configurePower(_ mode: WorkMode) async throws {
        if mode == .normal && fails { throw ModeError("Simulated cleanup failure") }
        self.mode = mode
    }
    func requestLockPolicy(_ policy: LockPolicy) async {}
    func sleepNow() async throws {}
}
