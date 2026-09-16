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
                maximumBytes: PrinterProfileJSON.maximumBytes
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
        guard profile.schemaVersion == selector.schemaVersion,
              profile.revision == selector.revision else {
            throw Error.profileIdentityMismatch
        }
        let reference = try ImmutableProfileReference(
            id: selector.id, schemaVersion: profile.schemaVersion,
            revision: profile.revision, sha256: Self.digest(bytes)
        )
        return StoredPrinterProfile(reference: reference, profile: profile)
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
        case .cannotWrite, .commitUncertain, .conflict, .recordCapacityReached, .publicationBusy: .cannotWrite
        case .cannotRead, .notFound, .none: .cannotRead
        }
    }
}
