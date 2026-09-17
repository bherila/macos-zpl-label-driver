import Foundation
import LabelCore

/// Versioned, file-independent settings for the offline conversion CLI.
/// This is deliberately not a CUPS ticket or a printer profile schema.
public struct OfflineConversionTicket: Equatable, Sendable {
    public enum TicketError: Swift.Error, Equatable, Sendable {
        case malformedJSON
        case unsupportedSchemaVersion(Int)
        case invalidPageNumber
        case invalidThreshold
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
        sourceRegion: NormalizedRect? = nil,
        expectedSourceRect: PDFSourceRect? = nil,
        regionRotation: ExtractionRotation = .degrees0
    ) throws {
        guard schemaVersion == 1 || schemaVersion == 2 else { throw TicketError.unsupportedSchemaVersion(schemaVersion) }
        if schemaVersion == 1 {
            guard sourceRegion == nil, expectedSourceRect == nil, regionRotation == .degrees0 else {
                throw TicketError.malformedJSON
            }
        } else {
            guard sourceRegion != nil, expectedSourceRect != nil, placementPolicy == .fit else {
                throw TicketError.malformedJSON
            }
            if let expectedSourceRect {
                _ = try PDFSourceRect.validated(x: expectedSourceRect.x, y: expectedSourceRect.y,
                    width: expectedSourceRect.width, height: expectedSourceRect.height)
            }
        }
        guard pageNumber > 0 else { throw TicketError.invalidPageNumber }
        self.schemaVersion = schemaVersion
        self.pageNumber = pageNumber
        self.physicalSize = physicalSize
        self.resolution = resolution
        self.conversion = conversion
        self.placementPolicy = placementPolicy
        self.sourceRegion = sourceRegion
        self.expectedSourceRect = expectedSourceRect
        self.regionRotation = regionRotation
    }

    /// Version 1 retains full-page conversion; version 2 requires a validated
    /// extraction region, expected source rectangle, and explicit rotation.
    public init(jsonData: Data) throws {
        let wire: WireTicket
        do {
            wire = try WorkerProtocolJSON.decode(WireTicket.self, from: jsonData, message: .conversionTicket)
        } catch {
            throw TicketError.malformedJSON
        }
        guard wire.schemaVersion == 1 || wire.schemaVersion == 2 else {
            throw TicketError.unsupportedSchemaVersion(wire.schemaVersion)
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
            region = try NormalizedRect(x: extraction.region.x, y: extraction.region.y,
                                        width: extraction.region.width, height: extraction.region.height)
            expected = try PDFSourceRect.validated(x: extraction.expectedSourceRect.x,
                y: extraction.expectedSourceRect.y, width: extraction.expectedSourceRect.width,
                height: extraction.expectedSourceRect.height)
            guard let selected = ExtractionRotation(rawValue: extraction.rotation) else {
                throw TicketError.malformedJSON
            }
            rotation = selected
        } else {
            region = nil; expected = nil; rotation = .degrees0
        }
        try self.init(
            schemaVersion: wire.schemaVersion,
            pageNumber: wire.pageNumber,
            physicalSize: PhysicalSize(
                width: try Millimeters(wire.physicalSize.widthMillimeters),
                height: try Millimeters(wire.physicalSize.heightMillimeters)
            ),
            resolution: try DotResolution(
                xDotsPerMillimeter: wire.resolution.xDotsPerMillimeter,
                yDotsPerMillimeter: wire.resolution.yDotsPerMillimeter
            ),
            conversion: conversion,
            placementPolicy: placementPolicy,
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
        private enum CodingKeys: String, CodingKey { case schemaVersion, pageNumber, physicalSize, resolution, conversion, placementPolicy, extraction }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            pageNumber = try values.decode(Int.self, forKey: .pageNumber)
            physicalSize = try values.decode(WirePhysicalSize.self, forKey: .physicalSize)
            resolution = try values.decode(WireResolution.self, forKey: .resolution)
            conversion = try values.decode(WireConversion.self, forKey: .conversion)
            placementPolicy = try values.decodeIfPresent(String.self, forKey: .placementPolicy)
            extraction = try values.decodeIfPresent(WireExtraction.self, forKey: .extraction)
        }
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
