import CryptoKit
import Foundation
import LabelCore

/// Analysis-only facts from original PDF bytes, using the same bounded child
/// admission and cancellation mechanism as final raster preparation.
public enum OfflineLayoutWorker {
    static let maximumOutputBytes = 2 * 1024 * 1024
    static let maximumAnchors = 4_096
    static let outputFilename = "layout.json"

    struct Request: Codable {
        let schemaVersion: Int
        let structuralPages: [Int]
        let maximumPages: Int?
        let analyzeAllPages: Bool?

        init(schemaVersion: Int, structuralPages: [Int], maximumPages: Int? = nil,
             analyzeAllPages: Bool? = nil) {
            self.schemaVersion = schemaVersion
            self.structuralPages = structuralPages
            self.maximumPages = maximumPages
            self.analyzeAllPages = analyzeAllPages
        }

        var pageLimit: Int { maximumPages ?? ResolvedJobTicket.maximumSourcePages }

        func requestedPages(count: Int) -> Set<Int> {
            analyzeAllPages == true ? Set(1...count) : Set(structuralPages)
        }

        func validate() throws {
            guard schemaVersion == 1,
                  (1...ResolvedJobTicket.maximumSourcePages).contains(pageLimit),
                  analyzeAllPages != true || structuralPages.isEmpty,
                  structuralPages.count <= ResolvedJobTicket.maximumSourcePages,
                  structuralPages == Array(Set(structuralPages)).sorted(),
                  structuralPages.allSatisfy({ (1...pageLimit).contains($0) }) else {
                throw OfflineConversionTicket.TicketError.malformedJSON
            }
        }
    }

    struct Result: Codable {
        let schemaVersion: Int
        let sourceSHA256: String
        let pages: [Page]
    }

    struct Page: Codable {
        let originX: Double
        let originY: Double
        let width: Double
        let height: Double
        let rotation: Int
        let userUnit: Double
        let anchors: [Anchor]?

        init(_ page: AnalyzedSourcePage) {
            let box = page.pageBox
            originX = box.originX; originY = box.originY
            width = box.width; height = box.height
            rotation = box.rotationDegreesClockwise; userUnit = box.userUnit
            anchors = page.anchors?.map(Anchor.init)
        }

        func validated() throws -> AnalyzedSourcePage {
            _ = try PDFSourceRect.validated(x: originX, y: originY, width: width, height: height)
            let box = try PDFPageBox(originX: originX, originY: originY, width: width,
                                     height: height, rotationDegreesClockwise: rotation, userUnit: userUnit)
            _ = try box.effectivePhysicalSize()
            return try AnalyzedSourcePage(pageBox: box, anchors: anchors?.map { try $0.validated() })
        }
    }

    struct Anchor: Codable {
        let kind: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ anchor: ObservedPageAnchor) {
            kind = anchor.kind.rawValue
            let rect = anchor.normalizedRect
            x = rect.x; y = rect.y; width = rect.width; height = rect.height
        }

