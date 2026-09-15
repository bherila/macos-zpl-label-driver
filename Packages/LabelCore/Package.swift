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
        .target(
            name: "CUPSOptionBridge",
            path: "Sources/CUPSOptionBridge",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("cups")]
        ),
        .executableTarget(name: "LabelCaptureFilter", dependencies: ["LabelCore", "CUPSOptionBridge"]),
        .testTarget(name: "LabelCoreTests", dependencies: ["LabelCore"]),
    ],
    swiftLanguageModes: [.v6]
)
