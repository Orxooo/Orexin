// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit
import WakeMacCore

enum UnlockedWorkAuthorization {
    @MainActor private static var pendingAlert: NSAlert?
    @MainActor static func cancelPending() {
        if pendingAlert != nil { NSApp.abortModal() }
    }
    @MainActor static func requestPassword() throws -> Data {
        try requestPassword(remembering: UserDefaults.standard.bool(forKey: UnlockedWorkCredentials.preferenceKey))
    }
    @MainActor static func requestPassword(remembering: Bool) throws -> Data {
        guard DisplayState.read().sessionLocked != true else { throw ModeError("请先解锁 Mac，再开始保持未锁定的工作模式。") }
        let alert = NSAlert()
        alert.messageText = L("授权本次工作保持未锁定")
        alert.informativeText = L(remembering
            ? "输入 Mac 账户密码以授权保持未锁定。认证成功后，密码将保存到本机钥匙串，供后续工作自动授权。工作结束后恢复即时密码保护。"
            : "输入 Mac 账户密码以授权本次工作保持未锁定。密码仅用于本次认证，工作结束后恢复即时密码保护。")
        alert.addButton(withTitle: L("授权本次工作"))
        alert.addButton(withTitle: L("取消"))
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        field.placeholderString = L("Mac 账户密码")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        pendingAlert = alert
        defer { pendingAlert = nil }
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else {
            field.stringValue = ""
            throw ModeError("已取消授权，系统密码要求未更改。")
        }
        let data = Data((field.stringValue + "\n").utf8)
        field.stringValue = ""
        return data
    }

    /// sysadminctl's documented password prompt reads standard input when there
    /// is no controlling terminal. No password is placed in arguments or files.
    static func disableScreenLock(password: Data) throws {
        guard DisplayState.read().sessionLocked != true else { throw ModeError("请先解锁 Mac，再开始保持未锁定的工作模式。") }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl")
        process.arguments = ["-screenLock", "off", "-password", "-"]
        process.standardInput = input; process.standardOutput = output; process.standardError = output
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        defer {
            timeout.cancel()
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        try input.fileHandleForWriting.write(contentsOf: password)
        try input.fileHandleForWriting.close()
        // Discard diagnostic output rather than retain authentication details.
        _ = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit else { throw UnlockedWorkAuthenticationError.interrupted }
        guard process.terminationStatus == 0 else { throw UnlockedWorkAuthenticationError.rejected }
        // sysadminctl can report an authentication failure with exit status 0.
        let status = try CommandRunner.run("/usr/sbin/sysadminctl", ["-screenLock", "status"], timeout: 5)
        guard SystemParsing.lockPolicy(status) == .off else { throw UnlockedWorkAuthenticationError.rejected }
    }
}
