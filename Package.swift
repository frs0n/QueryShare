// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "QueryShareCore", platforms: [.iOS(.v17), .macOS(.v14)],
 products: [.library(name: "QueryShareCore", targets: ["QueryShareCore"]), .executable(name: "queryshare-harness", targets: ["Harness"])],
 dependencies: [
 .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.15.1"),
 .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
 .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0"..<"6.0.0")],
 targets: [
 .target(name: "QueryShareCore", dependencies: [.product(name: "NIOSSH", package: "swift-nio-ssh"), .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOPosix", package: "swift-nio"), .product(name: "Crypto", package: "swift-crypto")], path: "Core", swiftSettings: [.swiftLanguageMode(.v5)]),
 .testTarget(name: "CoreTests", dependencies: ["QueryShareCore"], path: "Tests/Core", swiftSettings: [.swiftLanguageMode(.v5)]),
 .executableTarget(name: "Harness", dependencies: ["QueryShareCore"], path: "Harness", swiftSettings: [.swiftLanguageMode(.v5)])])
