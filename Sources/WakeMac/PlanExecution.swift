// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import WakeMacCore

extension AppModel {
    func recoverPlans(from url: URL) throws {
        planHistoryURL = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        planRuns = try ControlCoding.decode([PlanRun].self, from: Data(contentsOf: url))
        for i in planRuns.indices { planRuns[i].recover(now: Date()) }
        try savePlans()
    }
    func savePlans() throws {
        guard let url = planHistoryURL else { return }
        let terminal = planRuns.filter { $0.state.terminal }.suffix(30).map(\.id)
        planRuns.removeAll { $0.state.terminal && !terminal.contains($0.id) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try ControlCoding.encode(planRuns).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    @discardableResult func startPlan(_ plan: ExecutionPlan, id: UUID = UUID(), requestSpec: WorkRequestSpec? = nil) async throws -> PlanRun {
        _ = try plan.validated()
        guard planRuns.filter({ !$0.state.terminal }).count < 8 else { throw ModeError("At most 8 active plans are supported") }
        if let existing = planRuns.first(where: { $0.id == id }) {
            guard existing.plan == plan else { throw ModeError("Plan ID already used for another document") }
            return existing
        }
        // Check every directory before acquiring protection or executing a command.
        for task in plan.tasks {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: task.directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ModeError("Task directory does not exist: " + task.id)
            }
        }
        let run = try PlanRun(id: id, plan: plan)
        let handle = WorkRequestHandle(id: run.id)
        var spec = requestSpec ?? WorkRequestSpec(title: plan.title, source: "plan", mode: plan.mode, screen: plan.screen, teardown: plan.teardown)
        spec.source = requestSpec == nil ? "plan" : "command"; spec.process = nil; spec.leaseSeconds = nil
        _ = try await registerWork(spec, handle: handle)
        planRuns.append(run); planHandles[run.id] = handle
        do { try savePlans() }
        catch {
            planRuns.removeAll { $0.id == run.id }; planHandles.removeValue(forKey: run.id)
            await releaseWork(id: handle.id); throw error
        }
        Task { await self.advancePlans() }
        return run
    }
    func cancelPlan(id: UUID) async throws {
        guard let i = planRuns.firstIndex(where: { $0.id == id }) else { throw ModeError("Unknown plan") }
        planRuns[i].cancel(now: Date())
        try savePlans()
        await advancePlans()
    }
    func cancelPendingPlans() {
        for i in planRuns.indices { planRuns[i].cancel(now: Date()) }
        do { try savePlans() } catch { requestServiceMessage = "Plan history could not be saved: " + error.localizedDescription }
    }
    func advancePlans() async {
        guard !planAdvanceRunning, !busy, !requestReconcileRunning else { return }
        planAdvanceRunning = true
        defer { planAdvanceRunning = false }
        var launches: [(UUID, PlanTask)] = []
        for i in planRuns.indices where !planRuns[i].state.terminal {
            if let request = workRequests.active.first(where: { $0.id == planRuns[i].id }), requestSatisfied(request.spec) {
                // Protection still verified; dependencies may advance.
            } else { planRuns[i].cancel(now: Date()) }
            let ready = planRuns[i].schedule(now: Date())
            for id in ready { if let task = planRuns[i].plan.tasks.first(where: { $0.id == id }) { launches.append((planRuns[i].id, task)) } }
        }
        do { try savePlans() }
        catch {
            for i in planRuns.indices { planRuns[i].cancel(now: Date()) }
            for (id, task) in launches {
                if let i = planRuns.firstIndex(where: { $0.id == id }) { planRuns[i].finish(task.id, exitCode: 125, detail: "History write failed; command not started", now: Date()) }
            }
            launches.removeAll(); requestServiceMessage = error.localizedDescription
        }
        // No await between reservation, persistence and dispatch.
        for (id, task) in launches {
            runningCommandIDs.insert(id)
            Task { await self.executePlanTask(task, runID: id) }
        }
        jobRunning = !runningCommandIDs.isEmpty
        for run in planRuns where run.state.terminal {
            guard let handle = planHandles.removeValue(forKey: run.id) else { continue }
            if run.state == .succeeded || run.state == .failed { try? await completeWork(handle, exitCode: run.state == .succeeded ? 0 : 1) }
            else { await releaseWork(id: handle.id) }
        }
        onUpdate?()
    }
    private func executePlanTask(_ task: PlanTask, runID: UUID) async {
        // A global stop may arrive after scheduling but before this Task starts.
        guard let run = planRuns.first(where: { $0.id == runID }), run.state == .running,
              workRequests.active.contains(where: { $0.id == runID }) else {
            await finishPlanTask(runID: runID, taskID: task.id, code: 125, detail: "Stopped before command launch")
            return
        }
        let log = planLogURL(runID: runID, taskID: task.id)
        let runner = planCommandRunner
        do {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let result = try await Task.detached(priority: .utility) { try runner(task.command, task.directory, log) }.value
            await finishPlanTask(runID: runID, taskID: task.id, code: result.exitCode, detail: result.truncated ? "Log capped at 5 MiB" : nil)
        } catch { await finishPlanTask(runID: runID, taskID: task.id, code: 127, detail: error.localizedDescription) }
    }
    private func finishPlanTask(runID: UUID, taskID: String, code: Int32, detail: String?) async {
        guard let i = planRuns.firstIndex(where: { $0.id == runID }) else { return }
        planRuns[i].finish(taskID, exitCode: code, detail: detail, now: Date())
        if !planRuns[i].tasks.contains(where: { $0.state == .running }) { runningCommandIDs.remove(runID) }
        do { try savePlans() } catch { planRuns[i].cancel(now: Date()); requestServiceMessage = error.localizedDescription }
        await advancePlans()
    }
    func planLogURL(runID: UUID, taskID: String) -> URL {
        jobLogDirectory.appendingPathComponent("plan-" + runID.uuidString).appendingPathComponent(taskID + ".log")
    }
}
