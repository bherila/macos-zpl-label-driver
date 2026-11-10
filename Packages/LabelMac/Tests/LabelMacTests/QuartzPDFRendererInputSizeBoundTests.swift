import CoreGraphics
import Foundation
import XCTest
@testable import LabelCore
@testable import LabelMac

/// The renderer's own input-size bound, at each of its three entry points.
///
/// A mutation run for M2-AC09 on hosted macos-26 removed this guard at every site and no test failed.
/// The CLI test that rejects an oversized source passes regardless, because the CLI refuses the
/// file before the renderer sees it, so the renderer's own check was an untested second line of
/// defence. Each case brackets the bound from both sides: one byte under the document's size is
/// refused with the exact `inputTooLarge` values, and exactly the document's size is accepted, so a
/// check that is off by one in either direction fails.
final class QuartzPDFRendererInputSizeBoundTests: XCTestCase {
    private enum TestError: Error { case unavailable }

    private func smallPDF() throws -> Data {
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

    private func canvas() throws -> DotCanvas {
        let dotsPerMillimeter = 72.0 / 25.4
        return try DotCanvas(
            physicalSize: PhysicalSize(width: try Millimeters(10 / dotsPerMillimeter),
                                       height: try Millimeters(10 / dotsPerMillimeter)),
            resolution: try DotResolution(xDotsPerMillimeter: dotsPerMillimeter,
                                          yDotsPerMillimeter: dotsPerMillimeter))
    }

    private func assertTooLarge(_ body: () throws -> Void, size: Int, limit: Int,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error,
                           .inputTooLarge(actual: size, limit: limit), file: file, line: line)
        }
    }

    func testRenderRefusesADocumentOneByteOverItsInputLimitAndAcceptsExactlyTheLimit() throws {
        let pdf = try smallPDF()
        let canvas = try canvas()
        assertTooLarge({
            _ = try QuartzPDFRenderer.render(QuartzPDFRenderer.Request(
                originalPDF: pdf, pageNumber: 1, canvas: canvas, maximumInputBytes: pdf.count - 1))
        }, size: pdf.count, limit: pdf.count - 1)
        XCTAssertNoThrow(try QuartzPDFRenderer.render(QuartzPDFRenderer.Request(
            originalPDF: pdf, pageNumber: 1, canvas: canvas, maximumInputBytes: pdf.count)))
    }

    func testPageBoxRefusesADocumentOneByteOverItsInputLimitAndAcceptsExactlyTheLimit() throws {
        let pdf = try smallPDF()
        assertTooLarge({
            _ = try QuartzPDFRenderer.pageBox(originalPDF: pdf, pageNumber: 1, maximumInputBytes: pdf.count - 1)
        }, size: pdf.count, limit: pdf.count - 1)
        XCTAssertNoThrow(try QuartzPDFRenderer.pageBox(
            originalPDF: pdf, pageNumber: 1, maximumInputBytes: pdf.count))
    }

    func testDocumentPageBoxesRefusesADocumentOneByteOverItsInputLimitAndAcceptsExactlyTheLimit() throws {
        let pdf = try smallPDF()
        assertTooLarge({
            _ = try QuartzPDFRenderer.documentPageBoxes(originalPDF: pdf, maximumInputBytes: pdf.count - 1)
        }, size: pdf.count, limit: pdf.count - 1)
        XCTAssertNoThrow(try QuartzPDFRenderer.documentPageBoxes(
            originalPDF: pdf, maximumInputBytes: pdf.count))
    }
}
