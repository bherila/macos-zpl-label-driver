/// Independent model/adapter requirements for a future framed output plan.
/// R45 ^MM pages305–306 and ^PQ page324. This emits no printer commands.
/// Facts here do not establish physical behavior or authorize device delivery.
public struct FinishingOutputQualification: Equatable, Sendable {
    public enum Component: String, Equatable, Sendable {
        case mode, quantityOne, labelCompletion, rfid, delayedCutter
        case delayedCutReadiness, cutCompletion, peelLabelTaken, prepeel
    }
    public enum Error: Swift.Error, Equatable, Sendable {
        case profileMismatch
        case modelMismatch
        case invalidModel
        case unavailable(Component, CapabilityState)
        case missingModelEvidence(Component)
        case unverifiedFileBoundaries
        case absentFileBoundaries
        case unsupportedRFID
    }
    public enum ModePolicy: Equatable, Sendable {
        case tearOff
        case rewind
        case peelExplicitNoPrepeel
        case peelPrepeelNotApplicable
        case delayedCutSeparateFiles
    }
    public let profile: PrinterProfile
    public let model: String
    public let quantityOne: CapabilityFact
    public let labelCompletion: CapabilityFact
    public let rfid: CapabilityFact
    public let delayedCutter: CapabilityFact
    public let delayedCutReadiness: CapabilityFact
    public let cutCompletion: CapabilityFact
    public let completeFileDelivery: Observation<Bool>
    public let peelLabelTaken: CapabilityFact
    public let prepeel: CapabilityFact

    public init(profile: PrinterProfile, model: String,
        quantityOne: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
        labelCompletion: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
        rfid: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
        delayedCutter: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
        delayedCutReadiness: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
        cutCompletion: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
        completeFileDelivery: Observation<Bool> = .unobserved,
        peelLabelTaken: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
        prepeel: CapabilityFact = .init(state: .unknown, evidence: .unobserved)
    ) {
        self.profile = profile; self.model = model; self.quantityOne = quantityOne; self.labelCompletion = labelCompletion
        self.rfid = rfid; self.delayedCutter = delayedCutter; self.delayedCutReadiness = delayedCutReadiness; self.cutCompletion = cutCompletion
        self.completeFileDelivery = completeFileDelivery; self.peelLabelTaken = peelLabelTaken
        self.prepeel = prepeel
    }

    /// The sealed normalization already binds and validates the complete stored
    /// profile, stock and finishing policy. These additional wire/status facts
    /// are independent: support for ^MMC is not support for ^MMD or file delivery.
    public func validate(_ normalization: FinishingControlNormalization) throws -> ModePolicy {
        guard !model.isEmpty, model.utf8.count <= 256,
              !model.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw Error.invalidModel
        }
        guard profile == normalization.profile else { throw Error.profileMismatch }
        guard model == normalization.profile.capabilities.model else { throw Error.modelMismatch }
        try supported(normalization.plan.finishing.modes[normalization.plan.mode]
            ?? .init(state: .unknown, evidence: .unobserved), component: .mode)
        try supported(quantityOne, component: .quantityOne)
        try supported(labelCompletion, component: .labelCompletion)
        // RFID void-label cutting is not implemented. Absence must be a model
        // fact; unknown is never treated as a non-RFID printer.
        guard rfid.state != .unknown else { throw Error.unavailable(.rfid, .unknown) }
        try documented(rfid, component: .rfid)
        guard rfid.state == .unsupported else { throw Error.unsupportedRFID }
        switch normalization.plan.mode {
        case .tearOff: return .tearOff
        case .rewind: return .rewind
        case .cut:
            try supported(delayedCutter, component: .delayedCutter)
            try supported(delayedCutReadiness, component: .delayedCutReadiness)
            try supported(cutCompletion, component: .cutCompletion)
            guard case let .observed(available, evidence) = completeFileDelivery,
                  evidence == .reportedInstallation else { throw Error.unverifiedFileBoundaries }
            guard available else { throw Error.absentFileBoundaries }
            return .delayedCutSeparateFiles
        case .peel:
            try supported(peelLabelTaken, component: .peelLabelTaken)
            guard prepeel.state != .unknown else { throw Error.unavailable(.prepeel, .unknown) }
            try documented(prepeel, component: .prepeel)
            return prepeel.state == .supported ? .peelExplicitNoPrepeel : .peelPrepeelNotApplicable
        }
    }

    private func supported(_ fact: CapabilityFact, component: Component) throws {
        guard fact.state == .supported else { throw Error.unavailable(component, fact.state) }
        try documented(fact, component: component)
    }
    private func documented(_ fact: CapabilityFact, component: Component) throws {
        guard case let .documentedModel(sourceID) = fact.evidence,
              !sourceID.isEmpty, sourceID.utf8.count <= 256,
              !sourceID.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw Error.missingModelEvidence(component)
        }
    }
}
