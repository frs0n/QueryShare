import Foundation

// Only called on SFTPServer.io. Extensions use a bounded LRU and release on stop.
final class AccessManager {
    var enabled = true
    var groups: [String] = []
    private var grantOrder: [String] = []
    var handles: [String: Int64] = [:]
    var cacheUnsafe = false
    var failed = Set<String>()
    var log: (String) -> Void = { _ in }
    static let containers = [
        "/private/var/mobile/Containers/Data/Application",
        "/private/var/mobile/Containers/Data/InternalDaemon",
        "/private/var/mobile/Containers/Data/PluginKitPlugin",
        "/private/var/mobile/Containers/Shared/AppGroup",
        "/private/var/containers/Shared/SystemGroup",
        "/private/var/containers/Data/System"
    ]
    func refreshGroups() {
        groups = GestaltAppGroupResolver.usableAppGroups()
        failed.removeAll()
        log(groups.isEmpty ? "No usable signed App Group. WorseQuery is unavailable; standard file access remains available." : "App Groups: " + groups.joined(separator: ", "))
    }
    func grant(_ input: String) {
        #if !targetEnvironment(simulator)
        var path = input
        if path.hasPrefix("/var/") { path = "/private" + path }
        // Synthetic SFTP paths and ordinary system parents are not MCM containers.
        guard Self.containers.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return }
        // Request a container extension rather than querying separately for every file.
        if let base = Self.containers.first(where: { path.hasPrefix($0 + "/") }) {
            let suffix = path.dropFirst(base.count + 1).split(separator: "/")
            if let first = suffix.first { path = base + "/" + first }
        }
        guard enabled, !cacheUnsafe, !failed.contains(path), !groups.isEmpty else { return }
        if handles[path] != nil {
            grantOrder.removeAll { $0 == path }; grantOrder.append(path); return
        }
        for group in groups {
            let preferred = path.contains("/Containers/Shared/AppGroup") && ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
            for flags in [preferred, !preferred] {
                // The upstream create_dir flag skips pre-token lstat; it does not mkdir here.
                let handle = worse_query(path, group, flags, true)
                let error = errno
                if handle >= 0 {
                    handles[path] = handle; grantOrder.append(path)
                    while grantOrder.count > 128 {
                        let old = grantOrder.removeFirst()
                        if let token = handles.removeValue(forKey: old) { worse_query_release(token) }
                    }
                    log("Container access token acquired: \(path)"); return
                }
                log("\(path): WorseQuery=\(handle), errno=\(error)")
                if handle == -8 { cacheUnsafe = true; log("App Group cache restoration failed. Further grants are disabled. Check the preserved .gestaltedit-cache-* directories in Library."); return }
            }
        }
        failed.insert(path)
        #endif
    }
    func release() {
        enabled = false
        for handle in handles.values { worse_query_release(handle) }
        handles.removeAll(); grantOrder.removeAll(); failed.removeAll()
    }
}
