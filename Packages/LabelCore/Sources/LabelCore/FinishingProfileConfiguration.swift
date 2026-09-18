import Foundation

/// Immutable declarations for future ordinary mechanical-job integration.
/// Storing them does not enable an encoder, queue, or physical operation.
public struct FinishingProfileConfiguration: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case mediaMismatch
        case inconsistentModel(FinishingMode)
        case inconsistentInstallation(FinishingMode)
        case unverifiedStock(FinishingMode)
        case invalidBatchDeclaration
    }
    public let finishing: FinishingControlQualification
    public let stock: FinishingStockQualification
    public let schedules: CutScheduleQualification

    public init(finishing: FinishingControlQualification, stock: FinishingStockQualification,
                schedules: CutScheduleQualification = .init()) {
        self.finishing = finishing; self.stock = stock; self.schedules = schedules
    }

    func validate(media: MediaConfiguration, capabilities: PrinterCapabilities,
                  installed: InstalledHardware) throws {
        guard stock.media == media else { throw Error.mediaMismatch }
        for (mode, fact) in [(FinishingMode.cut, capabilities.cutter),
                             (.peel, capabilities.peeler), (.rewind, capabilities.rewind)] {
            if let declared = finishing.modes[mode], declared != fact {
                throw Error.inconsistentModel(mode)
            }
        }
        for (mode, observation, fact) in [(FinishingMode.cut, finishing.installed.cutter, installed.cutter),
                                          (.peel, finishing.installed.peeler, installed.peeler)] {
            if case let .observed(present, evidence) = observation {
                guard evidence == .reportedInstallation,
                      fact.evidence == .reportedInstallation,
                      fact.state == (present ? .supported : .unsupported) else {
                    throw Error.inconsistentInstallation(mode)
                }
            }
        }
        for mode in finishing.enabledModes {
            try finishing.validate(mode)
            guard case .observed(true, evidence: .reportedInstallation) = stock.compatibleModes[mode] else {
                throw Error.unverifiedStock(mode)
            }
        }
        if schedules.batch.state == .supported {
            guard schedules.batch.evidence != .unobserved,
                  let maximum = schedules.maximumBatchSize,
                  (1...CutSchedulePlanner.maximumLabels).contains(maximum) else {
                throw Error.invalidBatchDeclaration
            }
        } else if schedules.maximumBatchSize != nil { throw Error.invalidBatchDeclaration }
    }
}
