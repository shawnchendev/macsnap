// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "opensnap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "opensnap", targets: ["Opensnap"]),
        .executable(name: "opensnap-menubar", targets: ["OpensnapMenuBar"]),
        .library(name: "OpensnapCore", targets: ["OpensnapCore"])
    ],
    targets: [
        .target(
            name: "OpensnapCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "Opensnap",
            dependencies: ["OpensnapCore"]
        ),
        .executableTarget(
            name: "OpensnapMenuBar",
            dependencies: ["OpensnapCore"]
        ),
        .testTarget(
            name: "OpensnapTests",
            dependencies: ["OpensnapCore"]
        )
    ]
)
