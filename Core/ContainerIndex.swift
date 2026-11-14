import Foundation

/// Persisted discovery identities; a bounded search is separate from a full scan.
public struct ContainerIndex: Codable {
    public struct Record: Codable, Equatable {
        public var path: String
        public var witnessPath: String?
        public var inode: UInt64?
        public var identifier: String?
        public var name: String?
        public init(path: String, inode: UInt64? = nil, identifier: String? = nil, name: String? = nil) {
            self.path = path; self.inode = inode; self.identifier = identifier; self.name = name
        }
    }
    public var version = 2
    public var volume: String
    public var build: String
    public var databasePaths = Set<String>()
    public var storePath: String?
    public var nextInode: UInt64 = 1
    public var scannedThrough: UInt64 = 0
    public var searchBelow: UInt64?
    public var searchUpper: UInt64 = 0
    public var lastSearch: Date?
    public var records: [String: Record] = [:]
    public init(volume: String, build: String) { self.volume = volume; self.build = build }
    public mutating func validate(volume: String, build: String, upper: UInt64, resolve: (UInt64) -> String?) {
        guard version == 2, self.volume == volume, self.build == build, scannedThrough <= upper, nextInode <= upper + 1 else {
            self = .init(volume: volume, build: build); return
        }
        records = records.filter { path, record in
            guard let inode = record.inode else { return true }
            let witness = record.witnessPath ?? path
            guard witness == path || witness.hasPrefix(path + "/") else { return false }
            return resolve(inode) == witness
        }
    }
    /// Every byte of a range must be examined before advancing the high-water mark.
    public mutating func advance(next: UInt64) {
        nextInode = max(nextInode, next)
        scannedThrough = max(scannedThrough, nextInode - 1)
    }
    public func aliases() -> [String: String] {
        var result: [String: String] = [:]
        for record in records.values.sorted(by: { $0.path < $1.path }) {
            let path = record.path
            let category: String
            if path.contains("/Data/Application/") { category = "Apps" }
            else if path.contains("/Data/PluginKitPlugin/") { category = "Extensions" }
            else if path.contains("/Shared/AppGroup/") { category = "AppGroups" }
            else if path.contains("/Data/InternalDaemon/") { category = "Daemons" }
            else if path.contains("/Shared/SystemGroup/") { category = "SystemGroups" }
            else if path.contains("/containers/Data/System/") { category = "SystemData" }
            else { continue }
            let identity = record.identifier ?? URL(fileURLWithPath: path).lastPathComponent
            let title = record.name.map { "\($0) [\(identity)]" } ?? identity
            let label = title.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || $0 == "/" || $0 == "\\" ? "_" : String($0) }.joined()
            var alias = "/Containers/\(category)/\(label)"
            if result[alias] != nil { alias += " [\(URL(fileURLWithPath: path).lastPathComponent)]" }
            result[alias] = path
        }
        return result
    }
}
