import XCTest
import AppKit
import SwiftUI
import CoreText
@testable import WakeMac
import WakeMacCore

@MainActor final class ProfessionalIntegrationTests: XCTestCase {
    private final class Effects: SessionEffectManaging {
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport { .init(displayAssertionActive: working && choices.preventDisplaySleep) }
        func release() {}
    }
    private final class Source: TriggerObservationSource {
        func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
            var value = TriggerSnapshot(); value.externalDisplay = true; value.acConnected = true; value.cpuPercent = 10
            return value
        }
    }
    private func fixture() async throws -> (AppModel, LocalControlServer, String, URL) {
        let directory = URL(fileURLWithPath: "/tmp/orx-p345-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let preferences = UserDefaults(suiteName: "Orexin.ProfessionalTests." + UUID().uuidString)!
        let model = AppModel(backend: AutomationBackend(), preferences: preferences, historyURL: directory.appendingPathComponent("history.json"), jobLogDirectory: directory.appendingPathComponent("logs"), triggerSource: Source(), sessionEffects: Effects())
        model.thermalStateProvider = { .nominal }
        await model.choose(.normal)
        let path = directory.appendingPathComponent("control.sock").path
        let server = try LocalControlServer(path: path) { request in await model.handleTaskControl(request) }
        return (model, server, path, directory)
    }
    private func cli(_ arguments: [String], path: String) async throws -> (Int32, ControlReply) {
        let binary = ProcessInfo.processInfo.environment["OREXIN_CLI_BINARY"].map(URL.init(fileURLWithPath:))
            ?? Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("orexin")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("Build CLI before integration") }
        let process = Process(), output = Pipe()
        process.executableURL = binary; process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment; environment["OREXIN_SOCKET"] = path
        process.environment = environment; process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        if process.isRunning { process.terminate(); XCTFail("CLI timeout") }
        process.waitUntilExit()
        return (process.terminationStatus, try ControlCoding.decode(ControlReply.self, from: output.fileHandleForReading.readDataToEndOfFile()))
    }
    func testPackagedCLIConfigurationPreviewApplyRulesAndProfileExecution() async throws {
        let (model, server, path, dir) = try await fixture()
        defer { server.stop(); try? FileManager.default.removeItem(at: dir) }
        var profile = WorkProfile(name: "Review build"); profile.timeoutSeconds = 30
        let condition = TriggerCondition(kind: .acConnected)
        let rule = TriggerRule(name: "AC and not hot", enabled: true, conditions: [condition],
            expression: .all([.condition(condition), .not(.condition(.init(kind: .cpuAbove, value: "90")))]), priority: 10, sustainedMatchSeconds: 5, cooldownSeconds: 10)
        let file = dir.appendingPathComponent("work.json")
        try PortableWorkConfiguration(rules: [rule], profiles: [profile]).data().write(to: file)
        let preview = try await cli(["config-import", file.path, "--json"], path: path)
        XCTAssertEqual(preview.0, 0); XCTAssertTrue(model.profiles.profiles.isEmpty)
        let token = try XCTUnwrap(preview.1.previewToken)
        let applied = try await cli(["config-import", file.path, "--apply", "--expect", token, "--json"], path: path)
        XCTAssertEqual(applied.0, 0); XCTAssertEqual(model.profiles.profiles, [profile]); XCTAssertFalse(model.triggers.rules[0].enabled)
        let exported = try await cli(["config-export", "--json"], path: path)
        XCTAssertEqual(try PortableWorkConfiguration.decode(XCTUnwrap(exported.1.document)).profiles, [profile])
        let before = model.history.count
        let trial = try await cli(["rules-try", "--json"], path: path)
        XCTAssertEqual(trial.0, 0); XCTAssertEqual(model.history.count, before)
        let report = try ControlCoding.decode(TriggerEvaluationReport.self, from: XCTUnwrap(trial.1.document))
        XCTAssertEqual(report.rules.first?.state, .suppressed)
        let success = try await cli(["run", "--profile", profile.id.uuidString, "--json", "--", "/usr/bin/true"], path: path)
        XCTAssertEqual(success.0, 0); XCTAssertEqual(success.1.tasks.first?.request.state, .succeeded)
        let failure = try await cli(["run", "--profile", profile.id.uuidString, "--json", "--", "/bin/sh", "-c", "exit 7"], path: path)
        XCTAssertEqual(failure.0, 7); XCTAssertEqual(failure.1.tasks.first?.request.state, .failed)
        let marker = dir.appendingPathComponent("continued")
        let timeout = try await cli(["run", "--profile", profile.id.uuidString, "--timeout", "2", "--json", "--", "/bin/sh", "-c", "sleep 2.3; printf yes > '\(marker.path)'"], path: path)
        XCTAssertEqual(timeout.0, 75, timeout.1.error ?? ""); XCTAssertEqual(timeout.1.tasks.first?.request.state, .expired)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "yes")
        XCTAssertEqual(timeout.1.tasks.first?.request.exitCode, 0)
        let events = try await cli(["events", "--json"], path: path)
        let timeline = try ControlCoding.decode([HistoryEntry].self, from: XCTUnwrap(events.1.document))
        let timedOutID = try XCTUnwrap(timeout.1.tasks.first?.request.id)
        XCTAssertTrue(timeline.contains { $0.context?.requestIDs.contains(timedOutID) == true })
    }
    func testOptionalProfessionalUIReview() async throws {
        guard ProcessInfo.processInfo.environment["OREXIN_PHASE_UI"] == "1" else { throw XCTSkip("Opt-in isolated UI review") }
        let (model, server, path, dir) = try await fixture()
        defer { server.stop(); try? FileManager.default.removeItem(at: dir) }
        var profile = WorkProfile(name: "Build · restore and notify"); profile.timeoutSeconds = 3600; profile.success.notify = true
        let script = dir.appendingPathComponent("inspectable-outcome.zsh")
        try Data("# Review fixture: inert until explicitly enabled\nexit 0\n".utf8).write(to: script)
        profile.success.scriptPath = script.path
        try model.profiles.save(profile)
        let a = TriggerCondition(kind: .acConnected), b = TriggerCondition(kind: .cpuAbove, value: "90")
        let rule = TriggerRule(name: "Office · sustained AC", enabled: true, conditions: [a], expression: .all([.condition(a), .not(.condition(b))]), priority: 20, sustainedMatchSeconds: 30, cooldownSeconds: 60)
        XCTAssertNil(model.triggers.save(rule))
        _ = await model.triggers.matchingRules(now: Date(), battery: nil)
        await model.powerAnalysis.refresh(force: true)
        model.requestServiceMessage = "ISOLATED REVIEW · " + path
        let evidence = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OREXIN_UI_OUTPUT"] ?? "/tmp/orexin-phase345-evidence/ui")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let font = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/Fonts/IBMPlexMono-Regular.ttf")
        CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Orexin · Isolated professional review"; window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.close() }
        func capture<V: View>(_ view: V, name: String, width: CGFloat = 1100) async throws {
            window.setContentSize(.init(width: width, height: 800))
            let host = NSHostingView(rootView: view)
            window.contentView = host; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(350)); host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: evidence.appendingPathComponent(name + ".png"))
        }
        for width in [CGFloat(1100), CGFloat(650)] {
            try await capture(ScrollView { WorkConfigurationsView(model: model).padding(20) }.background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()), name: "policies-\(Int(width))", width: width)
            try model.profiles.replace([], revoke: [])
            try await capture(ScrollView { WorkConfigurationsView(model: model).padding(20) }.background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()), name: "policies-empty-\(Int(width))", width: width)
            try model.profiles.save(profile)
            try await capture(ScrollView { TaskIntegrationsView(model: model, availableWidth: width - 40).padding(20) }.background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()), name: "integrations-\(Int(width))", width: width)
            try await capture(ScrollView { TriggersView(controller: model.triggers).padding(20) }.background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()), name: "rules-\(Int(width))", width: width)
            try await capture(ScrollView { HistoryRecordsView(model: model, availableWidth: width - 40).padding(20) }.background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()), name: "power-\(Int(width))", width: width)
        }
        try await capture(TriggerRuleEditor(rule: rule, controller: model.triggers, finish: {}).padding(24).background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink).buttonStyle(TerminalButtonStyle()), name: "rule-editor", width: 700)
        try await capture(WorkProfileEditor(profile: profile, save: { _ in }).background(TerminalStyle.paper).foregroundStyle(TerminalStyle.ink), name: "profile-editor", width: 700)
        let root = PreferencesView(model: model, hotkeys: GlobalHotKeys(preferences: model.preferences), notifier: LocalNotifier(preferences: model.preferences))
        try await capture(root, name: "full-window", width: 1280)
        if ProcessInfo.processInfo.environment["OREXIN_PHASE_INTERACTIVE"] == "1" {
            try Data("\(getpid())\n\(path)\n".utf8).write(to: evidence.appendingPathComponent("ready.txt"))
            for _ in 0..<2400 {
                if FileManager.default.fileExists(atPath: evidence.appendingPathComponent("finish").path) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
