import CoreGraphics
import Foundation
import XCTest
@testable import LabelCore
@testable import LabelMac

final class QuartzPDFRendererTests: XCTestCase {
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

    private func request(pdf: Data, page: Int = 1, width: Int = 10, height: Int = 10) throws -> QuartzPDFRenderer.Request {
        let canvas = try DotCanvas(
            physicalSize: PhysicalSize(width: try Millimeters(10), height: try Millimeters(10)),
            resolution: try DotResolution(xDotsPerMillimeter: Double(width) / 10, yDotsPerMillimeter: Double(height) / 10)
        )
        return QuartzPDFRenderer.Request(originalPDF: pdf, pageNumber: page, canvas: canvas)
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

    private enum TestError: Error { case unavailable }
}
