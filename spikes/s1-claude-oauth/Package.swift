// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "S1Probe",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "S1Probe", path: "Sources/S1Probe")]
)
