// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LabelMac",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LabelMac", targets: ["LabelMac"]),
        .executable(name: "label-driver-diagnostics", targets: ["LabelDriverDiagnostics"]),
    ],
    dependencies: [.package(path: "../LabelCore")],
    targets: [
        .target(name: "LabelMac", dependencies: [.product(name: "LabelCore", package: "LabelCore")]),
        .executableTarget(name: "LabelDriverDiagnostics", dependencies: ["LabelMac"]),
        .testTarget(name: "LabelMacTests", dependencies: ["LabelMac"]),
    ],
    swiftLanguageModes: [.v6]
)
