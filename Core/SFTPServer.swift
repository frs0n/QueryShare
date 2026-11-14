import Foundation
import Crypto
import NIOCore
import NIOPosix
import NIOSSH
import Darwin

private final class PasswordAuth: NIOSSHServerUserAuthenticationDelegate {
    let username: String
    let password: String
    let log: (String) -> Void
    init(_ username: String, _ password: String, log: @escaping (String) -> Void) { self.username = username; self.password = password; self.log = log }
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .password }
    func requestReceived(request: NIOSSHUserAuthenticationRequest, responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        guard case .password(let value) = request.request else {
            responsePromise.succeed(.failure); return // Normal SSH method negotiation.
        }
        if request.username == username, SHA256.hash(data: Data(value.password.utf8)) == SHA256.hash(data: Data(password.utf8)) {
            log("Authenticated: \(username)"); responsePromise.succeed(.success)
        } else { log("Password authentication failed"); responsePromise.succeed(.failure) }
    }
}
private final class CloseOnError: ChannelInboundHandler {
    typealias InboundIn = Any
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}

public final class SFTPServer {
    public let io = DispatchQueue(label: "QueryShare.files", qos: .userInitiated)
    public let store = FileStore()
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var listener: Channel?
    private var clients: [ObjectIdentifier: Channel] = [:] // guarded by lock
    private let lock = NSLock()
    private var stopping = false
    public private(set) var fingerprint = ""
    public init() {}
    public static func connectionNotice(username: String) -> String {
        """
        QueryShare | Agent-driven iPhone customization over SFTP
        File access: worse_query (App Group container-query sandbox escape).
        Account: \(username) | Root: /
        /Containers is a virtual index mapped to real iOS container paths.
        Categories: Apps, Extensions, AppGroups, Daemons, SystemGroups, SystemData.
        Discovery runs automatically; refresh directory listings as results appear.
        Original absolute paths remain accessible. Changes affect the real files.
        Read/write access follows the permissions granted by iOS; this is not root access.
        SFTP only: no interactive shell, remote commands, or port forwarding.

        Agent tutorials: /Agent/README.md (read over SFTP).
        Categories: display, device, intelligence/region, multitasking, internal flags,
        configuration, wallpapers/themes, app sounds/launch images, app data, file editing.
        Tutorials contain exact paths, keys, values, apply and restore steps.

        """
    }
    deinit { try? group.syncShutdownGracefully() }

    // Call start/stop from a background queue, never the main thread or event loop.
    public func start(host bindHost: String = "0.0.0.0", port: Int, username: String = "mobile", password: String, keyURL: URL) throws {
        guard password.count >= 12 else { throw ShareError.message("Password must contain at least 12 characters") }
        let key: Curve25519.Signing.PrivateKey
        if FileManager.default.fileExists(atPath: keyURL.path) {
            key = try .init(rawRepresentation: Data(contentsOf: keyURL))
        } else {
            key = .init()
            try key.rawRepresentation.write(to: keyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
        let host = NIOSSHPrivateKey(ed25519Key: key)
        let publicString = String(openSSHPublicKey: host.publicKey)
        if let base64 = publicString.split(separator: " ").last, let blob = Data(base64Encoded: String(base64)) {
            fingerprint = "SHA256:" + Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        }
        lock.lock(); stopping = false; lock.unlock()
        listener = try ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .childChannelInitializer { channel in
                self.lock.lock()
                let allowed = !self.stopping && self.clients.count < 8
                if allowed { self.clients[ObjectIdentifier(channel)] = channel }
                self.lock.unlock()
                guard allowed else { return channel.close() }
                channel.closeFuture.whenComplete { _ in
                    self.lock.lock(); self.clients.removeValue(forKey: ObjectIdentifier(channel)); self.lock.unlock()
                }
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers([
                    IdleStateHandler(readTimeout: .seconds(300)),
                    NIOSSHHandler(role: .server(.init(hostKeys: [host], userAuthDelegate: PasswordAuth(username, password, log: { message in self.io.async { self.store.log(message) } }), banner: .init(message: Self.connectionNotice(username: username), languageTag: "en"))), allocator: channel.allocator,
                        inboundChildChannelInitializer: { child, type in
                            guard type == .session else { return child.eventLoop.makeFailedFuture(ShareError.message("SFTP only")) }
                            return child.eventLoop.makeCompletedFuture { try child.pipeline.syncOperations.addHandler(SFTPHandler(store: self.store, io: self.io)) }
                        }), CloseOnError(), IdleCloser()
                ])
                }
            }.bind(host: bindHost, port: port).wait()
    }
    public func stop() {
        lock.lock(); stopping = true; let active = Array(clients.values); lock.unlock()
        try? listener?.close().wait(); listener = nil
        for client in active { try? client.close().wait() }
        io.sync {} // complete all pending file work before releasing grants
    }
}
private final class IdleCloser: ChannelInboundHandler {
    typealias InboundIn = Any
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is IdleStateHandler.IdleStateEvent { context.close(promise: nil) }
        else { context.fireUserInboundEventTriggered(event) }
    }
}

