import Foundation

/// Typed vocabulary for a *planned* queue installation and the durable record of
/// what such a transaction created or was about to create.
///
/// Nothing in this file performs an installation. It builds no command line,
/// spawns no process, touches no filesystem, contacts no scheduler and reads no
/// device. It is the portable shape that ADR 0005 leaves common to every option
/// that ADR still holds open, and ADR 0005 remains *proposed*: this file selects
/// no mechanism, no adapter and no authorization flow.
public enum QueueInstallationError: Error, Equatable, Sendable {
    case invalidPath
    case invalidMode
    case invalidOwnership
    case invalidDigest
    case invalidQueueName
    case invalidTransactionID
    case invalidIncarnation
    case invalidObservation
    case artifactKindMismatch
    case artifactOutsideProtectedRoot
    case duplicateArtifactPath
    case tooManyArtifacts
    case refused(QueueInstallationRefusal)
    case invalidPhase
    case transactionMismatch
    /// Preconditions were captured for a different intent than the plan they
    /// were offered to.
    case preconditionsIntentMismatch
    case stagedArtifactInvalid(QueueInstallationArtifactKind, ArtifactValidationFailure)
    /// A queue was created but its configuration did not hand back the
    /// incarnation token this transaction wrote, so it cannot be claimed as
    /// this transaction's. It stays pending in the record for recovery.
    case queueIncarnationUnconfirmed
    case effectFailed
    case recoveryOrderingViolation
    /// A supplied recovery plan does not cover every artifact the record still
    /// names. Recovering part of a transaction is not recovering it.
    case incompleteRecoveryPlan
    case notOwnedByTransaction
    case invalidRecord
    /// A record's phase contradicts what it says it created.
    case inconsistentRecordPhase
    /// A record that should carry a journal artifact does not, so recovery has
    /// nowhere to read or write its own evidence.
    case recordHasNoJournal
    /// A decoded record's file list is not the exact four-artifact inventory an
    /// intent describes, so it cannot be reconstructed as one.
    case recordInventoryMismatch
    /// A record's created artifacts are not a prefix of the planned creation
    /// order, or its pending step is not the one that immediately follows them.
    /// Recovery reverses this list, so a permutation would remove a later
    /// artifact before an earlier one.
    case createdArtifactsOutOfOrder
    /// A destination could not be decoded from its canonical spelling.
    case invalidDestination
    /// The journal was larger than the bounded read it was given. Its contents
    /// were never materialized, so this is unknown, not a corrupt record.
    case ownershipRecordTooLarge
    /// The seam accepted a journal write but did not prove it had reached stable
    /// storage, so the step it precedes must not run.
    case journalWriteNotDurable
    /// A queue was created but its configuration did not hand back the exact
    /// destination this transaction asked for.
    case queueDestinationUnconfirmed
    /// A journal was loaded from an artifact the record it contains does not
    /// claim to have created, so cleaning up would report success while leaving
    /// that journal behind.
    case journalNotOwnedByRecord
    /// A staging allowlist naming nowhere admits nothing, and an intent checked
    /// against it would be an intent nobody declared a location for.
    case emptyStagingAllowlist
    /// A staging location inside a tree this project must never write to. This
    /// refusal does not consult the allowlist; it is what an allowlist may not
    /// override.
    case stagingLocationRefused
    /// The protected root's parent is not one of the locations the caller
    /// declared. Where installation may stage is a policy the caller states and
    /// this model checks, not "anywhere that parses".
    case stagingLocationNotPermitted
    /// A payload path was already occupied, so the create step refused without
    /// modifying whatever is there.
    case stagedArtifactAlreadyPresent(QueueInstallationArtifactKind)
    /// A create step could not say whether it took effect. Unknown is not
    /// created, and it is not absent either.
    case stagedArtifactCreationUnverified(QueueInstallationArtifactKind)
    /// A queue was created but its configuration did not hand back the exact
    /// printer description this transaction asked it to be built from.
    case queueDescriptionUnconfirmed
    /// The directory the protected root was to be reserved inside was no longer
    /// the one preconditions validated, so the reservation was declined and
    /// nothing was created.
    case stagingParentReplacedBeforeReservation
    /// The reservation could not be bound to the validated staging parent: the
    /// seam could not say which directory it acted inside, or named a different
    /// one. The root may or may not exist, and where it would be is unknown.
    case protectedRootParentUnconfirmed
    /// The printer description a caller staged declares that it invokes some
    /// executable other than the filter the same intent plans. The description
    /// and the filter are not two independent artifacts that happen to be
    /// staged together: one names the other, and an intent in which they
    /// disagree would stage a signed filter, point a queue at a description,
    /// and run something else.
    case descriptionFilterBindingMismatch
    /// A queue was created but its configuration did not hand back the exact
    /// executable this transaction's description declares it invokes. Which
    /// description file a queue is built from and which executable that queue
    /// is configured to run are two facts, and a queue may carry the planned
    /// description while running a different filter.
    case queueFilterBindingUnconfirmed
}

// MARK: - Bounded primitive values

/// An absolute POSIX path with no relative component and no character that could
/// make the durable record's line encoding ambiguous. A selector or display name
/// is never converted into one of these; a path is supplied explicitly.
public struct AbsolutePath: Equatable, Hashable, Sendable {
    public static let maximumByteCount = 1024

    public let value: String

    public init(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard (2...Self.maximumByteCount).contains(bytes.count) else { throw QueueInstallationError.invalidPath }
        guard bytes.first == 0x2f, bytes.last != 0x2f else { throw QueueInstallationError.invalidPath }
        // Printable ASCII only, minus the three characters the record encoding
        // reserves as separators. This keeps decode(encode(x)) == x injective
        // rather than relying on a quoting scheme.
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f && $0 != 0x3d && $0 != 0x3a && $0 != 0x7c }) else {
            throw QueueInstallationError.invalidPath
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard components.count >= 1,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw QueueInstallationError.invalidPath
        }
        self.value = value
    }

    public var componentCount: Int {
        value.split(separator: "/", omittingEmptySubsequences: false).dropFirst().count
    }

    /// The containing directory, or nil when this path has a single component
    /// and its parent would be the filesystem root.
    public var parent: AbsolutePath? {
        guard componentCount >= 2, let index = value.lastIndex(of: "/") else { return nil }
        return try? AbsolutePath(String(value[value.startIndex..<index]))
    }

    /// True when `self` is exactly one component below `directory`. Deeper
    /// nesting is deliberately not accepted: recovery must be finite and must
    /// not become a recursive delete.
    public func isImmediateChild(of directory: AbsolutePath) -> Bool {
        parent == directory
    }
}

/// POSIX ownership as a pair of bounded identifiers.
public struct POSIXOwnership: Equatable, Hashable, Sendable {
    public static let rootWheel = POSIXOwnership(unchecked: 0, gid: 0)

    public let uid: Int
    public let gid: Int

    private init(unchecked uid: Int, gid: Int) {
        self.uid = uid
        self.gid = gid
    }

    public init(uid: Int, gid: Int) throws {
        guard (0...Int(Int32.max)).contains(uid), (0...Int(Int32.max)).contains(gid) else {
            throw QueueInstallationError.invalidOwnership
        }
        self.uid = uid
        self.gid = gid
    }
}

/// A permission word restricted to what a protected staging root may ever carry:
/// no set-user-ID, no set-group-ID, no sticky bit, and never group- or
/// world-writable. An invalid mode is rejected, never clamped.
public struct POSIXMode: Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) throws {
        guard (0...0o7777).contains(rawValue) else { throw QueueInstallationError.invalidMode }
        guard rawValue & 0o7000 == 0 else { throw QueueInstallationError.invalidMode }
        guard rawValue & 0o022 == 0 else { throw QueueInstallationError.invalidMode }
        self.rawValue = rawValue
    }

    /// Exactly four octal digits, so the record encoding is fixed width.
    public var octalText: String {
        var digits = ""
        var shift = 9
        while shift >= 0 {
            digits.append(Character(UnicodeScalar(UInt8(0x30 + ((rawValue >> shift) & 0o7)))))
            shift -= 3
        }
        return digits
    }

    public static func decodeOctal(_ text: String) throws -> POSIXMode {
        let bytes = Array(text.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ (0x30...0x37).contains($0) }) else {
            throw QueueInstallationError.invalidMode
        }
        var value = 0
        for byte in bytes {
            // Bounded by construction: four octal digits cannot exceed 0o7777.
            value = (value << 3) | Int(byte - 0x30)
        }
        return try POSIXMode(value)
    }
}

/// A scheduler queue *name*. It is an identifier, never a path, a URI or a
/// command fragment, and this type refuses anything that could be read as one.
public struct PlannedSchedulerQueue: Equatable, Hashable, Sendable {
    public let name: String

    public init(name: String) throws {
        let bytes = Array(name.utf8)
        guard (1...127).contains(bytes.count) else { throw QueueInstallationError.invalidQueueName }
        guard let first = bytes.first, first != 0x2d, first != 0x5f else {
            throw QueueInstallationError.invalidQueueName
        }
        guard bytes.allSatisfy({
            (0x41...0x5a).contains($0) || (0x61...0x7a).contains($0)
                || (0x30...0x39).contains($0) || $0 == 0x2d || $0 == 0x5f
        }) else { throw QueueInstallationError.invalidQueueName }
        self.name = name
    }
}

