// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .library(name: "UsageCoreMac", targets: ["UsageCoreMac"]),
        .library(name: "UsageHistory", targets: ["UsageHistory"]),
        .executable(name: "usagectl", targets: ["usagectl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "UsageCore"),
        // GRDB lives here only, so the iOS app and widget never link it.
        .target(name: "UsageHistory", dependencies: ["UsageCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "UsageCoreMac", dependencies: ["UsageCore"]),
        .executableTarget(name: "usagectl", dependencies: ["UsageCore", "UsageCoreMac", "UsageHistory"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "UsageHistoryTests", dependencies: ["UsageHistory", "UsageCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "UsageCoreMacTests", dependencies: ["UsageCoreMac", "UsageCore", "UsageHistory"]),
        .testTarget(name: "UsagectlTests", dependencies: ["usagectl", "UsageCore"]),
    ]
)
