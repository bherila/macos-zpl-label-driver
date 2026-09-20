import Foundation

/// Produces a 64-character lowercase hexadecimal SHA-256 digest of the supplied
/// bytes.
///
/// The digest is a seam rather than an implementation in this package for two
/// reasons. LabelCore carries no dependencies and has to build and test on a
/// non-Apple host, where CryptoKit does not exist; and the alternative -- a
/// private SHA-256 written here -- would place unaudited cryptographic code on
/// the one path that stands between a device serial number and everything that
/// is logged, stored or displayed. The production conformance lives in LabelMac
/// and is CryptoKit.
///
/// A conformance is not trusted. Qualification rejects any return value that is
/// not exactly 64 lowercase hexadecimal characters, so a wrong, truncated or
/// hostile digest yields a reported failure rather than an identity.
public protocol StableIdentityDigest: Sendable {
    func hexDigest(_ bytes: [UInt8]) -> String
}

/// What a read-only registry scan found where a USB serial number would be.
///
/// The three outcomes are kept apart on purpose. "The device published no
/// serial-number property" and "a property was there but this code could not
/// turn it into a usable string" are different facts about different problems,
/// and neither is "the serial number is empty". None of them is a serial
/// number, so none of them qualifies; but each is reported as itself.
///
/// The reported text is stored in a payload that is `internal` to LabelCore, so
/// a caller in another module can construct a reading and hand it to
/// qualification but cannot read the serial number back out of it. The
/// `RedactedDiagnosticValue` conformance keeps it out of `dump`, `description`
/// and structural reflection as well.
public struct USBSerialNumberReading: Equatable, Sendable, RedactedDiagnosticValue {
    enum Payload: Equatable, Sendable {
        case absent
        case unreadable
        case reported(String)
    }

    let payload: Payload

    private init(payload: Payload) { self.payload = payload }

    /// The registry entry published no serial-number property at all.
    public static let absent = Self(payload: .absent)

    /// A property was present but was not a string this code could accept.
    public static let unreadable = Self(payload: .unreadable)

    /// A serial-number string was read. Qualification still decides whether it
    /// is usable; reading one is not the same as qualifying one.
    public static func reported(_ text: String) -> Self { Self(payload: .reported(text)) }

    /// True when a string was read, whatever qualification later makes of it.
    /// This is a fact about the scan, never about identity.
    public var isReported: Bool {
        if case .reported = payload { return true }
        return false
    }
}

/// A stable identity derived from a qualified USB observation, together with
/// the model identifiers that were part of its derivation.
///
/// The vendor and product identifiers are kept because they are not secret and
/// a caller may legitimately show them; the identity itself stays opaque and
/// redacted, and the serial number it was derived from is not stored anywhere
/// in this value.
public struct QualifiedUSBDeviceIdentity: Equatable, Sendable, RedactedDiagnosticValue {
    public let identity: StableConnectionIdentity
    public let vendorID: UInt16
    public let productID: UInt16

    init(identity: StableConnectionIdentity, vendorID: UInt16, productID: UInt16) {
        self.identity = identity
        self.vendorID = vendorID
        self.productID = productID
    }
}

/// Decides whether a read-only USB observation amounts to a stable per-unit
/// identity, and derives an opaque identity when it does.
///
/// A USB vendor and product identifier name a *model*. Two GC420d units on the
/// same desk publish the same pair, so that pair cannot distinguish them, and
/// an IORegistry entry ID is scoped to the current session and does not survive
/// a replug or a reboot. The only field in read-only registry metadata that a
/// vendor intends to be per-unit and persistent is the serial-number string.
///
/// That the string is per-unit is a vendor claim. This code cannot verify it,
/// and says so rather than implying a guarantee. What it can do is refuse the
/// values that are definitely not per-unit, and refuse to produce an identity
/// at all when nothing usable was read.
public enum USBIdentityQualification {
    /// Why an observation did not become a stable identity.
    ///
    /// Each case is a distinct, reportable outcome. None of them is silently a
    /// `false`, a zero, or an unobserved identity that a later reader would
    /// mistake for "not applicable".
    public enum Failure: Error, Equatable, Sendable {
        /// The device published no serial-number property.
        case serialNumberAbsent
        /// A serial-number property existed but was not a usable string.
        case serialNumberUnreadable
        /// The string was empty, or was nothing but whitespace.
        case serialNumberEmpty
        /// The string held a character outside printable ASCII.
        case serialNumberUnprintable
        /// The string was longer than a USB string descriptor can carry.
        case serialNumberTooLong
        /// The string carries no per-unit information, such as `00000000`.
        case serialNumberNotUnitDistinct
        /// The supplied digest did not return 64 lowercase hexadecimal characters.
        case digestMalformed
        /// The derived value was refused by `StableConnectionIdentity`.
        case identityRejected
    }

    /// Domain separator. It binds a digest to this derivation and this version
    /// of it, so a digest computed for some other purpose over the same bytes
    /// can never be mistaken for a device identity, and a future change to the
    /// derivation can be given its own separator instead of silently producing
    /// different identities under the same scheme name.
    static let domainSeparator = "LABEL_USB_STABLE_IDENTITY_V1"

    /// Names the derivation inside the opaque value. It reveals the scheme, not
    /// the device: every unit of every model shares this prefix.
    public static let opaqueValuePrefix = "usb-sha256-"

    /// A USB string descriptor carries at most 126 UTF-16 code units.
    static let maximumSerialNumberCharacters = 126