/// Where an installation is allowed to stage, as a value the caller declares
/// and this model checks.
///
/// **Naming the real location is ADR 0005's decision, not this type's.** ADR
/// 0005 remains *proposed*, so nothing here blesses a particular directory and
/// no default is supplied: the allowlist is supplied by whoever builds an
/// intent. What this type changes is that the location is a *declared, checked*
/// policy rather than "any absolute path with a parent", which is what an
/// intent previously accepted — and an intent under `/System` is exactly what
/// `AGENTS.md` forbids writing to.
///
/// Two rules, in this order:
///
/// - `refusedTrees` is refused whatever the allowlist says, and the refusal is
///   case-insensitive, so `/system` and `/PRIVATE/VAR/DB` are refused as
///   surely as their canonical spellings. A policy naming one of them cannot be
///   constructed at all, so no intent can be checked against one.
/// - The protected root's parent must be one of the permitted parents
///   *exactly*. Containment is deliberately not accepted: "somewhere under
///   /Library" is not a staging location, it is a region.
public struct QueueInstallationStagingPolicy: Equatable, Hashable, Sendable {
    public static let maximumPermittedParents = 8

    /// Trees no installation staging location may lie in or under. `AGENTS.md`
    /// forbids writing to `/System` outright; the rest are the directories a
    /// macOS system would be unbootable or unusable without. The filesystem
    /// root is absent from this list because `AbsolutePath` cannot spell it and
    /// a single-component root has no parent, so an intent staged at `/` is
    /// refused as `invalidPath` before any policy is consulted.
    public static let refusedTrees = [
        "/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib",
        "/private/var/db", "/dev",
    ]

    /// Sorted and deduplicated, so one policy has one canonical spelling in the
    /// durable record.
    public let permittedStagingParents: [AbsolutePath]

    public init(permittedStagingParents parents: [AbsolutePath]) throws {
        guard !parents.isEmpty else { throw QueueInstallationError.emptyStagingAllowlist }
        guard parents.count <= Self.maximumPermittedParents else {
            throw QueueInstallationError.tooManyArtifacts
        }
        let unique = Array(Set(parents)).sorted { $0.value < $1.value }
        for parent in unique {
            guard !Self.isSystemCritical(parent) else {
                throw QueueInstallationError.stagingLocationRefused
            }
        }
        permittedStagingParents = unique
    }

    /// True when the path *is* one of the refused trees or lies under one.
    ///
    /// The comparison is component-wise, so `/usr/libexec` is not under
    /// `/usr/lib`; a plain string prefix would make it one.
    ///
    /// It is also **case-insensitive over ASCII**, which is this model's
    /// portable approximation of filesystem identity. The model consults no
    /// filesystem — it cannot, and must not — so it cannot ask whether two
    /// spellings name the same directory. A byte-exact comparison answers a
    /// different question from the one being asked: macOS volumes are
    /// case-insensitive by default, so `/system` and `/PRIVATE/VAR/DB` reach
    /// exactly the trees `AGENTS.md` forbids writing to while passing a
    /// case-sensitive check, and the intent's exact-parent check would then
    /// admit a root beneath one of them.
    ///
    /// Folding errs deliberately in one direction. On a case-sensitive volume
    /// it can refuse a spelling that is genuinely a different directory — a
    /// real `/System` and a distinct `/system` could both exist there — and the
    /// cost of that is a staging location the caller must respell. The opposite
    /// error is staging inside `/System`, so the refusal is the safe side to be
    /// wrong on, and no allowlist may override it.
    ///
    /// `AbsolutePath` admits printable ASCII only, so folding is plain ASCII
    /// arithmetic: no locale, no Unicode case mapping, and no dependence on the
    /// host's collation.
    public static func isSystemCritical(_ path: AbsolutePath) -> Bool {
        let components = Self.asciiFoldedComponents(path.value)
        return refusedTrees.contains { tree in
            let treeComponents = Self.asciiFoldedComponents(tree)
            guard components.count >= treeComponents.count else { return false }
            return Array(components.prefix(treeComponents.count)) == treeComponents
        }
    }

    /// The path's components, each lowercased over A-Z and nothing else.
    /// Comparing components rather than characters is what keeps `/usr/libexec`
    /// out of `/usr/lib`.
    private static func asciiFoldedComponents(_ path: String) -> [[UInt8]] {
        path.split(separator: "/", omittingEmptySubsequences: true).map { component in
            component.utf8.map { (0x41...0x5a).contains($0) ? $0 + 0x20 : $0 }
        }
    }

    public func admits(_ parent: AbsolutePath) -> Bool {
        permittedStagingParents.contains(parent)
    }
}

/// One USB device a queue may deliver to: a vendor and product pair, which
/// names a *model*, together with the opaque identity that names the *unit*.
///
/// The pair alone was the whole of this value and that was a defect. Two
/// GC420d units on the same desk publish the same vendor and product
/// identifiers, so with both attached a conformer could point the queue at
/// either one and still hand back a destination that compares exactly equal to
/// the one that was asked for. Neither the creation readback nor recovery could
/// see the difference, and `AGENTS.md` requires that all product queues and
/// maintenance actions share one physical-device coordination domain — a domain
/// a model number cannot pick out.
///
/// `identity` is therefore required, not optional: a USB destination this model
/// will point a queue at is a unit, and a unit that cannot be told apart from
/// its twin is not one. A device whose registry metadata yields no qualifying
/// identity produces a `USBIdentityQualification.Failure`, which is a reported
/// refusal with a reason, not a destination with an unknown field.
///
/// **On the serial-number rule.** `AGENTS.md` forbids a serial number, or any
/// digest of one, from entering the repository, an issue, a pull request or a
/// log. That rule is satisfied here, and not by avoiding the question. This
/// reuses `StableConnectionIdentity` exactly as `ConnectionConfiguration`
/// already does, and `USBIdentityQualification` derives it as a
/// domain-separated SHA-256 over a canonical preimage, never storing the
/// serial. `docs/validation/M1-USB-IDENTITY-QUALIFICATION-2026-09-19.md` states
/// the consequence this depends on: the profile, its encoding, the diagnostic
/// surfaces and any log can hold the identity without holding the serial. An
/// earlier version of this comment claimed the opposite conclusion from the
/// same rule and declined to answer the identity question at all; the rule
/// constrains what an identity may *be*, and this one already satisfies it.
///
/// What still must not happen is a *real* unit's identity being committed.
/// Fixtures and tests use synthetic opaque values, and nothing in this model
/// reads a device.
public struct USBDeviceDestination: Equatable, Hashable, Sendable, RedactedDiagnosticValue {
    public let vendorID: Int
    public let productID: Int
    /// The opaque per-unit identity, carried verbatim into the durable record
    /// so that a queue's destination can be required to read back as the same
    /// physical unit rather than the same model.
    public let identity: StableConnectionIdentity

    public init(vendorID: Int, productID: Int, identity: StableConnectionIdentity) throws {
        guard (0...0xffff).contains(vendorID), (0...0xffff).contains(productID) else {
            throw QueueInstallationError.invalidDestination
        }
        // `StableConnectionIdentity` admits any non-empty, non-whitespace,
        // non-control string up to 512 bytes, which is wider than this
        // encoding. The record is a fixed canonical line sequence whose
        // destination field is `|`-separated, so an identity containing `|`
        // would decode as a different destination than the one encoded and
        // break the byte-exact round trip every journal comparison rests on.
        // Non-ASCII would do the same to the byte accounting in
        // `maximumCanonicalByteCount`. Both are refused here rather than
        // quoted: a quoting scheme is one more thing that can disagree with
        // itself.
        let bytes = Array(identity.privateProfileValue.utf8)
        guard !bytes.isEmpty, bytes.count <= Self.maximumIdentityByteCount,
              bytes.allSatisfy({ $0 > 0x20 && $0 < 0x7f && $0 != 0x7c }) else {
            throw QueueInstallationError.invalidDestination
        }
        self.vendorID = vendorID
        self.productID = productID
        self.identity = identity
    }

    /// The widest opaque identity this encoding accepts, which is also
    /// `StableConnectionIdentity`'s own bound.
    public static let maximumIdentityByteCount = 512

    /// `StableConnectionIdentity` is `Equatable` but not `Hashable`, and the
    /// raw value it wraps stays inside `LabelCore`, so the hash is written out
    /// here rather than synthesized. It hashes exactly the fields `==`
    /// compares.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(vendorID)
        hasher.combine(productID)
        hasher.combine(identity.privateProfileValue)
    }

    static func hex4(_ value: Int) -> String {
        var digits = ""
        var shift = 12
        while shift >= 0 {
            let nibble = (value >> shift) & 0xf
            digits.append(Character(UnicodeScalar(UInt8(nibble < 10 ? 0x30 + nibble : 0x61 + nibble - 10))))
            shift -= 4
        }
        return digits
    }

    static func decodeHex4(_ text: Substring) -> Int? {
        let bytes = Array(text.utf8)
        guard bytes.count == 4 else { return nil }
        var value = 0
        for byte in bytes {
            switch byte {
            case 0x30...0x39: value = (value << 4) | Int(byte - 0x30)
            case 0x61...0x66: value = (value << 4) | Int(byte - 0x61 + 10)
            default: return nil
            }
        }
        return value
    }
}

/// Where a queue would send what it accepts. A **closed** set of typed cases,
/// never a free string and never an interpolated fragment: the model builds no
/// device URI, no backend argument and no command line, and a conformer that
/// turns one of these into a scheduler target must do so from the case alone.
///
/// The two cases exist precisely so that they cannot be confused. `AGENTS.md`
/// requires that the inert discard sink is never connected to the GC420d; with
/// the destination typed, bound into the intent, written into the durable record
/// and required to read back exactly before a queue may be claimed as created or
/// complete, "which one is this queue pointed at" is an answerable question
/// rather than a property of whatever ambient state the conformer consulted.
public enum QueueDestination: Equatable, Hashable, Sendable {
    /// Everything accepted is discarded. This is a sink, not a printer, and it
    /// names no device.
    case inertDiscardSink
    /// One USB device *unit*. Naming a device here is not consent to print to
    /// one: it is what makes a queue aimed at a device distinguishable from a
    /// queue aimed at the sink, and — since the unit's opaque identity travels
    /// with it — from a queue aimed at the identical model sitting beside it.
    case usbDevice(USBDeviceDestination)

