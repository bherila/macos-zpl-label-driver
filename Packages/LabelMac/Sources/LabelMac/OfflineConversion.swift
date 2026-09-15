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

    public init(
        schemaVersion: Int = 1,
        pageNumber: Int,
        physicalSize: PhysicalSize,
        resolution: DotResolution,
        conversion: Conversion
    ) throws {
        guard schemaVersion == 1 else { throw TicketError.unsupportedSchemaVersion(schemaVersion) }
        guard pageNumber > 0 else { throw TicketError.invalidPageNumber }
        self.schemaVersion = schemaVersion
        self.pageNumber = pageNumber
        self.physicalSize = physicalSize
        self.resolution = resolution
        self.conversion = conversion
    }

    /// Decodes schema version 1 explicitly. New versions must add a reviewed
    /// migration rather than relying on synthesized Codable layout.
    public init(jsonData: Data) throws {
        let wire: WireTicket
        do {
            wire = try JSONDecoder().decode(WireTicket.self, from: jsonData)
        } catch {
            throw TicketError.malformedJSON
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
            conversion: conversion
        )
    }

    private struct WireTicket: Decodable {
        let schemaVersion: Int
        let pageNumber: Int
        let physicalSize: WirePhysicalSize
        let resolution: WireResolution
        let conversion: WireConversion

        private enum CodingKeys: String, CodingKey { case schemaVersion, pageNumber, physicalSize, resolution, conversion }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
            pageNumber = try values.decode(Int.self, forKey: .pageNumber)
            physicalSize = try values.decode(WirePhysicalSize.self, forKey: .physicalSize)
            resolution = try values.decode(WireResolution.self, forKey: .resolution)
            conversion = try values.decode(WireConversion.self, forKey: .conversion)
        }
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
