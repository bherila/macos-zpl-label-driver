import Foundation
import XCTest
import LabelCore
@testable import LabelMac

/// M3-AC04: ordinary finishing output carries no persistent-action command.
///
/// The assertions run over every byte `FinishingFramedOutput` assembled for a
/// mode, not over the encoders it composes from, so a persistent action that a
/// future framing step introduces is caught here even when each encoder is
/// individually well behaved. Fixtures are built independently of
/// `ProfileBoundFinishingJobPlanTests`; nothing is shared between the two files.
final class FinishingFramedCommandFamilyTests: XCTestCase {
    private let modes: [FinishingMode] = [.tearOff, .cut, .peel, .rewind]
    private let documented = CapabilityFact(state: .supported,
        evidence: .documentedModel(sourceID: "synthetic-framed-command-family"))

    /// Configuration update, calibration, setting save, restore-defaults, object
    /// delete, download and host-graphic families. Any of these would outlive the
    /// job and change the unit for whatever prints next, so none may appear in an
    /// ordinary print path. Maintenance actions are a separately authorized route.
    private static let persistentActionCommands = [
        "~JR", "^JU", "~JC", "~JA", "^ID", "~DY", "~DU", "~DG", "^DF", "~WC",
    ]

    /// The complete set of command prefixes the framing itself may emit: the
    /// format envelope, the quantity, the graphic fields, the finishing mode and
    /// the delayed-cut trigger. A denylist only catches what someone thought to
    /// list, so the emitted prefixes are also pinned against this allowlist.
    private static let framingCommandPrefixes: Set<String> = [
        "^XA", "^XZ", "^PQ", "^FO", "^GF", "^FS", "^MM", "~JK",
    ]

    /// The state-normalization prefixes the framing is allowed to carry through.
    /// Pinned rather than derived from the bytes under test: a new normalization
    /// command has to be reviewed here before it can widen the allowlist.
    private static let normalizationCommandPrefixes: Set<String> = [
        "^MT", "^PR", "^MD", "~SD", "^PW", "^LH", "^LS",
    ]

    /// Every `^xx`/`~xx` command introducer in `text`. Deliberately hand written
    /// rather than pattern matched, and covered by its own test below, so a
    /// silently empty result cannot turn the allowlist check into a pass.
    private func commandPrefixes(in text: String) -> Set<String> {
        var found: Set<String> = []
        let characters = Array(text)
        var index = characters.startIndex
        while index < characters.endIndex {
            defer { index += 1 }
            guard characters[index] == "^" || characters[index] == "~" else { continue }
            guard index + 2 < characters.endIndex else { continue }
            let first = characters[index + 1], second = characters[index + 2]
            guard first.isASCII, first.isLetter, second.isASCII, second.isLetter else { continue }
            found.insert(String([characters[index], first, second]))
        }
        return found
    }

    func testCommandPrefixScannerSeesBothIntroducersAndIgnoresGraphicPayload() {
        XCTAssertEqual(commandPrefixes(in: "^XA\n^FO0,0^GFA,4,4,1,FF00FF00^FS\n^XZ\n"),
                       ["^XA", "^FO", "^GF", "^FS", "^XZ"])
        // Each denylisted family is actually visible to the scanner, so the
        // allowlist assertion below cannot pass by simply finding nothing.
        for command in Self.persistentActionCommands {
            XCTAssertEqual(commandPrefixes(in: "^XA\n\(command)\n^XZ\n"), ["^XA", command, "^XZ"])
            XCTAssertFalse(Self.framingCommandPrefixes.contains(command), "denylist overlaps allowlist: \(command)")
            XCTAssertFalse(Self.normalizationCommandPrefixes.contains(command),
                           "denylist overlaps normalization allowlist: \(command)")
        }
        XCTAssertEqual(commandPrefixes(in: "FF00FF00\n1234\n"), [])
        XCTAssertEqual(commandPrefixes(in: "^X"), []) // Truncated introducer is not a command.
    }

