import XCTest
@testable import LabelCore

/// Fixtures follow the shape the 2026-11-09 hosted spike observed
/// (docs/validation/M1-HOSTED-QUEUE-SPIKE-2026-11-09.md). Serial values are fictional.
final class UninstallVerificationTests: XCTestCase {
    private let backupWithoutSerial = """
    NextPrinterId 2
    <Printer LabelPrinterDriver_GC420d>
    PrinterId 1
    DeviceURI usb://Zebra%20Technologies/ZTC%20GC420d%20(EPL)
    </Printer>
    """

    private func snapshot(
        destinations: [String: String] = ["Office": "ipp://office.example.test/ipp/print"],
        defaultDestination: String? = "Office",
        receipts: Set<String> = ["com.apple.pkg.Core"],
        files: [String: String] = ["/Library/Printers": "dir root:wheel 0555"],
        printers: String? = nil,
        backup: String? = nil,
        other: [String: String] = ["/private/etc/cups/cupsd.conf": "6b03187d"]
    ) throws -> UninstallSnapshot {
        try UninstallSnapshot(destinations: destinations, defaultDestination: defaultDestination,
                              packageReceipts: receipts, files: files, printersConfiguration: printers,
                              printersConfigurationBackup: backup, otherSchedulerFiles: other)
    }

    func testIdenticalSnapshotsAreClean() throws {
        let verdict = UninstallVerification.verify(before: try snapshot(), after: try snapshot())
        XCTAssertTrue(verdict.isClean)
        XCTAssertEqual(verdict.residue, [])
        XCTAssertEqual(verdict.tolerated, [])
    }

    /// The spike's exact outcome: an absent printers.conf became `NextPrinterId 2`, and the
    /// backup now holds the removed queue. With no serial in its URI, both are tolerated.
    func testTheSpikeOutcomeIsCleanWhenTheBackupCarriesNoSerial() throws {
        let verdict = UninstallVerification.verify(
            before: try snapshot(),
            after: try snapshot(printers: "NextPrinterId 2\n", backup: backupWithoutSerial))
        XCTAssertEqual(verdict.residue, [])
        XCTAssertEqual(verdict.tolerated, [.printerIDCounterAdvanced(from: nil, to: 2), .configurationBackupRewritten])
    }

    func testABackupDeviceURIWithASerialIsResidue() throws {
        for parameter in ["serial=FICTIONAL0001", "SERIAL=FICTIONAL0001", "interface=0&serial=FICTIONAL0001"] {
            let backup = "<Printer Q>\nDeviceURI usb://Zebra/GC420d?\(parameter)\n</Printer>"
            let verdict = UninstallVerification.verify(before: try snapshot(), after: try snapshot(backup: backup))
            XCTAssertEqual(verdict.residue, [.backupRetainsDeviceSerial], parameter)
            XCTAssertEqual(verdict.tolerated, [], parameter)
        }
    }

    /// A query parameter that merely contains the word is not a serial parameter.
    func testOnlyAParameterNamedSerialCounts() throws {
        let backup = "DeviceURI usb://Zebra/GC420d?serialized=no&notserial=1"
        let verdict = UninstallVerification.verify(before: try snapshot(), after: try snapshot(backup: backup))
        XCTAssertEqual(verdict.residue, [])
        XCTAssertEqual(verdict.tolerated, [.configurationBackupRewritten])
    }

    /// A serial already in an unchanged backup belongs to someone else's queue, not this uninstall.
    func testAnUnchangedBackupIsNotJudged() throws {
        let foreign = "DeviceURI usb://Other/Printer?serial=FICTIONAL0002"
        let verdict = UninstallVerification.verify(before: try snapshot(backup: foreign), after: try snapshot(backup: foreign))
        XCTAssertEqual(verdict.residue, [])
        XCTAssertEqual(verdict.tolerated, [])
    }

    func testACounterAdvanceAlongsideAnyOtherChangeIsResidue() throws {
        let verdict = UninstallVerification.verify(
            before: try snapshot(printers: "NextPrinterId 2"),
            after: try snapshot(printers: "NextPrinterId 3\n<Printer Left>\n</Printer>"))
        XCTAssertEqual(verdict.residue, [.printersConfigurationChanged])
        XCTAssertEqual(verdict.tolerated, [])
    }

    func testACounterThatGoesBackwardsOrDisappearsIsResidue() throws {
        for after in ["NextPrinterId 1", ""] {
            let verdict = UninstallVerification.verify(before: try snapshot(printers: "NextPrinterId 2"),
                                                       after: try snapshot(printers: after))
            XCTAssertEqual(verdict.residue, [.printersConfigurationChanged], after)
        }
    }

    func testAMalformedOrRepeatedCounterIsResidueNotTolerance() throws {
        for after in ["NextPrinterId two", "NextPrinterId 02", "NextPrinterId 3\nNextPrinterId 4", "NextPrinterId  3"] {
            let verdict = UninstallVerification.verify(before: try snapshot(), after: try snapshot(printers: after))
            XCTAssertEqual(verdict.residue, [.printersConfigurationChanged], after)
            XCTAssertEqual(verdict.tolerated, [], after)
        }
    }

