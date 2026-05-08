// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessionMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeSessionMonitor", targets: ["ClaudeSessionMonitor"]),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeSessionMonitor",
            path: "Sources/ClaudeSessionMonitor"
        ),
    ]
)