    /// A registry observation made by this installation on this Mac.
    ///
    /// This was `reportedInstallation` when the qualification path landed,
    /// because `CapabilityEvidence` had no case meaning "this host read it
    /// from the device". That stored a fact this Mac read out of the I/O
    /// Registry with the same provenance as a fact a person typed, which is
    /// the conflation #131 raised.
    ///
    /// It is deliberately not `documentedModel`, because no published document
    /// states a particular unit's serial number, and not `unobserved`, which
    /// profile validation rejects for an observation.
    public static let evidence: CapabilityEvidence =
        .observedByHost(method: .ioRegistryProperty)

    /// Qualifies an observation, or throws the specific reason it did not.
    ///
    /// There is no success path that runs on an absent or unusable serial
    /// number. A unit that reports none does not become `.observed` by any
    /// route through this function.
    public static func qualify(
        vendorID: UInt16,
        productID: UInt16,
        serialNumber: USBSerialNumberReading,
        digest: any StableIdentityDigest
    ) throws -> QualifiedUSBDeviceIdentity {
        let serial = try usableSerialNumber(serialNumber)
        let preimage = canonicalPreimage(
            vendorID: vendorID, productID: productID, serialNumber: serial)
        let hex = digest.hexDigest(preimage)
        guard isLowercaseSHA256Hex(hex) else { throw Failure.digestMalformed }
        guard let identity = try? StableConnectionIdentity(opaqueValue: opaqueValuePrefix + hex) else {
            throw Failure.identityRejected
        }
        return QualifiedUSBDeviceIdentity(
            identity: identity, vendorID: vendorID, productID: productID)
    }

    /// Normalises and screens a read serial-number string.
    ///
    /// Surrounding whitespace is trimmed, because padding is a property of how
    /// a descriptor was filled in rather than of the unit, and leaving it in
    /// would let the same physical printer produce two different identities.
    /// What survives trimming has to be printable ASCII, which also means the
    /// canonical preimage below can never contain the newline it uses as a
    /// field separator, and that no Unicode normalisation question arises.
    static func usableSerialNumber(_ reading: USBSerialNumberReading) throws -> String {
        let raw: String
        switch reading.payload {
        case .absent: throw Failure.serialNumberAbsent
        case .unreadable: throw Failure.serialNumberUnreadable
        case .reported(let text): raw = text
        }
        guard raw.count <= maximumSerialNumberCharacters else { throw Failure.serialNumberTooLong }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.serialNumberEmpty }
        guard trimmed.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else {
            throw Failure.serialNumberUnprintable
        }
        // A string made of one repeated character -- "0", "00000000",
        // "FFFFFFFFFFFF" -- is the classic unprogrammed placeholder, and
        // carries no per-unit information whatever the vendor intended. This
        // is a floor rather than a uniqueness test: a vendor that ships every
        // unit as "0123456789" is indistinguishable from one that does not,
        // and no read-only scan can tell them apart. Screening fails toward
        // "not qualified", which is the direction that cannot invent a device.
        guard Set(trimmed).count > 1 else { throw Failure.serialNumberNotUnitDistinct }
        return trimmed
    }

    /// An unambiguous byte encoding of everything the identity depends on.
    ///
    /// Fields are separated by newlines and the serial number is already known
    /// to contain none, and the identifiers are fixed-width hexadecimal, so no
    /// two distinct inputs can produce the same bytes. Without that, a vendor
    /// identifier ending in a digit and a serial number starting with one could
    /// run together and let two different units collide.
    static func canonicalPreimage(
        vendorID: UInt16, productID: UInt16, serialNumber: String
    ) -> [UInt8] {
        let text = domainSeparator + "\n"
            + PrinterTransport.usb.rawValue + "\n"
            + hex4(vendorID) + "\n"
            + hex4(productID) + "\n"
            + serialNumber + "\n"
        return Array(text.utf8)
    }

    /// Fixed-width uppercase hexadecimal, formatted without `String(format:)`
    /// so no locale or format string is involved.
    static func hex4(_ value: UInt16) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: 4 - digits.count) + digits
    }

    static func isLowercaseSHA256Hex(_ value: String) -> Bool {
        guard value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public extension PrinterProfile {
    /// A new immutable profile revision that differs only in its stable
    /// connection identity.
    ///
    /// The revision advances because a job binds an immutable profile
    /// revision. Rewriting the connection in place under the same revision
    /// would move the snapshot boundary without anything being able to observe
    /// that it moved, which is exactly what a bound job must be able to notice.
    /// Every other field is carried across unchanged, and the ordinary
    /// initialiser revalidates the result.
    func adoptingStableIdentity(
        _ identity: StableConnectionIdentity,
        evidence: CapabilityEvidence = USBIdentityQualification.evidence
    ) throws -> PrinterProfile {
        guard evidence != .unobserved else {
            throw PrinterProfileError.invalidObservationEvidence
        }
        // JSON round-trips the revision as an exact integer, so the bump is
        // bounded by what stays exactly representable rather than by `Int`.
        let (next, overflowed) = revision.addingReportingOverflow(1)
        guard !overflowed, next <= 9_007_199_254_740_991 else {
            throw PrinterProfileError.unrepresentableProfileRevision
        }
        return try PrinterProfile(
            schemaVersion: schemaVersion,
            revision: next,
            capabilities: capabilities,
            installedHardware: installedHardware,
            media: media,
            connection: ConnectionConfiguration(
                transport: connection.transport,
                stableIdentity: .observed(identity, evidence: evidence)
            ),
            configuredDefaults: configuredDefaults,
            thermalMedia: thermalMedia,
            finishingConfiguration: finishingConfiguration
        )
    }
}
