import Foundation
import LabelCore

/// Offline planning against a private store's exact immutable profile revision.
/// This binds profile/count/mode/schedule, not prepared raster order or delivery.
public struct ProfileBoundFinishingJobPlan: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedProfileSchema
        case missingConfiguration
        case bindingMismatch
    }
    public let printer: StoredPrinterProfile
    public let plan: FinishingJobPlan

    fileprivate init(printer: StoredPrinterProfile, plan: FinishingJobPlan) {
        self.printer = printer; self.plan = plan
    }

    /// A later acceptance/preparation layer must supply its independently bound
    /// values. Matching these alone is not authority for mechanical transmission.
    public func validateBinding(printer: ImmutableProfileReference, outputLabelCount: Int,
                                mode: FinishingMode, schedule: CutSchedule?) throws {
        guard self.printer.reference == printer, plan.outputLabelCount == outputLabelCount,
              plan.mode == mode, plan.schedule == schedule else { throw Error.bindingMismatch }
    }
}

public extension PrinterProfileStore {
    /// Original ordered engine output owns copies/ranges; this never expands them.
    /// Reads only the private profile store. No queue, command or printer I/O.
    func finishingPlan(reference: ImmutableProfileReference, mode: FinishingMode,
                       outputLabelCount: Int, schedule: CutSchedule? = nil) throws -> ProfileBoundFinishingJobPlan {
        let profile = try load(reference: reference)
        guard profile.schemaVersion == 8 else {
            throw ProfileBoundFinishingJobPlan.Error.unsupportedProfileSchema
        }
        guard let configuration = profile.finishingConfiguration else {
            throw ProfileBoundFinishingJobPlan.Error.missingConfiguration
        }
        let plan = try FinishingJobPlan(mode: mode, outputLabelCount: outputLabelCount,
            media: profile.media, stock: configuration.stock, finishing: configuration.finishing,
            schedule: schedule, scheduleQualification: configuration.schedules)
        return ProfileBoundFinishingJobPlan(printer: StoredPrinterProfile(reference: reference, profile: profile), plan: plan)
    }
}
