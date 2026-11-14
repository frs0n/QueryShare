import Foundation
import QueryShareCore
let server = SFTPServer()
let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()
let key = URL(fileURLWithPath: root).appendingPathComponent(".test-hostkey")
server.io.sync {
    if ProcessInfo.processInfo.environment["QS_DIRECT"] == "1" { server.store.directRoot = URL(fileURLWithPath: root) }
    if ProcessInfo.processInfo.environment["QS_ALIASES"] == "1" { server.store.aliases = ["/Containers/Apps/测试 [com.example.demo]": root] }
    server.store.log = { print($0) }
    _ = try! server.store.add(root)
    print("MOUNT=\(server.store.mounts[0].id)")
}
try server.start(host: "127.0.0.1", port: 22222, username: ProcessInfo.processInfo.environment["QS_USER"] ?? "mobile", password: "queryshare-test-password", keyURL: key)
print("READY \(server.fingerprint)")
fflush(stdout)
RunLoop.main.run()
