// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import XCTest
@testable import WakeMacCore

final class CommandSyntaxPreflightTests: XCTestCase {
    func testValidSyntaxDoesNotExecuteCommandsOrSubstitutions() throws {
        let directory = FileManager.default.temporaryDirectory
        let marker = directory.appendingPathComponent("wakemac-preflight-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let quoted = "'" + marker.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "print $(/usr/bin/touch \(quoted))\n/usr/bin/touch \(quoted)\nexec /usr/bin/touch \(quoted)"
        try CommandSyntaxPreflight.check(command: command, directory: directory.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Syntax preflight must never run the submitted command.")
    }

    func testMalformedSyntaxReportsTheShellDiagnostic() {
        XCTAssertThrowsError(try CommandSyntaxPreflight.check(command: "if true; then\n    print unfinished\n", directory: FileManager.default.temporaryDirectory.path)) { error in
            XCTAssertTrue(error.localizedDescription.contains("parse error"))
        }
    }

    func testEmptyCommandAndMissingDirectoryAreRejected() {
        XCTAssertThrowsError(try CommandSyntaxPreflight.check(command: " \n ", directory: FileManager.default.temporaryDirectory.path))
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        XCTAssertThrowsError(try CommandSyntaxPreflight.check(command: "print ok", directory: missing))
    }
}
