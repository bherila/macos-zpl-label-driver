import CryptoKit
import Darwin
import Foundation
import LabelCore

/// A private local store for immutable profile revisions and separately
/// confirmed unattended-use qualifications. Imported JSON is never itself a
/// qualification record.
public struct WorkflowProfileStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotCreateStore
        case cannotOpenStore
        case unsafeStoreDirectory
        case cannotRead
        case cannotWrite
        case profileConflict
        case profileIdentityMismatch
        case malformedQualification
        case qualificationMismatch
    }

    public let root: URL

    public init(root: URL) throws {
        self.root = root
        if mkdir(root.path, 0o700) != 0, errno != EEXIST { throw Error.cannotCreateStore }
        try withDirectories { _, _, _ in }
    }

    public func save(_ profile: WorkflowProfile) throws {
        let bytes = try WorkflowProfileJSON.encode(profile)
        try withDirectories { _, profiles, _ in
            try publishImmutable(bytes, named: Self.profileFileName(profile.id, profile.revision), in: profiles)
        }
    }

    public func load(profileID: String, revision: Int) throws -> WorkflowProfile {
        try withDirectories { _, profiles, _ in
            let bytes: Data
            do {
                bytes = try readRegular(
                    named: Self.profileFileName(profileID, revision),
                    in: profiles,
                    maximumBytes: WorkflowProfileJSON.maximumBytes
                )
            } catch POSIXReadError.notFound {
                throw Error.cannotRead
            }
            let profile = try WorkflowProfileJSON.decode(bytes)
            guard profile.id == profileID, profile.revision == revision else {
                throw Error.profileIdentityMismatch
            }
            return profile
        }
    }

    /// Persists local confirmation only after the exact immutable profile
    /// revision is present. The definition is never copied into this record.
    public func confirmForUnattendedUse(_ profile: WorkflowProfile) throws {
        let stored = try load(profileID: profile.id, revision: profile.revision)
        guard stored == profile else { throw Error.profileConflict }
        _ = try UnattendedWorkflowQualification(userConfirmed: profile)
        let digest = Self.digest(try WorkflowProfileJSON.encode(profile))
        let record = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "profileID": profile.id,
            "profileRevision": profile.revision,
            "profileSHA256": digest,
        ], options: [.sortedKeys])
        try withDirectories { _, _, qualifications in
            try publishImmutable(
                record,
                named: Self.qualificationFileName(profile.id, profile.revision),
                in: qualifications
            )
        }
    }

    /// Returns nil when no local confirmation exists. A present but malformed
    /// or mismatched record fails closed rather than becoming unconfirmed.
    public func qualification(
        for profile: WorkflowProfile
    ) throws -> UnattendedWorkflowQualification? {
        guard try load(profileID: profile.id, revision: profile.revision) == profile else {
            throw Error.profileConflict
        }
        return try withDirectories { _, _, qualifications -> UnattendedWorkflowQualification? in
            let name = Self.qualificationFileName(profile.id, profile.revision)
            let bytes: Data
            do {
                bytes = try readRegular(named: name, in: qualifications, maximumBytes: 4 * 1024)
            } catch POSIXReadError.notFound {
                return nil
            }
            let raw: Any
            do { raw = try JSONSerialization.jsonObject(with: bytes) }
            catch { throw Error.malformedQualification }
            guard let object = raw as? [String: Any],
                  Set(object.keys) == ["schemaVersion", "profileID", "profileRevision", "profileSHA256"],
                  let schema = object["schemaVersion"] as? NSNumber,
                  CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.intValue == 1,
                  let profileID = object["profileID"] as? String,
                  let revision = object["profileRevision"] as? NSNumber,
                  CFGetTypeID(revision) != CFBooleanGetTypeID(),
                  revision.doubleValue >= 1, revision.doubleValue < Double(Int.max),
                  revision.doubleValue == Double(revision.intValue),
                  let expectedDigest = object["profileSHA256"] as? String else {
                throw Error.malformedQualification
            }
            let actualDigest = Self.digest(try WorkflowProfileJSON.encode(profile))
            guard profileID == profile.id, revision.intValue == profile.revision,
                  expectedDigest == actualDigest else {
                throw Error.qualificationMismatch
            }
            return try UnattendedWorkflowQualification(userConfirmed: profile)
        }
    }

    static func profileFileName(_ id: String, _ revision: Int) -> String {
        "\(digest(Data(id.utf8)))-r\(revision).json"
    }

    static func qualificationFileName(_ id: String, _ revision: Int) -> String {
        "\(digest(Data(id.utf8)))-r\(revision).qualification.json"
    }

    private enum POSIXReadError: Swift.Error { case notFound }

    private func withDirectories<T>(
        _ body: (Int32, Int32, Int32) throws -> T
    ) throws -> T {
        let rootDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootDescriptor >= 0 else { throw Error.cannotOpenStore }
        defer { close(rootDescriptor) }
        try validateDirectory(rootDescriptor)
        let profiles = try openPrivateDirectory("profiles", parent: rootDescriptor)
        defer { close(profiles) }
        let qualifications = try openPrivateDirectory("qualifications", parent: rootDescriptor)
        defer { close(qualifications) }
        return try body(rootDescriptor, profiles, qualifications)
    }

    private func openPrivateDirectory(_ name: String, parent: Int32) throws -> Int32 {
        if mkdirat(parent, name, 0o700) != 0, errno != EEXIST { throw Error.cannotCreateStore }
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Error.cannotOpenStore }
        do { try validateDirectory(descriptor) }
        catch { close(descriptor); throw error }
        return descriptor
    }

    private func validateDirectory(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & 0o077) == 0 else {
            throw Error.unsafeStoreDirectory
        }
    }

    private func publishImmutable(_ data: Data, named name: String, in directory: Int32) throws {
        let temporary = ".tmp-\(UUID().uuidString)"
        let descriptor = openat(
            directory, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw Error.cannotWrite }
        var shouldUnlink = true
        defer {
            close(descriptor)
            if shouldUnlink { unlinkat(directory, temporary, 0) }
        }
        try data.withUnsafeBytes { raw in
            guard var cursor = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, cursor, remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw Error.cannotWrite }
                remaining -= count
                cursor = cursor.advanced(by: count)
            }
        }
        guard fsync(descriptor) == 0 else { throw Error.cannotWrite }
        if renameatx_np(directory, temporary, directory, name, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST else { throw Error.cannotWrite }
            let existing = try readRegular(
                named: name, in: directory,
                maximumBytes: max(data.count, WorkflowProfileJSON.maximumBytes)
            )
            guard existing == data else { throw Error.profileConflict }
        } else {
            shouldUnlink = false
            guard fsync(directory) == 0 else { throw Error.cannotWrite }
        }
    }

    private func readRegular(named name: String, in directory: Int32, maximumBytes: Int) throws -> Data {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { throw POSIXReadError.notFound }
        guard descriptor >= 0 else { throw Error.cannotRead }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1,
              before.st_size >= 0, before.st_size <= maximumBytes else {
            throw Error.cannotRead
        }
        var result = Data()
        result.reserveCapacity(Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: min(64 * 1024, maximumBytes + 1))
        while result.count <= maximumBytes {
            let requested = min(buffer.count, maximumBytes - result.count + 1)
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(descriptor, raw.baseAddress, requested)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw Error.cannotRead }
            if count == 0 { break }
            result.append(contentsOf: buffer[0..<count])
        }
        guard result.count <= maximumBytes else { throw Error.cannotRead }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              (after.st_mode & S_IFMT) == S_IFREG,
              after.st_uid == geteuid(), after.st_nlink == 1,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              after.st_size == result.count else {
            throw Error.cannotRead
        }
        return result
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
