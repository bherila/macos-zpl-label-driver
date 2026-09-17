import Foundation

/// Suitability declarations apply only to this immutable media snapshot.
/// They do not infer liner, adhesive, dimensions or mechanical behavior from
/// a media form, model capability, or another mode's successful declaration.
public struct FinishingStockQualification: Equatable, Sendable {
    public let media: MediaConfiguration
    public let compatibleModes: [FinishingMode: Observation<Bool>]

    public init(media: MediaConfiguration,
                compatibleModes: [FinishingMode: Observation<Bool>] = [:]) {
        self.media = media
        self.compatibleModes = compatibleModes
    }
}

/// Validated offline intention for the complete engine-expanded output list.
/// No encoder or transport accepts this as authority for mechanical delivery.
/// Profile/queue/ticket persistence and wire-boundary qualification remain separate.
public struct FinishingJobPlan: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLabelCount
        case mediaMismatch
        case unverifiedStock(FinishingMode)
        case incompatibleStock(FinishingMode)
        case missingCutSchedule
        case unexpectedCutSchedule
    }

    public let mode: FinishingMode
    public let outputLabelCount: Int
    public let media: MediaConfiguration
    public let stock: FinishingStockQualification
    public let finishing: FinishingControlQualification
    public let schedule: CutSchedule?
    public let scheduleQualification: CutScheduleQualification
    public let cutAfterOutputLabels: [Int]

    public init(mode: FinishingMode, outputLabelCount: Int, media: MediaConfiguration,
                stock: FinishingStockQualification, finishing: FinishingControlQualification,
                schedule: CutSchedule? = nil,
                scheduleQualification: CutScheduleQualification = .init()) throws {
        guard (1...CutSchedulePlanner.maximumLabels).contains(outputLabelCount) else {
            throw Error.invalidLabelCount
        }
        guard stock.media == media else { throw Error.mediaMismatch }
        try finishing.validate(mode)
        guard case let .observed(compatible, evidence) = stock.compatibleModes[mode],
              evidence == .reportedInstallation else { throw Error.unverifiedStock(mode) }
        guard compatible else { throw Error.incompatibleStock(mode) }
        let boundaries: [Int]
        if mode == .cut {
            guard let schedule else { throw Error.missingCutSchedule }
            boundaries = try CutSchedulePlanner.boundaries(afterOutputLabels: outputLabelCount,
                schedule: schedule, finishing: finishing, qualification: scheduleQualification)
        } else {
            guard schedule == nil else { throw Error.unexpectedCutSchedule }
            boundaries = []
        }
        self.mode = mode; self.outputLabelCount = outputLabelCount; self.media = media
        self.stock = stock; self.finishing = finishing; self.schedule = schedule
        self.scheduleQualification = scheduleQualification; self.cutAfterOutputLabels = boundaries
    }
}
