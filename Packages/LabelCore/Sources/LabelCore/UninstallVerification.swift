import Foundation

/// Decides whether an uninstall left the system as it found it (decision D19 in
/// docs/DECISIONS.md), from two snapshots taken before install and after uninstall.
///
/// "Clean" is judged from the snapshots, never from the uninstaller's own exit
/// status. Nothing in this file reads the system: it spawns no process, opens no
/// file and contacts no scheduler. A caller builds both snapshots the same way.
///
/// Exactly two scheduler-owned changes are tolerated, because the 2026-11-09
/// hosted spike (docs/validation/M1-HOSTED-QUEUE-SPIKE-2026-11-09.md) showed that
/// any add-then-remove produces them:
/// - `NextPrinterId` in `printers.conf` advancing, and nothing else in that file changing;
/// - cupsd's `printers.conf.O` backup being rewritten, provided no `DeviceURI` in it
///   carries a serial number (D24 keeps the serial out of the product's URI).
/// Every other difference is residue. A destination, receipt or file that existed
/// before and is gone afterwards is residue too: an uninstall that removes
/// something it did not install is not clean.
public struct UninstallSnapshot: Equatable, Sendable {
    public static let maximumEntries = 4096
    public static let maximumNameBytes = 4096
    public static let maximumConfigurationBytes = 1 << 20

    public enum ValidationError: Error, Equatable, Sendable {
        case tooManyEntries
        case nameTooLong
        case configurationTooLarge
    }

    /// Queue name to device URI. URIs are compared but never reported.
    public let destinations: [String: String]
    public let defaultDestination: String?
    public let packageReceipts: Set<String>
    /// Path to an opaque metadata descriptor (kind, owner, mode, digest) the caller
    /// derives the same way for both snapshots.
    public let files: [String: String]
    /// Non-comment text of `printers.conf`, or nil when the file is absent.
    public let printersConfiguration: String?
    /// Non-comment text of cupsd's `printers.conf.O` backup, or nil when absent.
    public let printersConfigurationBackup: String?
    /// Every other scheduler configuration file: path to content digest.
    public let otherSchedulerFiles: [String: String]

    public init(
        destinations: [String: String],
        defaultDestination: String?,
        packageReceipts: Set<String>,
        files: [String: String],
        printersConfiguration: String?,
        printersConfigurationBackup: String?,
        otherSchedulerFiles: [String: String]
    ) throws {
        for count in [destinations.count, packageReceipts.count, files.count, otherSchedulerFiles.count] {
            guard count <= Self.maximumEntries else { throw ValidationError.tooManyEntries }
        }
        let names = Array(destinations.keys) + Array(destinations.values) + Array(packageReceipts)
            + Array(files.keys) + Array(files.values) + Array(otherSchedulerFiles.keys)
            + Array(otherSchedulerFiles.values) + [defaultDestination].compactMap { $0 }
        guard names.allSatisfy({ $0.utf8.count <= Self.maximumNameBytes }) else {
            throw ValidationError.nameTooLong
        }
        for configuration in [printersConfiguration, printersConfigurationBackup] {
            guard (configuration?.utf8.count ?? 0) <= Self.maximumConfigurationBytes else {
                throw ValidationError.configurationTooLarge
            }
        }
        self.destinations = destinations
        self.defaultDestination = defaultDestination
        self.packageReceipts = packageReceipts
        self.files = files
        self.printersConfiguration = printersConfiguration
        self.printersConfigurationBackup = printersConfigurationBackup
        self.otherSchedulerFiles = otherSchedulerFiles
    }
}

/// Something an uninstall left behind or took away. Destination URIs, file
/// contents and backup text are never carried, so a residue report cannot leak
/// a device serial number.
public enum UninstallResidue: Equatable, Hashable, Sendable {
    case destinationLeft(String)
    case destinationRemoved(String)
    case destinationChanged(String)
    case defaultDestinationChanged
    case packageReceiptLeft(String)
    case packageReceiptRemoved(String)
    case fileLeft(String)
    case fileRemoved(String)
    case fileChanged(String)
    case schedulerFileLeft(String)
    case schedulerFileRemoved(String)
    case schedulerFileChanged(String)
    /// `printers.conf` differs by more than `NextPrinterId` advancing.
    case printersConfigurationChanged
    /// cupsd's backup was rewritten and a `DeviceURI` in it carries a serial number.
    case backupRetainsDeviceSerial
}

public enum ToleratedSchedulerChange: Equatable, Sendable {
    case printerIDCounterAdvanced(from: Int?, to: Int)
    case configurationBackupRewritten
}

