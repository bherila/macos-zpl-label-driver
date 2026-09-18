import XCTest
@testable import LabelCore

final class ZPLPreparedLabelEncoderTests: XCTestCase {
    func testSingleProductionEnvelopeCombinesTypedControlsAndGraphics() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let controls = try profile.resolveControls(job: .init(printSpeedIps: 3))
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0xA5])
        let text = String(decoding: try ZPLPreparedLabelEncoder().encode(bitmap: bitmap, controls: controls), as: UTF8.self)
        XCTAssertEqual(text, "^XA\n^MMT\n^PR3\n^FO0,0^GFA,1,1,1,A5^FS\n^XZ\n")
        XCTAssertEqual(text.components(separatedBy: "^XA").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "^XZ").count - 1, 1)
        for command in ["^PQ", "^JU", "~SD", "^MD", "^LL", "^PW", "~DG"] { XCTAssertFalse(text.contains(command)) }
    }
    func testEnvelopePreflightsTotalLimit() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let controls = try profile.resolveControls(job: .init())
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0])
        XCTAssertThrowsError(try ZPLPreparedLabelEncoder(maxOutputBytes: 12).encode(bitmap: bitmap, controls: controls))
    }

    func testPreparedLabelBindsBytesAndProfileSnapshotForDelivery() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 23)
        let bitmap = try MonochromeBitmap(width: 8, height: 1, bytes: [0x80])
        let prepared = try ZPLPreparedLabelEncoder().prepare(
            bitmap: bitmap,
            profile: profile,
            job: .init(printSpeedIps: 3)
        )
        XCTAssertEqual(prepared.profileSnapshot, JobProfileSnapshot(profile: profile))
        XCTAssertEqual(
            prepared.resolvedControls,
            try profile.resolveControls(job: .init(printSpeedIps: 3))
        )
        XCTAssertEqual(String(decoding: prepared.bytes, as: UTF8.self), "^XA\n^MMT\n^PR3\n^FO0,0^GFA,1,1,1,80^FS\n^XZ\n")

        let tracker = try DeliveryTracker(preparedLabel: prepared)
        XCTAssertEqual(tracker.receipt.expectedBytes, prepared.bytes.count)
        XCTAssertEqual(tracker.receipt.profileSnapshot, prepared.profileSnapshot)
    }

    func testPreparedJobPreservesResolvedOrderAndExactCount() throws {
        let profile = try PrinterProfile.gc420dUSBReference(revision: 23)
        let encoder = try ZPLPreparedLabelEncoder()
        let first = try encoder.prepare(
            bitmap: MonochromeBitmap(width: 8, height: 1, bytes: [0x80]),
            profile: profile
        )
        let second = try encoder.prepare(
            bitmap: MonochromeBitmap(width: 8, height: 1, bytes: [0x40]),
            profile: profile
        )
        let outputs = [
            ResolvedOutputLabel(sourcePage: 2, regionID: "top"),
            ResolvedOutputLabel(sourcePage: 1, regionID: "bottom"),
        ]
        let job = try PreparedJobPayload(
            labels: [
                PreparedOutputLabel(output: outputs[0], prepared: first),
                PreparedOutputLabel(output: outputs[1], prepared: second),
            ],
            expectedOutputLabels: outputs
        )
        XCTAssertEqual(job.bytes, first.bytes + second.bytes)
        XCTAssertEqual(job.labelCount, 2)
        XCTAssertEqual(job.outputLabels, outputs)
        XCTAssertEqual(job.profileSnapshot, JobProfileSnapshot(profile: profile))
        XCTAssertEqual(job.resolvedControls, first.resolvedControls)
    }

    func testPreparedJobRejectsMissingExtraAndEmptyLabels() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let output = ResolvedOutputLabel(sourcePage: 1, regionID: "label")
        let label = PreparedLabel(
            bytes: Data([1]), profileSnapshot: JobProfileSnapshot(profile: profile),
            resolvedControls: try profile.resolveControls(job: .init())
        )
        let item = PreparedOutputLabel(output: output, prepared: label)
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [item], expectedOutputLabels: [output, output]
        )) {
            XCTAssertEqual($0 as? PreparedJobPayload.Error, .invalidLabelCount)
        }
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [item, item], expectedOutputLabels: [output]
        )) {
            XCTAssertEqual($0 as? PreparedJobPayload.Error, .invalidLabelCount)
        }
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [PreparedOutputLabel(
                output: output,
                prepared: PreparedLabel(
                    bytes: Data(), profileSnapshot: JobProfileSnapshot(profile: profile),
                    resolvedControls: try profile.resolveControls(job: .init())
                )
            )],
            expectedOutputLabels: [output]
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .emptyLabel) }
    }

    func testPreparedJobRejectsWrongOrderMixedProfilesAndControls() throws {
        let outputA = ResolvedOutputLabel(sourcePage: 1, regionID: "a")
        let outputB = ResolvedOutputLabel(sourcePage: 1, regionID: "b")
        let profile1 = try PrinterProfile.gc420dUSBReference(revision: 1)
        let profile2 = try PrinterProfile.gc420dUSBReference(revision: 2)
        let first = PreparedLabel(
            bytes: Data([1]),
            profileSnapshot: JobProfileSnapshot(profile: profile1),
            resolvedControls: try profile1.resolveControls(job: .init(printSpeedIps: 2))
        )
        let second = PreparedLabel(
            bytes: Data([2]),
            profileSnapshot: JobProfileSnapshot(profile: profile2),
            resolvedControls: try profile2.resolveControls(job: .init(printSpeedIps: 2))
        )
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [
                PreparedOutputLabel(output: outputA, prepared: first),
                PreparedOutputLabel(output: outputB, prepared: second),
            ], expectedOutputLabels: [outputA, outputB]
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .profileMismatch) }

        let changedControls = PreparedLabel(
            bytes: Data([2]), profileSnapshot: first.profileSnapshot,
            resolvedControls: try profile1.resolveControls(job: .init(printSpeedIps: 3))
        )
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [
                PreparedOutputLabel(output: outputA, prepared: first),
                PreparedOutputLabel(output: outputB, prepared: changedControls),
            ], expectedOutputLabels: [outputA, outputB]
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .controlsMismatch) }

        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [
                PreparedOutputLabel(output: outputB, prepared: first),
                PreparedOutputLabel(output: outputA, prepared: first),
            ], expectedOutputLabels: [outputA, outputB]
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .outputOrderMismatch) }
    }

    func testPreparedJobPreflightsAggregateLimit() throws {
        let profile = try PrinterProfile.gc420dUSBReference()
        let snapshot = JobProfileSnapshot(profile: profile)
        let controls = try profile.resolveControls(job: .init())
        let first = PreparedLabel(
            bytes: Data([1, 2]), profileSnapshot: snapshot, resolvedControls: controls
        )
        let second = PreparedLabel(
            bytes: Data([3, 4]), profileSnapshot: snapshot, resolvedControls: controls
        )
        let outputA = ResolvedOutputLabel(sourcePage: 1, regionID: "a")
        let outputB = ResolvedOutputLabel(sourcePage: 1, regionID: "b")
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [
                PreparedOutputLabel(output: outputA, prepared: first),
                PreparedOutputLabel(output: outputB, prepared: second),
            ], expectedOutputLabels: [outputA, outputB], maximumBytes: 3
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .outputLimit) }
    }
}