    public var canonicalText: String {
        switch self {
        case .inertDiscardSink:
            return "inert-discard-sink"
        case let .usbDevice(device):
            return "usb-device|" + USBDeviceDestination.hex4(device.vendorID)
                + "|" + USBDeviceDestination.hex4(device.productID)
                + "|" + device.identity.privateProfileValue
        }
    }

    public static func decode(_ text: String) throws -> QueueDestination {
        if text == "inert-discard-sink" { return .inertDiscardSink }
        let parts = text.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "usb-device",
              let vendor = USBDeviceDestination.decodeHex4(parts[1]),
              let product = USBDeviceDestination.decodeHex4(parts[2]),
              let identity = try? StableConnectionIdentity(opaqueValue: String(parts[3])) else {
            throw QueueInstallationError.invalidDestination
        }
        return .usbDevice(
            try USBDeviceDestination(vendorID: vendor, productID: product, identity: identity)
        )
    }
}

/// What the seam could read back out of a present queue's configuration about
/// where that queue delivers.
///
/// `unknown` is its own case, distinct from a destination that matches and from
/// one that differs. A destination the seam could not read is never treated as
/// the one that was asked for.
public enum ObservedQueueDestination: Equatable, Sendable {
    case known(QueueDestination)
    case unknown
}

/// Which printer description a queue was built from, as a value that can be
/// required to read back.
///
/// The create operation takes the description as an argument, and until now
/// nothing read it back. A conformer that ignored `describedBy`, or applied a
/// different file, would produce a queue carrying this transaction's token,
/// delivering to this transaction's destination and running an unintended
/// filter — and no observation in the model could tell. That is the same
/// argument the destination already won: an argument nothing reads back is an
/// argument nothing keeps.
///
/// The identity is the description's path together with the digest of the bytes
/// that were planned for it, so "the same file, replaced" is a different
/// identity and not merely the same name.
public struct SchedulerQueueDescriptionIdentity: Equatable, Hashable, Sendable {
    public let path: AbsolutePath
    public let contentSHA256: String

    public init(path: AbsolutePath, contentSHA256: String) throws {
        guard isLowercaseSHA256(contentSHA256) else { throw QueueInstallationError.invalidDigest }
        self.path = path
        self.contentSHA256 = contentSHA256
    }

    /// The identity of the planned printer description a queue is to be built
    /// from. Only that kind of artifact has one.
    public init(describedBy artifact: PlannedFileArtifact) throws {
        guard artifact.kind == .printerDescription else {
            throw QueueInstallationError.artifactKindMismatch
        }
        guard let digest = artifact.contentSHA256 else { throw QueueInstallationError.invalidDigest }
        try self.init(path: artifact.path, contentSHA256: digest)
    }
}

/// What the seam could read back about the description a present queue is built
/// from. `unknown` is its own case and is never read as a match.
public enum ObservedQueueDescriptionIdentity: Equatable, Sendable {
    case known(SchedulerQueueDescriptionIdentity)
    case unknown
}

/// Which executable a printer description invokes, and which executable a queue
/// is configured to run — the same typed fact on both sides of the seam.
///
/// A printer description is not a leaf artifact: its bytes name the filter the
/// scheduler runs for that queue. Nothing in this model parses those bytes, and
/// nothing may: `AGENTS.md` forbids inserting arbitrary profile strings into
/// commands, and turning a description into strings to compare would be the
/// same move in the other direction. So the reference is carried as a *typed
/// declaration* instead. Whoever produced the description states, as this
/// value, which executable it invokes, and `QueueInstallationIntent` refuses
/// unless that is the filter the same intent plans and signs.
///
/// Without it, the intent validated the filter and the description as two
/// unrelated artifact kinds. A description whose declared digest was perfectly
/// correct, but whose filter entry named some other executable, passed staging,
/// passed every readback and reached `completed`, while the planned signed
/// filter was never run by anything.
///
/// The binding is the executable's path *and* the digest of its planned bytes,
/// so "the same name, different bytes" is a different binding rather than the
/// same one.
public struct PrinterDescriptionFilterBinding: Equatable, Hashable, Sendable {
    public let filterPath: AbsolutePath
    public let filterSHA256: String

    public init(filterPath: AbsolutePath, filterSHA256: String) throws {
        guard isLowercaseSHA256(filterSHA256) else { throw QueueInstallationError.invalidDigest }
        self.filterPath = filterPath
        self.filterSHA256 = filterSHA256
    }

    /// The binding a planned filter executable *is*. Only that kind of artifact
    /// has one, and one without planned bytes is not a binding: a reference to
    /// an executable whose contents are unpinned names a path, not a program.
    public init(invoking filter: PlannedFileArtifact) throws {
        guard filter.kind == .filterExecutable else {
            throw QueueInstallationError.artifactKindMismatch
        }
        guard let digest = filter.contentSHA256 else { throw QueueInstallationError.invalidDigest }
        try self.init(filterPath: filter.path, filterSHA256: digest)
    }
}

/// What the seam could read back about the executable a present queue is
/// configured to run.
///
/// This is deliberately a second question from `ObservedQueueDescriptionIdentity`
/// and gets its own refusal. That identity answers *which description file the
/// queue was built from*; this answers *what the queue actually runs*. A
/// scheduler configuration can carry a filter of its own alongside the
/// description it was built from, so the two can disagree, and a queue carrying
/// the planned description while running something else is exactly the case
/// that used to pass. `unknown` is its own case and never reads as a match.
public enum ObservedQueueFilterBinding: Equatable, Sendable {
    case known(PrinterDescriptionFilterBinding)
    case unknown
}

/// What a conformer proves it did to make a journal write survive a power loss.
///
/// The journal's whole purpose is that a step is named *before* its effect runs.
/// An ordinary temp-file rename satisfies "atomic conditional replacement" while
/// still allowing a power loss to restore the older journal, which would lose
/// the name of an artifact that by then exists. So a write is usable only when
/// the conformer states it flushed both the new contents and the containing
/// directory entry to stable storage before returning; anything else, including
/// not being able to tell, stops the transaction instead of advancing it.
public enum JournalDurability: String, Equatable, Sendable, CaseIterable {
    /// The new contents *and* the directory entry that published them reached
    /// stable storage before the call returned.
    case synchronizedToStorage = "synchronized-to-storage"
    /// The bytes were handed to the filesystem but not flushed. A power loss may
    /// restore older bytes or lose the entry.
    case notSynchronized = "not-synchronized"
    /// The conformer cannot say. Unknown is not success.
    case unknown
}

/// The outcome of a *conditional* queue removal, which is one operation rather
/// than an observation followed by an unconditional delete.
///
/// The condition is the queue's whole recorded identity, not its token alone.
/// An administrator who re-pointed the queue, or rebuilt it from a different
/// printer description, while its incarnation survived has a queue this
/// transaction may no longer delete: it is not the object that was checked.
public enum SchedulerQueueRemoval: String, Equatable, Sendable, CaseIterable {
    /// Deleted, with every expected property still bound at the moment of
    /// deletion.
    case removed
    /// Not deleted: the name no longer carried the expected incarnation, so what
    /// is there now is somebody else's queue.
    case incarnationChanged
    /// Not deleted: the queue still carries the expected incarnation but no
    /// longer delivers where it was recorded as delivering.
    case destinationChanged = "destination-changed"
    /// Not deleted: the queue still carries the expected incarnation but is no
    /// longer built from the printer description it was recorded with.
    case descriptionChanged = "description-changed"
    /// Not deleted: the queue still carries the expected incarnation and
    /// description but no longer runs the executable it was recorded with.
    case filterBindingChanged = "filter-binding-changed"
    /// The operation may or may not have taken effect. Never replayed blindly.
    case unknown
}

/// The outcome of a *create-if-absent* file placement.
///
/// Placing a payload is not a namespace reservation the transaction may skip:
/// an operation that silently replaces whatever is at the path would leave
/// validation afterwards looking at exactly the bytes it expected, unable to
/// tell that something else had been there. So the refusal is a value the
/// model handles, and `alreadyPresent` guarantees nothing at the path was
/// modified.
public enum FileArtifactCreation: String, Equatable, Sendable, CaseIterable {
    /// The path did not exist and now holds this artifact.
    case created
    /// The path was already occupied. Nothing was written, truncated, replaced
    /// or followed.
    case alreadyPresent = "already-present"
    /// The operation may or may not have taken effect.
    case unknown
}

/// An opaque, conformer-supplied identifier for one directory *object*, as
/// distinct from one directory *path*.
///
/// The model never parses one, never orders one and never writes one into the
/// durable record. It only ever compares two for equality, so what it means is
/// entirely the conformer's to decide, subject to one requirement: the same
/// directory object yields the same value, and a different object does not. A
/// POSIX conformer would spell it from the device and inode numbers of the
/// descriptor it is holding open.
///
/// It exists for the same reason `SchedulerQueueIncarnation` does. A queue name
/// is not a queue, and a path is not a directory: both can be made to refer to
/// something else between the moment they are checked and the moment they are
/// used.
public struct DirectoryIdentity: Equatable, Hashable, Sendable {
    public static let maximumByteCount = 128

    public let token: String

    public init(token: String) throws {
        let bytes = Array(token.utf8)
        guard (1...Self.maximumByteCount).contains(bytes.count),
              bytes.allSatisfy({ $0 > 0x20 && $0 < 0x7f }) else {
            throw QueueInstallationError.invalidObservation
        }
        self.token = token
    }
}

/// A directory identity the seam could read, or its honest absence. Defaults to
/// `unknown` wherever it appears, and unknown never matches anything.
public enum ObservedDirectoryIdentity: Equatable, Sendable {
    case known(DirectoryIdentity)
    case unknown
}

