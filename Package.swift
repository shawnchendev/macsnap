// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macsnap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "macsnap", targets: ["Macsnap"]),
        .executable(name: "macsnap-menubar", targets: ["MacsnapMenuBar"]),
        .library(name: "MacsnapCore", targets: ["MacsnapCore"])
    ],
    targets: [
        .target(
            name: "MacsnapCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "Macsnap",
            dependencies: ["MacsnapCore"]
        ),
        .executableTarget(
            name: "MacsnapMenuBar",
            dependencies: ["MacsnapCore"]
        ),
        .testTarget(
            name: "MacsnapTests",
            dependencies: ["MacsnapCore"]
        )
    ]
)
