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
        let job = try PreparedJobPayload(labels: [first, second], expectedLabelCount: 2)
        XCTAssertEqual(job.bytes, first.bytes + second.bytes)
        XCTAssertEqual(job.labelCount, 2)
        XCTAssertEqual(job.profileSnapshot, JobProfileSnapshot(profile: profile))
    }

    func testPreparedJobRejectsMissingExtraAndEmptyLabels() throws {
        let snapshot = JobProfileSnapshot(profile: try .gc420dUSBReference())
        let label = PreparedLabel(bytes: Data([1]), profileSnapshot: snapshot)
        XCTAssertThrowsError(try PreparedJobPayload(labels: [label], expectedLabelCount: 2)) {
            XCTAssertEqual($0 as? PreparedJobPayload.Error, .invalidLabelCount)
        }
        XCTAssertThrowsError(try PreparedJobPayload(labels: [label, label], expectedLabelCount: 1)) {
            XCTAssertEqual($0 as? PreparedJobPayload.Error, .invalidLabelCount)
        }
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [PreparedLabel(bytes: Data(), profileSnapshot: snapshot)],
            expectedLabelCount: 1
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .emptyLabel) }
    }

    func testPreparedJobRejectsMixedProfileSnapshots() throws {
        let first = PreparedLabel(
            bytes: Data([1]),
            profileSnapshot: JobProfileSnapshot(profile: try .gc420dUSBReference(revision: 1))
        )
        let second = PreparedLabel(
            bytes: Data([2]),
            profileSnapshot: JobProfileSnapshot(profile: try .gc420dUSBReference(revision: 2))
        )
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [first, second], expectedLabelCount: 2
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .profileMismatch) }
    }

    func testPreparedJobPreflightsAggregateLimit() throws {
        let snapshot = JobProfileSnapshot(profile: try .gc420dUSBReference())
        let first = PreparedLabel(bytes: Data([1, 2]), profileSnapshot: snapshot)
        let second = PreparedLabel(bytes: Data([3, 4]), profileSnapshot: snapshot)
        XCTAssertThrowsError(try PreparedJobPayload(
            labels: [first, second], expectedLabelCount: 2, maximumBytes: 3
        )) { XCTAssertEqual($0 as? PreparedJobPayload.Error, .outputLimit) }
    }
}