/// The outcome of reserving the protected root *inside a named directory
/// object*.
///
/// `createProtectedRoot` used to carry only the child path, so a conformer
/// spelling it as an ordinary `mkdir("/parent/child")` conformed perfectly while
/// creating the root underneath a parent that had been replaced — by a symbolic
/// link, or by a different directory — after `QueueInstallationPreconditions`
/// validated it. The preconditions bind to one directory object; the reservation
/// bound to nothing but a string.
///
/// So the reservation is conditional, in the shape the removals already use: it
/// carries the identity it expects and is performed only while that identity
/// still holds. And it hands back the identity it actually acted inside, so the
/// model checks the answer rather than trusting that the argument was honoured
/// — an argument nothing reads back is an argument a conformer can ignore.
public enum ProtectedRootReservation: Equatable, Sendable {
    /// Reserved, inside the directory object this identity names. It is read
    /// from the descriptor the creation used, not from a later stat of the
    /// parent's path.
    case reserved(DirectoryIdentity)
    /// The parent no longer had the identity the call carried, so **nothing was
    /// created**.
    case parentIdentityChanged
    /// The conformer cannot say which directory it acted inside, or whether it
    /// acted at all. Nothing may be assumed in either direction.
    case unknown
}

/// The outcome of a *conditional* file or directory removal.
public enum FileArtifactRemoval: String, Equatable, Sendable, CaseIterable {
    /// Deleted, with the expected metadata and contents still bound at the
    /// moment of deletion.
    case removed
    /// Not deleted: the path no longer holds the exact artifact that was
    /// expected.
    case artifactChanged
    /// The operation may or may not have taken effect.
    case unknown
}

/// An *unrepeatable* token this transaction writes into the queue's own
/// configuration and reads back, so that one particular queue object can be
/// told apart from any later queue of the same name.
///
/// It must be freshly generated per transaction and must **not** be derived from
/// the queue's configuration. A digest of the configuration would be
/// reproducible: another administrator creating the same name with the same
/// device target and description would produce the same value, and a removal
/// gated on it would delete their queue. This model generates no randomness, so
/// the token is supplied by the caller and its unrepeatability is the caller's
/// obligation.
public struct SchedulerQueueIncarnation: Equatable, Hashable, Sendable {
    public let token: String

    public init(token: String) throws {
        guard isLowercaseSHA256(token) else { throw QueueInstallationError.invalidIncarnation }
        self.token = token
    }
}

/// What a create operation could prove about acquiring the queue *name*.
///
/// `lpadmin -p` is create-or-modify, not an exclusive namespace acquisition.
/// `docs/validation/M1-TRANSACTION-RECOVERY.md` states the consequence
/// directly: "even a successful response and exact discard URI readback cannot
/// prove that no competing queue was modified". A seam built on it must
/// therefore report `ambiguousCreateOrModify`, and this model refuses to call
/// such a transaction complete.
public enum SchedulerQueueAcquisition: String, Equatable, Sendable, CaseIterable {
    /// The seam proved that this operation created the name and did not modify
    /// an existing queue.
    case exclusiveCreation = "exclusive-creation"
    /// The operation reported success but cannot distinguish creation from
    /// modification of a queue that appeared first.
    case ambiguousCreateOrModify = "ambiguous-create-or-modify"
}

/// A caller-supplied identifier for one transaction: 32 lowercase hex digits.
/// This model generates no randomness and reads no clock.
public struct QueueInstallationTransactionID: Equatable, Hashable, Sendable {
    public let hex: String

    public init(hex: String) throws {
        let bytes = Array(hex.utf8)
        guard bytes.count == 32,
              bytes.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
            throw QueueInstallationError.invalidTransactionID
        }
        self.hex = hex
    }
}

func isLowercaseSHA256(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return bytes.count == 64 && bytes.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
}

/// Parses the one decimal spelling this encoding emits: digits only, no sign, no
/// leading zero unless the value is exactly `0`. `Int(_: String)` is deliberately
/// not used, because it also accepts `+0`, `-0` and `00`, which re-encode to `0`
/// and would give the same record several byte representations.
func canonicalDecimal(_ text: Substring) -> Int? {
    let bytes = Array(text.utf8)
    guard (1...10).contains(bytes.count), bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
    guard bytes.count == 1 || bytes[0] != 0x30 else { return nil }
    var value = 0
    for byte in bytes {
        // Bounded: at most ten digits, so the accumulator stays far below Int.max.
        value = value * 10 + Int(byte - 0x30)
    }
    return value
}

// MARK: - Planned artifacts

public enum QueueInstallationArtifactKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case protectedRoot = "protected-root"
    case ownershipRecord = "ownership-record"
    case filterExecutable = "filter-executable"
    case printerDescription = "printer-description"
}

/// One artifact the transaction *would* create, with its intended absolute path,
/// ownership and mode declared up front. A plan is a value; holding one performs
/// nothing.
///
/// A digest is declared for artifacts whose bytes are fixed before the
/// transaction starts. The protected root is a directory and has none, and the
/// ownership record is the transaction's own journal: its bytes change every
/// time the transaction takes ownership of something, so it is validated by
/// reading the record back and decoding it, not against a digest fixed in
/// advance.
public struct PlannedFileArtifact: Equatable, Hashable, Sendable {
    public let kind: QueueInstallationArtifactKind
    public let path: AbsolutePath
    public let ownership: POSIXOwnership
    public let mode: POSIXMode
    public let contentSHA256: String?

    public init(
        kind: QueueInstallationArtifactKind,
        path: AbsolutePath,
        ownership: POSIXOwnership = .rootWheel,
        mode: POSIXMode,
        contentSHA256: String?
    ) throws {
        guard ownership == .rootWheel else { throw QueueInstallationError.invalidOwnership }
        switch kind {
        case .protectedRoot:
            guard contentSHA256 == nil, mode.rawValue == 0o755 else {
                throw QueueInstallationError.artifactKindMismatch
            }
        case .ownershipRecord:
            guard contentSHA256 == nil, mode.rawValue == 0o644 else {
                throw QueueInstallationError.artifactKindMismatch
            }
        case .filterExecutable:
            guard mode.rawValue == 0o755 else { throw QueueInstallationError.artifactKindMismatch }
        case .printerDescription:
            guard mode.rawValue == 0o644 else { throw QueueInstallationError.artifactKindMismatch }
        }
        if kind == .filterExecutable || kind == .printerDescription {
            guard let digest = contentSHA256, isLowercaseSHA256(digest) else {
                throw QueueInstallationError.invalidDigest
            }
        }
        self.kind = kind
        self.path = path
        self.ownership = ownership
        self.mode = mode
        self.contentSHA256 = contentSHA256
    }

    public var expectedFileKind: ObservedFileKind {
        kind == .protectedRoot ? .directory : .regularFile
    }
}

/// Names one artifact inside a single transaction's ownership domain.
public enum QueueInstallationArtifactID: Equatable, Hashable, Sendable {
    case schedulerQueue
    case file(AbsolutePath)
}

// MARK: - Observation (tri-state, never collapsed)

public enum ObservedFileKind: String, Equatable, Hashable, Sendable {
    case directory
    case regularFile = "regular-file"
    case symbolicLink = "symbolic-link"
    case other
}

/// Whether anything beyond the POSIX owner may write to a path.
///
/// POSIX mode bits are not the whole access story on macOS: an ACL can grant
/// another principal `add_file`, `delete_child` or equivalent write access while
/// `stat` still reports `root:wheel` and mode 0755. A staging parent admitted on
/// its mode bits alone can therefore be one another user is able to race, and an
/// inherited ACL can carry that grant onto the protected root the transaction
/// creates inside it. This is the observation that answers the question, and
/// `unknown` — including an observer that never looked — is never read as "no
/// grants".
public enum ObservedAccessControl: String, Equatable, Hashable, Sendable, CaseIterable {
    /// The observer enumerated the effective access control entries, including
    /// inherited ones, and none grants write, append, delete-child or
    /// change-permission access to any principal other than the POSIX owner.
    case noWriteGrantsBeyondOwner = "no-write-grants-beyond-owner"
    /// At least one effective entry grants such access to another principal.
    case grantsWriteToOtherPrincipals = "grants-write-to-other-principals"
    /// Not enumerated, or not enumerable. Unknown is not absence.
    case unknown
}

/// Whether an executable artifact carries a valid code signature.
///
/// `AGENTS.md` makes local ad-hoc signing the default and forbids weakening
/// signing to compensate for having no Developer ID, so "is this filter signed
/// at all" is a question the model has to be able to ask. It could not: digest,
/// ownership, mode, ACL and kind were the whole of validation, and a conformer
/// could satisfy every one of them while staging an unsigned executable.
///
/// This is **not** a substitution window. The planned digest already pins the
/// exact bytes, and a Mach-O's signature lives inside those bytes, so bytes
/// that hash as planned carry whatever signature was planned. The gap is that
/// nothing ever asked whether the planned bytes were signed. Hence a tri-state
/// observation, required to be affirmative for an executable: `unknown` —
/// including an observer that never looked — is not a valid signature.
public enum ObservedCodeSignature: String, Equatable, Hashable, Sendable, CaseIterable {
    /// The observer verified a signature over these bytes and it was valid. An
    /// ad-hoc signature counts; this model requires no Team ID and no
    /// notarization, which `AGENTS.md` also forbids depending on.
    case valid
    /// Verified and not valid, or not signed at all.
    case invalidOrAbsent = "invalid-or-absent"
    /// Not verified, or not verifiable. Unknown is not valid.
    case unknown
}

/// What a query reported about one path. Every field is optional because a
/// partially readable answer is *unknown for that field*, never a default.
public struct ObservedFileState: Equatable, Sendable {
    public let kind: ObservedFileKind
    public let uid: Int?
    public let gid: Int?
    public let modeBits: Int?
    public let contentSHA256: String?
    /// Defaults to `unknown`, so an observation that did not look at access
    /// control fails validation rather than passing on its mode bits.
    public let accessControl: ObservedAccessControl
    /// Defaults to `unknown` for the same reason: an executable whose signature
    /// nobody checked is not an executable with a valid signature.
    public let codeSignature: ObservedCodeSignature
    /// Which directory *object* this is, when the observation is of a
    /// directory. Defaults to `unknown`, again for the same reason: an
    /// observation that did not identify the directory has not identified it,
    /// and only a staging parent is required to carry one.
    public let directoryIdentity: ObservedDirectoryIdentity