    func testAnAbsentAndAnEmptyPrintersConfigurationAreTheSame() throws {
        let verdict = UninstallVerification.verify(before: try snapshot(printers: nil), after: try snapshot(printers: ""))
        XCTAssertEqual(verdict.residue, [])
        XCTAssertEqual(verdict.tolerated, [])
    }

    func testALeftoverQueueIsNamedButItsURIIsNot() throws {
        let verdict = UninstallVerification.verify(
            before: try snapshot(),
            after: try snapshot(destinations: ["Office": "ipp://office.example.test/ipp/print",
                                               "LabelPrinterDriver_GC420d": "usb://Zebra/GC420d?serial=FICTIONAL0003"]))
        XCTAssertEqual(verdict.residue, [.destinationLeft("LabelPrinterDriver_GC420d")])
        XCTAssertFalse(String(describing: verdict).contains("FICTIONAL0003"))
    }

    func testRemovingOrChangingAnUnrelatedQueueIsResidue() throws {
        XCTAssertEqual(UninstallVerification.verify(before: try snapshot(), after: try snapshot(destinations: [:])).residue,
                       [.destinationRemoved("Office")])
        XCTAssertEqual(UninstallVerification.verify(
            before: try snapshot(),
            after: try snapshot(destinations: ["Office": "ipp://elsewhere.example.test/ipp/print"])).residue,
            [.destinationChanged("Office")])
    }

    func testAChangedDefaultDestinationIsResidue() throws {
        XCTAssertEqual(UninstallVerification.verify(before: try snapshot(), after: try snapshot(defaultDestination: nil)).residue,
                       [.defaultDestinationChanged])
    }

    func testReceiptsLeftOrRemovedAreResidue() throws {
        XCTAssertEqual(UninstallVerification.verify(
            before: try snapshot(),
            after: try snapshot(receipts: ["com.apple.pkg.Core", "com.bherila.labelprinterdriver"])).residue,
            [.packageReceiptLeft("com.bherila.labelprinterdriver")])
        XCTAssertEqual(UninstallVerification.verify(before: try snapshot(), after: try snapshot(receipts: [])).residue,
                       [.packageReceiptRemoved("com.apple.pkg.Core")])
    }

    func testFilesLeftRemovedOrChangedAreResidueInPathOrder() throws {
        let verdict = UninstallVerification.verify(
            before: try snapshot(files: ["/Library/Printers": "dir root:wheel 0555", "/b": "file 1"]),
            after: try snapshot(files: ["/Library/Printers": "dir root:wheel 0755",
                                        "/Library/Printers/LabelPrinterDriver": "dir root:wheel 0755"]))
        XCTAssertEqual(verdict.residue, [.fileChanged("/Library/Printers"),
                                         .fileLeft("/Library/Printers/LabelPrinterDriver"),
                                         .fileRemoved("/b")])
    }

    /// cupsd.conf is global scheduler configuration; the project must never change it.
    func testAnyOtherSchedulerFileChangeIsResidue() throws {
        let path = "/private/etc/cups/cupsd.conf"
        XCTAssertEqual(UninstallVerification.verify(before: try snapshot(), after: try snapshot(other: [path: "changed"])).residue,
                       [.schedulerFileChanged(path)])
        XCTAssertEqual(UninstallVerification.verify(before: try snapshot(), after: try snapshot(other: [:])).residue,
                       [.schedulerFileRemoved(path)])
        XCTAssertEqual(UninstallVerification.verify(
            before: try snapshot(), after: try snapshot(other: [path: "6b03187d", "/private/etc/cups/x": "1"])).residue,
            [.schedulerFileLeft("/private/etc/cups/x")])
    }

    // MARK: - Bounds, bracketed from both sides

    func testEntryCountBound() throws {
        let atBound = Dictionary(uniqueKeysWithValues: (0..<UninstallSnapshot.maximumEntries).map { ("/f\($0)", "x") })
        XCTAssertNoThrow(try snapshot(files: atBound))
        var over = atBound
        over["/one-more"] = "x"
        XCTAssertThrowsError(try snapshot(files: over)) {
            XCTAssertEqual($0 as? UninstallSnapshot.ValidationError, .tooManyEntries)
        }
    }

    func testNameLengthBound() throws {
        let atBound = String(repeating: "a", count: UninstallSnapshot.maximumNameBytes)
        XCTAssertNoThrow(try snapshot(receipts: [atBound]))
        XCTAssertThrowsError(try snapshot(receipts: [atBound + "a"])) {
            XCTAssertEqual($0 as? UninstallSnapshot.ValidationError, .nameTooLong)
        }
        // A multi-byte scalar counts by its UTF-8 bytes, not as one character.
        XCTAssertThrowsError(try snapshot(defaultDestination: String(repeating: "é", count: UninstallSnapshot.maximumNameBytes / 2 + 1))) {
            XCTAssertEqual($0 as? UninstallSnapshot.ValidationError, .nameTooLong)
        }
    }

    func testConfigurationSizeBound() throws {
        let atBound = String(repeating: "#", count: UninstallSnapshot.maximumConfigurationBytes)
        XCTAssertNoThrow(try snapshot(backup: atBound))
        XCTAssertThrowsError(try snapshot(printers: atBound + "#")) {
            XCTAssertEqual($0 as? UninstallSnapshot.ValidationError, .configurationTooLarge)
        }
    }
}
