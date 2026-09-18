import Foundation

/// A supplied model bound, not a discovered current setting or inferred stock size.
public struct QualifiedDotLimit: Equatable, Sendable {
    public let fact: CapabilityFact
    public let maximumDots: Int?

    public init(fact: CapabilityFact, maximumDots: Int?) {
        self.fact = fact
        self.maximumDots = maximumDots
    }

    public static let unverified = Self(fact: .init(state: .unknown, evidence: .unobserved), maximumDots: nil)
}

/// Explicit physical controls. R45 covers width/home; R46 covers continuous length.
/// The 32000-dot ceiling is also this implementation's bounded geometry subset.
public struct PhysicalGeometryQualification: Equatable, Sendable {
    public enum Component: Equatable, Sendable { case width, continuousLength, homeX, homeY }
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidDeclaration(Component)
        case unavailable(Component, CapabilityState)
        case invalidValue(Component, Int)
        case emptyRequest
        case incompleteHome
        case continuousLengthRequired
        case continuousModeRequired
        case unavailableContinuousMode(CapabilityState)
        case unqualifiedContinuousMode
        case rasterExceedsWidth
        case rasterExceedsLength
    }

    public let width: QualifiedDotLimit
    public let continuousLength: QualifiedDotLimit
    public let homeX: QualifiedDotLimit
    public let homeY: QualifiedDotLimit

    public init(width: QualifiedDotLimit = .unverified, continuousLength: QualifiedDotLimit = .unverified,
                homeX: QualifiedDotLimit = .unverified, homeY: QualifiedDotLimit = .unverified) {
        self.width = width
        self.continuousLength = continuousLength
        self.homeX = homeX
        self.homeY = homeY
    }

    public static let unverified = Self()

    public func validateDeclaration() throws {
        for (component, limit, minimum) in entries {
            switch limit.fact.state {
            case .supported:
                guard limit.fact.evidence != .unobserved, let maximum = limit.maximumDots,
                      (minimum...32_000).contains(maximum) else { throw Error.invalidDeclaration(component) }
            case .unknown, .unsupported:
                guard limit.maximumDots == nil else { throw Error.invalidDeclaration(component) }
            }
        }
    }

    /// Resolves only physical geometry; no PDF, nominal stock, settings query or I/O.
    /// A length requires explicitly qualified continuous mode, never retained mode.
    public func controls(for request: MediaGeometryRequest, tracking: MediaTracking? = nil,
                         trackingFact: CapabilityFact = .init(state: .unknown, evidence: .unobserved)) throws
        -> [ZPLDocumentedControl] {
        try validateDeclaration()
        guard request.widthDots != nil || request.lengthDots != nil ||
              request.originXDot != nil || request.originYDot != nil else { throw Error.emptyRequest }
        guard (request.originXDot == nil) == (request.originYDot == nil) else { throw Error.incompleteHome }
        if tracking == .continuous && request.lengthDots == nil { throw Error.continuousLengthRequired }
        var result: [ZPLDocumentedControl] = []
        if let length = request.lengthDots {
            guard tracking == .continuous else { throw Error.continuousModeRequired }
            guard trackingFact.state == .supported else { throw Error.unavailableContinuousMode(trackingFact.state) }
            guard trackingFact.evidence != .unobserved else { throw Error.unqualifiedContinuousMode }
            try validate(length, component: .continuousLength, limit: continuousLength, minimum: 1)
            result.append(.continuousTracking(labelLengthDots: length))
        }
        if let value = request.widthDots {
            try validate(value, component: .width, limit: width, minimum: 2)
            result.append(.printWidth(dots: value))
        }
        if let x = request.originXDot, let y = request.originYDot {
            try validate(x, component: .homeX, limit: homeX, minimum: 0)
            try validate(y, component: .homeY, limit: homeY, minimum: 0)
            result.append(.labelHome(xDots: x, yDots: y))
        }
        return result
    }

    /// Necessary containment for controlled dimensions and known home components.
    /// Unknown home/shift/top/device state remains unknown; this is not physical proof.
    public func validateRaster(_ bitmap: MonochromeBitmap, request: MediaGeometryRequest,
                               tracking: MediaTracking? = nil,
                               trackingFact: CapabilityFact = .init(state: .unknown, evidence: .unobserved),
                               offsets: OffsetControlRequest? = nil) throws {
        _ = try controls(for: request, tracking: tracking, trackingFact: trackingFact)
        try Self.validateKnownRaster(bitmap, request: request, offsets: offsets)
    }

    static func validateKnownRaster(_ bitmap: MonochromeBitmap, request: MediaGeometryRequest,
                                    offsets: OffsetControlRequest? = nil) throws {
        var x = request.originXDot, y = request.originYDot
        if let home = x, let shift = offsets?.shiftLeftDots {
            let result = home.subtractingReportingOverflow(shift)
            guard !result.overflow, result.partialValue >= 0 else { throw Error.rasterExceedsWidth }
            x = result.partialValue
        }
        if let home = y, let top = offsets?.labelTopDots {
            let result = home.addingReportingOverflow(top)
            guard !result.overflow, result.partialValue >= 0 else { throw Error.rasterExceedsLength }
            y = result.partialValue
        }
        if let width = request.widthDots {
            guard bitmap.layout.width <= width else { throw Error.rasterExceedsWidth }
            if let x {
                guard x <= width, bitmap.layout.width <= width - x else { throw Error.rasterExceedsWidth }
            }
        }
        if let length = request.lengthDots {
            guard bitmap.layout.height <= length else { throw Error.rasterExceedsLength }
            if let y {
                guard y <= length, bitmap.layout.height <= length - y else { throw Error.rasterExceedsLength }
            }
        }
    }

    private var entries: [(Component, QualifiedDotLimit, Int)] {
        [(.width, width, 2), (.continuousLength, continuousLength, 1), (.homeX, homeX, 0), (.homeY, homeY, 0)]
    }

    private func validate(_ value: Int, component: Component, limit: QualifiedDotLimit, minimum: Int) throws {
        guard limit.fact.state == .supported else { throw Error.unavailable(component, limit.fact.state) }
        guard let maximum = limit.maximumDots, (minimum...maximum).contains(value) else {
            throw Error.invalidValue(component, value)
        }
    }
}

public extension ZPLDocumentedControlEncoder {
    /// Offline bridge from a typed physical request; ordinary profile admission is separate.
    func encodePhysicalGeometry(_ request: MediaGeometryRequest, qualification: PhysicalGeometryQualification,
                                tracking: MediaTracking? = nil,
                                trackingFact: CapabilityFact = .init(state: .unknown, evidence: .unobserved)) throws -> Data {
        let controls = try qualification.controls(for: request, tracking: tracking, trackingFact: trackingFact)
        return try encode(controls,
            qualification: Dictionary(uniqueKeysWithValues: controls.map { ($0.kind, CapabilityState.supported) }),
            limits: .init(maximumPrintWidthDots: qualification.width.maximumDots,
                          maximumContinuousLabelLengthDots: qualification.continuousLength.maximumDots))
    }
}
