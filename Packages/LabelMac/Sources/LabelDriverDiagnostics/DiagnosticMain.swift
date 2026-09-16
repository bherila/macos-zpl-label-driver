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
        if args.count == 4, args[0] == "--hold-device-lease" {
            holdDeviceLease(directory: args[1], identifier: args[2], milliseconds: args[3])
            return
        }
        if args.count == 3, args[0] == "--bounded-read" {
            boundedRead(path: args[1], maximumBytes: args[2])
            return
        }
        guard args.isEmpty else {
            FileHandle.standardError.write(Data("Usage: label-driver-diagnostics [--version]\n       label-driver-diagnostics --hold-device-lease DIRECTORY IDENTIFIER MILLISECONDS\n       label-driver-diagnostics --bounded-read PATH MAXIMUM_BYTES\nNo printer operations are implemented.\n".utf8))
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

    /// Bounded test-only process-lifetime probe for the coordinator primitive.
    /// It takes no printer URI and never opens a device or a network socket.
    private static func holdDeviceLease(directory: String, identifier: String, milliseconds: String) {
        guard let duration = Int(milliseconds), (1...5_000).contains(duration) else {
            FileHandle.standardError.write(Data("Invalid bounded lease duration.\n".utf8))
            exit(2)
        }
        do {
            let identity = try PhysicalDeviceIdentity(stableIdentifier: identifier)
            let lease = try PhysicalDeviceLease(acquiring: identity, inExistingDirectory: URL(fileURLWithPath: directory, isDirectory: true))
            print("lease-acquired")
            fflush(stdout)
            usleep(useconds_t(duration * 1_000))
            lease.release()
        } catch PhysicalDeviceLeaseError.alreadyHeld {
            exit(75)
        } catch {
            FileHandle.standardError.write(Data("Lease probe failed.\n".utf8))
            exit(1)
        }
    }

    /// Test-only probe for bounded file ingestion. It never prints file bytes.
    private static func boundedRead(path: String, maximumBytes: String) {
        guard let limit = Int(maximumBytes), limit > 0 else { exit(2) }
        do {
            let data = try BoundedRegularFile.read(
                URL(fileURLWithPath: path), maximumBytes: limit
            )
            print(data.count)
        } catch {
            exit(65)
        }
    }
}
