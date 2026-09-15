import Foundation
import XCTest
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
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
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
        XCTAssertTrue(String(decoding: output.zpl, as: UTF8.self).hasPrefix("^XA\n"))
        XCTAssertTrue(String(decoding: output.previewPBM.prefix(2), as: UTF8.self) == "P4")
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
}
