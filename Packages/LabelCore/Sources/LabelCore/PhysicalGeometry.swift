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
    public let physicalSize: PhysicalSize
    public let resolution: DotResolution
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
        self.physicalSize = physicalSize
        self.resolution = resolution
        self.width = width
        self.height = height
        self.bitmapLayout = try BitmapLayout(width: width, height: height, maxByteCount: maximumByteCount)
    }
}

public enum PagePlacementPolicy: String, Equatable, Sendable {
    /// Uniformly scale in physical units so the entire source is visible.
    case fit
    /// Preserve the source's physical dimensions and clip at the output stock.
    case actualSize
}

public struct DotRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public struct PagePlacement: Equatable, Sendable {
    public let target: DotRect
    public let visible: DotRect
}

public enum PagePlacementError: Error, Equatable, Sendable {
    case invalidLimit
    case scaleOverflow
    case placementExceedsLimit
}

public enum PagePlacementPlanner {
    /// Placement is centered. When an odd dot remains, the trailing edge gets
    /// that dot; this avoids a second fractional transform or rounding step.
    public static func plan(
        source: PhysicalSize,
        canvas: DotCanvas,
        policy: PagePlacementPolicy,
        maximumPlacementDimension: Int = 65_535
    ) throws -> PagePlacement {
        guard maximumPlacementDimension > 0 else { throw PagePlacementError.invalidLimit }
        let scale: Double
        switch policy {
        case .fit:
            scale = min(
                canvas.physicalSize.width.value / source.width.value,
                canvas.physicalSize.height.value / source.height.value
            )
        case .actualSize:
            scale = 1
        }
        guard scale.isFinite, scale > 0,
              let placedWidth = try? Millimeters(source.width.value * scale),
              let placedHeight = try? Millimeters(source.height.value * scale) else {
            throw PagePlacementError.scaleOverflow
        }
        var width = try canvas.resolution.roundedDots(for: placedWidth, horizontal: true)
        var height = try canvas.resolution.roundedDots(for: placedHeight, horizontal: false)
        if policy == .fit {
            // Independent dot rounding can cross the physical fit boundary by
            // one dot. Clip that quantization only, never rescale a second time.
            width = min(width, canvas.width)
            height = min(height, canvas.height)
        }
        guard width > 0, height > 0,
              width <= maximumPlacementDimension,
              height <= maximumPlacementDimension else {
            throw PagePlacementError.placementExceedsLimit
        }
        let x = (canvas.width - width) / 2
        let y = (canvas.height - height) / 2
        let visibleX = max(0, x)
        let visibleY = max(0, y)
        let visibleRight = min(canvas.width, x + width)
        let visibleBottom = min(canvas.height, y + height)
        return PagePlacement(
            target: DotRect(x: x, y: y, width: width, height: height),
            visible: DotRect(
                x: visibleX,
                y: visibleY,
                width: max(0, visibleRight - visibleX),
                height: max(0, visibleBottom - visibleY)
            )
        )
    }
}
