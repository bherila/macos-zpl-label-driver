import Foundation

/// A bounded, deterministic analysis-only grayscale image. Pixels are
/// top-to-bottom, where zero is black and 255 is white.
public struct StructuralAnalysisImage: Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixels: Data

    public init(width: Int, height: Int, bytesPerRow: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }
}

/// Local deterministic heuristics for structural profile validation. This
/// initial analyzer deliberately recognizes only rectangular borders. Other
/// anchor kinds remain available to separately qualified adapters.
public enum StructuralAnchorAnalyzer {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimits
        case invalidImage
        case pixelLimitExceeded(actual: Int, limit: Int)
        case featureLimitExceeded(limit: Int)
        case workLimitExceeded(limit: Int)
    }

    public struct Limits: Equatable, Sendable {
        public let maximumPixels: Int
        public let maximumLineRuns: Int
        public let maximumCandidates: Int
        public let maximumPairChecks: Int
        public let darknessCutoff: UInt8
        public let minimumLineFraction: Double
        public let minimumCoverage: Double

        public init(
            maximumPixels: Int = 1_048_576,
            maximumLineRuns: Int = 2_048,
            maximumCandidates: Int = 256,
            maximumPairChecks: Int = 100_000,
            darknessCutoff: UInt8 = 245,
            minimumLineFraction: Double = 0.08,
            minimumCoverage: Double = 0.65
        ) throws {
            guard maximumPixels > 0, maximumLineRuns > 0, maximumCandidates > 0,
                  maximumPairChecks > 0,
                  minimumLineFraction.isFinite, (0.01...1).contains(minimumLineFraction),
                  minimumCoverage.isFinite, (0.5...1).contains(minimumCoverage) else {
                throw Error.invalidLimits
            }
            self.maximumPixels = maximumPixels
            self.maximumLineRuns = maximumLineRuns
            self.maximumCandidates = maximumCandidates
            self.maximumPairChecks = maximumPairChecks
            self.darknessCutoff = darknessCutoff
            self.minimumLineFraction = minimumLineFraction
            self.minimumCoverage = minimumCoverage
        }
    }

    public static func analyzeBorders(
        _ image: StructuralAnalysisImage,
        limits requestedLimits: Limits? = nil
    ) throws -> [ObservedPageAnchor] {
        let limits = try requestedLimits ?? Limits()
        guard image.width > 0, image.height > 0, image.bytesPerRow >= image.width else {
            throw Error.invalidImage
        }
        let (pixelCount, pixelOverflow) = image.width.multipliedReportingOverflow(by: image.height)
        guard !pixelOverflow else { throw Error.invalidImage }
        guard pixelCount <= limits.maximumPixels else {
            throw Error.pixelLimitExceeded(actual: pixelCount, limit: limits.maximumPixels)
        }
        let (requiredBytes, byteOverflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !byteOverflow, requiredBytes <= image.pixels.count else { throw Error.invalidImage }

        return try image.pixels.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw Error.invalidImage
            }
            let isDark: (Int, Int) -> Bool = { x, y in
                base[y * image.bytesPerRow + x] <= limits.darknessCutoff
            }
            let minimumLength = max(4, Int(
                Double(min(image.width, image.height)) * limits.minimumLineFraction
            ))
            let horizontal = try horizontalRuns(
                width: image.width,
                height: image.height,
                minimumLength: minimumLength,
                minimumCoverage: limits.minimumCoverage,
                maximumRuns: limits.maximumLineRuns,
                isDark: isDark
            )
            return try borderCandidates(
                horizontal: horizontal,
                width: image.width,
                height: image.height,
                minimumLength: minimumLength,
                minimumCoverage: limits.minimumCoverage,
                maximumCandidates: limits.maximumCandidates,
                maximumPairChecks: limits.maximumPairChecks,
                isDark: isDark
            )
        }
    }

    private struct HorizontalRun {
        let y: Int
        let left: Int
        let right: Int
    }

    private static func horizontalRuns(
        width: Int,
        height: Int,
        minimumLength: Int,
        minimumCoverage: Double,
        maximumRuns: Int,
        isDark: (Int, Int) -> Bool
    ) throws -> [HorizontalRun] {
        var result: [HorizontalRun] = []
        for y in 0..<height {
            var x = 0
            while x < width {
                while x < width, !isDark(x, y) { x += 1 }
                guard x < width else { break }
                let start = x
                var dark = 0
                var lastDark = x
                var gap = 0
                while x < width {
                    if isDark(x, y) {
                        dark += 1
                        lastDark = x
                        gap = 0
                    } else {
                        gap += 1
                        if gap > 1 { break }
                    }
                    x += 1
                }
                let length = lastDark - start + 1
                if length >= minimumLength, Double(dark) / Double(length) >= minimumCoverage {
                    result.append(HorizontalRun(y: y, left: start, right: lastDark))
                    guard result.count <= maximumRuns else {
                        throw Error.featureLimitExceeded(limit: maximumRuns)
                    }
                }
                x = max(x, lastDark + 1)
            }
        }
        return result
    }

    private static func borderCandidates(
        horizontal: [HorizontalRun],
        width: Int,
        height: Int,
        minimumLength: Int,
        minimumCoverage: Double,
        maximumCandidates: Int,
        maximumPairChecks: Int,
        isDark: (Int, Int) -> Bool
    ) throws -> [ObservedPageAnchor] {
        let endpointTolerance = 2
        var rectangles: [(left: Int, top: Int, right: Int, bottom: Int)] = []
        var pairChecks = 0
        for topIndex in horizontal.indices {
            let top = horizontal[topIndex]
            for bottom in horizontal[(topIndex + 1)...] {
                pairChecks += 1
                guard pairChecks <= maximumPairChecks else {
                    throw Error.workLimitExceeded(limit: maximumPairChecks)
                }
                let rectHeight = bottom.y - top.y + 1
                guard rectHeight >= minimumLength,
                      abs(top.left - bottom.left) <= endpointTolerance,
                      abs(top.right - bottom.right) <= endpointTolerance else { continue }
                let left = (top.left + bottom.left) / 2
                let right = (top.right + bottom.right) / 2
                guard right > left,
                      verticalCoverage(x: left, top: top.y, bottom: bottom.y, width: width, isDark: isDark) >= minimumCoverage,
                      verticalCoverage(x: right, top: top.y, bottom: bottom.y, width: width, isDark: isDark) >= minimumCoverage else {
                    continue
                }
                let candidate = (left: left, top: top.y, right: right, bottom: bottom.y)
                if rectangles.contains(where: {
                    abs($0.left - candidate.left) <= endpointTolerance &&
                        abs($0.top - candidate.top) <= endpointTolerance &&
                        abs($0.right - candidate.right) <= endpointTolerance &&
                        abs($0.bottom - candidate.bottom) <= endpointTolerance
                }) { continue }
                rectangles.append(candidate)
                guard rectangles.count <= maximumCandidates else {
                    throw Error.featureLimitExceeded(limit: maximumCandidates)
                }
            }
        }
        return try rectangles.map { rectangle in
            ObservedPageAnchor(
                kind: .border,
                normalizedRect: try NormalizedRect(
                    x: Double(rectangle.left) / Double(width),
                    y: Double(rectangle.top) / Double(height),
                    width: Double(rectangle.right - rectangle.left + 1) / Double(width),
                    height: Double(rectangle.bottom - rectangle.top + 1) / Double(height)
                )
            )
        }
    }

    private static func verticalCoverage(
        x: Int,
        top: Int,
        bottom: Int,
        width: Int,
        isDark: (Int, Int) -> Bool
    ) -> Double {
        var covered = 0
        for y in top...bottom {
            let lower = max(0, x - 1)
            let upper = min(width - 1, x + 1)
            if (lower...upper).contains(where: { isDark($0, y) }) { covered += 1 }
        }
        return Double(covered) / Double(bottom - top + 1)
    }
}
