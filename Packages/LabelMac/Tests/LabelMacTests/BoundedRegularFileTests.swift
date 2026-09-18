import Darwin
import Foundation
import XCTest
@testable import LabelMac

final class BoundedRegularFileTests: XCTestCase {
    func testReadsExactLimitAndRejectsLargerFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BoundedRegularFile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "input.bin")
        try Data([1, 2, 3, 4]).write(to: file)

        XCTAssertEqual(try BoundedRegularFile.read(file, maximumBytes: 4), Data([1, 2, 3, 4]))
        XCTAssertThrowsError(try BoundedRegularFile.read(file, maximumBytes: 3)) {
            XCTAssertEqual($0 as? BoundedRegularFile.Error, .tooLarge)
        }
        XCTAssertThrowsError(try BoundedRegularFile.read(file, maximumBytes: Int.max)) {
            XCTAssertEqual($0 as? BoundedRegularFile.Error, .invalidLimit)
        }
    }

    func testRejectsFinalComponentSymbolicLinkAndNonRegularFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BoundedRegularFileType-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "target.bin")
        let link = directory.appending(path: "link.bin")
        try Data([1]).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try BoundedRegularFile.read(link, maximumBytes: 1)) {
            XCTAssertEqual($0 as? BoundedRegularFile.Error, .cannotOpen)
        }
        XCTAssertThrowsError(try BoundedRegularFile.read(directory, maximumBytes: 1)) {
            XCTAssertEqual($0 as? BoundedRegularFile.Error, .notRegular)
        }
    }

    func testRejectsHardLinkedPrivateArtifact() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BoundedRegularFileLinks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.bin")
        let second = directory.appending(path: "second.bin")
        try Data([1]).write(to: first)
        try FileManager.default.linkItem(at: first, to: second)

        XCTAssertThrowsError(try BoundedRegularFile.read(
            first,
            maximumBytes: 1,
            requireCurrentUserOwner: true,
            requireSingleLink: true
        )) {
            XCTAssertEqual($0 as? BoundedRegularFile.Error, .unexpectedLinkCount)
        }
    }

    func testFIFONamesAreRejectedWithinHardDeadlineWithAndWithoutWriter() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "BoundedRegularFileFIFO-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in [
            "input.pdf", "ticket.json", "state.json", "prepared.zpl",
            "workflow.json", "profile.json", "queue.json", "active.json",
        ] {
            let fifo = directory.appending(path: name)
            XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
            XCTAssertEqual(try runBoundedReadProbe(fifo), 65, name)
            try FileManager.default.removeItem(at: fifo)
        }

        let fifoWithWriter = directory.appending(path: "with-writer")
        XCTAssertEqual(mkfifo(fifoWithWriter.path, 0o600), 0)
        let writer = Darwin.open(fifoWithWriter.path, O_RDWR | O_NONBLOCK | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(writer, 0)
        defer { if writer >= 0 { close(writer) } }
        XCTAssertEqual(try runBoundedReadProbe(fifoWithWriter), 65)
    }

    private func runBoundedReadProbe(_ url: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent().appending(path: "label-driver-diagnostics")
        process.arguments = ["--bounded-read", url.path, "1024"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = XCTestExpectation(description: "bounded read probe exits")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        let result = XCTWaiter.wait(for: [exited], timeout: 2)
        if result != .completed, process.isRunning { process.terminate() }
        XCTAssertEqual(result, .completed, "prospective regular-file open blocked")
        process.waitUntilExit()
        return process.terminationStatus
    }
}
