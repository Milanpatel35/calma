// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Calma",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CalmaApp", targets: ["CalmaApp"]),
        .executable(name: "calmad", targets: ["calmad"]),
        .executable(name: "calma", targets: ["CalmaCLI"]),
        .library(name: "CalmaKit", targets: ["CalmaKit"]),
    ],
    targets: [
        // Raw AppleSMC user-client access, in C so the struct layout matches the kernel.
        .target(name: "CSMC"),

        // Pure Swift: models, settings, IPC protocol, the charge decision engine, scheduling.
        // No IOKit, no side effects — everything here is unit-testable.
        .target(name: "CalmaKit"),

        // Hardware access: SMC keys + allowlist, battery telemetry, power assertions.
        .target(name: "CalmaHardware", dependencies: ["CSMC", "CalmaKit"]),

        // Root LaunchDaemon. The only process that ever writes to the SMC.
        .executableTarget(name: "calmad", dependencies: ["CalmaKit", "CalmaHardware"]),

        // `calma` command-line tool. Talks to the daemon over its local socket.
        .executableTarget(name: "CalmaCLI", dependencies: ["CalmaKit", "CalmaHardware"]),

        // SwiftUI menu bar app (unprivileged).
        .executableTarget(name: "CalmaApp", dependencies: ["CalmaKit", "CalmaHardware"]),

        .testTarget(name: "CalmaKitTests", dependencies: ["CalmaKit"]),
        .testTarget(name: "CalmaHardwareTests", dependencies: ["CalmaHardware", "CalmaKit"]),
    ]
)