    public init(
        kind: ObservedFileKind,
        uid: Int? = nil,
        gid: Int? = nil,
        modeBits: Int? = nil,
        contentSHA256: String? = nil,
        accessControl: ObservedAccessControl = .unknown,
        codeSignature: ObservedCodeSignature = .unknown,
        directoryIdentity: ObservedDirectoryIdentity = .unknown
    ) throws {
        if let uid {
            guard (0...Int(Int32.max)).contains(uid) else { throw QueueInstallationError.invalidObservation }
        }
        if let gid {
            guard (0...Int(Int32.max)).contains(gid) else { throw QueueInstallationError.invalidObservation }
        }
        if let modeBits {
            guard (0...0o7777).contains(modeBits) else { throw QueueInstallationError.invalidObservation }
        }
        if let contentSHA256 {
            guard isLowercaseSHA256(contentSHA256) else { throw QueueInstallationError.invalidObservation }
        }
        self.kind = kind
        self.uid = uid
        self.gid = gid
        self.modeBits = modeBits
        self.contentSHA256 = contentSHA256
        self.accessControl = accessControl
        self.codeSignature = codeSignature
        self.directoryIdentity = directoryIdentity
    }
}

/// Present, confirmed absent, or *the query failed*. A failed query is never
/// reinterpreted as absence, and there is no fourth, convenient reading.
public enum FileArtifactObservation: Equatable, Sendable {
    case present(ObservedFileState)
    case confirmedAbsent
    case queryFailed

    public var isConfirmedAbsent: Bool {
        if case .confirmedAbsent = self { return true }
        return false
    }
}

/// What the seam could read out of one present queue's configuration.
///
/// A nil incarnation means a queue of that name exists but carries no readable
/// token; that is unknown, and unknown never authorizes a removal. The same
/// holds for `ObservedQueueDestination.unknown`.
public struct SchedulerQueueState: Equatable, Sendable {
    public let incarnation: SchedulerQueueIncarnation?
    public let destination: ObservedQueueDestination
    /// Which printer description the queue is built from. There is deliberately
    /// no default: a conformer that cannot read it says `unknown`, and unknown
    /// never matches.
    public let printerDescription: ObservedQueueDescriptionIdentity
    /// Which executable the queue is configured to run. Same rule, and for the
    /// same reason it is a separate field: the description a queue was built
    /// from does not settle what that queue runs.
    public let invokedFilter: ObservedQueueFilterBinding

    public init(
        incarnation: SchedulerQueueIncarnation?,
        destination: ObservedQueueDestination,
        printerDescription: ObservedQueueDescriptionIdentity,
        invokedFilter: ObservedQueueFilterBinding
    ) {
        self.incarnation = incarnation
        self.destination = destination
        self.printerDescription = printerDescription
        self.invokedFilter = invokedFilter
    }
}

/// The same three answers for a queue, and for a present queue what could be
/// read out of its configuration.
public enum SchedulerQueueObservation: Equatable, Sendable {
    case present(SchedulerQueueState)
    case confirmedAbsent
    case queryFailed

    public var isConfirmedAbsent: Bool {
        if case .confirmedAbsent = self { return true }
        return false
    }

    public var isConfirmedPresent: Bool {
        if case .present = self { return true }
        return false
    }

    public var incarnation: SchedulerQueueIncarnation? {
        if case let .present(state) = self { return state.incarnation }
        return nil
    }

    public var destination: ObservedQueueDestination {
        if case let .present(state) = self { return state.destination }
        return .unknown
    }

    public var printerDescription: ObservedQueueDescriptionIdentity {
        if case let .present(state) = self { return state.printerDescription }
        return .unknown
    }

    public var invokedFilter: ObservedQueueFilterBinding {
        if case let .present(state) = self { return state.invokedFilter }
        return .unknown
    }
}

/// The durable ownership record as it was read back: the artifact's state *and*
/// its bytes, from one open descriptor. A record the seam could not read is not
/// an empty record.
///
/// The state travels with the bytes because validating the journal and reading
/// it used to be two seam calls, and a replacement between them would hand a
/// record-validated recovery attacker-chosen bytes that had passed nobody's
/// validation. The state is the one the descriptor the bytes came out of
/// reports, so checking it is checking the file that was read — not a file that
/// merely had the same name a moment earlier.
public enum OwnershipRecordObservation: Equatable, Sendable {
    case present(ObservedFileState, String)
    case confirmedAbsent
    case queryFailed
    /// The file on the other side of the seam was larger than the maximum byte
    /// count the read was given, so nothing was materialized. This is a fourth
    /// answer on purpose: it is neither absence nor a corrupt record, and a
    /// caller must not decode its way past it.
    case exceededMaximumByteCount
}

public enum ArtifactValidationFailure: Equatable, Sendable {
    case absent
    case observationFailed
    case symbolicLink
    case wrongFileKind
    case ownershipUnknown
    case ownershipMismatch
    case modeUnknown
    case modeMismatch
    /// Effective access control was not enumerated, so whether another principal
    /// can write here is unknown.
    case accessControlUnknown
    /// An effective access control entry grants write access to a principal
    /// other than the POSIX owner.
    case accessControlGrantsOtherPrincipals
    /// The artifact is executable and no valid code signature was observed over
    /// its bytes.
    case codeSignatureInvalid
    /// The artifact is executable and its signature was never verified.
    case codeSignatureUnknown
    case contentUnknown
    case contentMismatch
    /// The artifact's bytes exceeded the bounded read they were given.
    case exceededSizeLimit
}

public extension PlannedFileArtifact {
    /// Returns nil when the observation matches this plan exactly, and otherwise
    /// the first reason it does not. An unreadable field fails as `unknown`; it
    /// never passes and never silently becomes a default.
    func validationFailure(against observation: FileArtifactObservation) -> ArtifactValidationFailure? {
        switch observation {
        case .queryFailed:
            return .observationFailed
        case .confirmedAbsent:
            return .absent
        case let .present(state):
            if state.kind == .symbolicLink { return .symbolicLink }
            guard state.kind == expectedFileKind else { return .wrongFileKind }
            guard let uid = state.uid, let gid = state.gid else { return .ownershipUnknown }
            guard uid == ownership.uid, gid == ownership.gid else { return .ownershipMismatch }
            guard let bits = state.modeBits else { return .modeUnknown }
            guard bits == mode.rawValue else { return .modeMismatch }
            switch state.accessControl {
            case .noWriteGrantsBeyondOwner: break
            case .unknown: return .accessControlUnknown
            case .grantsWriteToOtherPrincipals: return .accessControlGrantsOtherPrincipals
            }
            if let expected = contentSHA256 {
                guard let observed = state.contentSHA256 else { return .contentUnknown }
                guard observed == expected else { return .contentMismatch }
            }
            // An executable is the one artifact whose *contents* are code this
            // machine will run, so the local ad-hoc signing policy has to be a
            // property something checks rather than a claim about the build.
            // The digest above already fixes the bytes; this asks whether those
            // bytes are signed at all.
            if kind == .filterExecutable {
                switch state.codeSignature {
                case .valid: break
                case .invalidOrAbsent: return .codeSignatureInvalid
                case .unknown: return .codeSignatureUnknown
                }
            }
            return nil
        }
    }
}

// MARK: - Durable ownership record

public enum QueueInstallationRecordedPhase: String, Equatable, Sendable, CaseIterable {
    case inProgress = "in-progress"
    case completed
    case rolledBack = "rolled-back"
    case residual
}

/// The durable record naming every artifact the transaction created, plus the
/// one it is *about to* create, so recovery is finite and a human can recover
/// from evidence rather than from guesswork.
///
/// The pending entry exists because an effect and the note of it cannot happen
/// at the same instant. A step is written as pending *before* the effect runs
/// and moved to created afterwards, so an interruption at the worst moment
/// leaves an artifact whose existence is unknown but whose *name* is recorded.
/// Recovery probes a pending artifact and never assumes it was not created.
///
/// The encoding is a fixed, canonical line sequence, and decoding is strict: an
/// unknown key, a duplicate key, a reordered section, a non-canonical integer, a
/// phase that contradicts the artifact list, or any input whose re-encoding
/// differs by a single byte fails closed rather than being partly believed.
public struct QueueInstallationOwnershipRecord: Equatable, Sendable {
    public static let schemaVersion = 4
    public static let maximumFileArtifacts = 8
    public static let maximumCreatedArtifacts = 16
    public static let maximumEncodedByteCount = 16 * 1024

    public let transactionID: QueueInstallationTransactionID
    /// The whole intent this record describes, not a loose list of paths.
    ///
    /// A record is reached from the outside — it is decoded from a file that a
    /// hostile or merely wrong process may have written — and a record-validated
    /// recovery deletes what it names. Holding the intent means the four-artifact
    /// topology, the containment of every payload one component below the
    /// protected root, and the queue's typed destination are all established by
    /// the same initializer that establishes them for a live transaction, rather
    /// than re-checked (or forgotten) here.
    public let intent: QueueInstallationIntent
    /// The incarnation token confirmed for this transaction's own queue.
    /// Removal requires an exact match against it.
    public let queueIncarnation: SchedulerQueueIncarnation?
    /// The token this transaction is *about to* write into a queue it is
    /// creating, recorded with the pending queue step and therefore before the
    /// create effect runs.
    ///
    /// Without it, a crash between `createQueue` returning and the confirming
    /// journal write left a live queue no conditional removal could ever match,
    /// so the queue and every payload beneath it stayed residual for good. With
    /// it, recovery has the one value that identifies that queue.
    ///
    /// It says nothing else. It does not mean the queue exists, and it is not
    /// an acquisition: `queueAcquisition` stays `nil` until a readback confirms
    /// the queue, and `exclusiveCreation` remains the only thing that can make
    /// a record complete.
    public let pendingQueueIncarnation: SchedulerQueueIncarnation?
    /// What the create operation could prove about acquiring the name.
    public let queueAcquisition: SchedulerQueueAcquisition?
    public let phase: QueueInstallationRecordedPhase
    /// The step whose effect was about to run. Its existence is unknown.
    public let pendingArtifact: QueueInstallationArtifactID?
    /// The subset confirmed created, a prefix of the planned creation order.
    public let createdArtifacts: [QueueInstallationArtifactID]

