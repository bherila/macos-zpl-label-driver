import Darwin
import Foundation
import LabelMac

@main
struct DiagnosticMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--version"] {
            print("label-driver-diagnostics 0.0.0-scaffold")
            return
        }
        guard args.isEmpty else {
            FileHandle.standardError.write(Data("Usage: label-driver-diagnostics [--version]\nNo printer operations are implemented.\n".utf8))
            exit(2)
        }
        do {
            let pixel = try CoreGraphicsSmokeCheck.run()
            let result: [String: Any] = [
                "stage": "scaffold",
                "coreGraphicsWhitePixel": Int(pixel),
                "printerIOPerformed": false,
                "driverImplemented": false,
            ]
            let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Core Graphics smoke check failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
