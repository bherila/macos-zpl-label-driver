import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class OfflineExtractionWorkerTests: XCTestCase {
    func testReturnedBitmapRequiresExactCanvasPaddingAndDiagnosticEncoding() throws {
        let canvas = try DotCanvas(physicalSize: PhysicalSize(width: Millimeters(9), height: Millimeters(3)),
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
        let bitmap = try MonochromeBitmap(width: 9, height: 3, bytes: [128, 128, 0, 0, 255, 0])
        let zpl = try ZPLGraphicEncoder().diagnosticFormat(bitmap)
        func output(_ preview: Data, _ encoded: Data, width: Int = 9) -> OfflineRenderWorkerOutput {
            .init(result: .init(widthDots: width, heightDots: 3,
                                zplBytes: encoded.count, previewBytes: preview.count),
                  zpl: encoded, previewPBM: preview)
        }
        XCTAssertEqual(try OfflineExtractionWorker.validate(output: output(bitmap.pbmData(), zpl), canvas: canvas), bitmap)
        var badPadding = bitmap.pbmData()
        badPadding[badPadding.index(before: badPadding.endIndex)] = 1
        let invalidOutputs = [
            output(badPadding, zpl),
            output(bitmap.pbmData(), Data("unrelated output".utf8)),
            output(bitmap.pbmData(), zpl, width: 8),
            output(bitmap.pbmData() + Data([0]), zpl),
            output(Data(bitmap.pbmData().dropLast()), zpl),
            output(Data("P4\n8 3\n".utf8) + Data(bitmap.bytes), zpl),
        ]
        for invalid in invalidOutputs {
            XCTAssertThrowsError(try OfflineExtractionWorker.validate(output: invalid, canvas: canvas)) {
                XCTAssertEqual($0 as? OfflineExtractionWorker.Error, .invalidWorkerBitmap)
            }
        }
    }
}
