import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class WorkerBitmapBindingTests: XCTestCase {
    func testDimensionsAndAllocationBoundPrecedePackedBufferMaterialization() throws {
        for (width, height) in [(Int.max, 1), (1, Int.max), (0, 1), (32001, 1), (32000, 32000)] {
            let output = OfflineRenderWorkerOutput(result: .init(widthDots: width, heightDots: height,
                zplBytes: 0, previewBytes: 0), zpl: Data(), previewPBM: Data())
            XCTAssertThrowsError(try WorkerBitmapBinding.validate(output))
        }
        let bitmap = try MonochromeBitmap(width: 9, height: 2, bytes: [0x80, 0, 0, 0x80])
        let zpl = try ZPLGraphicEncoder().diagnosticFormat(bitmap), preview = bitmap.pbmData()
        let output = OfflineRenderWorkerOutput(result: .init(widthDots: 9, heightDots: 2,
            zplBytes: zpl.count, previewBytes: preview.count), zpl: zpl, previewPBM: preview)
        XCTAssertEqual(try WorkerBitmapBinding.validate(output, maximumPackedBytes: 4), bitmap)
        XCTAssertThrowsError(try WorkerBitmapBinding.validate(output, maximumPackedBytes: 3))
    }
}
