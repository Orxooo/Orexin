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
        guard DisplayState.read().sessionLocked != true else { throw ModeError("请先解锁 Mac，再开始保持未锁定的工作模式。") }
        let alert = NSAlert()
        alert.messageText = L("授权本次工作保持未锁定")
        alert.informativeText = L("熄屏或合盖后无需密码即可返回桌面，附近的人也能访问这台 Mac。输入 Mac 账户密码以授权本次工作；Orexin 不保存密码。工作结束后自动恢复即时密码保护。")
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
        guard process.terminationStatus == 0 else { throw ModeError("macOS 未接受授权；请确认账户密码，或检查设备管理策略。") }
    }
}
