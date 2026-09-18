// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LabelMac",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LabelMac", targets: ["LabelMac"]),
        .executable(name: "label-driver-diagnostics", targets: ["LabelDriverDiagnostics"]),
        .executable(name: "label-driver", targets: ["LabelDriverCLI"]),
        .executable(name: "label-render-worker", targets: ["LabelRenderWorker"]),
        .executable(name: "label-printer-setup", targets: ["LabelSetupApp"]),
        .executable(name: "label-worker-supervision-fixture", targets: ["WorkerSupervisionFixture"]),
    ],
    dependencies: [.package(path: "../LabelCore")],
    targets: [
        .target(name: "LabelMac", dependencies: [.product(name: "LabelCore", package: "LabelCore")]),
        .executableTarget(name: "LabelDriverDiagnostics", dependencies: ["LabelMac"]),
        .executableTarget(name: "LabelDriverCLI", dependencies: ["LabelMac"]),
        .executableTarget(name: "LabelRenderWorker", dependencies: ["LabelMac"]),
        .executableTarget(name: "LabelSetupApp", dependencies: ["LabelMac"]),
        .executableTarget(name: "WorkerSupervisionFixture", dependencies: ["LabelMac"]),
        .testTarget(name: "LabelMacTests", dependencies: ["LabelMac"]),
    ],
    swiftLanguageModes: [.v6]
)
