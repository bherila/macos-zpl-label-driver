/// Explicit physical and device-dot geometry for portable planning.
/// PDF coordinate transforms and printable-region qualification remain separate.
public enum PhysicalGeometryError: Error, Equatable, Sendable {
    case nonFiniteLength
    case nonPositiveLength
    case nonFiniteResolution
    case nonPositiveResolution
    case invalidDotLimit
    case dotCountOverflow
    case exceedsDotLimit(actual: Int, limit: Int)
}

public struct Millimeters: Equatable, Sendable {
    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite else { throw PhysicalGeometryError.nonFiniteLength }
        guard value > 0 else { throw PhysicalGeometryError.nonPositiveLength }
        self.value = value
    }

    public static func inches(_ value: Double) throws -> Millimeters {
        try Millimeters(value * 25.4)
    }
}

public struct PhysicalSize: Equatable, Sendable {
    public let width: Millimeters
    public let height: Millimeters

    public init(width: Millimeters, height: Millimeters) {
        self.width = width
        self.height = height
    }
}

public struct DotResolution: Equatable, Sendable {
    public let xDotsPerMillimeter: Double
    public let yDotsPerMillimeter: Double

    public init(xDotsPerMillimeter: Double, yDotsPerMillimeter: Double) throws {
        guard xDotsPerMillimeter.isFinite, yDotsPerMillimeter.isFinite else {
            throw PhysicalGeometryError.nonFiniteResolution
        }
        guard xDotsPerMillimeter > 0, yDotsPerMillimeter > 0 else {
            throw PhysicalGeometryError.nonPositiveResolution
        }
        self.xDotsPerMillimeter = xDotsPerMillimeter
        self.yDotsPerMillimeter = yDotsPerMillimeter
    }

    /// The project policy is nearest positive half-away-from-zero. Physical
    /// dimensions are positive, so this avoids an implicit Foundation rounding mode.
    public func roundedDots(for length: Millimeters, horizontal: Bool) throws -> Int {
        let resolution = horizontal ? xDotsPerMillimeter : yDotsPerMillimeter
        let raw = length.value * resolution
        guard raw.isFinite, raw < Double(Int.max) else {
            throw PhysicalGeometryError.dotCountOverflow
        }
        return Int(raw.rounded(.toNearestOrAwayFromZero))
    }
}

public struct DotCanvas: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bitmapLayout: BitmapLayout

    public init(
        physicalSize: PhysicalSize,
        resolution: DotResolution,
        maximumWidth: Int = 8_192,
        maximumHeight: Int = 65_535,
        maximumByteCount: Int = 512 * 1024 * 1024
    ) throws {
        guard maximumWidth > 0, maximumHeight > 0 else {
            throw PhysicalGeometryError.invalidDotLimit
        }
        let width = try resolution.roundedDots(for: physicalSize.width, horizontal: true)
        let height = try resolution.roundedDots(for: physicalSize.height, horizontal: false)
        guard width <= maximumWidth else {
            throw PhysicalGeometryError.exceedsDotLimit(actual: width, limit: maximumWidth)
        }
        guard height <= maximumHeight else {
            throw PhysicalGeometryError.exceedsDotLimit(actual: height, limit: maximumHeight)
        }
        self.width = width
        self.height = height
        self.bitmapLayout = try BitmapLayout(width: width, height: height, maxByteCount: maximumByteCount)
    }
}
