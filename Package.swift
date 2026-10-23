// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .library(name: "UsageCoreMac", targets: ["UsageCoreMac"]),
        .executable(name: "usagectl", targets: ["usagectl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "UsageCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "UsageCoreMac", dependencies: ["UsageCore"]),
        .executableTarget(name: "usagectl", dependencies: ["UsageCore", "UsageCoreMac"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore", "UsageCoreMac"], resources: [.copy("Fixtures")]),
        .testTarget(name: "UsagectlTests", dependencies: ["usagectl", "UsageCore"]),
    ]
)
