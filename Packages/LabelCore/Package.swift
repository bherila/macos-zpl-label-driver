// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LabelCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LabelCore", targets: ["LabelCore"]),
        .executable(name: "label-core-lab", targets: ["LabelCoreLab"]),
        .executable(name: "labelprobe", targets: ["LabelCaptureProbe"]),
        .executable(name: "labelcapture-filter", targets: ["LabelCaptureFilter"]),
    ],
    targets: [
        .target(name: "LabelCore"),
        .executableTarget(name: "LabelCoreLab", dependencies: ["LabelCore"]),
        .executableTarget(name: "LabelCaptureProbe", dependencies: ["LabelCore"]),
        .executableTarget(name: "LabelCaptureFilter", dependencies: ["LabelCore"]),
        .testTarget(name: "LabelCoreTests", dependencies: ["LabelCore"]),
    ],
    swiftLanguageModes: [.v6]
)
