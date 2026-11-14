import SwiftUI
import Observation
import QueryShareCore
import Darwin

final class ScanControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

@MainActor @Observable
final class ShareModel {
    nonisolated(unsafe) let server = SFTPServer()
    nonisolated(unsafe) let access = AccessManager()
    var running = false
    var busy = false
    var status = "Stopped"
    var username = "mobile"
    private let passwordStore = ConnectionPasswordStore()
    private var passwordLoaded = false
    var password = "" {
        didSet {
            guard passwordLoaded else { return }
            do { try passwordStore.save(password) }
            catch { append("Could not save password: \(error.localizedDescription)") }
        }
    }
    var port = "2222"
    var logs: [String] = []
    var error: String?
    var scanning = false
    var fingerprint = ""
    var addresses: [String] = []
    private var discovery: AutomaticDiscovery?
    private var bonjour: NetService?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
        do { password = try passwordStore.loadOrCreate() }
        catch { self.error = "Could not load the connection password: \(error.localizedDescription)" }
        passwordLoaded = true
        let report: (String) -> Void = { [weak self] value in Task { @MainActor in self?.append(value) } }
        server.io.async { [self] in
            access.log = report; server.store.log = report
            access.refreshGroups()
            server.store.grant = { [access] in access.grant($0) }
            server.store.directRoot = URL(fileURLWithPath: "/")
        }
    }
    func append(_ value: String) {
        logs.append("\(Date().formatted(date: .omitted, time: .standard))  \(value)")
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }
    func start() {
        guard !busy, !running, let number = Int(port), (1024...65535).contains(number), password.count >= 12, username.range(of: "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$", options: .regularExpression) != nil else {
            error = "Use a username starting with a letter, number, or underscore and containing only letters, numbers, dots, hyphens, or underscores; port 1024–65535; password at least 12 characters"; return
        }
        do { try passwordStore.save(password) }
        catch { self.error = "Could not save the connection password: \(error.localizedDescription)"; return }
        busy = true; status = "Starting"
        let secret = password
        let user = username
        let key = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QueryShare", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try FileManager.default.createDirectory(at: key, withIntermediateDirectories: true)
                server.io.sync { access.enabled = true }
                try server.start(port: number, username: user, password: secret, keyURL: key.appendingPathComponent("host.ed25519"))
                let fp = server.fingerprint
                Task { @MainActor in
                    self.append("Host fingerprint \(fp)"); self.running = true; self.busy = false; self.status = "Sharing over SFTP"
                    self.addresses = Self.localAddresses()
                    self.bonjour = NetService(domain: "local.", type: "_sftp-ssh._tcp.", name: "QueryShare", port: Int32(number))
                    self.bonjour?.publish()
                    UIApplication.shared.isIdleTimerDisabled = true
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                    self.append("QueryShare \(version) (\(build))")
                    self.append("SFTP started on port \(number), root /")
                    let discovery = AutomaticDiscovery(server: self.server, access: self.access)
                    discovery.onDeepState = { [weak self, weak discovery] state in
                        Task { @MainActor in
                            guard let self, self.discovery === discovery else { return }
                            self.scanning = state
                        }
                    }
                    self.discovery = discovery
                    discovery.start()
                }
            } catch { Task { @MainActor in self.error = error.localizedDescription; self.busy = false; self.status = "Could not start sharing" } }
        }
    }
    func refreshIndex() { discovery?.refresh(force: true) }
    func stop() {
        guard !busy else { return }
        busy = true; discovery?.cancel(); discovery = nil; scanning = false;
        server.io.async { self.access.enabled = false }; bonjour?.stop(); bonjour = nil
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            server.stop()
            server.io.sync { access.release() }
            Task { @MainActor in
                self.running = false; self.busy = false; self.status = "Sharing stopped"
                UIApplication.shared.isIdleTimerDisabled = false
                self.endBackgroundTask(); self.append("All connections closed and access tokens released")
            }
        }
    }
    func sceneChanged(_ phase: ScenePhase) {
        if phase == .active { endBackgroundTask() }
        else if phase == .background, running, backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish SFTP transfers") { [weak self] in self?.stop() }
            append("App entered the background; sharing will stop when background time expires")
        }
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    static func localAddresses() -> [String] {
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0 else { return [] }; defer { freeifaddrs(ptr) }
        var result: [String] = []; var current = ptr
        while let item = current {
            defer { current = item.pointee.ifa_next }
            guard let addr = item.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { result.append(String(cString: host)) }
        }
        return Array(Set(result)).sorted()
    }
}