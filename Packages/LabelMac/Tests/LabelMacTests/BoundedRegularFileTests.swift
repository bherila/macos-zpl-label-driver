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
}
