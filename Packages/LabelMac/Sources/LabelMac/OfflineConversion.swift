import Foundation
import LabelCore

/// Versioned, file-independent settings for the offline conversion CLI.
/// This is deliberately not a CUPS ticket or a printer profile schema.
public struct OfflineConversionTicket: Equatable, Sendable {
    /// The complete set of errors either initializer can throw.
    ///
    /// This is the app-to-worker process boundary and its input is
    /// attacker-influenced, so the documented type is the whole surface: a
    /// caller that switches exhaustively over `TicketError` has handled every
    /// way a ticket can be refused. Component initializers in `LabelCore`
    /// throw their own domains -- `PhysicalGeometryError`, `PagePlacementError`
    /// and `PageGeometryError` -- and those used to cross this boundary
    /// unannounced, which is how a caller ended up with an unhandled path.
    ///
    /// They are wrapped rather than folded into `malformedJSON`. Which
    /// constraint a hostile ticket violated is the useful part of the refusal,
    /// and collapsing four domains into one case would throw it away to buy
    /// nothing: the boundary needs one *type*, not one *cause*.
    public enum TicketError: Swift.Error, Equatable, Sendable {
        case malformedJSON
        case unsupportedSchemaVersion(Int)
        case invalidPageNumber
        case invalidThreshold
        /// A physical length or resolution the geometry type refused.
        case invalidPhysicalGeometry(PhysicalGeometryError)
        /// Margins or a placement the planner refused.
        case invalidPagePlacement(PagePlacementError)
        /// A normalized region or source rectangle the page geometry refused.
        case invalidPageGeometry(PageGeometryError)
        /// A component threw an error from none of the domains above, carrying
        /// its type name. Reaching this case means the component surface grew
        /// and this mapping did not; it is deliberately NOT `malformedJSON`,
        /// because an unrecognised failure must not read as a recognised one.
        case unclassifiedComponentFailure(String)
    }

    /// Runs a component initializer and admits only `TicketError` past it.
    private static func admitting<T>(_ build: () throws -> T) throws -> T {
        do {
            return try build()
        } catch let error as TicketError {
            throw error
        } catch let error as PhysicalGeometryError {
            throw TicketError.invalidPhysicalGeometry(error)
        } catch let error as PagePlacementError {
            throw TicketError.invalidPagePlacement(error)
        } catch let error as PageGeometryError {
            throw TicketError.invalidPageGeometry(error)
        } catch {
            throw TicketError.unclassifiedComponentFailure(String(describing: type(of: error)))
        }
    }

