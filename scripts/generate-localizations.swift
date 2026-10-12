// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
// Development tool: translate the checked-in source keys with installed macOS language models.
import Foundation
import Translation

@main struct GenerateLocalizations {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "Localization", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "usage: generate-localizations INPUT.json OUTPUT_DIR"])
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let keys = try JSONDecoder().decode([String].self, from: Data(contentsOf: input))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try write(Dictionary(uniqueKeysWithValues: keys.map { ($0, $0) }), code: "zh-Hans", to: output)
        try write(Dictionary(uniqueKeysWithValues: keys.map { ($0, $0.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? $0) }),
                  code: "zh-Hant", to: output)

        for code in ["en", "ja", "fr", "de", "es"] {
            let session = TranslationSession(installedSource: Locale.Language(identifier: "zh-Hans"),
                                             target: Locale.Language(identifier: code))
            guard await session.isReady else {
                throw NSError(domain: "Localization", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Language model not installed: \(code)"])
            }
            var translated: [String: String] = [:]
            for offset in stride(from: 0, to: keys.count, by: 48) {
                let end = min(offset + 48, keys.count)
                let batch = Array(keys[offset..<end])
                let requests = batch.enumerated().map {
                    TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                }
                let answers = try await session.translations(from: requests)
                for answer in answers {
                    guard let id = answer.clientIdentifier.flatMap(Int.init), batch.indices.contains(id) else { continue }
                    translated[batch[id]] = answer.targetText
                }
                guard batch.allSatisfy({ translated[$0] != nil }) else {
                    throw NSError(domain: "Localization", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Incomplete \(code) batch at \(offset)"])
                }
                print("\(code): \(end)/\(keys.count)")
                fflush(stdout)
            }
            try write(translated, code: code, to: output)
        }
    }

    private static func write(_ pairs: [String: String], code: String, to output: URL) throws {
        let folder = output.appendingPathComponent("\(code).lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lines = try pairs.keys.sorted().map { key in
            let quotedKey = String(data: try JSONEncoder().encode(key), encoding: .utf8)!
            let quotedValue = String(data: try JSONEncoder().encode(pairs[key]!), encoding: .utf8)!
            return "\(quotedKey) = \(quotedValue);"
        }
        try (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
    }
}
