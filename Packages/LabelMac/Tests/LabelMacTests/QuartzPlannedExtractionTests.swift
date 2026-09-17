import CoreGraphics
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class QuartzPlannedExtractionTests: XCTestCase {
    private enum TestError: Error { case unavailable }
    private let dotsPerMillimeter = 72.0 / 25.4

    private func leftHalfBlackPDF(rotation: Int = 0) throws -> Data {
        if rotation == 90 { return rotatedLeftHalfBlackPDF() }
        guard rotation == 0 else { throw TestError.unavailable }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw TestError.unavailable }
        var box = CGRect(x: 0, y: 0, width: 20, height: 10)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw TestError.unavailable }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func rotatedLeftHalfBlackPDF() -> Data {
        let content = "0 0 0 rg 0 0 10 10 re f\n"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 10] /CropBox [0 0 20 10] /Rotate 90 /Resources << >> /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream",
        ]
        var result = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(result.count)
            result.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xrefOffset = result.count
        result.append(Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets.dropFirst() {
            result.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        result.append(Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        return result
    }

    private func physical(widthPoints: Double, heightPoints: Double) throws -> PhysicalSize {
        PhysicalSize(
            width: try Millimeters(widthPoints * 25.4 / 72),
            height: try Millimeters(heightPoints * 25.4 / 72)
        )
    }

    private func plannedLabel(
        region: NormalizedRect,
        rotation: ExtractionRotation = .degrees0,
        outputStock: PhysicalSize,
        outputMargins: OutputMargins = .zero,
        sourceBox: PDFPageBox? = nil
    ) throws -> PlannedExtractionLabel {
        let box: PDFPageBox
        if let sourceBox { box = sourceBox }
        else { box = try PDFPageBox(originX: 0, originY: 0, width: 20, height: 10) }
        let sourceSize = try box.effectivePhysicalSize()
        let profile = try WorkflowProfile(
            schemaVersion: outputMargins == .zero ? 2 : 3, id: "planned-extraction", revision: 8,
            outputStockID: "test-stock", outputStock: outputStock, outputMargins: outputMargins,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: sourceSize),
                disposition: .extract([try ExtractionRegion(
                    id: "selected", normalizedRect: region,
                    rotation: rotation, outputOrder: 0
                )])
            )]
        )
        let plan = try ExtractionPlanner.plan(
            sourcePages: [box],
            profile: profile
        )
        return plan.outputLabels[0]
    }

    private func canvas(_ stock: PhysicalSize) throws -> DotCanvas {
        try DotCanvas(
            physicalSize: stock,
            resolution: DotResolution(
                xDotsPerMillimeter: dotsPerMillimeter,
                yDotsPerMillimeter: dotsPerMillimeter
            )
        )
    }

    func testUnwiredMarginsRejectBothRenderPathsBeforeParsingOrWorkerLaunch() throws {
        let stock = PhysicalSize(width: try Millimeters(10), height: try Millimeters(10))
        let label = try plannedLabel(region: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            outputStock: stock, outputMargins: OutputMargins(left: 1, top: 1, right: 1, bottom: 1))
        let canvas = try DotCanvas(physicalSize: stock,
            resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8))
        let conversion = MonochromeConversion.textAndBarcodeThreshold(cutoff: 128)
        XCTAssertThrowsError(try QuartzPlannedExtraction.prepare(originalPDF: Data(), label: label,
            canvas: canvas, conversion: conversion)) {
            XCTAssertEqual($0 as? QuartzPlannedExtraction.Error, .unsupportedOutputMargins)
        }
        XCTAssertThrowsError(try OfflineExtractionWorker.render(originalPDF: Data(), label: label,
            canvas: canvas, conversion: conversion, workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"))) {
            XCTAssertEqual($0 as? OfflineExtractionWorker.Error, .unsupportedOutputMargins)
        }
    }

    func testSelectedRegionRendersFromOriginalPDFToExactPreviewAndEncoderInput() throws {
        let stock = try physical(widthPoints: 10, heightPoints: 10)
        let label = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
            outputStock: stock
        )
        let prepared = try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(),
            label: label,
            canvas: canvas(stock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        )
        XCTAssertEqual(prepared.bitmap.layout.width, 10)
        XCTAssertEqual(prepared.bitmap.layout.height, 10)
        XCTAssertEqual(prepared.bitmap.bytes, Array(repeating: [0xFF, 0xC0], count: 10).flatMap { $0 })
        XCTAssertEqual(prepared.previewPBM, prepared.bitmap.pbmData())
        XCTAssertEqual(prepared.profileRevision, 8)
        XCTAssertTrue(String(decoding: prepared.zpl, as: UTF8.self).contains("^GFA,20,20,2,"))
    }

    func testClockwiseRegionRotationMapsLeftSideToTopWithoutIntermediateRaster() throws {
        let stock = try physical(widthPoints: 10, heightPoints: 20)
        let label = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            rotation: .degrees90,
            outputStock: stock
        )
        let prepared = try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(),
            label: label,
            canvas: canvas(stock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        )
        let preview = prepared.bitmap.grayscalePreview()
        XCTAssertTrue(preview.pixels.prefix(100).allSatisfy { $0 == 0 })
        XCTAssertTrue(preview.pixels.suffix(100).allSatisfy { $0 == 255 })
    }

    func testRemainingRightAngleRotationsHaveExplicitPixelOrientation() throws {
        let horizontalStock = try physical(widthPoints: 20, heightPoints: 10)
        let rotated180 = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            rotation: .degrees180,
            outputStock: horizontalStock
        )
        let preview180 = try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(),
            label: rotated180,
            canvas: canvas(horizontalStock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        ).bitmap.grayscalePreview()
        for row in 0..<10 {
            let pixels = preview180.pixels[(row * 20)..<((row + 1) * 20)]
            XCTAssertTrue(pixels.prefix(10).allSatisfy { $0 == 255 })
            XCTAssertTrue(pixels.suffix(10).allSatisfy { $0 == 0 })
        }

        let verticalStock = try physical(widthPoints: 10, heightPoints: 20)
        let rotated270 = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            rotation: .degrees270,
            outputStock: verticalStock
        )
        let preview270 = try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(),
            label: rotated270,
            canvas: canvas(verticalStock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        ).bitmap.grayscalePreview()
        XCTAssertTrue(preview270.pixels.prefix(100).allSatisfy { $0 == 255 })
        XCTAssertTrue(preview270.pixels.suffix(100).allSatisfy { $0 == 0 })
    }

    func testRotatedPDFPageRegionUsesUprightNormalizedCoordinates() throws {
        let stock = try physical(widthPoints: 10, heightPoints: 10)
        let rotatedPage = try PDFPageBox(
            originX: 0, originY: 0, width: 20, height: 10,
            rotationDegreesClockwise: 90
        )
        let label = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 1, height: 0.5),
            outputStock: stock,
            sourceBox: rotatedPage
        )
        let prepared = try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(rotation: 90),
            label: label,
            canvas: canvas(stock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        )
        XCTAssertEqual(prepared.bitmap.bytes, Array(repeating: [0xFF, 0xC0], count: 10).flatMap { $0 })
    }

    func testPlanGeometryAndOutputStockAreRevalidatedAgainstOriginal() throws {
        let stock = try physical(widthPoints: 10, heightPoints: 10)
        let mismatched = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
            outputStock: stock,
            sourceBox: PDFPageBox(originX: 1, originY: 0, width: 20, height: 10)
        )
        XCTAssertThrowsError(try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(),
            label: mismatched,
            canvas: canvas(stock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        )) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .invalidPageGeometry)
        }

        let label = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
            outputStock: stock
        )
        let wrongStock = try physical(widthPoints: 11, heightPoints: 10)
        XCTAssertThrowsError(try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(),
            label: label,
            canvas: canvas(wrongStock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        )) {
            XCTAssertEqual($0 as? QuartzPlannedExtraction.Error, .outputStockMismatch)
        }
    }

    func testNearZeroRegionCannotCreateUnboundedQuartzTransform() throws {
        let stock = try physical(widthPoints: 10, heightPoints: 10)
        let label = try plannedLabel(
            region: NormalizedRect(x: 0, y: 0, width: 1e-12, height: 2e-12),
            outputStock: stock
        )
        XCTAssertThrowsError(try QuartzPlannedExtraction.prepare(
            originalPDF: leftHalfBlackPDF(),
            label: label,
            canvas: canvas(stock),
            conversion: .textAndBarcodeThreshold(cutoff: 128)
        )) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .invalidPageGeometry)
        }
    }
}