private extension ByteBuffer {
    mutating func string() throws -> String {
        guard let n: UInt32 = readInteger(), n <= 1_048_576, let value = readString(length: Int(n)), !value.contains("\0") else { throw ShareError.message("Invalid SFTP string") }
        return value
    }
    mutating func u32() throws -> UInt32 { guard let n: UInt32 = readInteger() else { throw ShareError.message("Invalid packet") }; return n }
    mutating func u64() throws -> UInt64 { guard let n: UInt64 = readInteger() else { throw ShareError.message("Invalid packet") }; return n }
    mutating func text(_ s: String) { writeInteger(UInt32(s.utf8.count)); writeString(s) }
}
private final class OpenItem {
    let fd: Int32?
    var names: [String]?
    let path: String
    var index = 0
    init(fd: Int32? = nil, names: [String]? = nil, path: String) { self.fd = fd; self.names = names; self.path = path }
    deinit { if let fd { close(fd) } }
}
private final class SFTPHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData
    let store: FileStore
    let io: DispatchQueue
    var input = ByteBuffer()
    var active = false
    var initialized = false // IO queue
    var handles: [String: OpenItem] = [:] // IO queue
    init(store: FileStore, io: DispatchQueue) { self.store = store; self.io = io }
    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.autoRead, value: false).whenSuccess { context.read() }
    }
    func channelReadComplete(context: ChannelHandlerContext) {
        let channel = context.channel
        io.async { channel.eventLoop.execute { channel.read() } }
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let request = event as? SSHChannelRequestEvent.SubsystemRequest {
            if request.subsystem == "sftp" && !active {
                active = true
                if request.wantReply { context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil) }
            } else if request.wantReply { context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil) }
        } else if event is SSHChannelRequestEvent.ExecRequest || event is SSHChannelRequestEvent.ShellRequest || event is SSHChannelRequestEvent.PseudoTerminalRequest {
            context.triggerUserOutboundEvent(ChannelFailureEvent(), promise: nil)
        } else { context.fireUserInboundEventTriggered(event) }
    }
    func channelInactive(context: ChannelHandlerContext) {
        io.async { self.handles.removeAll() }
        context.fireChannelInactive()
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let incoming = unwrapInboundIn(data)
        guard active, case .channel = incoming.type, case .byteBuffer(var bytes) = incoming.data else { context.close(promise: nil); return }
        input.writeBuffer(&bytes)
        while let size: UInt32 = input.getInteger(at: input.readerIndex) {
            guard size > 0, size <= 1_048_576 else { context.close(promise: nil); return }
            guard input.readableBytes >= Int(size) + 4 else { break }
            input.moveReaderIndex(forwardBy: 4)
            let packet = input.readSlice(length: Int(size))!
            let channel = context.channel
            // Bound queued work through manual read flow control (one inbound batch at a time).
            io.async {
                let reply = self.process(packet)
                channel.eventLoop.execute {
                    var wire = channel.allocator.buffer(capacity: reply.readableBytes + 4)
                    wire.writeInteger(UInt32(reply.readableBytes)); var payload = reply; wire.writeBuffer(&payload)
                    channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(wire)), promise: nil)
                }
            }
        }
        input.discardReadBytes()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
    private func status(_ id: UInt32, _ code: UInt32, _ message: String = "") -> ByteBuffer {
        var b = ByteBuffer(); b.writeInteger(UInt8(101)); b.writeInteger(id); b.writeInteger(code); b.text(message); b.text(""); return b
    }
    private func normal(_ value: String) -> String {
        var parts: [Substring] = []
        for component in value.split(separator: "/") {
            if component == "." { continue }
            if component == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(component) }
        }
        return "/" + parts.joined(separator: "/")
    }
    private func path(_ value: String, writing: Bool = false) throws -> URL {
        let url = try store.resolve(normal(value)).0
        if writing, store.isTutorial(url) { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
        return url
    }
    private func item(_ name: String) throws -> OpenItem { guard let h = handles[name] else { throw ShareError.message("Invalid handle") }; return h }
    private func attr(_ st: stat) -> ByteBuffer {
        var b = ByteBuffer(); b.writeInteger(UInt32(15)); b.writeInteger(UInt64(st.st_size)); b.writeInteger(st.st_uid); b.writeInteger(st.st_gid); b.writeInteger(UInt32(st.st_mode)); b.writeInteger(UInt32(clamping: st.st_atimespec.tv_sec)); b.writeInteger(UInt32(clamping: st.st_mtimespec.tv_sec)); return b
    }
    private func attributes(_ value: String, follow: Bool = true) throws -> ByteBuffer {
        var st = stat()
        if normal(value) == "/" || store.virtualDirectory(normal(value)) { st.st_mode = mode_t(S_IFDIR | 0o755); return attr(st) }
        let target = try path(value)
        let result = follow ? stat(target.path, &st) : lstat(target.path, &st)
        guard result == 0 else {
            let prefix = target.path == "/" ? "/" : target.path + "/"
            if store.directRoot != nil, store.knownPaths.contains(where: { $0.hasPrefix(prefix) }) {
                st.st_mode = mode_t(S_IFDIR | 0o755); return attr(st)
            }
            throw posix()
        }; return attr(st)
    }
    private func posix() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    private func check(_ result: Int32) throws { if result < 0 { throw posix() } }
    private func setAttributes(_ b: inout ByteBuffer, fd: Int32) throws {
        let flags = try b.u32()
        if flags & 1 != 0 { let size = try b.u64(); guard size <= UInt64(Int64.max) else { throw ShareError.message("File is too large") }; try check(ftruncate(fd, off_t(size))) }
        if flags & 2 != 0 { let uid = try b.u32(), gid = try b.u32(); try check(fchown(fd, uid, gid)) }
        if flags & 4 != 0 { try check(fchmod(fd, mode_t(try b.u32() & 0o7777))) }
        if flags & 8 != 0 {
            let atime = try b.u32(), mtime = try b.u32()
            var times = [timeval(tv_sec: Int(atime), tv_usec: 0), timeval(tv_sec: Int(mtime), tv_usec: 0)]
            try check(futimes(fd, &times))
        }
        if flags & 0x80000000 != 0 {
            let count = try b.u32(); guard count < 128 else { throw ShareError.message("Too many attributes") }
            for _ in 0..<count { _ = try b.string(); _ = try b.string() }
        }
    }
    private func process(_ original: ByteBuffer) -> ByteBuffer {
        store.noteFileRequest()
        var b = original
        guard let type: UInt8 = b.readInteger() else { return status(0, 5, "Missing packet type") }
        if type == 1 {
            guard !initialized, let _: UInt32 = b.readInteger() else { return status(0, 5) }
            initialized = true
            var reply = ByteBuffer(); reply.writeInteger(UInt8(2)); reply.writeInteger(UInt32(3)); reply.text("posix-rename@openssh.com"); reply.text("1"); reply.text("fsync@openssh.com"); reply.text("1"); return reply
        }
        guard initialized, let id: UInt32 = b.readInteger() else { return status(0, 5, "Initialize the session first") }
        do {
            if let operation = [UInt8(3): "open", 9: "setstat", 13: "remove", 14: "mkdir", 15: "rmdir", 18: "rename", 20: "symlink"][type] {
                var inspect = b
                if let target = try? inspect.string() { store.log("\(operation) \(target)") }
            }
            switch type {
            case 16: // REALPATH
                let p = normal(try b.string())
                if p != "/" { _ = try path(p) }
                var r = ByteBuffer(); r.writeInteger(UInt8(104)); r.writeInteger(id); r.writeInteger(UInt32(1)); r.text(p); r.text(p); r.writeInteger(UInt32(0)); return r
            case 7, 17: // LSTAT, STAT
                var a = try attributes(b.string(), follow: type == 17)
                var r = ByteBuffer(); r.writeInteger(UInt8(105)); r.writeInteger(id); r.writeBuffer(&a); return r
            case 8: // FSTAT
                let h = try item(b.string()); var st = stat()
                guard let fd = h.fd else { var a = try attributes(h.path); var r = ByteBuffer(); r.writeInteger(UInt8(105)); r.writeInteger(id); r.writeBuffer(&a); return r }
                try check(fstat(fd, &st)); var a = attr(st); var r = ByteBuffer(); r.writeInteger(UInt8(105)); r.writeInteger(id); r.writeBuffer(&a); return r
            case 11, 3: // OPENDIR, OPEN
                guard handles.count < 128 else { return status(id, 4, "Open handle limit reached") }
                let p = normal(try b.string()); let h: OpenItem
                if type == 11 {
                    let names = p == "/" && store.directRoot == nil ? (store.mounts.map(\.id) + ["Agent"]) : try store.listedChildren(p)
                    h = OpenItem(names: names, path: p)
                } else {
                    let flags = try b.u32()
                    var f: Int32 = flags & 1 != 0 ? (flags & 2 != 0 ? O_RDWR : O_RDONLY) : O_WRONLY
                    if flags & 4 != 0 { f |= O_APPEND }; if flags & 8 != 0 { f |= O_CREAT }
                    if flags & 16 != 0 { f |= O_TRUNC }; if flags & 32 != 0 { f |= O_EXCL }
                    let url = try path(p, writing: flags != 1)
                    let fd = open(url.resolvingSymlinksInPath().path, f | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW, 0o644)
                    guard fd >= 0 else { throw posix() }
                    var st = stat()
                    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { close(fd); throw ShareError.message("Only regular files are supported") }
                    h = OpenItem(fd: fd, path: p)
                }
                let token = UUID().uuidString; handles[token] = h
                var r = ByteBuffer(); r.writeInteger(UInt8(102)); r.writeInteger(id); r.text(token); return r
            case 4: // CLOSE
                let token = try b.string(); guard handles.removeValue(forKey: token) != nil else { return status(id, 4, "Invalid handle") }; return status(id, 0)
            case 12: // READDIR
                let h = try item(b.string()); guard let names = h.names else { return status(id, 4) }
                if h.index >= names.count { return status(id, 1, "EOF") }
                var r = ByteBuffer(); r.writeInteger(UInt8(104)); r.writeInteger(id)
                var records = ByteBuffer(); var count: UInt32 = 0
                while h.index < names.count, count < 64 {
                    let name = names[h.index]; h.index += 1
                    let p = h.path == "/" ? "/" + name : h.path + "/" + name
                    guard var a = try? attributes(p, follow: false) else { continue }
                    records.text(name); records.text(name); records.writeBuffer(&a); count += 1
                }
                r.writeInteger(count); r.writeBuffer(&records); return r
            case 5: // READ, bounded random access
                let h = try item(b.string()), offset = try b.u64(), length = min(try b.u32(), 262144)
                guard let fd = h.fd, offset <= UInt64(Int64.max) else { return status(id, 4) }
                var data = [UInt8](repeating: 0, count: Int(length))
                let n = pread(fd, &data, data.count, off_t(offset)); if n < 0 { throw posix() }; if n == 0 { return status(id, 1, "EOF") }
                var r = ByteBuffer(); r.writeInteger(UInt8(103)); r.writeInteger(id); r.writeInteger(UInt32(n)); r.writeBytes(data.prefix(n)); return r
            case 6: // WRITE
                let h = try item(b.string()), offset = try b.u64(), n = try b.u32()
                guard let fd = h.fd, offset <= UInt64(Int64.max), n <= 524288, let bytes = b.readBytes(length: Int(n)) else { return status(id, 5) }
                try bytes.withUnsafeBytes { ptr in
                    var done = 0
                    while done < ptr.count {
                        let result = pwrite(fd, ptr.baseAddress!.advanced(by: done), ptr.count - done, off_t(offset) + off_t(done))
                        if result < 0 { if errno == EINTR { continue }; throw posix() }
                        if result == 0 { throw ShareError.message("Write did not complete") }; done += result
                    }
                }
                return status(id, 0)
            case 9, 10: // SETSTAT, FSETSTAT
                let token = try b.string(); let fd: Int32; let owned: Bool
                if type == 10 { _ = try path(item(token).path, writing: true); guard let existing = try item(token).fd else { return status(id, 4) }; fd = existing; owned = false }
                else { let flags: UInt32 = b.getInteger(at: b.readerIndex) ?? 0; fd = open(try path(token, writing: true).resolvingSymlinksInPath().path, (flags & 1 != 0 ? O_WRONLY : O_RDONLY) | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC); owned = true; guard fd >= 0 else { throw posix() } }
                defer { if owned { close(fd) } }; try setAttributes(&b, fd: fd); return status(id, 0)
            case 13, 15: // REMOVE, RMDIR
                let p = try path(b.string(), writing: true); try check(type == 13 ? unlink(p.path) : rmdir(p.path)); return status(id, 0)
            case 14: // MKDIR
                let p = try path(b.string(), writing: true); try check(mkdir(p.path, 0o755)); return status(id, 0)
            case 18: // RENAME (SFTP v3 no-overwrite)
                let from = try path(b.string(), writing: true), to = try path(b.string(), writing: true)
                try check(renamex_np(from.path, to.path, UInt32(RENAME_EXCL))); return status(id, 0)
            case 19: // READLINK
                let p = try path(b.string()); let dest = try store.fm.destinationOfSymbolicLink(atPath: p.path)
                var r = ByteBuffer(); r.writeInteger(UInt8(104)); r.writeInteger(id); r.writeInteger(UInt32(1)); r.text(dest); r.text(dest); r.writeInteger(UInt32(0)); return r
            case 20: // OpenSSH SFTP v3 SYMLINK: target, then link path
                let target = try b.string(), link = try b.string()
                guard !target.hasPrefix("/") || store.directRoot != nil else { return status(id, 4, "Use a relative link target within the shared directory") }
                let base = (normal(link) as NSString).deletingLastPathComponent
                let virtualTarget = target.hasPrefix("/") ? target : base + "/" + target
                let resolvedTarget = try path(virtualTarget), linkURL = try path(link, writing: true)
                let mountA = try store.resolve(normal(virtualTarget)).1
                let mountB = try store.resolve(normal(link)).1
                guard mountA.id == mountB.id else { return status(id, 3, "Link and target must be in the same share") }
                _ = resolvedTarget
                try check(symlink(target.hasPrefix("/") ? resolvedTarget.path : target, linkURL.path)); return status(id, 0)
            case 200:
                let name = try b.string()
                if name == "posix-rename@openssh.com" {
                    let from = try path(b.string(), writing: true), to = try path(b.string(), writing: true)
                    try check(rename(from.path, to.path)); return status(id, 0)
                }
                if name == "fsync@openssh.com" {
                    guard let fd = try item(b.string()).fd else { return status(id, 4) }
                    try check(fsync(fd)); return status(id, 0)
                }
                return status(id, 8, "Extension not supported")
            default: return status(id, 8, "SFTP operation not supported")
            }
        } catch {
            let e = error as NSError
            let code: UInt32 = e.domain == NSPOSIXErrorDomain && e.code == ENOENT ? 2 : ((e.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(e.code)) ? 3 : 4)
            store.log("SFTP \(type): \(error.localizedDescription)")
            return status(id, code, error.localizedDescription)
        }
    }
}
