import CryptoKit
import Foundation
import LabelCore

/// Immutable geometry facts for later finishing acceptance. These declarations
/// do not discover a device, establish scheduler authority or prove physical output.
public struct FinishingDeviceGeometry: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case profileMismatch, unverifiedPitch, invalidProvenance, modelPitchMismatch
        case bindingMismatch, stockMismatch
    }
    public let printer: StoredPrinterProfile
    public let physicalDevice: PhysicalDeviceCoordinationID
    public let nativePitch: Observation<DotResolution>
    public let resolution: DotResolution

    public init(printer: StoredPrinterProfile, physicalDevice: PhysicalDeviceCoordinationID,
                nativePitch: Observation<DotResolution>) throws {
        let bytes = try PrinterProfileJSON.encode(printer.profile)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard printer.profile.schemaVersion == 8, printer.reference.schemaVersion == 8,
              printer.reference.revision == printer.profile.revision,
              printer.reference.sha256 == digest else { throw Error.profileMismatch }
        guard case let .observed(resolution, evidence) = nativePitch,
              evidence != .unobserved else { throw Error.unverifiedPitch }
        if case let .documentedModel(sourceID) = evidence {
            let bytes = Array(sourceID.utf8)
            func alphanumeric(_ byte: UInt8) -> Bool {
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
            }
            guard let first = bytes.first, alphanumeric(first), bytes.count <= 128,
                  bytes.allSatisfy({ alphanumeric($0) || [45, 46, 95].contains($0) }) else {
                throw Error.invalidProvenance
            }
        }
        // Model-documented native pitch is the geometric truth, not nominal203DPI.
        if printer.profile.capabilities.model == "GC420d" {
            guard resolution.xDotsPerMillimeter == 8, resolution.yDotsPerMillimeter == 8 else {
                throw Error.modelPitchMismatch
            }
        }
        self.printer = printer; self.physicalDevice = physicalDevice
        self.nativePitch = nativePitch; self.resolution = resolution
    }

    public func canvas(for queue: FinishingQueueDefinition, workflow: WorkflowProfile,
                       maximumPackedBytes: Int = FinishingRasterBinding.maximumTotalBytes) throws -> DotCanvas {
        guard queue.printerProfile == printer.reference, queue.physicalDevice == physicalDevice else {
            throw Error.bindingMismatch
        }
        // Also checks complete workflow/printer snapshots and qualified defaults.
        _ = try queue.resolve(outputLabelCount: 1, workflow: workflow, printer: printer.profile)
        guard case let .observed(stock, evidence) = printer.profile.media.nominalLabelFace,
              evidence == .reportedInstallation, stock == workflow.outputStock else { throw Error.stockMismatch }
        guard (1...FinishingRasterBinding.maximumTotalBytes).contains(maximumPackedBytes) else {
            throw FinishingRasterPreparation.Error.invalidLimit
        }
        return try DotCanvas(physicalSize: stock, resolution: resolution,
                             maximumByteCount: maximumPackedBytes)
    }

    public func validate(canvas: DotCanvas, queue: FinishingQueueDefinition,
                         workflow: WorkflowProfile) throws {
        guard canvas == (try self.canvas(for: queue, workflow: workflow)) else { throw Error.bindingMismatch }
    }
}
