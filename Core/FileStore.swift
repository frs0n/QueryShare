import Foundation
import Crypto

public struct Mount: Identifiable, Codable {
    public var id: String
    public var path: String
    public var name: String
}
public struct FileEntry {
    public let name: String
    public let directory: Bool
    public let size: UInt64
    public let modified: Date
}
enum ShareError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

// All access, token acquisition and SFTP routing run on the server's serial IO queue.
public final class FileStore {
    public init() {}
    private var lastFileRequest: TimeInterval = -.infinity
    public func noteFileRequest(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) { lastFileRequest = uptime }
    public func shouldYieldDiscovery(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool { uptime - lastFileRequest < 0.15 }
    public var aliases: [String: String] = [:]
    public var directRoot: URL?
    public var knownPaths = Set<String>()
    public var mounts: [Mount] = []
    public var groups: [String] = []
    public var log: (String) -> Void = { _ in }
    let fm = FileManager.default
    public var grant: (String) -> Void = { _ in }
    func acquire(_ path: String) { grant(path) }
    @discardableResult public func add(_ input: String) throws -> Mount {
        guard input.hasPrefix("/"), !input.contains("\0") else { throw ShareError.message("Enter an absolute path") }
        let path = URL(fileURLWithPath: input).standardizedFileURL.path
        if let existing = mounts.first(where: { $0.path == path }) { return existing }
        acquire(path)
        _ = try fm.attributesOfItem(atPath: path)
        let name = path == "/" ? "root" : URL(fileURLWithPath: path).lastPathComponent
        let digest = SHA256.hash(data: Data(path.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        let mount = Mount(id: name + "-" + digest, path: path, name: name)
        mounts.append(mount)
        log("Sharing \(path)")
        return mount
    }
    func resolve(_ raw: String) throws -> (URL, Mount) {
        let decoded = raw
        guard !decoded.contains("\0"), !decoded.contains("\\") else { throw ShareError.message("Invalid path") }
        let parts = decoded.split(separator: "/").map(String.init)
        if let directRoot {
            guard !parts.contains(".."), !parts.contains(".") else { throw ShareError.message("Invalid path") }
            let root = directRoot.resolvingSymlinksInPath().standardizedFileURL
            let virtual = "/" + parts.joined(separator: "/")
            let alias = aliases.keys.filter { virtual == $0 || virtual.hasPrefix($0 + "/") }.max { $0.count < $1.count }
            let url: URL
            if let alias, let destination = aliases[alias] {
                let tail = String(virtual.dropFirst(alias.count)).split(separator: "/")
                url = tail.reduce(URL(fileURLWithPath: destination)) { $0.appendingPathComponent(String($1)) }.standardizedFileURL
            } else { url = parts.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL }
            acquire(url.path); acquire(url.deletingLastPathComponent().path)
            let canonical = url.resolvingSymlinksInPath().path
            guard root.path == "/" || canonical == root.path || canonical.hasPrefix(root.path + "/") else { throw ShareError.message("Path is outside the root directory") }
            acquire(canonical)
            return (url, Mount(id: "root", path: root.path, name: "root"))
        }
        guard let id = parts.first, let mount = mounts.first(where: { $0.id == id }), !parts.contains(".."), !parts.contains(".") else { throw ShareError.message("Shared path not found") }
        acquire(mount.path)
        let root = URL(fileURLWithPath: mount.path).resolvingSymlinksInPath().standardizedFileURL
        let url = parts.dropFirst().reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard canonical == root.path || canonical.hasPrefix(root.path == "/" ? "/" : root.path + "/") else { throw ShareError.message("Symbolic link points outside the shared root") }
        // Some containers require their own extension even if their parent can be enumerated.
        if parts.count > 1 { acquire(url.path); acquire(url.deletingLastPathComponent().path) }
        return (url, mount)
    }
    public func entry(_ url: URL) throws -> FileEntry {
        let a = try fm.attributesOfItem(atPath: url.path)
        let type = a[.type] as? FileAttributeType
        guard type == .typeDirectory || type == .typeRegular || type == .typeSymbolicLink else { throw ShareError.message("Device and special files are not supported") }
        return FileEntry(name: url.lastPathComponent, directory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                         size: (a[.size] as? NSNumber)?.uint64Value ?? 0, modified: a[.modificationDate] as? Date ?? .distantPast)
    }
    func virtualDirectory(_ virtual: String) -> Bool {
        let prefix = virtual == "/" ? "/" : virtual + "/"
        return directRoot != nil && aliases.keys.contains { $0.hasPrefix(prefix) }
    }
    func listedChildren(_ virtual: String) throws -> [String] {
        let prefix = virtual == "/" ? "/" : virtual + "/"
        let names = aliases.keys.compactMap { p -> String? in
            guard p.hasPrefix(prefix) else { return nil }
            return p.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
        }
        var result = Set(names)
        do { result.formUnion(try children(resolve(virtual).0).map(\.lastPathComponent)) }
        catch { if result.isEmpty { throw error } }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    public func children(_ url: URL) throws -> [URL] {
        let prefix = url.path == "/" ? "/" : url.path + "/"
        let discovered = knownPaths.compactMap { p -> String? in
            guard p.hasPrefix(prefix) else { return nil }
            return p.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
        }
        var names = Set(discovered)
        do { names.formUnion(try fm.contentsOfDirectory(atPath: url.path)) }
        catch { if names.isEmpty { throw error } }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { url.appendingPathComponent($0) }
    }
}