    public var queue: PlannedSchedulerQueue { intent.queue }
    /// Where this transaction's queue was asked to deliver. Bound here so that a
    /// later observation can be required to match it exactly.
    public var destination: QueueDestination { intent.destination }
    /// Which printer description this transaction's queue was asked to be built
    /// from. Derived from the intent, so it needs no separate encoding and
    /// cannot drift from the artifact the transaction staged.
    public var queueDescriptionIdentity: SchedulerQueueDescriptionIdentity? {
        try? SchedulerQueueDescriptionIdentity(describedBy: intent.printerDescription)
    }
    /// Which executable this transaction's queue was asked to run.
    ///
    /// Derived from the intent's filter rather than encoded separately, because
    /// the intent cannot exist unless its description declared exactly that
    /// filter — so a second copy in the journal could only ever agree, or be a
    /// second answer to a settled question.
    ///
    /// That the declaration was truthful is an obligation discharged by
    /// whoever built the intent, and a decoded journal has no declarant to
    /// discharge it again. This is sound in the direction a record is used: a
    /// record-validated recovery only ever *removes*, and removing is refused
    /// unless the live queue matches this value as well.
    public var queueFilterBinding: PrinterDescriptionFilterBinding? {
        try? PrinterDescriptionFilterBinding(invoking: intent.filter)
    }
    /// Every planned file artifact, in the order the transaction would create them.
    public var files: [PlannedFileArtifact] { intent.creationOrderedFiles }
    /// Every artifact this transaction may ever own, in creation order.
    public var plannedArtifactIDs: [QueueInstallationArtifactID] {
        files.map { .file($0.path) } + [.schedulerQueue]
    }

    private init(
        validated transactionID: QueueInstallationTransactionID,
        intent: QueueInstallationIntent,
        queueIncarnation: SchedulerQueueIncarnation?,
        pendingQueueIncarnation: SchedulerQueueIncarnation?,
        queueAcquisition: SchedulerQueueAcquisition?,
        phase: QueueInstallationRecordedPhase,
        pendingArtifact: QueueInstallationArtifactID?,
        createdArtifacts: [QueueInstallationArtifactID]
    ) {
        self.transactionID = transactionID
        self.intent = intent
        self.queueIncarnation = queueIncarnation
        self.pendingQueueIncarnation = pendingQueueIncarnation
        self.queueAcquisition = queueAcquisition
        self.phase = phase
        self.pendingArtifact = pendingArtifact
        self.createdArtifacts = createdArtifacts
    }

    public init(
        transactionID: QueueInstallationTransactionID,
        intent: QueueInstallationIntent,
        queueIncarnation: SchedulerQueueIncarnation? = nil,
        pendingQueueIncarnation: SchedulerQueueIncarnation? = nil,
        queueAcquisition: SchedulerQueueAcquisition? = nil,
        phase: QueueInstallationRecordedPhase,
        pendingArtifact: QueueInstallationArtifactID? = nil,
        createdArtifacts: [QueueInstallationArtifactID]
    ) throws {
        let files = intent.creationOrderedFiles
        guard (1...Self.maximumFileArtifacts).contains(files.count) else {
            throw QueueInstallationError.tooManyArtifacts
        }
        guard createdArtifacts.count <= Self.maximumCreatedArtifacts else {
            throw QueueInstallationError.tooManyArtifacts
        }
        // The aggregate encoding, not just the counts and the path lengths.
        // This is checked against the intent's *worst* case rather than this
        // record's current one, because the encoding grows as steps are
        // confirmed: a record that fitted while empty and stopped fitting three
        // artifacts later would fail in the middle of staging, after effects had
        // already run. Refusing the whole shape up front means the first record
        // a transaction builds is the one that refuses, before any effect and
        // therefore before anything is persisted.
        guard Self.maximumCanonicalByteCount(for: intent) <= Self.maximumEncodedByteCount else {
            throw QueueInstallationError.ownershipRecordTooLarge
        }
        let plannedPaths = Set(files.map(\.path))
        var seenCreated = Set<QueueInstallationArtifactID>()
        for created in createdArtifacts {
            guard seenCreated.insert(created).inserted else { throw QueueInstallationError.duplicateArtifactPath }
            if case let .file(path) = created {
                guard plannedPaths.contains(path) else { throw QueueInstallationError.notOwnedByTransaction }
            }
        }
        if let pendingArtifact {
            // A pending step is one this transaction planned and has not yet
            // confirmed. It cannot already be created.
            guard !seenCreated.contains(pendingArtifact) else { throw QueueInstallationError.duplicateArtifactPath }
            if case let .file(path) = pendingArtifact {
                guard plannedPaths.contains(path) else { throw QueueInstallationError.notOwnedByTransaction }
            }
        }
        // Recovery reverses this list, so the order it is written in decides the
        // order artifacts are destroyed in. A permutation such as
        // `[root, filter, journal]` would remove the journal before the filter
        // and so destroy the durable evidence for what is still outstanding. A
        // transaction only ever creates artifacts in the planned order, so what
        // it has created is always a prefix of that order, and what is pending is
        // always the step immediately after it. Anything else did not come from a
        // transaction and is refused rather than executed.
        let plannedIDs = files.map { QueueInstallationArtifactID.file($0.path) } + [.schedulerQueue]
        guard createdArtifacts.count <= plannedIDs.count,
              Array(plannedIDs.prefix(createdArtifacts.count)) == createdArtifacts else {
            throw QueueInstallationError.createdArtifactsOutOfOrder
        }
        if let pendingArtifact {
            guard createdArtifacts.count < plannedIDs.count,
                  plannedIDs[createdArtifacts.count] == pendingArtifact else {
                throw QueueInstallationError.createdArtifactsOutOfOrder
            }
        }
        let createdQueue = seenCreated.contains(.schedulerQueue)
        // An incarnation or an acquisition can only describe a queue this
        // transaction created, and they are recorded together.
        guard (queueIncarnation == nil) == (queueAcquisition == nil) else {
            throw QueueInstallationError.inconsistentRecordPhase
        }
        guard queueIncarnation == nil || createdQueue else {
            throw QueueInstallationError.inconsistentRecordPhase
        }
        // An *intended* incarnation describes the queue step that is in flight
        // and nothing else. It belongs to a pending queue, never to a created
        // one, and it never stands in for the confirmed token: a record cannot
        // hold both, so nothing can read an intention as a confirmation.
        if pendingQueueIncarnation != nil {
            guard pendingArtifact == .schedulerQueue else {
                throw QueueInstallationError.inconsistentRecordPhase
            }
            guard queueIncarnation == nil, queueAcquisition == nil else {
                throw QueueInstallationError.inconsistentRecordPhase
            }
        }
        switch phase {
        case .completed:
            // Completion means every planned artifact exists, in the order it
            // was planned, with nothing pending, the queue identified, and the
            // name provably acquired. Anything less is in progress or residual.
            let expected = files.map { QueueInstallationArtifactID.file($0.path) } + [.schedulerQueue]
            guard createdArtifacts == expected, pendingArtifact == nil,
                  queueIncarnation != nil, queueAcquisition == .exclusiveCreation else {
                throw QueueInstallationError.inconsistentRecordPhase
            }
        case .rolledBack:
            // Rolled back means nothing of this transaction remains, and nothing
            // is left in the unknown pending state either.
            guard createdArtifacts.isEmpty, pendingArtifact == nil else {
                throw QueueInstallationError.inconsistentRecordPhase
            }
        case .inProgress, .residual:
            break
        }
        self.transactionID = transactionID
        self.intent = intent
        self.queueIncarnation = queueIncarnation
        self.pendingQueueIncarnation = pendingQueueIncarnation
        self.queueAcquisition = queueAcquisition
        self.phase = phase
        self.pendingArtifact = pendingArtifact
        self.createdArtifacts = createdArtifacts
    }

    /// The token that identifies this transaction's queue object, whether it
    /// was confirmed or only intended. Recovery needs one value to match a
    /// present queue against; it must not need to know which of the two moments
    /// the transaction died in.
    ///
    /// Reading this is never permission to remove anything. Authority,
    /// destination and description are all checked separately, and an intended
    /// token still says nothing about who acquired the name.
    public var identifyingQueueIncarnation: SchedulerQueueIncarnation? {
        queueIncarnation ?? pendingQueueIncarnation
    }

    public func artifact(for id: QueueInstallationArtifactID) -> PlannedFileArtifact? {
        guard case let .file(path) = id else { return nil }
        return files.first { $0.path == path }
    }

    /// The journal this record lives in. Recovery needs it to read its own
    /// evidence back and to shorten it as it proceeds. It is not optional,
    /// because the record carries a whole intent and every intent has one.
    public var journalArtifact: PlannedFileArtifact { intent.ownershipRecord }

    /// Created artifacts plus the pending one, in creation order. This is what
    /// recovery must cover: a pending step may or may not exist, and assuming it
    /// does not is exactly the mistake that leaves an orphan.
    public var ownedArtifactsInCreationOrder: [QueueInstallationArtifactID] {
        createdArtifacts + (pendingArtifact.map { [$0] } ?? [])
    }

    public func owns(_ id: QueueInstallationArtifactID) -> Bool {
        createdArtifacts.contains(id) || pendingArtifact == id
    }

