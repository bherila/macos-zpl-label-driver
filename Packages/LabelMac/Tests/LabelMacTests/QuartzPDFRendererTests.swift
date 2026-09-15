import CoreGraphics
import Foundation
import XCTest
@testable import LabelCore
@testable import LabelMac

final class QuartzPDFRendererTests: XCTestCase {
    private func fixture(named name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appending(path: "Fixtures/generated/\(name).pdf"))
    }

    private func repositoryRoot() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root
    }

    private func cliExecutable() throws -> URL {
        let root = repositoryRoot()
        let candidates = [
            root.appending(path: "Packages/LabelMac/.build/debug/label-driver"),
            root.appending(path: "Packages/LabelMac/.build/release/label-driver"),
            root.appending(path: "Packages/LabelMac/.build/arm64-apple-macosx/debug/label-driver"),
            root.appending(path: "Packages/LabelMac/.build/arm64-apple-macosx/release/label-driver"),
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw TestError.unavailable
        }
        return executable
    }

    private func runCLI(_ arguments: [String]) throws -> (status: Int32, stdout: Data, stderr: Data) {
        let process = Process()
        process.executableURL = try cliExecutable()
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, stdout.fileHandleForReading.readDataToEndOfFile(), stderr.fileHandleForReading.readDataToEndOfFile())
    }

    private func lowerHalfBlackPDF() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw TestError.unavailable }
        var box = CGRect(x: 0, y: 0, width: 10, height: 10)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw TestError.unavailable }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 5))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func twoPagePDF() throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw TestError.unavailable }
        var box = CGRect(x: 0, y: 0, width: 10, height: 10)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw TestError.unavailable }
        for _ in 0..<2 {
            context.beginPDFPage(nil)
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private func request(pdf: Data, page: Int = 1, width: Int = 10, height: Int = 10) throws -> QuartzPDFRenderer.Request {
        let canvas = try DotCanvas(
            physicalSize: PhysicalSize(width: try Millimeters(10), height: try Millimeters(10)),
            resolution: try DotResolution(xDotsPerMillimeter: Double(width) / 10, yDotsPerMillimeter: Double(height) / 10)
        )
        return QuartzPDFRenderer.Request(originalPDF: pdf, pageNumber: page, canvas: canvas)
    }

    private func packed(_ bitmap: QuartzPDFRenderer.GrayscaleBitmap) throws -> MonochromeBitmap {
        try MonochromeBitmap.threshold(
            width: bitmap.width,
            height: bitmap.height,
            grayscale: bitmap.pixels,
            stride: bitmap.bytesPerRow
        )
    }

    func testRendersOriginalPDFWithWhiteBackgroundAndTopDownRows() throws {
        let bitmap = try QuartzPDFRenderer.render(request( pdf: try lowerHalfBlackPDF()))
        XCTAssertEqual(bitmap.pixels.count, 100)
        XCTAssertTrue(bitmap.pixels.prefix(50).allSatisfy { $0 == 255 })
        XCTAssertTrue(bitmap.pixels.suffix(50).allSatisfy { $0 == 0 })
    }

    func testRejectsInvalidInputAndBoundsBeforeRendering() throws {
        let pdf = try lowerHalfBlackPDF()
        XCTAssertThrowsError(try QuartzPDFRenderer.render(request(pdf: Data("not-pdf".utf8)))) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .malformedOrUnsupportedPDF)
        }
        XCTAssertThrowsError(try QuartzPDFRenderer.render(request(pdf: pdf, page: 2))) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .pageOutOfRange(requested: 2, pageCount: 1))
        }
        var limited = try request(pdf: pdf)
        limited = QuartzPDFRenderer.Request(originalPDF: pdf, pageNumber: 1, canvas: limited.canvas, maximumPixels: 99)
        XCTAssertThrowsError(try QuartzPDFRenderer.render(limited)) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .pixelLimitExceeded(actual: 100, limit: 99))
        }
        let sourceLimit = QuartzPDFRenderer.Request(
            originalPDF: try twoPagePDF(), pageNumber: 1, canvas: limited.canvas, maximumSourcePages: 1
        )
        XCTAssertThrowsError(try QuartzPDFRenderer.render(sourceLimit)) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .sourcePageLimitExceeded(actual: 2, limit: 1))
        }
        let invalidLimit = QuartzPDFRenderer.Request(
            originalPDF: pdf, pageNumber: 1, canvas: limited.canvas, maximumSourcePages: 0
        )
        XCTAssertThrowsError(try QuartzPDFRenderer.render(invalidLimit)) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .invalidLimits)
        }
    }

    func testRendersOriginalPDFDirectlyToCanonicalMonochrome() throws {
        let source = try lowerHalfBlackPDF()
        let request = try request(pdf: source)
        let grayscale = try QuartzPDFRenderer.render(request)
        let bitmap = try QuartzPDFToMonochrome.render(request)

        XCTAssertEqual(bitmap.layout.width, grayscale.width)
        XCTAssertEqual(bitmap.layout.height, grayscale.height)
        XCTAssertEqual(
            bitmap.bytes,
            Array(repeating: [0, 0], count: 5).flatMap { $0 }
                + Array(repeating: [0xFF, 0xC0], count: 5).flatMap { $0 }
        )
        XCTAssertEqual(
            bitmap.grayscalePreview().pixels,
            grayscale.pixels.map { $0 < 128 ? UInt8(0) : UInt8(255) }
        )
    }

    func testUserUnitFixturePagesRenderToTheSamePhysicalDots() throws {
        let source = try fixture(named: "user-unit")
        let first = try QuartzPDFRenderer.render(request(pdf: source, page: 1, width: 100, height: 150))
        let second = try QuartzPDFRenderer.render(request(pdf: source, page: 2, width: 100, height: 150))
        // Quartz antialiasing varies at edge samples, so the RGB/grayscale
        // intermediate is not a stable output oracle. The packed bitmap is the
        // actual encoder input and must remain identical for the two pages.
        XCTAssertEqual(try packed(first), try packed(second))
        XCTAssertGreaterThan(first.pixels.filter { $0 < 255 }.count, 0)
    }

    func testShiftedAndNegativeCropBoxOriginsDoNotMoveFinalPackedDots() throws {
        let source = try fixture(named: "box-origins")
        let shifted = try QuartzPDFRenderer.render(request(pdf: source, page: 1, width: 100, height: 150))
        let negative = try QuartzPDFRenderer.render(request(pdf: source, page: 2, width: 100, height: 150))
        XCTAssertEqual(try packed(shifted), try packed(negative))
        XCTAssertGreaterThan(shifted.pixels.filter { $0 < 255 }.count, 0)
    }

    func testRejectsInteractiveAnnotationFormRatherThanDroppingItsAppearance() throws {
        let source = try fixture(named: "annotation-form")
        XCTAssertThrowsError(try QuartzPDFRenderer.render(request(pdf: source))) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error, .annotationsUnsupported)
        }
    }

    func testTransparencyCompositesAgainstTheExplicitWhiteLabelBackground() throws {
        let source = try fixture(named: "transparency")
        let bitmap = try QuartzPDFRenderer.render(request(pdf: source, width: 288, height: 432))
        let overlayPixel = bitmap.pixels[221 * bitmap.bytesPerRow + 165]
        let adjacentWhitePixel = bitmap.pixels[221 * bitmap.bytesPerRow + 180]

        XCTAssertGreaterThan(overlayPixel, 150)
        XCTAssertLessThan(overlayPixel, 190)
        XCTAssertEqual(adjacentWhitePixel, 255)
    }

    func testEmbeddedRasterPagesRetainBlackAndWhiteStructureAtFinalGeometry() throws {
        let source = try fixture(named: "raster-high-low")
        for page in 1...2 {
            let bitmap = try QuartzPDFRenderer.render(request(pdf: source, page: page, width: 288, height: 432))
            var samples: [UInt8] = []
            for row in 228..<278 {
                let start = row * bitmap.bytesPerRow + 112
                samples.append(contentsOf: bitmap.pixels[start..<(start + 50)])
            }
            XCTAssertLessThan(samples.min() ?? 255, 32, "page \(page) lost embedded black structure")
            XCTAssertGreaterThan(samples.max() ?? 0, 223, "page \(page) lost embedded white structure")
        }
    }

    func testMixedPageSizesUseEachOriginalPagesGeometry() throws {
        let source = try fixture(named: "mixed-pages")
        let native = try QuartzPDFRenderer.render(request(pdf: source, page: 1, width: 288, height: 432))
        let letter = try QuartzPDFRenderer.render(request(pdf: source, page: 2, width: 288, height: 432))
        let middleRow = 216

        XCTAssertLessThan(native.pixels[middleRow * native.bytesPerRow + 10], 224)
        XCTAssertEqual(letter.pixels[middleRow * letter.bytesPerRow + 10], 255)
        XCTAssertEqual(native.pixels[middleRow * native.bytesPerRow + 147], 255)
        XCTAssertLessThan(letter.pixels[middleRow * letter.bytesPerRow + 147], 224)
    }

    func testOfflineTicketDecodesExplicitSchemaAndPreparesExactPreview() throws {
        let ticket = try OfflineConversionTicket(jsonData: Data("""
        {
          "schemaVersion": 1,
          "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 }
        }
        """.utf8))
        let prepared = try OfflineConversion.prepare(originalPDF: try lowerHalfBlackPDF(), ticket: ticket)
        XCTAssertEqual(prepared.bitmap.layout.width, 10)
        XCTAssertEqual(prepared.bitmap.layout.height, 10)
        XCTAssertEqual(prepared.previewPBM, prepared.bitmap.pbmData())
        XCTAssertTrue(String(decoding: prepared.zpl, as: UTF8.self).hasPrefix("^XA\n^FO0,0^GFA,"))
        XCTAssertTrue(String(decoding: prepared.zpl, as: UTF8.self).hasSuffix("^XZ\n"))
    }

    func testOfflineTicketRejectsUnknownSchemaAndBadConversion() {
        let unsupported = Data("""
        { "schemaVersion": 2, "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "photographicOrderedDither4x4" } }
        """.utf8)
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: unsupported)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .unsupportedSchemaVersion(2))
        }
        let invalidMode = Data("""
        { "schemaVersion": 1, "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "unknown" } }
        """.utf8)
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: invalidMode)) {
            XCTAssertEqual($0 as? OfflineConversionTicket.TicketError, .malformedJSON)
        }
    }

    func testOfflineCLIValidatesConvertsAndRefusesOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LabelDriverCLI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ticket = directory.appending(path: "ticket.json")
        try Data("""
        { "schemaVersion": 1, "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 } }
        """.utf8).write(to: ticket)
        let source = repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf")
        let validation = try runCLI(["validate", source.path, "--job-ticket", ticket.path, "--json"])
        XCTAssertEqual(validation.status, 0)
        XCTAssertTrue(String(decoding: validation.stdout, as: UTF8.self).contains("\"wroteFiles\":false"))
        XCTAssertTrue(String(decoding: validation.stdout, as: UTF8.self).contains("\"renderIsolation\":\"subprocess\""))
        let zpl = directory.appending(path: "output.zpl")
        let conversion = try runCLI(["convert", source.path, "--job-ticket", ticket.path, "--output", zpl.path, "--preview-dir", directory.path, "--json"])
        XCTAssertEqual(conversion.status, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zpl.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appending(path: "page-0001.pbm").path))
        let repeatConversion = try runCLI(["convert", source.path, "--job-ticket", ticket.path, "--output", zpl.path, "--preview-dir", directory.path, "--json"])
        XCTAssertEqual(repeatConversion.status, 73)
        XCTAssertTrue(repeatConversion.stdout.isEmpty)
        XCTAssertTrue(String(decoding: repeatConversion.stderr, as: UTF8.self).contains("refusing to overwrite"))
        let malformedTicket = directory.appending(path: "malformed-ticket.json")
        try Data("{}".utf8).write(to: malformedTicket)
        let invalid = try runCLI(["validate", source.path, "--job-ticket", malformedTicket.path, "--json"])
        XCTAssertEqual(invalid.status, 65)
        XCTAssertTrue(invalid.stdout.isEmpty)
        let error = try JSONSerialization.jsonObject(with: invalid.stderr) as? [String: Any]
        XCTAssertEqual(error?["status"] as? String, "error")
        XCTAssertEqual(error?["code"] as? String, "JOB_TICKET_INVALID")
    }

    func testOfflineCLIRollsBackPreviewWhenZPLOutputCreationFails() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LabelDriverCLIRollback-\(UUID().uuidString)")
        let previewDirectory = directory.appending(path: "preview")
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ticket = directory.appending(path: "ticket.json")
        try Data("""
        { "schemaVersion": 1, "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 } }
        """.utf8).write(to: ticket)
        let source = repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf")
        let impossibleOutput = directory.appending(path: String(repeating: "x", count: 300))
        let result = try runCLI([
            "convert", source.path, "--job-ticket", ticket.path,
            "--output", impossibleOutput.path, "--preview-dir", previewDirectory.path, "--json",
        ])

        XCTAssertEqual(result.status, 73)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: impossibleOutput.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewDirectory.appending(path: "page-0001.pbm").path))
        let parentEntries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let previewEntries = try FileManager.default.contentsOfDirectory(atPath: previewDirectory.path)
        XCTAssertFalse(parentEntries.contains { $0.hasPrefix(".label-driver-") })
        XCTAssertFalse(previewEntries.contains { $0.hasPrefix(".label-driver-") })
        let error = try JSONSerialization.jsonObject(with: result.stderr) as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "OUTPUT_ERROR")
        XCTAssertEqual(error?["message"] as? String, "conversion outputs were not retained")
    }

    func testOfflineCLIRejectsAliasedOutputPairBeforeWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LabelDriverCLIAlias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ticket = directory.appending(path: "ticket.json")
        try Data("""
        { "schemaVersion": 1, "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 } }
        """.utf8).write(to: ticket)
        let source = repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf")
        let shared = directory.appending(path: "page-0001.pbm")
        let result = try runCLI([
            "convert", source.path, "--job-ticket", ticket.path,
            "--output", shared.path, "--preview-dir", directory.path, "--json",
        ])

        XCTAssertEqual(result.status, 73)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path))
    }

    func testOfflineCLIRejectsOversizedSourceAndTicketBeforePreparation() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LabelDriverCLILimits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ticket = directory.appending(path: "ticket.json")
        try Data("""
        { "schemaVersion": 1, "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 } }
        """.utf8).write(to: ticket)
        let oversizedPDF = directory.appending(path: "oversized.pdf")
        FileManager.default.createFile(atPath: oversizedPDF.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversizedPDF)
        try handle.truncate(atOffset: UInt64(OfflineConversion.maximumInputBytes + 1))
        try handle.close()
        let sourceResult = try runCLI(["validate", oversizedPDF.path, "--job-ticket", ticket.path, "--json"])
        XCTAssertEqual(sourceResult.status, 65)
        XCTAssertTrue(sourceResult.stdout.isEmpty)

        let oversizedTicket = directory.appending(path: "oversized-ticket.json")
        try Data(repeating: 0x20, count: 64 * 1024 + 1).write(to: oversizedTicket)
        let source = repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf")
        let ticketResult = try runCLI(["validate", source.path, "--job-ticket", oversizedTicket.path, "--json"])
        XCTAssertEqual(ticketResult.status, 65)
        XCTAssertTrue(ticketResult.stdout.isEmpty)
    }

    private enum TestError: Error { case unavailable }
}
