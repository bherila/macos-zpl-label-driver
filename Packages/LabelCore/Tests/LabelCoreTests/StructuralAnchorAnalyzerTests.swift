import Foundation
import XCTest
@testable import LabelCore

final class StructuralAnchorAnalyzerTests: XCTestCase {
    private func image(
        width: Int = 40,
        height: Int = 30,
        rectangles: [(Int, Int, Int, Int)],
        prefix: Int = 0
    ) -> StructuralAnalysisImage {
        let stride = width + 3
        var storage = Data(repeating: 255, count: prefix + stride * height)
        for (left, top, right, bottom) in rectangles {
            for x in left...right {
                storage[prefix + top * stride + x] = 0
                storage[prefix + bottom * stride + x] = 0
            }
            for y in top...bottom {
                storage[prefix + y * stride + left] = 0
                storage[prefix + y * stride + right] = 0
            }
        }
        let pixels = storage.dropFirst(prefix) as Data
        return StructuralAnalysisImage(width: width, height: height, bytesPerRow: stride, pixels: pixels)
    }

    func testFindsDistinctBordersInTopLeftNormalizedCoordinates() throws {
        let candidates = try StructuralAnchorAnalyzer.analyzeBorders(image(
            rectangles: [(4, 3, 19, 17), (24, 5, 36, 25)]
        ))
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map(\.kind), [.border, .border])
        XCTAssertEqual(candidates[0].normalizedRect, try NormalizedRect(
            x: 0.1, y: 0.1, width: 0.4, height: 0.5
        ))
        XCTAssertEqual(candidates[1].normalizedRect, try NormalizedRect(
            x: 0.6, y: 1.0 / 6.0, width: 0.325, height: 0.7
        ))
    }

    func testDataSliceAndPaddedStrideAreReadRelativeToTheirOwnStart() throws {
        let zeroBased = image(rectangles: [(4, 3, 19, 17)])
        let sliced = image(rectangles: [(4, 3, 19, 17)], prefix: 7)
        XCTAssertEqual(
            try StructuralAnchorAnalyzer.analyzeBorders(zeroBased),
            try StructuralAnchorAnalyzer.analyzeBorders(sliced)
        )
    }

    func testBrokenBorderDoesNotBecomeCandidate() throws {
        var broken = image(rectangles: [(4, 3, 19, 17)])
        var pixels = broken.pixels
        for y in 6...14 { pixels[y * broken.bytesPerRow + 4] = 255 }
        broken = StructuralAnalysisImage(
            width: broken.width, height: broken.height,
            bytesPerRow: broken.bytesPerRow, pixels: pixels
        )
        XCTAssertEqual(try StructuralAnchorAnalyzer.analyzeBorders(broken), [])
    }

    func testInvalidImagesAndLimitsFailBeforeScanning() throws {
        XCTAssertThrowsError(try StructuralAnchorAnalyzer.analyzeBorders(.init(
            width: 10, height: 10, bytesPerRow: 9, pixels: Data(repeating: 0, count: 100)
        ))) {
            XCTAssertEqual($0 as? StructuralAnchorAnalyzer.Error, .invalidImage)
        }
        let small = try StructuralAnchorAnalyzer.Limits(maximumPixels: 10)
        XCTAssertThrowsError(try StructuralAnchorAnalyzer.analyzeBorders(
            image(rectangles: []), limits: small
        )) {
            XCTAssertEqual(
                $0 as? StructuralAnchorAnalyzer.Error,
                .pixelLimitExceeded(actual: 1_200, limit: 10)
            )
        }
        XCTAssertThrowsError(try StructuralAnchorAnalyzer.Limits(maximumCandidates: 0)) {
            XCTAssertEqual($0 as? StructuralAnchorAnalyzer.Error, .invalidLimits)
        }
    }

    func testPairWorkIsBoundedIndependentlyFromImageSize() throws {
        let manyLines = image(
            rectangles: (0..<10).map { index in
                (2, 1 + index * 2, 37, 2 + index * 2)
            }
        )
        let limits = try StructuralAnchorAnalyzer.Limits(maximumPairChecks: 3)
        XCTAssertThrowsError(try StructuralAnchorAnalyzer.analyzeBorders(
            manyLines, limits: limits
        )) {
            XCTAssertEqual(
                $0 as? StructuralAnchorAnalyzer.Error,
                .workLimitExceeded(limit: 3)
            )
        }
    }
}