    /// A phase must stay consistent with what the record says it created, so
    /// this revalidates rather than assuming.
    public func replacingPhase(_ phase: QueueInstallationRecordedPhase) throws -> Self {
        try Self(
            transactionID: transactionID, intent: intent,
            queueIncarnation: queueIncarnation,
            pendingQueueIncarnation: pendingQueueIncarnation,
            queueAcquisition: queueAcquisition,
            phase: phase, pendingArtifact: pendingArtifact,
            createdArtifacts: createdArtifacts
        )
    }

    /// `residual` places no requirement on the artifact list — it exists exactly
    /// to describe a state nobody can vouch for — so this cannot fail and does
    /// not need a throwing caller.
    public func markingResidual() -> Self {
        Self(
            validated: transactionID, intent: intent,
            queueIncarnation: queueIncarnation,
            pendingQueueIncarnation: pendingQueueIncarnation,
            queueAcquisition: queueAcquisition,
            phase: .residual, pendingArtifact: pendingArtifact,
            createdArtifacts: createdArtifacts
        )
    }

    /// Names the step whose effect is about to run. Written durably *before* the
    /// effect, so an interruption cannot hide it.
    ///
    /// For the queue step that is not enough on its own: the name of a queue is
    /// not an identity, so a record that names a pending queue without the
    /// token it is about to write describes an object nothing can later pick
    /// out. `intendedQueueIncarnation` is that token, and it is recorded with
    /// the pending mark — before the effect — for exactly the reason the mark
    /// itself is.
    public func markingPending(
        _ id: QueueInstallationArtifactID,
        intendedQueueIncarnation intended: SchedulerQueueIncarnation? = nil
    ) throws -> Self {
        try Self(
            transactionID: transactionID, intent: intent,
            queueIncarnation: queueIncarnation,
            pendingQueueIncarnation: intended,
            queueAcquisition: queueAcquisition,
            phase: phase, pendingArtifact: id,
            createdArtifacts: createdArtifacts
        )
    }

    /// Promotes the pending step to created, once its effect has been confirmed.
    public func confirmingPending(
        queueIncarnation incarnation: SchedulerQueueIncarnation? = nil,
        queueAcquisition acquisition: SchedulerQueueAcquisition? = nil
    ) throws -> Self {
        guard let pendingArtifact else { throw QueueInstallationError.invalidPhase }
        // Nothing is pending afterwards, so neither is an intended token: from
        // here the queue is identified by the one that was read back, or by
        // nothing at all.
        return try Self(
            transactionID: transactionID, intent: intent,
            queueIncarnation: incarnation ?? queueIncarnation,
            pendingQueueIncarnation: nil,
            queueAcquisition: acquisition ?? queueAcquisition,
            phase: phase, pendingArtifact: nil,
            createdArtifacts: createdArtifacts + [pendingArtifact]
        )
    }

    /// Drops an artifact that is confirmed gone, and with the queue its
    /// incarnation and acquisition. This is what makes a second recovery pass
    /// idempotent rather than a second deletion.
    ///
    /// Shortening the list cannot break the `in-progress`, `residual` or
    /// `rolled-back` rules, but it can contradict `completed`, which asserts
    /// that everything planned exists. A record that loses an artifact is
    /// therefore no longer complete, and says so.
    public func removingCreatedArtifact(_ id: QueueInstallationArtifactID) -> Self {
        let droppedQueue = id == .schedulerQueue
        return Self(
            validated: transactionID, intent: intent,
            queueIncarnation: droppedQueue ? nil : queueIncarnation,
            pendingQueueIncarnation: pendingArtifact == id ? nil : pendingQueueIncarnation,
            queueAcquisition: droppedQueue ? nil : queueAcquisition,
            phase: phase == .completed ? .inProgress : phase,
            pendingArtifact: pendingArtifact == id ? nil : pendingArtifact,
            createdArtifacts: createdArtifacts.filter { $0 != id }
        )
    }

    /// The largest canonical encoding **any** record over `intent` can ever
    /// produce, in bytes.
    ///
    /// This exists because the record's own bound and the bound every read of
    /// it carries are the same number, and nothing used to compare the two. The
    /// initializer checked counts and path lengths; the reader checked an
    /// aggregate. With the allowlist at `maximumPermittedParents` and paths near
    /// `AbsolutePath.maximumByteCount`, a record passed the initializer, was
    /// persisted, and was then rejected as oversized by every subsequent bounded
    /// read — including `QueueInstallationRecovery.load` — stranding whatever it
    /// named. A journal nothing can read back is worse than no journal, because
    /// the artifacts exist either way.
    ///
    /// Every line is `key=value` plus one newline, so the bound is a sum of
    /// known widths. With `P` permitted parents and the four files an intent
    /// always has:
    ///
    ///     fixed   = the nine header lines, each key plus its *longest*
    ///               possible value plus 1
    ///     parents = P x (23 + |parent| + 1)          // "permittedStagingParent="
    ///     files   = sum over files of
    ///               5 + |kind| + 1 + |path| + 1 + 10 + 1 + 10 + 1 + 4 + 1 + 64 + 1
    ///     created = sum over the F+1 planned identifiers of 8 + |spelling| + 1
    ///
    /// `10` is the widest decimal uid or gid, since `POSIXOwnership` bounds both
    /// at `Int32.max` = 2147483647; `4` is `POSIXMode.octalText`'s fixed width;
    /// `64` is a lowercase SHA-256 and `32` a transaction identifier.
    ///
    /// The bound is deliberately not reachable. It gives `queueIncarnation`,
    /// `pendingQueueIncarnation`, `queueAcquisition` and `pending` their longest
    /// spellings at once, and lists every planned artifact as created, although
    /// the validating initializer would reject that combination: a pending queue
    /// may not also carry a confirmed token. An upper bound that is only correct
    /// for reachable states is not an upper bound. Erring long refuses a
    /// borderline intent a little early; erring short strands a journal, so this
    /// is the side to be wrong on.
    ///
    /// Worked worst case, for the record: 8 parents of 1024 bytes is 8384, four
    /// files of 1024-byte paths is about 4572, five created identifiers is about
    /// 5165, and the header about 1487 — roughly 19.6 KiB against a 16 KiB cap.
    /// The bound is therefore not decorative; it refuses real shapes.
    public static func maximumCanonicalByteCount(for intent: QueueInstallationIntent) -> Int {
        let sha256Width = 64
        let identifierWidth = 10
        let modeWidth = 4
        let plannedIDs = intent.creationOrderedFiles.map { QueueInstallationArtifactID.file($0.path) }
            + [QueueInstallationArtifactID.schedulerQueue]
        let longestIDSpelling = plannedIDs.map { encode(artifact: $0).utf8.count }.max() ?? 1
        let longestAcquisition = SchedulerQueueAcquisition.allCases
            .map(\.rawValue.utf8.count).max() ?? 1
        let longestPhase = QueueInstallationRecordedPhase.allCases
            .map(\.rawValue.utf8.count).max() ?? 1

        var total = 0
        func line(_ key: String, _ valueWidth: Int) { total += key.utf8.count + 1 + valueWidth + 1 }
        line("schemaVersion", String(schemaVersion).utf8.count)
        line("transactionID", 32)
        line("queue", intent.queue.name.utf8.count)
        line("queueDestination", intent.destination.canonicalText.utf8.count)
        line("queueIncarnation", sha256Width)
        line("queueAcquisition", longestAcquisition)
        line("phase", longestPhase)
        line("pending", longestIDSpelling)
        line("pendingQueueIncarnation", sha256Width)
        for parent in intent.stagingPolicy.permittedStagingParents {
            line("permittedStagingParent", parent.value.utf8.count)
        }
        for file in intent.creationOrderedFiles {
            // kind|path|uid|gid|mode|digest, five separators.
            line("file", file.kind.rawValue.utf8.count + file.path.value.utf8.count
                + identifierWidth + identifierWidth + modeWidth + sha256Width + 5)
        }
        for id in plannedIDs {
            line("created", encode(artifact: id).utf8.count)
        }
        return total
    }

    /// Retracts the pending mark for a step whose effect provably did not run.
    ///
    /// This is **not** the same as dropping a created artifact, and it is not
    /// the same as a step whose outcome is unknown. A pending entry exists to
    /// say "this path may hold something of ours, so probe it"; recovery
    /// therefore treats a pending artifact as owned, and deletes what it finds
    /// there once that thing matches the plan. Only an answer that *guarantees*
    /// the seam modified nothing may retract the mark —
    /// `FileArtifactCreation.alreadyPresent` is that answer, and
    /// `FileArtifactCreation.unknown` is precisely not, so it keeps its mark.
    ///
    /// Without the retraction, a foreign file sitting at a planned path — one
    /// whose metadata, mode, digest and signature all match the plan, because
    /// that is exactly the case validation cannot tell apart from our own work —
    /// is deleted by the next automatic rollback. Conserving ownership in that
    /// direction is what this model claims, so the mark has to go.
    ///
    /// Dropping the pending step can never contradict a phase: `completed` and
    /// `rolledBack` both already require nothing pending, and `inProgress` and
    /// `residual` place no requirement on it. It also only ever shortens the
    /// encoding, so it cannot cross the aggregate size bound.
    public func retractingPendingArtifact() -> Self {
        Self(
            validated: transactionID, intent: intent,
            queueIncarnation: queueIncarnation,
            pendingQueueIncarnation: nil,
            queueAcquisition: queueAcquisition,
            phase: phase, pendingArtifact: nil,
            createdArtifacts: createdArtifacts
        )
    }

