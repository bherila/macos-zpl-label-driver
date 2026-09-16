import CryptoKit
import Foundation
import LabelCore

/// A private local store for immutable profile revisions and separately
/// confirmed unattended-use qualifications. Imported JSON is never itself a
/// qualification record.
public struct WorkflowProfileStore: @unchecked Sendable {
    public struct CatalogEntry: Identifiable, Equatable, Sendable {
        public let profile: WorkflowProfile
        public var id: String { WorkflowProfileStore.profileFileName(profile.id, profile.revision) }
    }
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotCreateStore
        case cannotOpenStore
        case unsafeStoreDirectory
        case cannotRead
        case cannotWrite
        case commitUncertain(ImmutablePublicationIdentity)
        case profileConflict
        case profileIdentityMismatch
        case malformedQualification
        case qualificationMismatch
    }

    public let root: URL
    private let storage: PrivateImmutableDirectory

    public init(root: URL) throws {
        self.root = root
        do { storage = try PrivateImmutableDirectory(root: root) }
        catch { throw Self.mapStorage(error) }
    }

    init(root: URL, storage: PrivateImmutableDirectory) {
        self.root = root
        self.storage = storage
    }

    public func save(_ profile: WorkflowProfile) throws {
        let bytes = try WorkflowProfileJSON.encode(profile)
        let identity = Self.identity(profile, bytes: bytes)
        do {
            try storage.publish(
                bytes, directory: "profiles",
                fileName: Self.profileFileName(profile.id, profile.revision),
                maximumBytes: WorkflowProfileJSON.maximumBytes
            )
        } catch PrivateImmutableDirectory.Error.conflict {
            throw Error.profileConflict
        } catch PrivateImmutableDirectory.Error.commitUncertain {
            throw Error.commitUncertain(identity)
        } catch {
            throw Self.mapStorage(error)
        }
    }

    public func load(profileID: String, revision: Int) throws -> WorkflowProfile {
        let bytes: Data
        do {
            bytes = try storage.read(
                directory: "profiles",
                fileName: Self.profileFileName(profileID, revision),
                maximumBytes: WorkflowProfileJSON.maximumBytes
            )
        } catch {
            throw Self.mapStorage(error)
        }
        let profile = try WorkflowProfileJSON.decode(bytes)
        guard profile.id == profileID, profile.revision == revision,
              try WorkflowProfileJSON.encode(profile) == bytes else {
            throw Error.profileIdentityMismatch
        }
        return profile
    }

    /// No document payload or qualification authority is included. Malformed,
    /// misnamed, unsafe or over-budget candidates fail the entire catalog.
    public func savedWorkflows(maximumProfiles: Int = 256) throws -> [CatalogEntry] {
        let records: [(name: String, data: Data)]
        do {
            records = try storage.catalog(directory: "profiles", maximumRecords: maximumProfiles,
                maximumRecordBytes: WorkflowProfileJSON.maximumBytes,
                maximumTotalBytes: 64 * 1024 * 1024)
        } catch { throw Self.mapStorage(error) }
        return try records.map { record in
            let profile = try WorkflowProfileJSON.decode(record.data)
            guard record.name == Self.profileFileName(profile.id, profile.revision),
                  try WorkflowProfileJSON.encode(profile) == record.data else {
                throw Error.profileIdentityMismatch
            }
            return CatalogEntry(profile: profile)
        }.sorted {
            if $0.profile.id != $1.profile.id { return $0.profile.id < $1.profile.id }
            return $0.profile.revision > $1.profile.revision
        }
    }

    /// Persists local confirmation only after the exact immutable profile
    /// revision is present. The definition is never copied into this record.
    public func confirmForUnattendedUse(_ profile: WorkflowProfile) throws {
        let stored = try load(profileID: profile.id, revision: profile.revision)
        guard stored == profile else { throw Error.profileConflict }
        _ = try UnattendedWorkflowQualification(userConfirmed: profile)
        let profileBytes = try WorkflowProfileJSON.encode(profile)
        let identity = Self.identity(profile, bytes: profileBytes)
        let record = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "profileID": profile.id,
            "profileRevision": profile.revision,
            "profileSHA256": identity.sha256,
        ], options: [.sortedKeys])
        do {
            try storage.publish(
                record, directory: "qualifications",
                fileName: Self.qualificationFileName(profile.id, profile.revision),
                maximumBytes: 4 * 1024
            )
        } catch PrivateImmutableDirectory.Error.conflict {
            throw Error.profileConflict
        } catch PrivateImmutableDirectory.Error.commitUncertain {
            throw Error.commitUncertain(identity)
        } catch {
            throw Self.mapStorage(error)
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
        let name = Self.qualificationFileName(profile.id, profile.revision)
        let bytes: Data
        do {
            bytes = try storage.read(
                directory: "qualifications", fileName: name, maximumBytes: 4 * 1024
            )
        } catch PrivateImmutableDirectory.Error.notFound {
            return nil
        } catch {
            throw Self.mapStorage(error)
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

    static func profileFileName(_ id: String, _ revision: Int) -> String {
        "\(digest(Data(id.utf8)))-r\(revision).json"
    }

    static func qualificationFileName(_ id: String, _ revision: Int) -> String {
        "\(digest(Data(id.utf8)))-r\(revision).qualification.json"
    }

    private static func identity(
        _ profile: WorkflowProfile, bytes: Data
    ) -> ImmutablePublicationIdentity {
        ImmutablePublicationIdentity(
            id: profile.id, schemaVersion: profile.schemaVersion,
            revision: profile.revision, sha256: digest(bytes)
        )
    }

    private static func mapStorage(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .cannotCreate: .cannotCreateStore
        case .cannotOpen: .cannotOpenStore
        case .unsafeDirectory: .unsafeStoreDirectory
        case .cannotWrite, .commitUncertain, .conflict: .cannotWrite
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
