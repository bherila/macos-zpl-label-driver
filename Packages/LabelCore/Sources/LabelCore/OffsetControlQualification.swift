import Foundation

/// An evidenced model interval, distinct from a measured current setting.
public struct QualifiedDotRange: Equatable, Sendable {
    public let fact: CapabilityFact
    public let range: ClosedRange<Int>?

    public init(fact: CapabilityFact, range: ClosedRange<Int>?) {
        self.fact = fact
        self.range = range
    }

    public static let unverified = Self(fact: .init(state: .unknown, evidence: .unobserved), range: nil)
}

/// Explicit ordinary-job offsets. Zero is a supplied value, not an absent observation.
public struct OffsetControlRequest: Equatable, Sendable {
    public let blackMarkOffsetDots: Int?
    public let shiftLeftDots: Int?
    public let labelTopDots: Int?

    public init(blackMarkOffsetDots: Int? = nil, shiftLeftDots: Int? = nil, labelTopDots: Int? = nil) {
        self.blackMarkOffsetDots = blackMarkOffsetDots
        self.shiftLeftDots = shiftLeftDots
        self.labelTopDots = labelTopDots
    }
}

/// Model qualification for the conservative R45 offset-command subset.
/// Does not infer stock sensing, rendering placement or physically printable area.
public struct OffsetControlQualification: Equatable, Sendable {
    public enum Component: CaseIterable, Equatable, Sendable { case blackMark, shiftLeft, labelTop }
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidDeclaration(Component)
        case unavailable(Component, CapabilityState)
        case invalidValue(Component, Int)
        case emptyRequest
        case blackMarkModeRequired
        case blackMarkOffsetRequired
        case unqualifiedBlackMarkMode
    }

    public let blackMark: QualifiedDotRange
    public let shiftLeft: QualifiedDotRange
    public let labelTop: QualifiedDotRange

    public init(blackMark: QualifiedDotRange = .unverified, shiftLeft: QualifiedDotRange = .unverified,
                labelTop: QualifiedDotRange = .unverified) {
        self.blackMark = blackMark
        self.shiftLeft = shiftLeft
        self.labelTop = labelTop
    }

    public static let unverified = Self()

    public func validateDeclaration() throws {
        for component in Component.allCases {
            let limit = limit(for: component)
            if limit.fact.state == .supported {
                guard limit.fact.evidence != .unobserved, let range = limit.range,
                      protocolRange(for: component).contains(range.lowerBound),
                      protocolRange(for: component).contains(range.upperBound) else {
                    throw Error.invalidDeclaration(component)
                }
            } else if limit.range != nil { throw Error.invalidDeclaration(component) }
        }
    }

    public func controls(for request: OffsetControlRequest, tracking: MediaTracking? = nil,
                         trackingFact: CapabilityFact = .init(state: .unknown, evidence: .unobserved)) throws
        -> [ZPLDocumentedControl] {
        try validateDeclaration()
        if tracking == .blackMark && request.blackMarkOffsetDots == nil { throw Error.blackMarkOffsetRequired }
        guard request.blackMarkOffsetDots != nil || request.shiftLeftDots != nil || request.labelTopDots != nil else {
            throw Error.emptyRequest
        }
        var result: [ZPLDocumentedControl] = []
        if let value = request.blackMarkOffsetDots {
            guard tracking == .blackMark else { throw Error.blackMarkModeRequired }
            guard trackingFact.state == .supported, trackingFact.evidence != .unobserved else {
                throw Error.unqualifiedBlackMarkMode
            }
            try validate(value, component: .blackMark)
            result.append(.blackMarkTracking(offsetDots: value))
        }
        if let value = request.shiftLeftDots {
            try validate(value, component: .shiftLeft)
            result.append(.labelShiftLeft(dots: value))
        }
        if let value = request.labelTopDots {
            try validate(value, component: .labelTop)
            result.append(.labelTop(dots: value))
        }
        return result
    }

    private func validate(_ value: Int, component: Component) throws {
        let limit = limit(for: component)
        guard limit.fact.state == .supported else { throw Error.unavailable(component, limit.fact.state) }
        guard limit.range?.contains(value) == true else { throw Error.invalidValue(component, value) }
    }

    private func limit(for component: Component) -> QualifiedDotRange {
        switch component {
        case .blackMark: blackMark
        case .shiftLeft: shiftLeft
        case .labelTop: labelTop
        }
    }

    private func protocolRange(for component: Component) -> ClosedRange<Int> {
        switch component {
        case .blackMark: -75...283
        case .shiftLeft: -9_999...9_999
        case .labelTop: -120...120
        }
    }
}

public extension ZPLDocumentedControlEncoder {
    /// Offline fragment only; ordinary profile/acceptance integration is separate.
    func encodeOffsets(_ request: OffsetControlRequest, policy: OffsetControlQualification,
                       tracking: MediaTracking? = nil,
                       trackingFact: CapabilityFact = .init(state: .unknown, evidence: .unobserved)) throws -> Data {
        let controls = try policy.controls(for: request, tracking: tracking, trackingFact: trackingFact)
        return try encode(controls, qualification: Dictionary(uniqueKeysWithValues: controls.map { ($0.kind, .supported) }),
                          limits: .init(blackMarkOffsetDots: policy.blackMark.range, labelTopDots: policy.labelTop.range))
    }
}