    public var canonicalText: String {
        var lines: [String] = []
        lines.append("schemaVersion=\(Self.schemaVersion)")
        lines.append("transactionID=\(transactionID.hex)")
        lines.append("queue=\(queue.name)")
        lines.append("queueDestination=\(destination.canonicalText)")
        lines.append("queueIncarnation=\(queueIncarnation?.token ?? "-")")
        lines.append("queueAcquisition=\(queueAcquisition?.rawValue ?? "-")")
        lines.append("phase=\(phase.rawValue)")
        lines.append("pending=\(pendingArtifact.map(Self.encode(artifact:)) ?? "-")")
        lines.append("pendingQueueIncarnation=\(pendingQueueIncarnation?.token ?? "-")")
        for parent in intent.stagingPolicy.permittedStagingParents {
            lines.append("permittedStagingParent=\(parent.value)")
        }
        for file in files {
            let fields = [
                file.kind.rawValue,
                file.path.value,
                String(file.ownership.uid),
                String(file.ownership.gid),
                file.mode.octalText,
                file.contentSHA256 ?? "-",
            ]
            lines.append("file=" + fields.joined(separator: "|"))
        }
        for created in createdArtifacts {
            lines.append("created=" + Self.encode(artifact: created))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func encode(artifact: QueueInstallationArtifactID) -> String {
        switch artifact {
        case .schedulerQueue: "queue"
        case let .file(path): path.value
        }
    }

    private static func decode(artifact value: String) throws -> QueueInstallationArtifactID {
        value == "queue" ? .schedulerQueue : .file(try AbsolutePath(value))
    }

    public static func decode(_ text: String) throws -> Self {
        guard text.utf8.count <= maximumEncodedByteCount, text.hasSuffix("\n") else {
            throw QueueInstallationError.invalidRecord
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.last == "" else { throw QueueInstallationError.invalidRecord }
        lines.removeLast()
        // Nine fixed lines, at least one permitted staging parent, and the four
        // files an intent is made of.
        guard lines.count >= 14 else { throw QueueInstallationError.invalidRecord }

        func field(_ line: Substring, _ key: String) throws -> String {
            let prefix = key + "="
            guard line.hasPrefix(prefix) else { throw QueueInstallationError.invalidRecord }
            return String(line.dropFirst(prefix.count))
        }

        guard try field(lines[0], "schemaVersion") == String(schemaVersion) else {
            throw QueueInstallationError.invalidRecord
        }
        let transactionID = try QueueInstallationTransactionID(hex: field(lines[1], "transactionID"))
        let queue = try PlannedSchedulerQueue(name: field(lines[2], "queue"))
        let destination = try QueueDestination.decode(field(lines[3], "queueDestination"))
        let incarnationField = try field(lines[4], "queueIncarnation")
        let incarnation = incarnationField == "-"
            ? nil : try SchedulerQueueIncarnation(token: incarnationField)
        let acquisitionField = try field(lines[5], "queueAcquisition")
        var acquisition: SchedulerQueueAcquisition?
        if acquisitionField != "-" {
            guard let parsed = SchedulerQueueAcquisition(rawValue: acquisitionField) else {
                throw QueueInstallationError.invalidRecord
            }
            acquisition = parsed
        }
        guard let phase = QueueInstallationRecordedPhase(rawValue: try field(lines[6], "phase")) else {
            throw QueueInstallationError.invalidRecord
        }
        let pendingField = try field(lines[7], "pending")
        let pending = pendingField == "-" ? nil : try decode(artifact: pendingField)
        let intendedField = try field(lines[8], "pendingQueueIncarnation")
        let intended = intendedField == "-"
            ? nil : try SchedulerQueueIncarnation(token: intendedField)

        var index = 9
        var permittedParents: [AbsolutePath] = []
        while index < lines.count, lines[index].hasPrefix("permittedStagingParent=") {
            guard permittedParents.count < QueueInstallationStagingPolicy.maximumPermittedParents else {
                throw QueueInstallationError.tooManyArtifacts
            }
            permittedParents.append(try AbsolutePath(field(lines[index], "permittedStagingParent")))
            index += 1
        }
        // The policy's own initializer refuses an empty allowlist and every
        // system-critical tree, so a journal arriving from outside this process
        // cannot declare one either.
        let stagingPolicy = try QueueInstallationStagingPolicy(
            permittedStagingParents: permittedParents
        )
        var files: [PlannedFileArtifact] = []
        while index < lines.count, lines[index].hasPrefix("file=") {
            guard files.count < maximumFileArtifacts else { throw QueueInstallationError.tooManyArtifacts }
            files.append(try decodeFile(field(lines[index], "file")))
            index += 1
        }
        var created: [QueueInstallationArtifactID] = []
        while index < lines.count, lines[index].hasPrefix("created=") {
            guard created.count < maximumCreatedArtifacts else { throw QueueInstallationError.tooManyArtifacts }
            created.append(try decode(artifact: field(lines[index], "created")))
            index += 1
        }
        // Any remaining line is an unknown key, a reordered section or trailing
        // junk. A record that is not exactly canonical is not believed at all.
        guard index == lines.count else { throw QueueInstallationError.invalidRecord }
        // A decoded file list is not an inventory until it *is* one. The record
        // is rebuilt through `QueueInstallationIntent`, which is the same
        // initializer a live transaction goes through, so a journal listing a
        // fifth artifact, a missing journal, a swapped pair of kinds, or a
        // root-owned file that lives somewhere other than one component below
        // this transaction's protected root cannot hydrate a record-validated
        // recovery and license deleting it.
        guard files.count == 4,
              files[0].kind == .protectedRoot, files[1].kind == .ownershipRecord,
              files[2].kind == .filterExecutable, files[3].kind == .printerDescription else {
            throw QueueInstallationError.recordInventoryMismatch
        }
        // The binding is derived from the decoded filter rather than read from
        // the journal, because it is not separately encoded: see
        // `queueFilterBinding`. A decoded record therefore satisfies the
        // intent's check by construction, which is the honest outcome — there
        // is no declarant on this side to hold to a declaration, and a journal
        // asserting one would only be asserting about itself.
        let intent = try QueueInstallationIntent(
            queue: queue, destination: destination,
            protectedRoot: files[0], ownershipRecord: files[1],
            filter: files[2], printerDescription: files[3],
            descriptionInvokesFilter: try PrinterDescriptionFilterBinding(invoking: files[2]),
            stagingPolicy: stagingPolicy
        )
        let record = try Self(
            transactionID: transactionID, intent: intent,
            queueIncarnation: incarnation, pendingQueueIncarnation: intended,
            queueAcquisition: acquisition,
            phase: phase, pendingArtifact: pending,
            createdArtifacts: created
        )
        // One canonical spelling per record. Anything that decodes but would
        // re-encode differently is a second byte representation of the same
        // claim, which would defeat comparing records by their bytes.
        guard record.canonicalText == text else { throw QueueInstallationError.invalidRecord }
        return record
    }

    private static func decodeFile(_ value: String) throws -> PlannedFileArtifact {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 6 else { throw QueueInstallationError.invalidRecord }
        guard let kind = QueueInstallationArtifactKind(rawValue: String(parts[0])) else {
            throw QueueInstallationError.invalidRecord
        }
        let path = try AbsolutePath(String(parts[1]))
        guard let uid = canonicalDecimal(parts[2]), let gid = canonicalDecimal(parts[3]) else {
            throw QueueInstallationError.invalidRecord
        }
        let ownership = try POSIXOwnership(uid: uid, gid: gid)
        let mode = try POSIXMode.decodeOctal(String(parts[4]))
        let digest = parts[5] == "-" ? nil : String(parts[5])
        return try PlannedFileArtifact(
            kind: kind, path: path, ownership: ownership, mode: mode, contentSHA256: digest
        )
    }
}

// MARK: - Recovery ordering

/// Recovery is queue-first by construction. A partial failure must never leave a
/// live queue pointing at a removed filter, so the queue step, when present, is
/// the first step; the protected root, when present, is the last. Both rules are
/// enforced by the initializer, so a wrongly ordered recovery plan is not a
/// value this type can hold.
///
/// Ordering is all this type can enforce. *Completeness* is a question about a
/// particular record, so a recovery additionally requires that a supplied plan
/// is exactly the one its own record derives — an empty or partial plan recovers
/// nothing and must never be mistaken for a rollback.
public struct QueueInstallationRecoveryPlan: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case removeQueue(PlannedSchedulerQueue)
        case removeFile(PlannedFileArtifact)

        public var artifactID: QueueInstallationArtifactID {
            switch self {
            case .removeQueue: .schedulerQueue
            case let .removeFile(artifact): .file(artifact.path)
            }
        }
    }

    public let steps: [Step]

    public init(steps: [Step]) throws {
        guard steps.count <= QueueInstallationOwnershipRecord.maximumCreatedArtifacts else {
            throw QueueInstallationError.tooManyArtifacts
        }
        var seen = Set<QueueInstallationArtifactID>()
        for step in steps {
            guard seen.insert(step.artifactID).inserted else { throw QueueInstallationError.duplicateArtifactPath }
        }
        if let queueIndex = steps.firstIndex(where: {
            if case .removeQueue = $0 { return true }
            return false
        }) {
            guard queueIndex == 0 else { throw QueueInstallationError.recoveryOrderingViolation }
        }
        if let rootIndex = steps.firstIndex(where: {
            if case let .removeFile(artifact) = $0 { return artifact.kind == .protectedRoot }
            return false
        }) {
            guard rootIndex == steps.count - 1 else { throw QueueInstallationError.recoveryOrderingViolation }
        }
        self.steps = steps
    }

    /// Reverses the record's creation order — created artifacts *and* the
    /// pending one — which puts the queue first and the protected root last,
    /// then re-checks that ordering through `init(steps:)`.
    public init(record: QueueInstallationOwnershipRecord) throws {
        var steps: [Step] = []
        for id in record.ownedArtifactsInCreationOrder.reversed() {
            switch id {
            case .schedulerQueue:
                steps.append(.removeQueue(record.queue))
            case .file:
                guard let artifact = record.artifact(for: id) else {
                    throw QueueInstallationError.notOwnedByTransaction
                }
                steps.append(.removeFile(artifact))
            }
        }
        try self.init(steps: steps)
    }
}