public struct UninstallVerdict: Equatable, Sendable {
    public let residue: [UninstallResidue]
    public let tolerated: [ToleratedSchedulerChange]
    public var isClean: Bool { residue.isEmpty }
}

public enum UninstallVerification {
    public static func verify(before: UninstallSnapshot, after: UninstallSnapshot) -> UninstallVerdict {
        var residue: [UninstallResidue] = []
        var tolerated: [ToleratedSchedulerChange] = []

        for name in Set(before.destinations.keys).union(after.destinations.keys).sorted() {
            switch (before.destinations[name], after.destinations[name]) {
            case (nil, .some): residue.append(.destinationLeft(name))
            case (.some, nil): residue.append(.destinationRemoved(name))
            case let (.some(old), .some(new)) where old != new: residue.append(.destinationChanged(name))
            default: break
            }
        }
        if before.defaultDestination != after.defaultDestination {
            residue.append(.defaultDestinationChanged)
        }
        residue += after.packageReceipts.subtracting(before.packageReceipts).sorted().map { .packageReceiptLeft($0) }
        residue += before.packageReceipts.subtracting(after.packageReceipts).sorted().map { .packageReceiptRemoved($0) }
        residue += compare(before.files, after.files,
                           left: UninstallResidue.fileLeft, removed: UninstallResidue.fileRemoved,
                           changed: UninstallResidue.fileChanged)
        residue += compare(before.otherSchedulerFiles, after.otherSchedulerFiles,
                           left: UninstallResidue.schedulerFileLeft, removed: UninstallResidue.schedulerFileRemoved,
                           changed: UninstallResidue.schedulerFileChanged)

        switch printersConfigurationChange(before.printersConfiguration, after.printersConfiguration) {
        case .unchanged: break
        case let .counterAdvanced(from, to): tolerated.append(.printerIDCounterAdvanced(from: from, to: to))
        case .changed: residue.append(.printersConfigurationChanged)
        }

        if before.printersConfigurationBackup != after.printersConfigurationBackup {
            if let backup = after.printersConfigurationBackup, containsSerialDeviceURI(backup) {
                residue.append(.backupRetainsDeviceSerial)
            } else {
                tolerated.append(.configurationBackupRewritten)
            }
        }
        return UninstallVerdict(residue: residue, tolerated: tolerated)
    }

    private static func compare(
        _ before: [String: String], _ after: [String: String],
        left: (String) -> UninstallResidue, removed: (String) -> UninstallResidue,
        changed: (String) -> UninstallResidue
    ) -> [UninstallResidue] {
        Set(before.keys).union(after.keys).sorted().compactMap { path in
            switch (before[path], after[path]) {
            case (nil, .some): left(path)
            case (.some, nil): removed(path)
            case let (.some(old), .some(new)) where old != new: changed(path)
            default: nil
            }
        }
    }

    enum PrintersConfigurationChange: Equatable { case unchanged, counterAdvanced(Int?, Int), changed }

    /// An absent file and an empty one are the same configuration: cupsd creates the
    /// file on its first write.
    static func printersConfigurationChange(_ before: String?, _ after: String?) -> PrintersConfigurationChange {
        let old = splitCounter(before ?? ""), new = splitCounter(after ?? "")
        guard let old, let new, old.lines == new.lines else { return .changed }
        switch (old.counter, new.counter) {
        case let (a, b) where a == b: return .unchanged
        case let (a, .some(b)) where a.map({ b > $0 }) ?? true: return .counterAdvanced(a, b)
        default: return .changed
        }
    }

    /// The file's non-blank lines without its `NextPrinterId` line, and that line's value.
    /// Blank lines carry no configuration, so a trailing newline is not a difference.
    /// Nil when the counter line is malformed or repeated, which is not cupsd's shape.
    private static func splitCounter(_ text: String) -> (lines: [Substring], counter: Int?)? {
        var lines: [Substring] = [], counter: Int?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix("NextPrinterId") else { lines.append(line); continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: false)
            guard counter == nil, fields.count == 2, fields[0] == "NextPrinterId",
                  let value = Int(fields[1]), value >= 0, String(value) == fields[1] else { return nil }
            counter = value
        }
        return (lines, counter)
    }

    /// True when any `DeviceURI` line's query names a `serial` parameter, in any case.
    static func containsSerialDeviceURI(_ text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            guard trimmed.hasPrefix("DeviceURI"),
                  let query = trimmed.split(separator: "?", maxSplits: 1).dropFirst().first else { return false }
            return query.split(separator: "&").contains { parameter in
                parameter.split(separator: "=", maxSplits: 1).first?.lowercased() == "serial"
            }
        }
    }
}
