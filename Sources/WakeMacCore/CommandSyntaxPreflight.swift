// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

public enum CommandSyntaxPreflight {
    /// Parse a noninteractive zsh command without executing it or loading user startup files.
    public static func check(command: String, directory: String) throws {
        let path = (directory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ModeError("命令不能为空，工作目录必须存在。")
        }
        _ = try CommandRunner.run("/bin/zsh", ["-f", "-n", "-c", command], timeout: 5)
    }
}
