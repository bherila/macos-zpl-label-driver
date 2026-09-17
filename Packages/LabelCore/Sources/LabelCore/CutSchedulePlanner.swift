import Foundation

/// Boundaries refer to the complete ordered, engine-expanded output label list.
/// They are intentions for a future qualified adapter, not wire commands or
/// evidence that a physical cutter performed an action.
public enum CutSchedule: Equatable, Sendable {
    case everyLabel
    /// Explicit final-remainder behavior avoids silently leaving trailing stock.
    case batch(size: Int, cutRemainderAtJobEnd: Bool)
    case endOfJob
}

public struct CutScheduleQualification: Equatable, Sendable {
    public let everyLabel: CapabilityFact
    public let batch: CapabilityFact
    public let endOfJob: CapabilityFact
    public let maximumBatchSize: Int?

    public init(everyLabel: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
                batch: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
                endOfJob: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
                maximumBatchSize: Int? = nil) {
        self.everyLabel = everyLabel; self.batch = batch; self.endOfJob = endOfJob
        self.maximumBatchSize = maximumBatchSize
    }
}

public enum CutSchedulePlanner {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLabelCount
        case invalidBatchDeclaration
        case unavailableSchedule(CapabilityState)
        case missingScheduleEvidence
        case invalidBatchSize
    }

    public static let maximumLabels = 10_000

    /// Does not expand copies, discard pages, select print quantities, concatenate
    /// delayed-cut commands or release a physical-device lease.
    public static func boundaries(afterOutputLabels count: Int, schedule: CutSchedule,
                                  finishing: FinishingControlQualification,
                                  qualification: CutScheduleQualification = .init()) throws -> [Int] {
        guard (1...maximumLabels).contains(count) else { throw Error.invalidLabelCount }
        try finishing.validate(.cut)
        if qualification.batch.state == .supported {
            guard qualification.batch.evidence != .unobserved,
                  let maximum = qualification.maximumBatchSize,
                  (1...maximumLabels).contains(maximum) else { throw Error.invalidBatchDeclaration }
        } else if qualification.maximumBatchSize != nil { throw Error.invalidBatchDeclaration }
        let fact: CapabilityFact
        switch schedule {
        case .everyLabel: fact = qualification.everyLabel
        case .batch: fact = qualification.batch
        case .endOfJob: fact = qualification.endOfJob
        }
        guard fact.state == .supported else { throw Error.unavailableSchedule(fact.state) }
        guard fact.evidence != .unobserved else { throw Error.missingScheduleEvidence }
        switch schedule {
        case .everyLabel: return Array(1...count)
        case .endOfJob: return [count]
        case let .batch(size, cutRemainder):
            guard let maximum = qualification.maximumBatchSize, (1...maximum).contains(size) else {
                throw Error.invalidBatchSize
            }
            var result: [Int] = []
            // Division before multiplication keeps every product at most count.
            for batch in 1..<(count / size + 1) { result.append(batch * size) }
            if cutRemainder && count % size != 0 { result.append(count) }
            return result
        }
    }
}
