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
        return ControlReply(handle: handle, tasks: tasks, mode: active, verified: verifiedWork, sleepAt: automation.jobSleepAt)
    }
    private func taskMutationReply(id: UUID) -> ControlReply {
        var reply = taskControlReply(id: id)
        if error || pending != nil { reply.ok = false; reply.error = message }
        return reply
    }
    func handleTaskControl(_ request: ControlMessage) async -> ControlReply {
        let entryStopEpoch = workStopEpoch
        do {
            guard request.version == 1 else { throw ModeError("Unsupported local API version") }
            try Task.checkCancellation()
            // Inspection/preview never reaps leases, advances rule timers or changes power.
            if let reply = try await handleConfigurationControl(request) { return reply }
            await reapWorkRequests(now: Date())
            switch request.operation {
            case "register":
                guard entryStopEpoch == workStopEpoch, !requestStopInProgress else { throw ModeError("Registration was superseded by a global stop") }
                guard var spec = request.spec, let handle = request.handle else { throw ModeError("register requires spec and owner handle") }
                spec.source = "external"
                spec.leaseSeconds = spec.leaseSeconds ?? 60
                if let owner = spec.process, LocalProcessIdentity.capture(pid: owner.pid) != owner { throw ModeError("Owner process identity cannot be verified for this user") }
                // Never open a system authorization window on behalf of a socket client.
                let current = try await backend.snapshot()
                try Task.checkCancellation()
                guard entryStopEpoch == workStopEpoch, !requestStopInProgress else { throw ModeError("Registration was superseded by a global stop") }
                guard lockRequirement.accepts(current.lockPolicy) else { throw ModeError("Current lock policy is not authorized; resolve it in Orexin first") }
                _ = try await registerWork(spec, handle: handle)
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
