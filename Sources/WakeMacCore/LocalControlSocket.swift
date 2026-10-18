// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation
import Darwin

/// One newline-delimited JSON request/response per connection, same-UID only.
/// The socket never grants privileged helper or authentication capabilities.
public enum LocalControlSocket {
    public static var defaultPath: String { "/tmp/orexin-\(getuid())/control.sock" }
    public static func call(_ message: ControlMessage, path: String = defaultPath) throws -> ControlReply {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure("socket") }
        defer { close(fd) }
        configure(fd)
        var address = try address(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw ModeError("Orexin is unavailable at \(path). Start the background service with orexin service-start. (\(String(cString: strerror(errno))))") }
        guard sameUser(fd) else { throw ModeError("Local server belongs to a different user") }
        try write(ControlCoding.encode(message), to: fd)
        return try ControlCoding.decode(ControlReply.self, from: read(fd, limit: 512 * 1024))
    }
    fileprivate static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path), !path.utf8.contains(0) else { throw ModeError("Unix socket path is too long or invalid") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    fileprivate static func configure(_ fd: Int32) {
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    fileprivate static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }
    fileprivate static func read(_ fd: Int32, limit: Int) throws -> Data {
        let deadline = Date().addingTimeInterval(10)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw failure("read (closed or timed out)") }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= limit else { throw ModeError("Local control frame exceeds size limit") }
            if let newline = data.firstIndex(of: 10) {
                guard newline == data.count - 1 else { throw ModeError("Only one control message is allowed per connection") }
                return data.prefix(upTo: newline)
            }
        }
        throw ModeError("Local control read timed out")
    }
    fileprivate static func write(_ data: Data, to fd: Int32) throws {
        var frame = data; frame.append(10)
        try frame.withUnsafeBytes { buffer in
            var sent = 0
            let deadline = Date().addingTimeInterval(10)
            while sent < buffer.count && Date() < deadline {
                let count = send(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw failure("write") }
                sent += count
            }
            guard sent == buffer.count else { throw ModeError("Local control write timed out") }
        }
    }
    fileprivate static func failure(_ operation: String) -> ModeError { ModeError("Local control \(operation): " + String(cString: strerror(errno))) }
}

public final class LocalControlServer: @unchecked Sendable {
    private let source: DispatchSourceRead
    private let path: String
    private let lockFD: Int32
    public init(path: String = LocalControlSocket.defaultPath, handler: @escaping @Sendable (ControlMessage) async -> ControlReply) throws {
        self.path = path
        let parent = (path as NSString).deletingLastPathComponent
        if mkdir(parent, 0o700) != 0 && errno != EEXIST { throw LocalControlSocket.failure("create directory") }
        var info = stat()
        guard lstat(parent, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw ModeError("Control directory must be a private, current-user directory (0700), not a symlink")
        }
        let lock = open(path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw LocalControlSocket.failure("open lock") }
        guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); throw ModeError("Another Orexin instance owns the local control endpoint") }
        lockFD = lock
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { close(lock); throw LocalControlSocket.failure("socket") }
        do {
            LocalControlSocket.configure(fd)
            if lstat(path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else { throw ModeError("Refusing to replace a non-socket control path") }
                guard unlink(path) == 0 else { throw LocalControlSocket.failure("remove stale socket") }
            }
            var address = try LocalControlSocket.address(path)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else { throw LocalControlSocket.failure("bind/listen") }
        } catch { close(fd); close(lock); throw error }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let queue = DispatchQueue(label: "com.orxooo.Orexin.local-control", qos: .utility)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            LocalControlSocket.configure(client)
            guard LocalControlSocket.sameUser(client) else { return }
            do {
                let request = try ControlCoding.decode(ControlMessage.self, from: LocalControlSocket.read(client, limit: 64 * 1024))
                let result = ReplyBox(), semaphore = DispatchSemaphore(value: 0)
                let task = Task { result.set(await handler(request)); semaphore.signal() }
                guard semaphore.wait(timeout: .now() + 15) == .success else {
                    task.cancel(); throw ModeError("Application did not respond in time")
                }
                try LocalControlSocket.write(ControlCoding.encode(result.get()), to: client)
            } catch { try? LocalControlSocket.write(ControlCoding.encode(ControlReply(ok: false, error: error.localizedDescription)), to: client) }
        }
        source.setCancelHandler { close(fd); unlink(path); close(lock) }
        source.resume()
    }
    public func stop() { source.cancel() }
    deinit { source.cancel() }
}
private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ControlReply(ok: false, error: "No response")
    func set(_ value: ControlReply) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> ControlReply { lock.lock(); defer { lock.unlock() }; return value }
}
