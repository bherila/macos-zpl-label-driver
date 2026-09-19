import CryptoKit
import Foundation
import LabelCore

/// The production digest behind a stable connection identity.
///
/// LabelCore states the derivation and screens the result; the hash itself is
/// Apple's. Nothing in this repository implements SHA-256.
public struct CryptoKitStableIdentityDigest: StableIdentityDigest {
    public init() {}

    public func hexDigest(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }
}

public extension USBIdentityQualification.Failure {
    /// What to put in front of a person when an observation did not qualify.
    ///
    /// Raw enum case names have reached this application's UI as user-facing
    /// error text before. Every case is spelled out here instead, each one
    /// saying what was found and what follows from it, and none of them
    /// implying the device is faulty when the honest answer is that this Mac
    /// cannot tell two units apart.
    var setupMessage: String {
        switch self {
        case .serialNumberAbsent:
            return String(localized: """
                This USB device publishes no serial number, so this Mac cannot tell it apart from \
                another unit of the same model. Queue installation stays unavailable.
                """)
        case .serialNumberUnreadable:
            return String(localized: """
                This USB device's serial-number entry could not be read as text. Nothing was \
                identified, and queue installation stays unavailable.
                """)
        case .serialNumberEmpty:
            return String(localized: """
                This USB device reports an empty serial number, which identifies no particular \
                unit. Queue installation stays unavailable.
                """)
        case .serialNumberUnprintable:
            return String(localized: """
                This USB device's serial number contains characters this Mac will not accept as \
                an identifier. Nothing was identified, and queue installation stays unavailable.
                """)
        case .serialNumberTooLong:
            return String(localized: """
                This USB device reports a serial number longer than a USB descriptor can carry, \
                so it was not accepted as an identifier. Queue installation stays unavailable.
                """)
        case .serialNumberNotUnitDistinct:
            return String(localized: """
                This USB device's serial number is a placeholder that every unit of the model can \
                report, so it identifies no particular printer. Queue installation stays \
                unavailable.
                """)
        case .digestMalformed, .identityRejected:
            return String(localized: """
                A stable identity could not be derived from this observation. Nothing was \
                identified, and queue installation stays unavailable.
                """)
        }
    }
}
