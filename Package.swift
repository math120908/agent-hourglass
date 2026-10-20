// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "usagectl", targets: ["usagectl"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "usagectl", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "UsagectlTests", dependencies: ["usagectl", "UsageCore"]),
    ]
)
