import Foundation
import Dispatch
import LabelCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Finite encoding-only comparison on synthetic packed 4x6 input. No files,
// parser, queue, transport or printer capability qualification is involved.
func encodingBenchmark(_ arguments: [String]) throws {
    guard arguments.count == 5, ["plain", "ascii"].contains(arguments[2]),
          ["white", "checker", "analytic"].contains(arguments[3]),
          let iterations = Int(arguments[4]), (1...100).contains(iterations) else {
        throw NSError(domain: "Invalid finite encoding benchmark arguments", code: 2)
    }
    let width = 813, height = 1219
    let layout = try BitmapLayout(width: width, height: height)
    var bytes = [UInt8](repeating: 0, count: layout.byteCount)
    for y in 0..<height {
        for x in 0..<width {
            let black: Bool
            switch arguments[3] {
            case "white": black = false
            case "checker": black = (x + y) % 2 == 0
            default:
                black = x == 0 || x == width - 1 || y == 0 || y == height - 1
                    || ((x * 17 + y * 31) % 113 < 11)
            }
            if black { bytes[y * layout.bytesPerRow + x / 8] |= UInt8(0x80 >> (x % 8)) }
        }
    }
    let bitmap = try MonochromeBitmap(width: width, height: height, bytes: bytes)
    let encoder = try ZPLGraphicEncoder()
    func encode() throws -> Data {
        if arguments[2] == "ascii" { return try encoder.compressedDiagnosticFormat(bitmap) }
        return try encoder.diagnosticFormat(bitmap)
    }
    let expected = try encode() // Untimed warm-up; retain exact bytes as oracle.
    var nanoseconds: [UInt64] = []
    for _ in 0..<iterations {
        let started = DispatchTime.now().uptimeNanoseconds
        let result = try encode()
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        guard elapsed > 0, result == expected else {
            throw NSError(domain: "Unstable encoding benchmark result", code: 2)
        }
        nanoseconds.append(elapsed)
    }
    let report: [String: Any] = ["schemaVersion": 1, "scope": "offline-encoding-no-transport",
        "encoding": arguments[2], "pattern": arguments[3], "iterations": iterations,
        "widthDots": width, "heightDots": height, "packedBytes": layout.byteCount,
        "outputBytes": expected.count, "encodingNanoseconds": nanoseconds]
    let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    FileHandle.standardOutput.write(json + Data([10]))
}

// Developer-only offline vector producer. No input-document parser or transport.
do {
    if CommandLine.arguments.dropFirst().first == "--benchmark-encoding" {
        try encodingBenchmark(CommandLine.arguments)
        exit(0)
    }
    guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--vectors-dir" else {
        throw NSError(domain: "Usage: label-core-lab --vectors-dir NEW_DIRECTORY", code: 2)
    }
    let dir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    guard !FileManager.default.fileExists(atPath: dir.path) else {
        throw NSError(domain: "Refusing existing output directory", code: 2)
    }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var entries: [[String: Any]] = []
    var vectors = [("tiny", 9, 3, 4), ("aligned", 16, 17, 16),
                   ("gc420d", 813, 1219, 32768), ("forced-bands", 813, 11, 102)]
    for i in 0..<128 {
        let w = 1 + (i * 37) % 97, h = 1 + (i * 53) % 89
        vectors.append(("sweep-\(i)", w, h, ((w + 7) / 8) * (1 + i % 10)))
    }
    for (name, width, height, cap) in vectors {
        let layout = try BitmapLayout(width: width, height: height)
        var bytes = [UInt8](repeating: 0, count: layout.byteCount)
        for y in 0..<height {
            for x in 0..<width {
                // Registration border + asymmetric deterministic analytic pattern.
                let black = x == 0 || x == width - 1 || y == 0 || y == height - 1
                    || ((x * 17 + y * 31) % 113 < 11)
                if black { bytes[y * layout.bytesPerRow + x / 8] |= UInt8(0x80 >> (x % 8)) }
            }
        }
        let bitmap = try MonochromeBitmap(width: width, height: height, bytes: bytes)
        let encoder = try ZPLGraphicEncoder(maxDecodedBandBytes: cap)
        try bitmap.pbmData().write(to: dir.appendingPathComponent(name + ".pbm"), options: .withoutOverwriting)
        try encoder.diagnosticFormat(bitmap).write(to: dir.appendingPathComponent(name + ".zpl"), options: .withoutOverwriting)
        try encoder.compressedDiagnosticFormat(bitmap).write(to: dir.appendingPathComponent(name + ".acs.zpl"), options: .withoutOverwriting)
        entries.append(["name": name, "width": width, "height": height, "bandLimit": cap,
                        "bandRows": try encoder.bands(for: layout).map(\.rowCount)])
    }
    let manifest = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "vectors": entries], options: [.prettyPrinted, .sortedKeys])
    try (manifest + Data([10])).write(to: dir.appendingPathComponent("vectors.json"), options: .withoutOverwriting)
    var compressionEntries: [[String: Any]] = []
    for (pattern, value) in [("white", UInt8(0)), ("black", UInt8(255)), ("nibble", UInt8(0x66)), ("checker", UInt8(0xA5))] {
        for stride in [1, 2, 3, 9, 10, 19, 20, 199, 200, 201, 400, 801] {
            let name = "compression-\(pattern)-\(stride)"
            let bitmap = try MonochromeBitmap(width: stride * 8, height: 3, bytes: [UInt8](repeating: value, count: stride * 3))
            let encoder = try ZPLGraphicEncoder(maxDecodedBandBytes: stride * 2)
            try encoder.compressedDiagnosticFormat(bitmap).write(to: dir.appendingPathComponent(name + ".acs.zpl"), options: .withoutOverwriting)
            compressionEntries.append(["name": name, "pattern": pattern, "stride": stride])
        }
    }
    let compressionManifest = try JSONSerialization.data(withJSONObject: compressionEntries, options: [.prettyPrinted, .sortedKeys])
    try compressionManifest.write(to: dir.appendingPathComponent("compression.json"), options: .withoutOverwriting)
    print("Offline vectors written. No printer accessed. Diagnostic ZPL is not a qualified job.")
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(2)
}