    /// Re-reads the ticket bytes as a dictionary, so the *presence* of a key can
    /// be told from its absence -- something `Decodable` alone cannot express.
    ///
    /// `JSONSerialization` is a second parser run over bytes a first parser has
    /// already accepted, and the two are not guaranteed to agree: it throws
    /// `NSError` in `NSCocoaErrorDomain`, which is not part of this type's
    /// documented failure surface. Both of its failure modes -- a throw and a
    /// top level that is not an object -- become `malformedJSON` here, matching
    /// how `init(jsonData:)` already treats bytes the first parser rejects. The
    /// closure of the surface is then a property of this function rather than of
    /// an unstated argument that two JSON parsers behave identically.
    ///
    /// Internal rather than `private` so the error-surface test can pin the
    /// mapping directly, on bytes every JSON parser rejects.
    static func rootObject(from jsonData: Data) throws -> [String: Any] {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: jsonData)
        } catch {
            throw TicketError.malformedJSON
        }
        guard let root = parsed as? [String: Any] else { throw TicketError.malformedJSON }
        return root
    }

    public enum Conversion: Equatable, Sendable {
        case textAndBarcodeThreshold(cutoff: UInt8)
        case photographicOrderedDither4x4

        fileprivate var coreConversion: MonochromeConversion {
            switch self {
            case let .textAndBarcodeThreshold(cutoff): .textAndBarcodeThreshold(cutoff: cutoff)
            case .photographicOrderedDither4x4: .photographicOrderedDither4x4
            }
        }
    }

    public let schemaVersion: Int
    public let pageNumber: Int
    public let physicalSize: PhysicalSize
    public let resolution: DotResolution
    public let conversion: Conversion
    public let placementPolicy: PagePlacementPolicy
    public let outputMargins: OutputMargins
    public let sourceRegion: NormalizedRect?
    public let expectedSourceRect: PDFSourceRect?
    public let regionRotation: ExtractionRotation

    public init(
        schemaVersion: Int = 1,
        pageNumber: Int,
        physicalSize: PhysicalSize,
        resolution: DotResolution,
        conversion: Conversion,
        placementPolicy: PagePlacementPolicy = .fit,
        outputMargins: OutputMargins = .zero,
        sourceRegion: NormalizedRect? = nil,
        expectedSourceRect: PDFSourceRect? = nil,
        regionRotation: ExtractionRotation = .degrees0
    ) throws {
        guard (1...3).contains(schemaVersion) else { throw TicketError.unsupportedSchemaVersion(schemaVersion) }
        guard schemaVersion == 3 || outputMargins == .zero else { throw TicketError.malformedJSON }
        guard physicalSize.width.value - outputMargins.left - outputMargins.right > 0,
              physicalSize.height.value - outputMargins.top - outputMargins.bottom > 0 else {
            throw TicketError.malformedJSON
        }
        if schemaVersion == 1 {
            guard sourceRegion == nil, expectedSourceRect == nil, regionRotation == .degrees0 else {
                throw TicketError.malformedJSON
            }
        } else {
            guard sourceRegion != nil, expectedSourceRect != nil, placementPolicy == .fit else {
                throw TicketError.malformedJSON
            }
            if let expectedSourceRect {
                _ = try Self.admitting {
                    try PDFSourceRect.validated(x: expectedSourceRect.x, y: expectedSourceRect.y,
                        width: expectedSourceRect.width, height: expectedSourceRect.height)
                }
            }
        }
        guard pageNumber > 0 else { throw TicketError.invalidPageNumber }
        self.schemaVersion = schemaVersion
        self.pageNumber = pageNumber
        self.physicalSize = physicalSize
        self.resolution = resolution
        self.conversion = conversion
        self.placementPolicy = placementPolicy
        self.outputMargins = outputMargins
        self.sourceRegion = sourceRegion
        self.expectedSourceRect = expectedSourceRect
        self.regionRotation = regionRotation
    }

    /// Version 1 retains full-page conversion; version 2 requires a validated
    /// extraction region, expected source rectangle, and explicit rotation.
    /// Version 3 adds required explicit output margins; older versions reject that field.
    ///
    /// - Throws: `TicketError`, and nothing else. Component domains are wrapped
    ///   by `admitting(_:)` rather than propagated, and the second parse of the
    ///   same bytes goes through `rootObject(from:)`, so every call that can
    ///   fail here is inside one of the two. The documented type is therefore
    ///   the whole failure surface by construction, not by an argument about
    ///   which inputs reach which parser.
    ///   `OfflineConversionTicketErrorSurfaceTests` pins that set; widening it
    ///   is a visible test change, not a silent one.
    public init(jsonData: Data) throws {
        let wire: WireTicket
        do {
            wire = try WorkerProtocolJSON.decode(WireTicket.self, from: jsonData, message: .conversionTicket)
        } catch {
            throw TicketError.malformedJSON
        }
        guard (1...3).contains(wire.schemaVersion) else {
            throw TicketError.unsupportedSchemaVersion(wire.schemaVersion)
        }
        let root = try Self.rootObject(from: jsonData)
        let margins: OutputMargins
        if wire.schemaVersion == 3 {
            guard let fields = root["outputMargins"] as? [String: Any],
                  Set(fields.keys) == Set(["left", "top", "right", "bottom"]),
                  let decoded = wire.outputMargins else { throw TicketError.malformedJSON }
            margins = try Self.admitting {
                try OutputMargins(left: decoded.left, top: decoded.top,
                    right: decoded.right, bottom: decoded.bottom)
            }
        } else {
            guard root["outputMargins"] == nil else { throw TicketError.malformedJSON }
            margins = .zero
        }
        let conversion: Conversion
        switch wire.conversion.mode {
        case "textAndBarcodeThreshold":
            guard let cutoff = wire.conversion.cutoff, (0...255).contains(cutoff) else {
                throw TicketError.invalidThreshold
            }
            conversion = .textAndBarcodeThreshold(cutoff: UInt8(cutoff))
        case "photographicOrderedDither4x4":
            guard wire.conversion.cutoff == nil else { throw TicketError.malformedJSON }
            conversion = .photographicOrderedDither4x4
        default:
            throw TicketError.malformedJSON
        }
        let placementPolicy: PagePlacementPolicy
        switch wire.placementPolicy ?? "fit" {
        case "fit": placementPolicy = .fit
        case "actualSize": placementPolicy = .actualSize
        default: throw TicketError.malformedJSON
        }
        let region: NormalizedRect?
        let expected: PDFSourceRect?
        let rotation: ExtractionRotation
        if let extraction = wire.extraction {
            region = try Self.admitting {
                try NormalizedRect(x: extraction.region.x, y: extraction.region.y,
                                   width: extraction.region.width, height: extraction.region.height)
            }
            expected = try Self.admitting {
                try PDFSourceRect.validated(x: extraction.expectedSourceRect.x,
                    y: extraction.expectedSourceRect.y, width: extraction.expectedSourceRect.width,
                    height: extraction.expectedSourceRect.height)
            }
            guard let selected = ExtractionRotation(rawValue: extraction.rotation) else {
                throw TicketError.malformedJSON
            }
            rotation = selected
        } else {
            region = nil; expected = nil; rotation = .degrees0
        }
        let physicalSize = try Self.admitting {
            PhysicalSize(
                width: try Millimeters(wire.physicalSize.widthMillimeters),
                height: try Millimeters(wire.physicalSize.heightMillimeters)
            )
        }
        let resolution = try Self.admitting {
            try DotResolution(
                xDotsPerMillimeter: wire.resolution.xDotsPerMillimeter,
                yDotsPerMillimeter: wire.resolution.yDotsPerMillimeter
            )
        }
        try self.init(
            schemaVersion: wire.schemaVersion,
            pageNumber: wire.pageNumber,
            physicalSize: physicalSize,
            resolution: resolution,
            conversion: conversion,
            placementPolicy: placementPolicy, outputMargins: margins,
            sourceRegion: region, expectedSourceRect: expected, regionRotation: rotation
        )
    }

    private struct WireTicket: Decodable {
        let schemaVersion: Int
        let pageNumber: Int
        let physicalSize: WirePhysicalSize
        let resolution: WireResolution
        let conversion: WireConversion

        let placementPolicy: String?
        let extraction: WireExtraction?
        let outputMargins: WireMargins?
        private enum CodingKeys: String, CodingKey { case schemaVersion, pageNumber, physicalSize, resolution, conversion, placementPolicy, extraction, outputMargins }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            pageNumber = try values.decode(Int.self, forKey: .pageNumber)
            physicalSize = try values.decode(WirePhysicalSize.self, forKey: .physicalSize)
            resolution = try values.decode(WireResolution.self, forKey: .resolution)
            conversion = try values.decode(WireConversion.self, forKey: .conversion)
            placementPolicy = try values.decodeIfPresent(String.self, forKey: .placementPolicy)
            extraction = try values.decodeIfPresent(WireExtraction.self, forKey: .extraction)
            outputMargins = try values.decodeIfPresent(WireMargins.self, forKey: .outputMargins)
        }
    }

    private struct WireMargins: Decodable {
        let left: Double
        let top: Double
        let right: Double
        let bottom: Double
    }

    private struct WireExtraction: Decodable {
        let region: WireRect
        let expectedSourceRect: WireRect
        let rotation: Int
    }

    private struct WireRect: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private struct WirePhysicalSize: Decodable {
        let widthMillimeters: Double
        let heightMillimeters: Double
        private enum CodingKeys: String, CodingKey { case widthMillimeters, heightMillimeters }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            widthMillimeters = try values.decode(Double.self, forKey: .widthMillimeters)
            heightMillimeters = try values.decode(Double.self, forKey: .heightMillimeters)
        }
    }

    private struct WireResolution: Decodable {
        let xDotsPerMillimeter: Double
        let yDotsPerMillimeter: Double
        private enum CodingKeys: String, CodingKey { case xDotsPerMillimeter, yDotsPerMillimeter }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            xDotsPerMillimeter = try values.decode(Double.self, forKey: .xDotsPerMillimeter)
            yDotsPerMillimeter = try values.decode(Double.self, forKey: .yDotsPerMillimeter)
        }
    }

    private struct WireConversion: Decodable {
        let mode: String
        let cutoff: Int?
        private enum CodingKeys: String, CodingKey { case mode, cutoff }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            mode = try values.decode(String.self, forKey: .mode)
            cutoff = try values.decodeIfPresent(Int.self, forKey: .cutoff)
        }
    }
}