        func validated() throws -> ObservedPageAnchor {
            // This concrete analyzer supports borders only, not invented
            // barcode values or unqualified detector kinds.
            guard kind == StructuralAnchorKind.border.rawValue else {
                throw OfflineRenderWorkerProcess.Error.invalidResult
            }
            return ObservedPageAnchor(kind: .border,
                normalizedRect: try NormalizedRect(x: x, y: y, width: width, height: height))
        }
    }

    public static func analyze(
        originalPDF: Data, structuralPages: [Int], workerExecutable: URL,
        maximumSourcePages: Int = ResolvedJobTicket.maximumSourcePages,
        analyzeAllPages: Bool = false,
        deadlineSeconds: Double = OfflineRenderWorkerProcess.defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> [AnalyzedSourcePage] {
        let request = Request(schemaVersion: 1, structuralPages: structuralPages.sorted(),
                              maximumPages: maximumSourcePages, analyzeAllPages: analyzeAllPages)
        try request.validate()
        let ticket = try JSONEncoder().encode(request)
        return try OfflineRenderWorkerProcess.runJob(
            originalPDF: originalPDF, ticketJSON: ticket, workerExecutable: workerExecutable,
            operationFlag: "--analysis-directory", deadlineSeconds: deadlineSeconds,
            cancellation: cancellation
        ) { directory in
            let data = try OfflineRenderWorkerProcess.readPrivateRegularFile(
                directory.appending(path: outputFilename), maximumBytes: maximumOutputBytes
            )
            return try validate(data, originalPDF: originalPDF, request: request)
        }
    }

    static func validate(_ data: Data, originalPDF: Data, request: Request) throws -> [AnalyzedSourcePage] {
        do {
            guard data.count <= maximumOutputBytes else { throw OfflineRenderWorkerProcess.Error.outputLimitExceeded }
            try request.validate()
            let result = try JSONDecoder().decode(Result.self, from: data)
            guard result.schemaVersion == 1, result.sourceSHA256 == digest(originalPDF),
                  !result.pages.isEmpty, result.pages.count <= request.pageLimit,
                  request.structuralPages.allSatisfy({ $0 <= result.pages.count }) else {
                throw OfflineRenderWorkerProcess.Error.invalidResult
            }
            let requested = request.requestedPages(count: result.pages.count)
            var total = 0
            return try result.pages.enumerated().map { index, page in
                guard (page.anchors != nil) == requested.contains(index + 1),
                      page.anchors.map({ $0.count <= 256 }) ?? true else {
                    throw OfflineRenderWorkerProcess.Error.invalidResult
                }
                total += page.anchors?.count ?? 0
                guard total <= maximumAnchors else { throw OfflineRenderWorkerProcess.Error.outputLimitExceeded }
                return try page.validated()
            }
        } catch let error as OfflineRenderWorkerProcess.Error {
            throw error
        } catch {
            throw OfflineRenderWorkerProcess.Error.invalidResult
        }
    }

    static func digest(_ source: Data) -> String {
        SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
    }
}

extension OfflineRenderWorkerProcess {
    public static func performLayoutAnalysis(in directory: URL) throws {
        try validatePrivateScratchDirectory(directory)
        let source = try readPrivateRegularFile(directory.appending(path: inputFilename),
                                               maximumBytes: ResolvedJobTicket.maximumSourceBytes)
        let ticket = try readPrivateRegularFile(directory.appending(path: ticketFilename),
                                               maximumBytes: maximumTicketBytes)
        let request: OfflineLayoutWorker.Request
        do {
            request = try JSONDecoder().decode(OfflineLayoutWorker.Request.self, from: ticket)
            try request.validate()
        } catch {
            throw OfflineConversionTicket.TicketError.malformedJSON
        }
        let boxes = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source,
            maximumInputBytes: ResolvedJobTicket.maximumSourceBytes,
            maximumSourcePages: request.pageLimit)
        for page in request.structuralPages where page > boxes.count {
            throw QuartzPDFRenderer.Error.pageOutOfRange(requested: page, pageCount: boxes.count)
        }
        let requested = request.requestedPages(count: boxes.count)
        var total = 0
        let pages = try boxes.enumerated().map { index, box in
            let page = requested.contains(index + 1)
                ? try QuartzStructuralAnalyzer.analyzeBorders(originalPDF: source, pageNumber: index + 1,
                    maximumInputBytes: ResolvedJobTicket.maximumSourceBytes,
                    maximumSourcePages: request.pageLimit)
                : try AnalyzedSourcePage(pageBox: box, anchors: nil)
            total += page.anchors?.count ?? 0
            guard total <= OfflineLayoutWorker.maximumAnchors else { throw Error.outputLimitExceeded }
            return OfflineLayoutWorker.Page(page)
        }
        let result = OfflineLayoutWorker.Result(schemaVersion: 1,
            sourceSHA256: OfflineLayoutWorker.digest(source), pages: pages)
        let data = try JSONEncoder().encode(result)
        // Apply the same checked result contract before publishing any facts.
        _ = try OfflineLayoutWorker.validate(data, originalPDF: source, request: request)
        try writePrivate(data, to: directory.appending(path: OfflineLayoutWorker.outputFilename))
    }
}
