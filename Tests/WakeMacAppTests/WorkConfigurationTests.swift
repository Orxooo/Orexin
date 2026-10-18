import XCTest
@testable import WakeMac
import WakeMacCore

@MainActor final class WorkConfigurationTests: XCTestCase {
    private final class Effects: SessionEffectManaging {
        func update(working: Bool, choices: SessionEffectChoices, directories: [URL], now: Date) -> SessionEffectReport { .init(displayAssertionActive: working && choices.preventDisplaySleep) }
        func release() {}
    }
    private func fixture() async -> AppModel {
        let defaults = UserDefaults(suiteName: "Orexin.ConfigurationTests." + UUID().uuidString)!
        let model = AppModel(backend: AutomationBackend(), preferences: defaults, sessionEffects: Effects())
        model.thermalStateProvider = { .nominal }
        await model.choose(.normal)
        return model
    }
    func testPortableRoundTripMergeReplaceAndInvalidImportAtomicity() async throws {
        let model = await fixture()
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let example = try Data(contentsOf: repository.appendingPathComponent("docs/examples/work-configuration.json"))
        XCTAssertEqual(try PortableWorkConfiguration.decode(example).profiles.first?.name, "Build and notify")
        let existing = WorkProfile(name: "Existing")
        try model.profiles.save(existing)
        var rule = TriggerRule(); rule.name = "AC only"; rule.enabled = true
        XCTAssertNil(model.triggers.save(rule))
        let baseline = try model.exportWorkConfiguration()
        let decoded = try PortableWorkConfiguration.decode(baseline)
        XCTAssertEqual(decoded.profiles, [existing]); XCTAssertEqual(decoded.rules, [rule])
        XCTAssertFalse(String(decoding: baseline, as: UTF8.self).contains("token"))
        var added = WorkProfile(name: "Added"); added.timeoutSeconds = 300
        var modified = existing; modified.name = "Updated"
        let incoming = try PortableWorkConfiguration(rules: [rule], profiles: [modified, added]).data()
        let preview = try model.previewWorkConfiguration(incoming, mode: .merge)
        XCTAssertEqual(try model.exportWorkConfiguration(), baseline)
        XCTAssertFalse(preview.result.rules[0].enabled)
        XCTAssertTrue(preview.changes.contains { $0.contains("Updated") })
        try model.applyWorkConfiguration(preview)
        XCTAssertEqual(model.profiles.profiles.map(\.name), ["Updated", "Added"])
        let valid = try model.exportWorkConfiguration()
        for invalid in [Data("{}".utf8), Data(repeating: 32, count: 33000), Data(String(decoding: incoming, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99").utf8), try PortableWorkConfiguration(profiles: [added, added]).data()] {
            XCTAssertThrowsError(try model.previewWorkConfiguration(invalid, mode: .replace))
            XCTAssertEqual(try model.exportWorkConfiguration(), valid)
        }
        let replacement = try model.previewWorkConfiguration(PortableWorkConfiguration(profiles: [added]).data(), mode: .replace)
        try model.applyWorkConfiguration(replacement)
        XCTAssertTrue(model.triggers.rules.isEmpty); XCTAssertEqual(model.profiles.profiles, [added])
    }
    func testStaleOrUnboundPreviewCannotApplyAndInspectionDoesNotReap() async throws {
        let model = await fixture()
        let data = try PortableWorkConfiguration(profiles: [WorkProfile(name: "A")]).data()
        var request = ControlMessage("config-preview"); request.document = data
        let preview = await model.handleTaskControl(request)
        XCTAssertTrue(preview.ok); XCTAssertNotNil(preview.previewToken)
        request.operation = "config-apply"
        let deniedWithoutToken = await model.handleTaskControl(request)
        XCTAssertFalse(deniedWithoutToken.ok)
        request.previewToken = preview.previewToken
        try model.profiles.save(WorkProfile(name: "Concurrent change"))
        let deniedStale = await model.handleTaskControl(request)
        XCTAssertFalse(deniedStale.ok)
        let past = Date().addingTimeInterval(-10)
        _ = try model.workRequests.register(.init(title: "expired but not reaped", deadline: past.addingTimeInterval(1)), now: past)
        let records = model.workRequests.records
        for operation in ["config-export", "profiles", "rules-try", "power", "events"] {
            let result = await model.handleTaskControl(.init(operation))
            XCTAssertTrue(result.ok, operation); XCTAssertEqual(model.workRequests.records, records, operation)
        }
    }
    func testProfileSnapshotAndRetryDoNotChangeTaskOwnershipOrDeadline() async throws {
        let model = await fixture()
        var profile = WorkProfile(name: "Bounded"); profile.timeoutSeconds = 10
        try model.profiles.save(profile)
        let spec = WorkRequestSpec(title: "Profile task", profileID: profile.id), handle = WorkRequestHandle()
        _ = try await model.registerWork(spec, handle: handle)
        let initial = try XCTUnwrap(model.workRequests.active.first)
        profile.timeoutSeconds = 20; try model.profiles.save(profile)
        _ = try await model.registerWork(spec, handle: handle)
        XCTAssertEqual(model.workRequests.active.first?.spec.deadline, initial.spec.deadline)
        try model.profiles.replace([], revoke: [profile.id])
        _ = try await model.registerWork(spec, handle: handle)
        XCTAssertEqual(model.workRequests.active.first?.spec.deadline, initial.spec.deadline)
        var changed = spec; changed.title = "different"
        do { _ = try await model.registerWork(changed, handle: handle); XCTFail("Changed retry accepted") } catch {}
        await model.releaseWork(id: handle.id)
        try await model.completeWork(handle, exitCode: 0)
        XCTAssertEqual(model.workRequests.records.last?.state, .cancelled)
        XCTAssertEqual(model.workRequests.records.last?.exitCode, 0)
        XCTAssertNil(model.automation.jobSleepAt)
    }
    func testHookActivationContentChangeAndImportRevocation() async throws {
        let model = await fixture()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OrexinHook-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("outcome.zsh"), marker = dir.appendingPathComponent("result")
        try Data("print -r -- \"$OREXIN_OUTCOME\" > '\(marker.path)'\n".utf8).write(to: script)
        var profile = WorkProfile(name: "Hook"); profile.success.scriptPath = script.path
        try model.profiles.save(profile)
        var handle = try await model.registerWork(.init(title: "unapproved", profileID: profile.id))
        try await model.completeWork(handle, exitCode: 0)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        try model.profiles.setHooksEnabled(true, profile: profile)
        handle = try await model.registerWork(.init(title: "approved", profileID: profile.id))
        try await model.completeWork(handle, exitCode: 0)
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "succeeded")
        try Data("# changed\nexit 0\n".utf8).write(to: script)
        XCTAssertFalse(model.profiles.hooksEnabled(profile))
        try model.profiles.setHooksEnabled(true, profile: profile)
        let preview = try model.previewWorkConfiguration(model.exportWorkConfiguration(), mode: .merge)
        try model.applyWorkConfiguration(preview)
        XCTAssertFalse(model.profiles.hooksEnabled(profile))
    }
    func testManualStopCancelsOwnedHookAndDoesNotReplayOnLateCompletion() async throws {
        let model = await fixture()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OrexinHookStop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("hook.zsh"), marker = dir.appendingPathComponent("should-not-exist")
        try Data("sleep 0.5\nprint late > '\(marker.path)'\n".utf8).write(to: script)
        var profile = WorkProfile(name: "Stop hook"); profile.success.scriptPath = script.path
        try model.profiles.save(profile); try model.profiles.setHooksEnabled(true, profile: profile)
        let handle = try await model.registerWork(.init(title: "completion", profileID: profile.id))
        try await model.completeWork(handle, exitCode: 0)
        for _ in 0..<30 where model.policyHooks.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.policyHooks.count, 1)
        await model.choose(.normal)
        try await model.completeWork(handle, exitCode: 0)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path)); XCTAssertEqual(model.policyHooks.count, 0)
        XCTAssertEqual(model.history.filter { $0.context?.kind == .request && $0.text.contains("工作请求结束") }.count, 1)
    }
    func testTimeoutPolicyNotifiesWithoutInferringCommandFailureOrSuccess() async throws {
        let model = await fixture()
        var profile = WorkProfile(name: "Timeout"); profile.timeoutSeconds = 1; profile.timeout.notify = true
        try model.profiles.save(profile)
        var notifications: [String] = []; model.notificationHandler = { notifications.append($0) }
        let handle = try await model.registerWork(.init(title: "long command", profileID: profile.id))
        await model.reapWorkRequests(now: Date().addingTimeInterval(2))
        XCTAssertEqual(model.workRequests.records.last?.state, .expired); XCTAssertNil(model.workRequests.records.last?.exitCode)
        XCTAssertEqual(notifications.count, 1); XCTAssertNil(model.automation.jobSleepAt)
        try await model.completeWork(handle, exitCode: 0)
        XCTAssertEqual(notifications.count, 1); XCTAssertEqual(model.workRequests.records.last?.state, .expired)
    }
    func testPreviewTokenIncludesApprovalRevocationAndHookHashesKeepFileBoundaries() async throws {
        let model = await fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrexinApproval-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = directory.appendingPathComponent("a.zsh"), b = directory.appendingPathComponent("b.zsh")
        try Data("print one\n".utf8).write(to: a); try Data("print two\n".utf8).write(to: b)
        var profile = WorkProfile(name: "Two hooks"); profile.success.scriptPath = a.path; profile.failure.scriptPath = b.path
        try model.profiles.save(profile); try model.profiles.setHooksEnabled(true, profile: profile)
        let empty = try model.previewWorkConfiguration(PortableWorkConfiguration().data(), mode: .merge)
        let revoking = try model.previewWorkConfiguration(PortableWorkConfiguration(profiles: [profile]).data(), mode: .merge)
        XCTAssertEqual(empty.afterJSON, revoking.afterJSON); XCTAssertNotEqual(empty.token, revoking.token)
        let approved = try XCTUnwrap(model.profiles.approvals[profile.id.uuidString])
        let captured = try model.profiles.approvedScript(profile, path: a.path, expected: approved)
        try Data("print one\nprint two\n".utf8).write(to: a); try Data().write(to: b)
        XCTAssertFalse(model.profiles.hooksEnabled(profile))
        XCTAssertEqual(String(decoding: captured, as: UTF8.self), "print one\n")
        XCTAssertThrowsError(try model.profiles.approvedScript(profile, path: a.path, expected: approved))
    }
    func testBatteryBlocksHookAndThermalProtectionCancelsRunningHook() async throws {
        let model = await fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrexinProtectedHook-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("hook.zsh"), marker = directory.appendingPathComponent("forbidden")
        try Data("sleep 0.4\nprint bad > '\(marker.path)'\n".utf8).write(to: script)
        var profile = WorkProfile(name: "Protected"); profile.success.scriptPath = script.path
        try model.profiles.save(profile); try model.profiles.setHooksEnabled(true, profile: profile)
        var handle = try await model.registerWork(.init(title: "battery", profileID: profile.id))
        model.battery = .init(percent: 10, onBattery: true)
        try await model.completeWork(handle, exitCode: 0)
        try await Task.sleep(for: .milliseconds(50)); XCTAssertEqual(model.policyHooks.count, 0)
        model.battery = .init(percent: 90, onBattery: false)
        handle = try await model.registerWork(.init(title: "thermal", profileID: profile.id))
        try await model.completeWork(handle, exitCode: 0)
        for _ in 0..<20 where model.policyHooks.count == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.policyHooks.count, 1)
        model.thermalStateProvider = { .critical }
        await model.tick(battery: model.battery)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path)); XCTAssertEqual(model.policyHooks.count, 0)
    }
    func testHookTimeLimitOnlyStopsItsOwnProcessGroup() async throws {
        let model = await fixture()
        let handle = try await model.registerWork(.init(title: "unrelated work"))
        let record = try XCTUnwrap(model.workRequests.records.first)
        do {
            _ = try await model.policyHooks.run(script: Data("sleep 10\n".utf8), sourcePath: "/test/hook.zsh", record: record, limit: 0.05)
            XCTFail("Hook exceeded configured test limit")
        } catch { XCTAssertTrue(error.localizedDescription.contains("limit")) }
        XCTAssertEqual(model.workRequests.active.first?.id, handle.id); XCTAssertTrue(model.verifiedWork)
        await model.releaseWork(id: handle.id)
    }
}
