import Foundation
import XCTest
import LabelCore
@testable import LabelMac

final class OfflineRenderWorkerTests: XCTestCase {
    private func repositoryRoot() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root
    }

    private func workerExecutable() throws -> URL {
        let root = repositoryRoot()
        let candidates = [
            root.appending(path: "Packages/LabelMac/.build/debug/label-render-worker"),
            root.appending(path: "Packages/LabelMac/.build/release/label-render-worker"),
            root.appending(path: "Packages/LabelMac/.build/arm64-apple-macosx/debug/label-render-worker"),
            root.appending(path: "Packages/LabelMac/.build/arm64-apple-macosx/release/label-render-worker"),
        ]
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let matchingCandidates = candidates.filter { $0.path.contains("/" + configuration + "/") }
        guard let executable = matchingCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw TestError.unavailable
        }
        return executable
    }

    private var ticket: Data {
        Data("""
        { "schemaVersion": 1, "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1 },
          "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 } }
        """.utf8)
    }

    func testMarginTicketAdmissionAndRealWorkerMatchOriginalSourceRendering() throws {
        let source = try Data(contentsOf: repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf"))
        let box = try QuartzPDFRenderer.pageBox(originalPDF: source, pageNumber: 1)
        let rect = box.sourceRect(for: try NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: ticket) as? [String: Any])
        root["schemaVersion"] = 3
        root["extraction"] = ["region": ["x": 0, "y": 0, "width": 1, "height": 1],
            "expectedSourceRect": ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height],
            "rotation": 0] as [String: Any]
        root["outputMargins"] = ["left": 1, "top": 2, "right": 3, "bottom": 1]
        let data = try JSONSerialization.data(withJSONObject: root)
        let parsed = try OfflineConversionTicket(jsonData: data)
        XCTAssertEqual(parsed.outputMargins, try OutputMargins(left: 1, top: 2, right: 3, bottom: 1))
        let direct = try OfflineConversion.prepare(originalPDF: source, ticket: parsed)
        let worker = try OfflineRenderWorkerProcess.run(originalPDF: source, ticketJSON: data,
            workerExecutable: workerExecutable(), deadlineSeconds: 5)
        XCTAssertEqual(worker.previewPBM, direct.previewPBM)
        XCTAssertEqual(worker.zpl, direct.zpl)
        let region = try NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        let profile = try WorkflowProfile(schemaVersion: 3, id: "margin-worker", revision: 1,
            outputStockID: "test-stock", outputStock: parsed.physicalSize, outputMargins: parsed.outputMargins,
            pageRules: [WorkflowPageRule(sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: box.effectivePhysicalSize()),
                disposition: .extract([ExtractionRegion(id: "whole", normalizedRect: region,
                    rotation: .degrees0, outputOrder: 0)]))])
        let label = try XCTUnwrap(ExtractionPlanner.plan(sourcePages: [box], profile: profile).outputLabels.first)
        let canvas = try DotCanvas(physicalSize: parsed.physicalSize, resolution: parsed.resolution)
        let conversion = MonochromeConversion.textAndBarcodeThreshold(cutoff: 128)
        let planned = try QuartzPlannedExtraction.prepare(originalPDF: source, label: label,
            canvas: canvas, conversion: conversion)
        let plannedWorker = try OfflineExtractionWorker.render(originalPDF: source, label: label,
            canvas: canvas, conversion: conversion, workerExecutable: workerExecutable(), deadlineSeconds: 5)
        XCTAssertEqual(planned.bitmap, direct.bitmap)
        XCTAssertEqual(plannedWorker, direct.bitmap)
        for y in 0..<10 {
            for x in 0..<10 where x < 1 || x >= 7 || y < 2 || y >= 9 {
                XCTAssertEqual(direct.bitmap.bytes[y * 2 + x / 8] & UInt8(0x80 >> (x % 8)), 0)
            }
        }
        for invalid: Any in [NSNull(), ["left": -1, "top": 2, "right": 3, "bottom": 1],
            ["left": true, "top": 2, "right": 3, "bottom": 1],
            ["left": 1, "top": 2, "right": 3],
            ["left": 1, "top": 2, "right": 3, "bottom": 1, "extra": 0],
            ["left": 7, "top": 2, "right": 3, "bottom": 1]] {
            var changed = root; changed["outputMargins"] = invalid
            XCTAssertThrowsError(try OfflineConversionTicket(jsonData: JSONSerialization.data(withJSONObject: changed)))
        }
        var missing = root; missing.removeValue(forKey: "outputMargins")
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: JSONSerialization.data(withJSONObject: missing)))
        root["schemaVersion"] = 2
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: JSONSerialization.data(withJSONObject: root)))
        XCTAssertEqual(try OfflineConversionTicket(jsonData: ticket).outputMargins, .zero)
    }

    func testWorkerPreparesBoundedArtifactsThroughPrivateProtocol() throws {
        let source = try Data(contentsOf: repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf"))
        let output = try OfflineRenderWorkerProcess.run(
            originalPDF: source,
            ticketJSON: ticket,
            workerExecutable: try workerExecutable(),
            deadlineSeconds: 5
        )

        XCTAssertEqual(output.result.schemaVersion, 1)
        XCTAssertEqual(output.result.widthDots, 10)
        XCTAssertEqual(output.result.heightDots, 10)
        XCTAssertEqual(output.result.zplBytes, output.zpl.count)
        XCTAssertEqual(output.result.previewBytes, output.previewPBM.count)
        let resident = try XCTUnwrap(output.result.workerMaximumResidentBytes)
        XCTAssertGreaterThan(resident, 0)
        XCTAssertLessThanOrEqual(resident, OfflineRenderWorkerResult.maximumReportedResidentBytes)
        XCTAssertTrue(String(decoding: output.zpl, as: UTF8.self).hasPrefix("^XA\n"))
        XCTAssertTrue(String(decoding: output.previewPBM.prefix(2), as: UTF8.self) == "P4")
    }

    func testWorkerMemoryMetadataRejectsInvalidValuesBeforeReturningPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        for value in [0, -1, OfflineRenderWorkerResult.maximumReportedResidentBytes + 1] {
            let worker = directory.appendingPathComponent("inert-worker-\(value)")
            let metadata = "{\"schemaVersion\":1,\"widthDots\":1,\"heightDots\":1,\"zplBytes\":0,\"previewBytes\":0,\"workerMaximumResidentBytes\":\(value)}"
            let script = "#!/bin/sh\numask 077\nprintf '%s' '" + metadata + "' > \"$2/result.json\"\n: > \"$2/prepared.zpl\"\n: > \"$2/preview.pbm\"\n"
            try Data(script.utf8).write(to: worker)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: worker.path)
            XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(originalPDF: Data([1]),
                ticketJSON: ticket, workerExecutable: worker, deadlineSeconds: 5)) {
                XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .invalidResult)
            }
        }
        let legacy = try JSONDecoder().decode(OfflineRenderWorkerResult.self,
            from: Data("{\"schemaVersion\":1,\"widthDots\":1,\"heightDots\":1,\"zplBytes\":0,\"previewBytes\":0}".utf8))
        XCTAssertNil(legacy.workerMaximumResidentBytes)
    }

    func testWorkerIntegerFieldsRejectFractionalTokensBeforeReturningArtifacts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let fields = ["schemaVersion", "widthDots", "heightDots", "zplBytes", "previewBytes", "workerMaximumResidentBytes"]
        for invalidField in fields {
            let worker = directory.appendingPathComponent("inert-worker-" + invalidField)
            let metadata = "{" + fields.map {
                "\"" + $0 + "\":" + ($0 == invalidField ? "1.00000000000000000000000000000000001" : "1")
            }.joined(separator: ",") + "}"
            let script = "#!/bin/sh\numask 077\nprintf '%s' '" + metadata + "' > \"$2/result.json\"\nprintf x > \"$2/prepared.zpl\"\nprintf x > \"$2/preview.pbm\"\n"
            try Data(script.utf8).write(to: worker)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: worker.path)
            XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(originalPDF: Data([1]),
                ticketJSON: ticket, workerExecutable: worker, deadlineSeconds: 5)) {
                XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .invalidResult)
            }
        }
    }

    func testParentRejectsWorkerBitmapAndZPLSubstitutionDespiteMatchingByteCounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let black = try MonochromeBitmap(width: 8, height: 1, bytes: [0x80])
        let narrow = try MonochromeBitmap(width: 1, height: 1, bytes: [0x80])
        let zpl = try ZPLGraphicEncoder().diagnosticFormat(black)
        let good = black.pbmData()
        var white = good; white[white.count - 1] = 0
        var padding = narrow.pbmData(); padding[padding.count - 1] = 0x81
        let cases: [(Int, Data, Data, Bool)] = [
            (8, good, zpl, true), (8, white, zpl, false),
            (9, good, zpl, false), (1, padding, try ZPLGraphicEncoder().diagnosticFormat(narrow), false)]
        for (index, value) in cases.enumerated() {
            let (width, preview, commands, valid) = value
            // Match the request to metadata so each malformed artifact fails
            // on bitmap binding even when request-canvas binding is enabled.
            let matchingTicket = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "pageNumber": 1,
                "physicalSize": ["widthMillimeters": width, "heightMillimeters": 1],
                "resolution": ["xDotsPerMillimeter": 1, "yDotsPerMillimeter": 1],
                "conversion": ["mode": "textAndBarcodeThreshold", "cutoff": 128]])
            let previewFile = directory.appendingPathComponent("fixture-preview-\(index)")
            let zplFile = directory.appendingPathComponent("fixture-zpl-\(index)")
            try preview.write(to: previewFile); try commands.write(to: zplFile)
            let result = OfflineRenderWorkerResult(widthDots: width, heightDots: 1,
                zplBytes: commands.count, previewBytes: preview.count)
            let metadata = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
            func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let script = "#!/bin/sh\numask 077\nprintf '%s' '" + metadata + "' > \"$2/result.json\"\ncp "
                + quoted(zplFile.path) + " \"$2/prepared.zpl\"\ncp " + quoted(previewFile.path) + " \"$2/preview.pbm\"\n"
            let worker = directory.appendingPathComponent("inert-worker-\(index)")
            try Data(script.utf8).write(to: worker)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: worker.path)
            if valid {
                let output = try OfflineRenderWorkerProcess.run(originalPDF: Data([1]),
                    ticketJSON: matchingTicket, workerExecutable: worker, deadlineSeconds: 5)
                XCTAssertEqual(output.previewPBM, good); XCTAssertEqual(output.zpl, zpl)
            } else {
                XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(originalPDF: Data([1]),
                    ticketJSON: matchingTicket, workerExecutable: worker, deadlineSeconds: 5)) {
                    XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .invalidResult)
                }
            }
        }
    }

    func testParentBindsCanonicalWorkerOutputToRoundedRequestCanvas() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0x80])
        let preview = bitmap.pbmData(), zpl = try ZPLGraphicEncoder().diagnosticFormat(bitmap)
        let previewFile = directory.appendingPathComponent("fixture-preview")
        let zplFile = directory.appendingPathComponent("fixture-zpl")
        try preview.write(to: previewFile); try zpl.write(to: zplFile)
        let metadata = String(decoding: try JSONEncoder().encode(OfflineRenderWorkerResult(
            widthDots: 8, heightDots: 1, zplBytes: zpl.count, previewBytes: preview.count)), as: UTF8.self)
        func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
        let script = "#!/bin/sh\numask 077\nprintf '%s' '" + metadata + "' > \"$2/result.json\"\ncp "
            + quoted(zplFile.path) + " \"$2/prepared.zpl\"\ncp " + quoted(previewFile.path) + " \"$2/preview.pbm\"\n"
        let worker = directory.appendingPathComponent("inert-worker")
        try Data(script.utf8).write(to: worker)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: worker.path)
        let cases: [(Double, Double, Double, Double, Bool)] = [
            (8, 1, 1, 1, true), (8.49, 1.49, 1, 1, true), (4, 1, 2, 1, true),
            (8.5, 1, 1, 1, false), (8, 2, 1, 1, false), (4, 1, 2, 2, false)]
        for (width, height, xResolution, yResolution, valid) in cases {
            let requested = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "pageNumber": 1,
                "physicalSize": ["widthMillimeters": width, "heightMillimeters": height],
                "resolution": ["xDotsPerMillimeter": xResolution, "yDotsPerMillimeter": yResolution],
                "conversion": ["mode": "textAndBarcodeThreshold", "cutoff": 128]])
            if valid {
                let output = try OfflineRenderWorkerProcess.run(originalPDF: Data([1]),
                    ticketJSON: requested, workerExecutable: worker, deadlineSeconds: 5)
                XCTAssertEqual(output.previewPBM, preview); XCTAssertEqual(output.zpl, zpl)
            } else {
                XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(originalPDF: Data([1]),
                    ticketJSON: requested, workerExecutable: worker, deadlineSeconds: 5)) {
                    XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .invalidResult)
                }
            }
        }
    }

    func testDeadlineTerminatesOwnedWorkerWithoutReturningArtifacts() throws {
        let start = ContinuousClock.now
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(
            originalPDF: Data("%PDF".utf8),
            ticketJSON: ticket,
            workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"),
            deadlineSeconds: 0.05
        )) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .timedOut)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
    }

    func testCancellationTerminatesOwnedWorkerWithoutReturningArtifacts() throws {
        let cancellation = OfflineRenderWorkerCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) {
            cancellation.cancel()
        }
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(
            originalPDF: Data("%PDF".utf8),
            ticketJSON: ticket,
            workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"),
            deadlineSeconds: 5,
            cancellation: cancellation
        )) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .cancelled)
        }
    }

    func testAlreadyCancelledRequestIsRejectedBeforeWorkerAdmission() throws {
        let cancellation = OfflineRenderWorkerCancellation()
        cancellation.cancel()
        // Even an unavailable executable is never inspected/admitted for an
        // already cancelled, otherwise bounded request.
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(
            originalPDF: Data("%PDF".utf8),
            ticketJSON: ticket,
            workerExecutable: URL(fileURLWithPath: "/nonexistent-label-render-worker"),
            cancellation: cancellation
        )) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .cancelled)
        }
    }

    func testMalformedInputProducesControlledWorkerFailure() throws {
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(
            originalPDF: Data("not a PDF".utf8),
            ticketJSON: ticket,
            workerExecutable: try workerExecutable(),
            deadlineSeconds: 5
        )) {
            XCTAssertEqual(
                $0 as? OfflineRenderWorkerProcess.Error,
                .jobRejected(code: .inputUnsupported)
            )
        }
    }

    func testWorkerReturnsSanitizedTicketFailureCode() throws {
        let source = try Data(contentsOf: repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf"))
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(
            originalPDF: source,
            ticketJSON: Data("{}".utf8),
            workerExecutable: try workerExecutable(),
            deadlineSeconds: 5
        )) {
            XCTAssertEqual(
                $0 as? OfflineRenderWorkerProcess.Error,
                .jobRejected(code: .jobTicketInvalid)
            )
        }
    }

    func testEncryptedFixtureAndTruncatedSourceRemainDistinctThroughWorker() throws {
        let encrypted = try Data(contentsOf: repositoryRoot().appending(path: "Fixtures/generated/encrypted-input.pdf"))
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(
            originalPDF: encrypted,
            ticketJSON: ticket,
            workerExecutable: try workerExecutable(),
            deadlineSeconds: 5
        )) {
            XCTAssertEqual(
                $0 as? OfflineRenderWorkerProcess.Error,
                .jobRejected(code: .inputEncrypted)
            )
        }

        let source = try Data(contentsOf: repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf"))
        let truncated = Data(source.prefix(source.count / 2))
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(
            originalPDF: truncated,
            ticketJSON: ticket,
            workerExecutable: try workerExecutable(),
            deadlineSeconds: 5
        )) {
            XCTAssertEqual(
                $0 as? OfflineRenderWorkerProcess.Error,
                .jobRejected(code: .inputUnsupported)
            )
        }
    }

    func testFailureClassificationKeepsEncryptedAndMalformedDistinct() {
        XCTAssertEqual(
            OfflineRenderWorkerProcess.classifyFailure(QuartzPDFRenderer.Error.encryptedPDF).code,
            .inputEncrypted
        )
        XCTAssertEqual(
            OfflineRenderWorkerProcess.classifyFailure(QuartzPDFRenderer.Error.malformedOrUnsupportedPDF).code,
            .inputUnsupported
        )
    }

    private enum TestError: Error { case unavailable }

    private func extractionTicket(version: Int = 2, rotation: Int = 90, expectedWidth: Int = 288) -> Data {
        Data("""
        { "schemaVersion": \(version), "pageNumber": 1,
          "physicalSize": { "widthMillimeters": 10, "heightMillimeters": 10 },
          "resolution": { "xDotsPerMillimeter": 10, "yDotsPerMillimeter": 10 },
          "conversion": { "mode": "textAndBarcodeThreshold", "cutoff": 128 },
          "extraction": {
            "region": { "x": 0, "y": 0, "width": 1, "height": 0.5 },
            "expectedSourceRect": { "x": 0, "y": 216, "width": \(expectedWidth), "height": 216 },
            "rotation": \(rotation) } }
        """.utf8)
    }

    func testExtractionWorkerMatchesOriginalRegionAndRotation() throws {
        let source = try Data(contentsOf: repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf"))
        let data = extractionTicket()
        let decoded = try OfflineConversionTicket(jsonData: data)
        let direct = try OfflineConversion.prepare(originalPDF: source, ticket: decoded)
        let output = try OfflineRenderWorkerProcess.run(originalPDF: source, ticketJSON: data,
            workerExecutable: try workerExecutable(), deadlineSeconds: 5)
        XCTAssertEqual(output.previewPBM, direct.previewPBM)
        XCTAssertEqual(output.zpl, direct.zpl)
        let unrotated = try OfflineConversion.prepare(originalPDF: source,
            ticket: OfflineConversionTicket(jsonData: extractionTicket(rotation: 0)))
        XCTAssertNotEqual(output.previewPBM, unrotated.previewPBM)
    }

    func testExtractionContractRejectsVersionOneAndInvalidRotation() throws {
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: extractionTicket(version: 1)))
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData: extractionTicket(rotation: 45)))
        XCTAssertThrowsError(try OfflineConversionTicket(jsonData:
            Data(String(decoding: ticket, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2").utf8)))
    }

    func testExtractionWorkerRejectsChangedSourceGeometry() throws {
        let source = try Data(contentsOf: repositoryRoot().appending(path: "Fixtures/generated/native-vector.pdf"))
        XCTAssertThrowsError(try OfflineRenderWorkerProcess.run(originalPDF: source,
            ticketJSON: extractionTicket(expectedWidth: 287),
            workerExecutable: try workerExecutable(), deadlineSeconds: 5)) {
            XCTAssertEqual($0 as? OfflineRenderWorkerProcess.Error, .jobRejected(code: .geometryInvalid))
        }
    }
}