    private func store() throws -> PrinterProfileStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "FramedFamilies-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try PrinterProfileStore(root: root)
    }

    private func profile() throws -> PrinterProfile {
        let base = try PrinterProfile.gc420dUSBReference(), c = base.capabilities
        let installed = CapabilityFact(state: .supported, evidence: .reportedInstallation)
        return try .init(schemaVersion: 8, revision: 11,
            capabilities: .init(model: "synthetic-framed-command-family-model", thermalTransfer: c.thermalTransfer,
                cutter: documented, peeler: documented, rewind: documented, tracking: c.tracking,
                printSpeedChoicesIps: c.printSpeedChoicesIps, darkness: documented,
                physicalGeometry: .init(width: .init(fact: documented, maximumDots: 200),
                    homeX: .init(fact: documented, maximumDots: 200),
                    homeY: .init(fact: documented, maximumDots: 200)),
                offsets: .init(shiftLeft: .init(fact: documented, range: -5...5),
                    labelTop: .init(fact: documented, range: -5...5)), directThermal: documented),
            installedHardware: .init(transport: .usb, selectedFinishing: .tearOff, cutter: installed,
                peeler: installed, observedSpeedIps: nil, observedDarkness: nil, observedTracking: nil),
            media: base.media, connection: base.connection,
            configuredDefaults: .init(thermalMethod: .directThermal),
            thermalMedia: .init(method: .observed(.directThermal, evidence: .reportedInstallation),
                ribbonPresent: .observed(false, evidence: .reportedInstallation)),
            finishingConfiguration: .init(finishing: .init(
                modes: Dictionary(uniqueKeysWithValues: modes.map { ($0, documented) }), enabledModes: Set(modes),
                installed: .init(cutter: .observed(true, evidence: .reportedInstallation),
                    peeler: .observed(true, evidence: .reportedInstallation),
                    rewinder: .observed(true, evidence: .reportedInstallation))),
                stock: .init(media: base.media, compatibleModes: Dictionary(uniqueKeysWithValues: modes.map {
                    ($0, .observed(true, evidence: .reportedInstallation))
                })), schedules: .init(everyLabel: documented, batch: documented, endOfJob: documented,
                    maximumBatchSize: 3)))
    }

    @MainActor
    func testFramedFinishingOutputCarriesNoPersistentActionCommandInAnyMode() async throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let source = try Data(contentsOf: root.appending(path: "Fixtures/generated/native-vector.pdf"))
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let worker = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FramedCommandFamilies-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let model = try WorkflowEditorBootstrap.makeModel(originalPDF: source,
            store: WorkflowProfileStore(root: directory))
        let pages = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source)
        let canvas = try DotCanvas(physicalSize: model.profile.outputStock,
            resolution: DotResolution(xDotsPerMillimeter: 1, yDotsPerMillimeter: 1))
        let store = try store()
        let reference = try store.save(id: "synthetic-framed-families", profile: profile())
        let nonRFID = CapabilityFact(state: .unsupported,
            evidence: .documentedModel(sourceID: "synthetic-framed-command-family-non-rfid"))
        for mode in modes {
            // Seven cut labels against a batch of three so the delayed-cut files
            // after labels 3, 6 and 7 are actually part of the assembled output.
            let count = mode == .cut ? 7 : 2
            let expectedCutOrdinals = mode == .cut ? [3, 6, 7] : []
            let plan = try ExtractionPlanner.plan(sourcePages: pages, profile: model.profile,
                copyPolicy: .engine(copies: count, collated: true))
            let job = try store.finishingPlan(reference: reference, mode: mode, outputLabelCount: count,
                schedule: mode == .cut ? .batch(size: 3, cutRemainderAtJobEnd: true) : nil)
            let preparation = try FinishingRasterPreparation.prepare(job: job,
                controlRequest: .init(finishing: mode, printSpeedIps: 3, darkness: 0), originalPDF: source,
                extraction: plan, canvas: canvas, conversion: .textAndBarcodeThreshold(cutoff: 128),
                workerExecutable: worker)
            XCTAssertEqual(preparation.rasters.count, count)
            let qualification = FinishingOutputQualification(profile: job.printer.profile,
                model: job.printer.profile.capabilities.model,
                quantityOne: documented, labelCompletion: documented, rfid: nonRFID,
                delayedCutter: documented, delayedCutReadiness: documented, cutCompletion: documented,
                completeFileDelivery: .observed(true, evidence: .reportedInstallation),
                peelLabelTaken: documented, prepeel: documented)
            let framed = try FinishingFramedOutput.prepare(preparation, qualification: qualification)

            // The state block is allowed through the framing, so pin what it may
            // carry instead of deriving the allowlist from the bytes under test.
            let normalizationText = String(decoding: preparation.normalization.bytes, as: UTF8.self)
            let normalizationPrefixes = commandPrefixes(in: normalizationText)
            XCTAssertFalse(normalizationPrefixes.isEmpty, "\(mode): no normalization commands to allow")
            XCTAssertTrue(normalizationPrefixes.isSubset(of: Self.normalizationCommandPrefixes),
                "\(mode): unreviewed normalization commands \(normalizationPrefixes)")
            let allowedPrefixes = Self.framingCommandPrefixes.union(normalizationPrefixes)

            // Every payload the plan would actually put on the wire, with its
            // ordinal, so an empty or short collection cannot pass vacuously.
            var formatOrdinals: [Int] = [], cutOrdinals: [Int] = [], payloads: [Data] = []
            for step in framed.steps {
                switch step {
                case .formatFile(let ordinal, let bytes):
                    formatOrdinals.append(ordinal); payloads.append(bytes)
                case .delayedCutFile(let ordinal, let bytes):
                    cutOrdinals.append(ordinal); payloads.append(bytes)
                case .awaitLabelPrinted, .awaitDelayedCutReady, .awaitCutCompleted, .awaitLabelTaken:
                    continue
                }
            }
            XCTAssertEqual(formatOrdinals, Array(1...count), "\(mode): unexpected format files")
            XCTAssertEqual(cutOrdinals, expectedCutOrdinals, "\(mode): unexpected delayed-cut files")
            XCTAssertEqual(payloads.count, count + expectedCutOrdinals.count, "\(mode): unexpected payload count")

            for (index, bytes) in payloads.enumerated() {
                let text = String(decoding: bytes, as: UTF8.self)
                XCTAssertFalse(text.isEmpty, "\(mode): empty payload \(index)")
                for command in Self.persistentActionCommands {
                    XCTAssertFalse(text.contains(command), "\(mode): payload \(index) carries \(command)")
                }
                let prefixes = commandPrefixes(in: text)
                XCTAssertFalse(prefixes.isEmpty, "\(mode): payload \(index) carries no command at all")
                XCTAssertTrue(prefixes.isSubset(of: allowedPrefixes),
                    "\(mode): payload \(index) carries unlisted commands \(prefixes.subtracting(allowedPrefixes))")
            }
        }
    }
}
