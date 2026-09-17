import CryptoKit
import Foundation
import LabelCore

public struct StoredPrinterProfile: Equatable, Sendable {
    public let reference: ImmutableProfileReference
    public let profile: PrinterProfile
}

/// Private immutable printer-profile revisions. The canonical byte digest
/// returned here is the only printer reference accepted by VirtualQueueStore.
public struct PrinterProfileStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case catalogCapacityReached
        case publicationBusy
        case cannotCreateStore
        case cannotOpenStore
        case unsafeStoreDirectory
        case cannotRead
        case cannotWrite
        case commitUncertain(ImmutablePublicationIdentity)
        case profileConflict
        case profileIdentityMismatch
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

    @discardableResult
    public func save(id: String, profile: PrinterProfile) throws -> ImmutableProfileReference {
        let bytes = try PrinterProfileJSON.encode(profile)
        let reference: ImmutableProfileReference
        do {
            reference = try ImmutableProfileReference(
                id: id, schemaVersion: profile.schemaVersion,
                revision: profile.revision, sha256: Self.digest(bytes)
            )
        } catch {
            throw Error.profileIdentityMismatch
        }
        do {
            try storage.publish(
                bytes,
                directory: "printer-profiles",
                fileName: Self.fileName(id, profile.revision),
                maximumBytes: PrinterProfileJSON.maximumBytes,
                maximumRecords: 256
            )
        } catch PrivateImmutableDirectory.Error.conflict {
            throw Error.profileConflict
        } catch PrivateImmutableDirectory.Error.commitUncertain {
            throw Error.commitUncertain(ImmutablePublicationIdentity(
                id: reference.id, schemaVersion: reference.schemaVersion,
                revision: reference.revision, sha256: reference.sha256
            ))
        } catch {
            throw Self.mapStorage(error)
        }
        return reference
    }

    public func load(reference: ImmutableProfileReference) throws -> PrinterProfile {
        let stored = try load(id: reference.id, revision: reference.revision)
        guard stored.reference == reference else { throw Error.profileIdentityMismatch }
        return stored.profile
    }

    public func load(id: String, revision: Int) throws -> StoredPrinterProfile {
        let selector: ImmutableProfileReference
        do {
            selector = try ImmutableProfileReference(
                id: id, revision: revision, sha256: String(repeating: "0", count: 64)
            )
        } catch {
            throw Error.profileIdentityMismatch
        }
        let bytes: Data
        do {
            bytes = try storage.read(
                directory: "printer-profiles",
                fileName: Self.fileName(selector.id, selector.revision),
                maximumBytes: PrinterProfileJSON.maximumBytes
            )
        } catch {
            throw Self.mapStorage(error)
        }
        let profile: PrinterProfile
        do { profile = try PrinterProfileJSON.decode(bytes) }
        catch { throw Error.cannotRead }
        // This API selects an immutable name by ID/revision, not an expected
        // schema. The decoder restricts supported versions; load(reference:)
        // still compares the full actual schema/revision/digest reference.
        guard profile.revision == selector.revision else {
            throw Error.profileIdentityMismatch
        }
        let reference = try ImmutableProfileReference(
            id: selector.id, schemaVersion: profile.schemaVersion,
            revision: profile.revision, sha256: Self.digest(bytes)
        )
        return StoredPrinterProfile(reference: reference, profile: profile)
    }

    /// Bounded private revisions for one exact profile identity. This is a
    /// point-in-time catalog, not a reservation for a subsequent revision.
    public func savedProfiles(id: String, maximumProfiles: Int = 256) throws -> [StoredPrinterProfile] {
        do { _ = try ImmutableProfileReference(id: id, revision: 1, sha256: String(repeating: "0", count: 64)) }
        catch { throw Error.profileIdentityMismatch }
        let records: [(name: String, data: Data)]
        do {
            records = try storage.catalog(directory: "printer-profiles", maximumRecords: maximumProfiles,
                maximumRecordBytes: PrinterProfileJSON.maximumBytes, maximumTotalBytes: 8 * 1024 * 1024)
        } catch { throw Self.mapStorage(error) }
        let prefix = Self.digest(Data(id.utf8)) + "-r"
        return try records.filter { $0.name.hasPrefix(prefix) }.map { record in
            let profile: PrinterProfile
            do { profile = try PrinterProfileJSON.decode(record.data) } catch { throw Error.cannotRead }
            guard record.name == Self.fileName(id, profile.revision),
                  try PrinterProfileJSON.encode(profile) == record.data else { throw Error.profileIdentityMismatch }
            return StoredPrinterProfile(reference: try ImmutableProfileReference(id: id,
                schemaVersion: profile.schemaVersion, revision: profile.revision, sha256: Self.digest(record.data)), profile: profile)
        }.sorted { $0.profile.revision > $1.profile.revision }
    }

    static func fileName(_ id: String, _ revision: Int) -> String {
        "\(digest(Data(id.utf8)))-r\(revision).json"
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mapStorage(_ error: Swift.Error) -> Error {
        switch error as? PrivateImmutableDirectory.Error {
        case .cannotCreate: .cannotCreateStore
        case .cannotOpen: .cannotOpenStore
        case .unsafeDirectory: .unsafeStoreDirectory
        case .cannotWrite, .commitUncertain, .conflict: .cannotWrite
        case .recordCapacityReached: .catalogCapacityReached
        case .publicationBusy: .publicationBusy
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }
}