/// A fully materialized, bounded offline graphics envelope. It contains no
/// printer controls, profile state, queue identity, or transport operation.
public struct OfflinePreparedConversion: Equatable, Sendable {
    public let bitmap: MonochromeBitmap
    public let zpl: Data

    /// This exact PBM expands the same packed input passed to the encoder.
    public var previewPBM: Data { bitmap.pbmData() }
}

public enum OfflineConversion {
    public static let maximumInputBytes = 100 * 1024 * 1024

    public static func prepare(originalPDF: Data, ticket: OfflineConversionTicket) throws -> OfflinePreparedConversion {
        let canvas = try DotCanvas(physicalSize: ticket.physicalSize, resolution: ticket.resolution)
        let rendered = try QuartzPDFRenderer.render(.init(
            originalPDF: originalPDF,
            pageNumber: ticket.pageNumber,
            canvas: canvas,
            placementPolicy: ticket.placementPolicy,
            outputMargins: ticket.outputMargins,
            sourceRegion: ticket.sourceRegion,
            regionRotation: ticket.regionRotation,
            expectedSourceRect: ticket.expectedSourceRect,
            maximumInputBytes: maximumInputBytes
        ))
        let bitmap = try ticket.conversion.coreConversion.convert(
            width: rendered.width,
            height: rendered.height,
            grayscale: rendered.pixels,
            stride: rendered.bytesPerRow,
            maxByteCount: canvas.bitmapLayout.byteCount
        )
        let zpl = try ZPLGraphicEncoder().diagnosticFormat(bitmap)
        return OfflinePreparedConversion(bitmap: bitmap, zpl: zpl)
    }
}
