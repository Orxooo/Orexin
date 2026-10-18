// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import Combine
import CryptoKit
import WakeMacCore

struct PortableWorkConfiguration: Codable, Equatable {
    var format = "org.orexin.work-configuration"
    var version = 1
    var rules: [TriggerRule] = []
    var profiles: [WorkProfile] = []
    static let maximumBytes = 32 * 1024
    func validated() throws -> Self {
        guard format == "org.orexin.work-configuration", version == 1 else { throw ModeError("Unsupported Orexin configuration format/version") }
        guard rules.count <= 64, profiles.count <= 64 else { throw ModeError("At most 64 rules and 64 profiles are supported") }
        if let error = TriggerController.validateRules(rules) { throw ModeError(error) }
        guard Set(profiles.map(\.id)).count == profiles.count else { throw ModeError("Duplicate profile IDs") }
        if let error = profiles.compactMap(\.validationError).first { throw ModeError(error) }
        return self
    }
    func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ModeError("Configuration exceeds 32 KiB") }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw ModeError("Configuration exceeds 32 KiB") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["format", "version", "rules", "profiles"]) else { throw ModeError("Expected only format, version, rules and profiles") }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}

enum ConfigurationImportMode: String, Codable, CaseIterable { case merge, replace }
struct ConfigurationPreview {
    let baseline: Data
    let result: PortableWorkConfiguration
    let importedProfileIDs: Set<UUID>
    let changes: [String]
    let beforeJSON: String
    let afterJSON: String
    var token: String {
        let effects = importedProfileIDs.map(\.uuidString).sorted().joined(separator: "\n")
        return SHA256.hash(data: baseline + Data(afterJSON.utf8) + Data(effects.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor final class WorkProfileStore: ObservableObject {
    static let key = "orexin.WorkProfiles.v1"
    private static let trustKey = "orexin.WorkProfileHookApprovals.v1"
    @Published private(set) var profiles: [WorkProfile]
    @Published private(set) var approvals: [String: String]
    private let preferences: UserDefaults
    init(preferences: UserDefaults) {
        self.preferences = preferences
        profiles = preferences.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([WorkProfile].self, from: $0) } ?? []
        approvals = preferences.dictionary(forKey: Self.trustKey) as? [String: String] ?? [:]
    }
    func replace(_ values: [WorkProfile], revoke: Set<UUID>) throws {
        guard Set(values.map(\.id)).count == values.count, values.count <= 64 else { throw ModeError("Duplicate or too many profiles") }
        if let error = values.compactMap(\.validationError).first { throw ModeError(error) }
        let data = try JSONEncoder().encode(values)
        preferences.set(data, forKey: Self.key)
        profiles = values
        for id in revoke { approvals.removeValue(forKey: id.uuidString) }
        approvals = approvals.filter { key, _ in values.contains { $0.id.uuidString == key } }
        preferences.set(approvals, forKey: Self.trustKey)
    }
    func save(_ profile: WorkProfile) throws {
        var values = profiles
        if let index = values.firstIndex(where: { $0.id == profile.id }) { values[index] = profile } else { values.append(profile) }
        try replace(values, revoke: [profile.id])
    }
    func setHooksEnabled(_ enabled: Bool, profile: WorkProfile) throws {
        if enabled {
            guard !profile.scriptPaths.isEmpty else { throw ModeError("No hook scripts configured") }
            approvals[profile.id.uuidString] = try fingerprint(profile)
        } else { approvals.removeValue(forKey: profile.id.uuidString) }
        preferences.set(approvals, forKey: Self.trustKey)
    }
    func fingerprint(_ profile: WorkProfile) throws -> String {
        try inspectedScripts(profile).fingerprint
    }
    func inspectedScripts(_ profile: WorkProfile) throws -> (fingerprint: String, scripts: [String: Data]) {
        var bytes = try ControlCoding.encode(profile)
        var scripts: [String: Data] = [:]
        for path in profile.scriptPaths {
            let url = URL(fileURLWithPath: path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 1024 * 1024 else { throw ModeError("Hook must be a regular file of at most 1 MiB") }
            // Fixed-length content digests preserve file boundaries in multi-hook profiles.
            let content = try Data(contentsOf: url)
            guard content.count <= 1024 * 1024 else { throw ModeError("Hook grew beyond 1 MiB while reading") }
            scripts[path] = content
            bytes.append(contentsOf: SHA256.hash(data: content))
        }
        return (SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), scripts)
    }
    func approvedScript(_ profile: WorkProfile, path: String, expected: String) throws -> Data {
        let inspected = try inspectedScripts(profile)
        guard approvals[profile.id.uuidString] == expected, inspected.fingerprint == expected, let script = inspected.scripts[path] else {
            throw ModeError("Hook activation or content changed")
        }
        return script
    }
    func hooksEnabled(_ profile: WorkProfile) -> Bool {
        guard let approved = approvals[profile.id.uuidString], !profile.scriptPaths.isEmpty else { return false }
        return (try? fingerprint(profile)) == approved
    }
}

extension AppModel {
    func exportWorkConfiguration() throws -> Data {
        try PortableWorkConfiguration(rules: triggers.rules, profiles: profiles.profiles).validated().data()
    }
    func previewWorkConfiguration(_ data: Data, mode: ConfigurationImportMode) throws -> ConfigurationPreview {
        let incoming = try PortableWorkConfiguration.decode(data)
        let baseline = try exportWorkConfiguration()
        let current = try PortableWorkConfiguration.decode(baseline)
        // Imported rules are inspectable but inert until enabled in the rule editor.
        let rules = incoming.rules.map { rule in var rule = rule; rule.enabled = false; return rule }
        func merged<T: Identifiable>(_ old: [T], _ new: [T]) -> [T] where T.ID == UUID {
            let table = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
            let oldIDs = Set(old.map(\.id))
            return old.map { table[$0.id] ?? $0 } + new.filter { !oldIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        let result = try PortableWorkConfiguration(
            rules: mode == .replace ? rules : merged(current.rules, rules),
            profiles: mode == .replace ? incoming.profiles : merged(current.profiles, incoming.profiles)).validated()
        let after = try result.data()
        var changes: [String] = []
        func diff<T: Identifiable & Equatable>(_ old: [T], _ new: [T], label: String, name: (T) -> String) where T.ID == UUID {
            for item in old where !new.contains(where: { $0.id == item.id }) { changes.append("− \(label): \(name(item)) [\(item.id)]") }
            for item in new {
                if let previous = old.first(where: { $0.id == item.id }) {
                    if previous != item { changes.append("~ \(label): \(name(item)) [\(item.id)]") }
                } else { changes.append("+ \(label): \(name(item)) [\(item.id)]") }
            }
        }
        diff(current.rules, result.rules, label: "rule", name: { $0.name })
        diff(current.profiles, result.profiles, label: "profile", name: { $0.name })
        changes.append("Imported rules are disabled; imported hook approvals are cleared locally.")
        return .init(baseline: baseline, result: result, importedProfileIDs: Set(incoming.profiles.map(\.id)), changes: changes,
                     beforeJSON: String(decoding: baseline, as: UTF8.self), afterJSON: String(decoding: after, as: UTF8.self))
    }
    func applyWorkConfiguration(_ preview: ConfigurationPreview) throws {
        guard try exportWorkConfiguration() == preview.baseline else { throw ModeError("Configuration changed; preview the import again") }
        _ = try preview.result.validated()
        // All decoding, size checking and validation finish before either store changes.
        _ = try preview.result.data()
        try profiles.replace(preview.result.profiles, revoke: preview.importedProfileIDs)
        if let error = triggers.replaceAllRules(preview.result.rules) { throw ModeError(error) }
        record("工作配置已导入；规则与脚本需在本机确认启用。")
        onUpdate?()
    }
}
