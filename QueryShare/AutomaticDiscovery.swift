import Foundation
import QueryShareCore

// Search/parse on a utility queue; only sandbox token changes use server.io.
final class AutomaticDiscovery {
    let server: SFTPServer
    let access: AccessManager
    let queue = DispatchQueue(label: "QueryShare.discovery", qos: .utility)
    let lifetime = ScanControl()
    private let lock = NSLock()
    private var deep: ScanControl?
    private var refreshing = false
    private var index: ContainerIndex?
    private var upper: UInt64 = 0
    private var lastCheckpoint: TimeInterval = 0
    private var batchCounter = 0
    private var storeSignature: String?
    var onDeepState: (Bool) -> Void = { _ in }
    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("QueryShare-container-index.json")

    init(server: SFTPServer, access: AccessManager) { self.server = server; self.access = access }
    func cancel() { lifetime.cancel(); stopDeepScan() }
    func start() { refresh() }
    func refresh(force: Bool = false) {
        lock.lock(); guard !refreshing else { lock.unlock(); return }; refreshing = true; lock.unlock()
        queue.async { [self] in
            defer {
                lock.lock(); refreshing = false; lock.unlock()
                // A failed shortcut must never leave discovery waiting for a button.
                if !lifetime.cancelled, upper > 0, let next = index?.nextInode, next <= upper,
                   server.io.sync(execute: { !access.groups.isEmpty && !access.cacheUnsafe }) {
                    startDeepScan()
                }
            }
            guard !lifetime.cancelled else { return }
            server.io.sync { access.refreshGroups() }
            #if !targetEnvironment(simulator)
            prepareIndex()
            #endif
            quickDirectories()
            saveAndPublish()
            #if !targetEnvironment(simulator)
            guard !lifetime.cancelled, server.io.sync(execute: { !access.groups.isEmpty && !access.cacheUnsafe }) else { saveAndPublish(); return }
            if let remembered = index?.storePath, loadStore(remembered) {
                index?.lastSearch = Date(); saveAndPublish(); return
            }
            let last = index?.lastSearch ?? .distantPast
            if force || Date().timeIntervalSince(last) >= 600 { findStore(seconds: 5) }
            #endif
            saveAndPublish()
        }
    }
    private func report(_ message: String) { server.io.async { self.server.store.log(message) } }
    private func prepareIndex() {
        guard let volume = QSDiscoveryVolume(), let volumeID = volume["volume"] as? String,
              let build = volume["build"] as? String, let maxID = volume["upper"] as? NSNumber,
              maxID.uint64Value < UInt64.max else { report("Index: could not determine the data-volume inode bound"); return }
        report("Scan volume \(volumeID), /var volume \(volume["varVolume"] ?? "?"), mobile volume \(volume["mobileVolume"] ?? "?"), probe verified")
        upper = maxID.uint64Value
        if index == nil { index = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(ContainerIndex.self, from: $0) } }
        if index == nil { index = ContainerIndex(volume: volumeID, build: build) }
        index?.validate(volume: volumeID, build: build, upper: upper, resolve: { QSDiscoveryResolve($0) })
    }
    private func quickDirectories() {
        guard !lifetime.cancelled else { return }
        if index == nil { index = ContainerIndex(volume: "native", build: ProcessInfo.processInfo.operatingSystemVersionString) }
        for base in AccessManager.containers {
            if lifetime.cancelled { return }
            let paths: [String] = server.io.sync {
                access.grant(base)
                return (try? FileManager.default.contentsOfDirectory(atPath: base))?.map { base + "/" + $0 } ?? []
            }
            for path in paths { remember(path) }
        }
        for name in ["systemgroup.com.apple.mobilegestaltcache", "systemgroup.com.apple.configurationprofiles"] {
            let path = "/private/var/containers/Shared/SystemGroup/" + name
            let exists = server.io.sync { access.grant(path); return (try? FileManager.default.attributesOfItem(atPath: path)) != nil }
            if exists { remember(path) }
        }
    }
    @discardableResult private func remember(_ path: String, inode: UInt64? = nil, identifier: String? = nil, name: String? = nil, witness: String? = nil) -> Bool {
        guard !path.contains("\0"), AccessManager.containers.contains(where: { base in
            path.hasPrefix(base + "/") && !path.dropFirst(base.count + 1).contains("/")
        }) else { return false }
        let previous = index?.records[path]
        var record = index?.records[path] ?? .init(path: path)
        if let inode, record.inode == nil { record.inode = inode; record.witnessPath = witness }
        if let identifier { record.identifier = identifier }
        if let name { record.name = name }
        index?.records[path] = record
        return previous != record
    }
    private func loadStore(_ hint: String) -> Bool {
        if lifetime.cancelled { return false }
        let file = URL(fileURLWithPath: hint)
        // Prefer the current store after an OS update left an older schema nearby.
        let candidates: [(URL, Date)] = server.io.sync {
            access.grant(hint)
            return ((try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: [.contentModificationDateKey])) ?? [file])
                .filter { $0.lastPathComponent.hasPrefix("com.apple.LaunchServices-") && $0.pathExtension == "csstore" }
                .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
                .sorted { $0.1 > $1.1 }
        }
        for (candidate, _) in candidates {
            do {
                let before = try FileManager.default.attributesOfItem(atPath: candidate.path)
                guard let bytes = before[.size] as? NSNumber, (4096...67_108_864).contains(bytes.intValue), before[.type] as? FileAttributeType == .typeRegular else { continue }
                let signature = "\(candidate.path)|\(before[.systemNumber] ?? "")|\(before[.systemFileNumber] ?? "")|\(bytes)|\(before[.modificationDate] ?? "")"
                if signature == storeSignature { return true }
                // Bounded regular-file read. Check identity/size/time again before parsing.
                let handle = try FileHandle(forReadingFrom: candidate)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 67_108_865) ?? Data()
                guard data.count == bytes.intValue else { continue }
                let after = try FileManager.default.attributesOfItem(atPath: candidate.path)
                guard [FileAttributeKey.systemNumber, .systemFileNumber, .size, .modificationDate].allSatisfy({ (before[$0] as? NSObject) == (after[$0] as? NSObject) }) else { report("Index: database changed during read; retry later"); continue }
                guard let result = QSParseLaunchServices(data, { [weak self] in self?.report($0) }),
                      let paths = result["paths"] as? [String], !paths.isEmpty else { continue }
                let identifiers = result["identifiers"] as? [String: Any] ?? [:]
                let names = result["names"] as? [String: String] ?? [:]
                // Replace the previous LS snapshot; retain identities proven by inode scans.
                var refreshed: [(String, String?, String?)] = []
                for path in paths {
                    if lifetime.cancelled { return false }
                    let id = identifiers[path] as? String
                    let exists = server.io.sync { () -> Bool in
                        var info = stat()
                        if lstat(path, &info) == 0 { return info.st_mode & S_IFMT == S_IFDIR }
                        if errno == ENOENT { return false }
                        access.grant(path)
                        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
                    }
                    if exists { refreshed.append((path, id, id.flatMap { names[$0] })) }
                }
                guard !refreshed.isEmpty else { continue }
                for old in index?.databasePaths ?? [] {
                    if index?.records[old]?.inode == nil { index?.records.removeValue(forKey: old) }
                }
                index?.databasePaths = []
                for (path, identifier, name) in refreshed {
                    remember(path, identifier: identifier, name: name); index?.databasePaths.insert(path)
                }
                index?.storePath = candidate.path; storeSignature = signature
                report("LaunchServices: \(paths.count) paths, \(index?.records.count ?? 0) current containers")
                return true
            } catch { report("LaunchServices: \(error.localizedDescription)") }
        }
        return false
    }
    private func findStore(seconds: TimeInterval) {
        guard upper > 0, !lifetime.cancelled else { return }
        // New ids first; preserve progress through older ids if the recent window misses.
        let start = Date()
        let previousUpper = index?.searchUpper ?? 0
        let previousCursor = index?.searchBelow ?? upper
        var ranges: [(UInt64, UInt64)] = []
        if previousUpper == upper { ranges = [(1, previousCursor)] }
        else { ranges = [(max(1, previousUpper + 1), upper), (1, previousCursor)] }
        for (first, last) in ranges where last >= first && last > 0 {
            var cursor = last
            while cursor >= first && !lifetime.cancelled && Date().timeIntervalSince(start) < seconds {
                if server.io.sync(execute: { server.store.shouldYieldDiscovery() }) { break }
                guard let batch = QSDiscoveryBatch(first, cursor, true, 0.01), let next = batch["next"] as? NSNumber else { break }
                let discovered = absorb(batch)
                if let path = batch["store"] as? String, !path.isEmpty, loadStore(path) {
                    index?.lastSearch = Date(); index?.searchUpper = upper; return
                }
                if discovered { saveAndPublish() }
                cursor = next.uint64Value
                index?.searchBelow = cursor
                if cursor == 0 || (batch["finished"] as? NSNumber)?.boolValue == true { break }
                // No tight scan loop competing with foreground SFTP work.
                Thread.sleep(forTimeInterval: 0.015)
            }
        }
        index?.searchUpper = upper; index?.lastSearch = Date()
        report("No usable LaunchServices database found; using the cached index and continuing automatic discovery")
    }
    func startDeepScan() {
        lock.lock(); guard deep == nil else { lock.unlock(); return }
        let token = ScanControl(); deep = token; lock.unlock(); onDeepState(true)
        queue.async { [self] in
            prepareIndex()
            guard index != nil, upper > 0, !lifetime.cancelled, !token.cancelled else { finishDeep(token); return }
            report("Automatic discovery: starting at inode \(index!.nextInode)")
            deepBatch(token, bound: upper)
        }
    }
    func stopDeepScan() { lock.lock(); let current = deep; lock.unlock(); current?.cancel() }
    private func finishDeep(_ token: ScanControl) {
        saveAndPublish()
        lock.lock(); if deep === token { deep = nil }; lock.unlock()
        onDeepState(false)
        if !lifetime.cancelled {
            queue.asyncAfter(deadline: .now() + .seconds(600)) {
                if !self.lifetime.cancelled { self.refresh() }
            }
        }
    }
    private func deepBatch(_ token: ScanControl, bound: UInt64) {
        guard !lifetime.cancelled, !token.cancelled, let next = index?.nextInode, next <= bound else {
            report(token.cancelled || lifetime.cancelled ? "Discovery paused; progress saved" : "Discovery complete; subsequent passes check new inode IDs only")
            finishDeep(token); return
        }
        if server.io.sync(execute: { server.store.shouldYieldDiscovery() }) {
            queue.asyncAfter(deadline: .now() + .milliseconds(150)) { self.deepBatch(token, bound: bound) }
            return
        }
        batchCounter += 1
        // Keep the newest-first database search moving alongside direct container discovery.
        if batchCounter % 8 == 0, index?.storePath == nil, let cursor = index?.searchBelow, cursor > 0,
           let search = QSDiscoveryBatch(1, cursor, true, 0.01) {
            if absorb(search) { saveAndPublish() }
            index?.searchBelow = (search["next"] as? NSNumber)?.uint64Value
            if let path = search["store"] as? String, !path.isEmpty, loadStore(path) { saveAndPublish() }
        }
        guard let batch = QSDiscoveryBatch(next, bound, false, 0.01), let following = batch["next"] as? NSNumber else {
            report("Container scan failed: \(String(cString: strerror(errno)))"); finishDeep(token); return
        }
        let discovered = absorb(batch)
        if let store = batch["store"] as? String, !store.isEmpty, loadStore(store) { saveAndPublish() }
        index?.advance(next: following.uint64Value)
        if following.uint64Value / 1_000_000 != next / 1_000_000 || discovered {
            report("Discovery \(following.uint64Value - 1) / \(bound), \(index?.records.count ?? 0) containers")
            saveAndPublish()
        } else if ProcessInfo.processInfo.systemUptime - lastCheckpoint >= 2 {
            saveAndPublish()
        }
        let delay = (index?.databasePaths.isEmpty ?? true) ? 30 : 120
        queue.asyncAfter(deadline: .now() + .milliseconds(delay)) { self.deepBatch(token, bound: bound) }
    }
    @discardableResult private func absorb(_ batch: [String: Any]) -> Bool {
        var changed = false
        let witnesses = batch["witnesses"] as? [String: String] ?? [:]
        for (path, inode) in batch["containers"] as? [String: NSNumber] ?? [:] {
            let updated = remember(path, inode: inode.uint64Value, witness: witnesses[path])
            changed = updated || changed
        }
        return changed
    }
    private func saveAndPublish() {
        guard let index else { return }
        lastCheckpoint = ProcessInfo.processInfo.systemUptime
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(index).write(to: cacheURL, options: .atomic)
        } catch { report("Could not save index: \(error.localizedDescription)") }
        let paths = Set(index.records.keys), aliases = index.aliases()
        server.io.async {
            guard !self.lifetime.cancelled else { return }
            self.server.store.knownPaths = paths
            self.server.store.aliases = aliases
        }
    }
}
