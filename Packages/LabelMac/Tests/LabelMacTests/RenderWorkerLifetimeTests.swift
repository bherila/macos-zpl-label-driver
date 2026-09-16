import Darwin
import Foundation
import XCTest
@testable import LabelMac

final class RenderWorkerLifetimeTests: XCTestCase {
    private func base() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "WorkerRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func candidate(_ base: URL, suffix: String = "ABC123") throws -> URL {
        let url = base.appending(path: RenderWorkerScratch.prefix + suffix)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return url
    }

    func testDeadParentRecoveryWaitsForActualWriterLockThenRemovesOwnedFiles() throws {
        let root = try base()
        let directory = try candidate(root)
        let ownership = try RenderWorkerScratch.install(in: directory, parentPID: Int32.max)
        try OfflineRenderWorkerProcess.writePrivate(Data("synthetic source".utf8), to: directory.appending(path: "input.pdf"))
        let blocked = try RenderWorkerScratch.recover(in: root)
        XCTAssertEqual(blocked.active, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        close(ownership.descriptor)
        let recovered = try RenderWorkerScratch.recover(in: root)
        XCTAssertEqual(recovered.removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLiveParentAndUnmarkedUnknownArtifactsAreNeverAdopted() throws {
        let root = try base()
        let live = try candidate(root)
        let ownership = try RenderWorkerScratch.install(in: live)
        close(ownership.descriptor)
        _ = try candidate(root, suffix: "EMPTY1")
        let unknown = try candidate(root, suffix: "EXTRA1")
        let extraOwnership = try RenderWorkerScratch.install(in: unknown, parentPID: Int32.max)
        close(extraOwnership.descriptor)
        try OfflineRenderWorkerProcess.writePrivate(Data("retain".utf8), to: unknown.appending(path: "unknown.bin"))
        let report = try RenderWorkerScratch.recover(in: root)
        XCTAssertEqual(report.active, 1)
        XCTAssertEqual(report.requiresReview, 2)
        XCTAssertEqual(report.removed, 0)
    }

    func testReplacedDirectoryAndNonregularMarkerRemainWithoutBlocking() throws {
        let root = try base()
        let original = try candidate(root)
        let ownership = try RenderWorkerScratch.install(in: original, parentPID: Int32.max)
        close(ownership.descriptor)
        let moved = root.appending(path: "held-original")
        try FileManager.default.moveItem(at: original, to: moved)
        let replacement = try candidate(root)
        try FileManager.default.copyItem(at: moved.appending(path: RenderWorkerScratch.markerName),
                                        to: replacement.appending(path: RenderWorkerScratch.markerName))
        let fifo = try candidate(root, suffix: "FIFO01")
        XCTAssertEqual(mkfifo(fifo.appending(path: RenderWorkerScratch.markerName).path, 0o600), 0)
        let start = ContinuousClock.now
        let report = try RenderWorkerScratch.recover(in: root)
        XCTAssertEqual(report.requiresReview, 2)
        XCTAssertEqual(report.removed, 0)
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
    }

    func testNonceBindingAndRecoveryScanLimitAreExplicit() throws {
        let root = try base()
        let directory = try candidate(root)
        let ownership = try RenderWorkerScratch.install(in: directory)
        defer { close(ownership.descriptor) }
        XCTAssertThrowsError(try RenderWorkerScratch.hold(in: directory, parentPID: getpid(), token: "wrong"))
        let held = try RenderWorkerScratch.hold(in: directory, parentPID: getpid(), token: ownership.token)
        close(held)
        _ = try candidate(root, suffix: "SECOND")
        XCTAssertTrue(try RenderWorkerScratch.recover(in: root, maximumCandidates: 1).truncated)
    }

    func testNativeChildIndependentDeadlineAndParentDeath() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let fixture = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-worker-supervision-fixture")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: fixture.path))
        let recoveryBase = try base()
        let scratch = try candidate(recoveryBase)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [root.appending(path: "scripts/test-worker-supervision.py").path,
                             fixture.path, scratch.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let recovered = try RenderWorkerScratch.recover(in: recoveryBase)
        XCTAssertEqual(recovered.removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.path))
    }
}
