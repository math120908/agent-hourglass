// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "usagectl", targets: ["usagectl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "UsageCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "usagectl", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "UsagectlTests", dependencies: ["usagectl", "UsageCore"]),
    ]
)
