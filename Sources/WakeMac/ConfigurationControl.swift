// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import WakeMacCore

extension AppModel {
    func handleConfigurationControl(_ request: ControlMessage) async throws -> ControlReply? {
        var reply = ControlReply(mode: active, verified: verifiedWork)
        switch request.operation {
        case "config-export": reply.document = try exportWorkConfiguration()
        case "profiles": reply.document = try ControlCoding.encode(profiles.profiles)
        case "config-preview", "config-apply":
            guard let data = request.document, let strategy = ConfigurationImportMode(rawValue: request.strategy ?? "merge") else { throw ModeError("Configuration and merge|replace strategy required") }
            let preview = try previewWorkConfiguration(data, mode: strategy)
            if request.operation == "config-apply" {
                guard request.previewToken == preview.token else { throw ModeError("Import needs a current preview token for this exact result") }
                try applyWorkConfiguration(preview)
            }
            reply.document = Data(preview.afterJSON.utf8); reply.changes = preview.changes; reply.previewToken = preview.token
        case "rules-try": reply.document = try ControlCoding.encode(await triggers.dryRun(now: Date(), battery: battery))
        case "power":
            // Reading the snapshot does not append timeline events.
            reply.document = try ControlCoding.encode(powerAnalysis.snapshot)
        case "events": reply.document = try ControlCoding.encode(Array(history.prefix(50)))
        default: return nil
        }
        return reply
    }
}
