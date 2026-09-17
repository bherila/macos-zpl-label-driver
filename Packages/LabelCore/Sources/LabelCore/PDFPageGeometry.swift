/// Portable PDF page-box planning. Rendering remains a LabelMac responsibility.
public enum PageGeometryError: Error, Equatable, Sendable {
    case nonFiniteValue
    case nonPositiveBox
    case invalidUserUnit
    case unsupportedRotation
    case invalidNormalizedRegion
}

/// A rectangle in the visually upright effective page box, with a top-left
/// origin. It is deliberately independent of PDF user-space coordinates.
public struct NormalizedRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else {
            throw PageGeometryError.nonFiniteValue
        }
        guard x >= 0, y >= 0, width > 0, height > 0, x + width <= 1, y + height <= 1 else {
            throw PageGeometryError.invalidNormalizedRegion
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A rectangle in the original, unrotated PDF page-box coordinate system.
public struct PDFSourceRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public struct PDFPageBox: Equatable, Sendable {
    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double
    public let rotationDegreesClockwise: Int
    public let userUnit: Double

    public init(
        originX: Double,
        originY: Double,
        width: Double,
        height: Double,
        rotationDegreesClockwise: Int = 0,
        userUnit: Double = 1
    ) throws {
        guard originX.isFinite, originY.isFinite, width.isFinite, height.isFinite else {
            throw PageGeometryError.nonFiniteValue
        }
        guard width > 0, height > 0 else { throw PageGeometryError.nonPositiveBox }
        // Finite components alone do not bound original-coordinate corners.
        guard (originX + width).isFinite, (originY + height).isFinite else {
            throw PageGeometryError.nonFiniteValue
        }
        guard (0...270).contains(rotationDegreesClockwise), rotationDegreesClockwise % 90 == 0 else {
            throw PageGeometryError.unsupportedRotation
        }
        // PDF 1.6 defines a supported range of 1 through 75,000.
        guard userUnit.isFinite, (1...75_000).contains(userUnit) else {
            throw PageGeometryError.invalidUserUnit
        }
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
        self.rotationDegreesClockwise = rotationDegreesClockwise
        self.userUnit = userUnit
    }

    /// Maps an upright top-left normalized region to the original PDF box. The
    /// source rect is clipped by construction; no downstream consumer should
    /// expand it to the full page.
    public func sourceRect(for region: NormalizedRect) -> PDFSourceRect {
        switch rotationDegreesClockwise {
        case 0:
            return PDFSourceRect(
                x: originX + region.x * width,
                y: originY + (1 - region.y - region.height) * height,
                width: region.width * width,
                height: region.height * height
            )
        case 90:
            return PDFSourceRect(
                x: originX + region.y * width,
                y: originY + region.x * height,
                width: region.height * width,
                height: region.width * height
            )
        case 180:
            return PDFSourceRect(
                x: originX + (1 - region.x - region.width) * width,
                y: originY + region.y * height,
                width: region.width * width,
                height: region.height * height
            )
        case 270:
            return PDFSourceRect(
                x: originX + (1 - region.y - region.height) * width,
                y: originY + (1 - region.x - region.width) * height,
                width: region.height * width,
                height: region.width * height
            )
        default:
            preconditionFailure("rotation was validated at initialization")
        }
    }

    /// Converts the effective visual page size to physical units without
    /// changing source coordinates. A PDF point is 1/72 inch before UserUnit.
    public func effectivePhysicalSize() throws -> PhysicalSize {
        let pointsToMillimeters = userUnit * 25.4 / 72
        let visualWidth = rotationDegreesClockwise == 90 || rotationDegreesClockwise == 270 ? height : width
        let visualHeight = rotationDegreesClockwise == 90 || rotationDegreesClockwise == 270 ? width : height
        return PhysicalSize(
            width: try Millimeters(visualWidth * pointsToMillimeters),
            height: try Millimeters(visualHeight * pointsToMillimeters)
        )
    }
}
