// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import WakeMacCore

extension AppModel {
    func taskControlReply(id: UUID? = nil, handle: WorkRequestHandle? = nil) -> ControlReply {
        let tasks = workRequests.records.filter { id == nil || $0.id == id }.map { item in
            let satisfied = item.state == .active && requestSatisfied(item.spec)
            return ControlTaskStatus(request: item, satisfied: satisfied,
                detail: item.state != .active ? item.reason ?? item.state.rawValue : satisfied ? "Verified" : requestUnsatisfiedReason(item.spec),
                commandRunning: runningCommandIDs.contains(item.id))
        }
        var reply = ControlReply(handle: handle, tasks: tasks, mode: active, verified: verifiedWork, sleepAt: automation.jobSleepAt)
        reply.displayDimmingPaused = workScreen.dimmingPaused
        reply.dimExitNeedsInputAccess = workScreen.dimExitNeedsInputAccess
        reply.batterySleepAt = automation.batterySleepAt
        reply.timeline = try? ControlCoding.encode(Array(history.prefix(100)))
        reply.notices = notices.controlPayload()
        reply.capabilities = ["notices-v1", "session-effects-v1"]
        reply.service = serviceInfo; reply.snapshot = snapshot
        reply.plans = planRuns.reversed().map(PlanRunSummary.init)
        reply.commandLogs = commandLogs.mapValues(\.path)
        return reply
    }
    private func taskMutationReply(id: UUID) -> ControlReply {
        var reply = taskControlReply(id: id)
        if error || pending != nil { reply.ok = false; reply.error = message }
        return reply
    }
    func handleTaskControl(_ request: ControlMessage) async -> ControlReply {
        if serviceStopping {
            var reply = ControlReply(ok: false, error: "Task service is stopping"); reply.service = serviceInfo; return reply
        }
        let entryStopEpoch = workStopEpoch
        do {
            guard request.version == 1 else { throw ModeError("Unsupported local API version") }
            try Task.checkCancellation()
            if isTaskService { reloadServicePreferences() }
            if let reply = try await handleServiceControl(request) { return reply }
            // Inspection/preview never reaps leases, advances rule timers or changes power.
            if let reply = try await handleConfigurationControl(request) { return reply }
            await reapWorkRequests(now: Date())
            switch request.operation {
            case "register", "interface-register":
                guard entryStopEpoch == workStopEpoch, !requestStopInProgress else { throw ModeError("Registration was superseded by a global stop") }
                guard var spec = request.spec, let handle = request.handle else { throw ModeError("register requires spec and owner handle") }
                if request.operation == "interface-register" {
                    guard let owner = spec.process, owner.isAlive == true, spec.leaseSeconds != nil else { throw ModeError("Interface requests require a live owner and bounded lease") }
                }
                spec.source = request.operation == "interface-register" ? "interface" : "external"
                spec.leaseSeconds = spec.leaseSeconds ?? 60
                if let owner = spec.process, LocalProcessIdentity.capture(pid: owner.pid) != owner { throw ModeError("Owner process identity cannot be verified for this user") }
                // Never open a system authorization window on behalf of a socket client.
                let current = try await backend.snapshot()
                try Task.checkCancellation()
                guard entryStopEpoch == workStopEpoch, !requestStopInProgress else { throw ModeError("Registration was superseded by a global stop") }
                guard lockRequirement.accepts(current.lockPolicy) else { throw ModeError("Current lock policy is not authorized; resolve it in Orexin first") }
                _ = try await registerWork(spec, handle: handle)
                if request.operation == "interface-register" { pendingUnlockedOwner = nil; pendingUnlockedDeadline = nil }
                return taskControlReply(id: handle.id, handle: handle)
            case "heartbeat":
                guard let handle = request.handle else { throw ModeError("heartbeat requires owner handle") }
                try workRequests.heartbeat(handle, now: Date()); saveWorkRequests()
                return taskControlReply(id: handle.id)
            case "complete":
                guard let handle = request.handle, let code = request.exitCode else { throw ModeError("complete requires owner handle and actual exit code") }
                try await completeWork(handle, exitCode: code)
                return taskMutationReply(id: handle.id)
            case "release":
                guard let handle = request.handle else { throw ModeError("release requires owner handle") }
                let teardown = try workRequests.release(handle, now: Date())
                saveWorkRequests(); await finishWorkMutation(teardown, now: Date())
                return taskMutationReply(id: handle.id)
            case "status", "list":
                if let id = request.id, !workRequests.records.contains(where: { $0.id == id }) { throw ModeError("Unknown request; no successful completion can be inferred") }
                return taskControlReply(id: request.id)
            case "stop-all":
                await choose(.normal)
                var reply = taskControlReply()
                if busy || error || pending != nil || active != .normal {
                    reply.ok = false
                    reply.error = busy ? "Stop-all is queued; cleanup has not finished" : message
                }
                return reply
            default: throw ModeError("Unknown operation")
            }
        } catch { return ControlReply(ok: false, error: error.localizedDescription, mode: active, verified: verifiedWork) }
    }
}
