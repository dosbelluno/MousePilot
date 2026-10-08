// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MousePilot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MousePilot", targets: ["MousePilot"])],
    targets: [
        .target(name: "MousePilotCore"),
        .executableTarget(name: "MousePilot", dependencies: ["MousePilotCore"]),
        .testTarget(name: "MousePilotCoreTests", dependencies: ["MousePilotCore"]),
        .testTarget(name: "MousePilotRuntimeTests", dependencies: ["MousePilot"])
    ],
    swiftLanguageModes: [.v6]
)
