import CoreGraphics
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class WorkflowEditorBootstrapTests: XCTestCase {
    private enum TestError: Error { case unavailable }

    func testChangedStockReopensAsUnreviewedCorrectionAndRendersOriginalPDF() async throws {
        let source = try fixture("letter-one")
        let profileStore = try store()
        let original = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let stock = PhysicalSize(width: try .inches(2), height: try .inches(3))
        try original.setOutputStock(id: "custom-stock", size: stock)
        try original.save()
        let saved = original.profile
        let reopened = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, savedProfile: saved, stockPolicy: .offlineCandidate)
        XCTAssertTrue(reopened.isReopenedWorkflow)
        XCTAssertFalse(reopened.isSaved)
        XCTAssertEqual(reopened.profile.revision, saved.revision + 1)
        XCTAssertEqual(reopened.profile.pageRules, saved.pageRules)
        XCTAssertEqual(reopened.profile.outputStock, stock)
        XCTAssertEqual(reopened.unreviewedRegionCount, reopened.regions.count)
        XCTAssertEqual(try profileStore.load(profileID: saved.id, revision: saved.revision), saved)
        await reopened.refreshPreviewInWorker(workerExecutable: try worker(), deadlineSeconds: 5)
        let preview = try XCTUnwrap(reopened.preview)
        XCTAssertEqual(preview.bitmap.layout.width, 406)
        XCTAssertEqual(preview.bitmap.layout.height, 610)
        XCTAssertEqual(preview.previewPBM, preview.bitmap.pbmData())
        XCTAssertFalse(reopened.canApproveForUnattendedUse)
    }

    func testOversizedSavedStockRejectedBeforeWorkerLaunch() async throws {
        let source = try fixture("letter-one")
        let profileStore = try store()
        let model = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let current = model.profile
        let oversized = try WorkflowProfile(id: current.id, revision: current.revision,
            outputStockID: "oversized-stock", outputStock: PhysicalSize(
                width: Millimeters(10_000), height: Millimeters(10)),
            pageRules: current.pageRules)
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"),
                deadlineSeconds: 5, savedProfile: oversized, stockPolicy: .offlineCandidate)
            XCTFail("oversized saved stock admitted")
        } catch {
            XCTAssertEqual(error as? PhysicalGeometryError, .exceedsDotLimit(actual: 80_000, limit: 8_192))
        }
        XCTAssertEqual(model.profile, current)
    }

    /// 600x900mm is admissible to DotCanvas on every individual bound but its
    /// 4800x7200 dot product exceeds the renderer's pixel budget. Without
    /// admission here a revision saves and reopens whose every preview fails.
    /// The neighbouring oversized-stock test only covers the dimension limit.
    func testCandidateStockInsideDotLimitsButBeyondPixelBudgetIsRejected() async throws {
        let stock = PhysicalSize(width: try Millimeters(600), height: try Millimeters(900))
        let resolution = try DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8)
        // The canvas itself is valid: rejection below is the pixel product alone.
        let canvas = try DotCanvas(physicalSize: stock, resolution: resolution)
        XCTAssertEqual(canvas.width, 4_800)
        XCTAssertEqual(canvas.height, 7_200)
        XCTAssertGreaterThan(canvas.width * canvas.height,
                             QuartzPDFRenderer.Request.defaultMaximumPixels)
        XCTAssertThrowsError(try QuartzPDFRenderer.admitRenderableCanvas(canvas)) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error,
                .pixelLimitExceeded(actual: 34_560_000,
                                    limit: QuartzPDFRenderer.Request.defaultMaximumPixels))
        }

        let source = try fixture("letter-one")
        let profileStore = try store()
        let model = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let current = model.profile
        let candidate = try WorkflowProfile(id: current.id, revision: current.revision,
            outputStockID: "pixel-budget-stock", outputStock: stock, pageRules: current.pageRules)
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"),
                deadlineSeconds: 5, savedProfile: candidate, stockPolicy: .offlineCandidate)
            XCTFail("stock beyond the renderer pixel budget was admitted")
        } catch {
            XCTAssertEqual(error as? QuartzPDFRenderer.Error,
                .pixelLimitExceeded(actual: 34_560_000,
                                    limit: QuartzPDFRenderer.Request.defaultMaximumPixels))
        }
        XCTAssertEqual(model.profile, current)
    }

    /// Margins round to dots independently, so physical area can stay positive
    /// while the rounded insets consume the whole canvas. 0.45 and 0.54mm on a
    /// 1mm stock leaves 0.01mm physically but rounds to 4 + 4 dots on an 8-dot
    /// canvas. Distinct from the pixel-product case: this is quantization.
    func testSavedCandidateWithMarginsQuantizingToTheWholeCanvasIsRejected() async throws {
        let stock = PhysicalSize(width: try Millimeters(1), height: try Millimeters(10))
        let margins = try OutputMargins(left: 0.45, top: 0, right: 0.54, bottom: 0)
        // The profile itself is valid: physical area remains positive.
        XCTAssertGreaterThan(stock.width.value - margins.left - margins.right, 0)

        let source = try fixture("letter-one")
        let profileStore = try store()
        let model = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let current = model.profile
        let candidate = try WorkflowProfile(schemaVersion: 3, id: current.id, revision: current.revision,
            outputStockID: "quantizing-margin-stock", outputStock: stock, outputMargins: margins,
            pageRules: current.pageRules)
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"),
                deadlineSeconds: 5, savedProfile: candidate, stockPolicy: .offlineCandidate)
            XCTFail("margins quantizing to the whole canvas were admitted")
        } catch {
            XCTAssertEqual(error as? PagePlacementError, .invalidMargins)
        }
        XCTAssertEqual(model.profile, current)
    }

    /// The pre-worker probe uses the stock as its own source, so it sees neither
    /// region geometry nor rotation. A narrow crop onto a long thin stock passes
    /// that probe and the pixel budget, yet the renderer plans the actual region
    /// and rounds its target to zero. Third variant of one structural gap: the
    /// surrogate source, which is why this validates the real planned labels.
    func testNarrowRegionOnChangedStockIsRejectedDespitePassingSurrogateProbe() async throws {
        let source = try fixture("letter-one")
        let profileStore = try store()
        let model = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let current = model.profile
        let stock = PhysicalSize(width: try Millimeters(1000), height: try Millimeters(0.1))

        // The surrogate probe and the pixel budget both admit this stock, which
        // is exactly why the earlier admission let it through.
        let canvas = try DotCanvas(physicalSize: stock,
            resolution: try DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8))
        XCTAssertNoThrow(try QuartzPDFRenderer.admitRenderableCanvas(canvas))
        XCTAssertNoThrow(try PagePlacementPlanner.plan(source: stock, canvas: canvas,
                                                      policy: .fit, margins: .zero))

        let narrow = try WorkflowPageRule(
            sourcePage: current.pageRules[0].sourcePage,
            expectedInput: current.pageRules[0].expectedInput,
            disposition: .extract([try ExtractionRegion(id: "narrow-strip",
                normalizedRect: try NormalizedRect(x: 0, y: 0, width: 0.1, height: 1),
                outputOrder: 0)]))
        let candidate = try WorkflowProfile(id: current.id, revision: current.revision,
            outputStockID: "long-thin-stock", outputStock: stock, pageRules: [narrow])
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), deadlineSeconds: 5,
                savedProfile: candidate, stockPolicy: .offlineCandidate)
            XCTFail("a region that cannot be placed on the candidate stock was admitted")
        } catch {
            XCTAssertEqual(error as? PagePlacementError, .placementExceedsLimit)
        }
        XCTAssertEqual(model.profile, current)
    }

    /// The editor's own stock edit shares the gap, so it shares the admission.
    func testSetOutputStockRejectsStockBeyondRendererPixelBudget() async throws {
        let source = try fixture("letter-one")
        let model = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: try store(), workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let before = model.profile
        XCTAssertThrowsError(try model.setOutputStock(id: "pixel-budget-stock",
            size: PhysicalSize(width: try Millimeters(600), height: try Millimeters(900)))) {
            XCTAssertEqual($0 as? QuartzPDFRenderer.Error,
                .pixelLimitExceeded(actual: 34_560_000,
                                    limit: QuartzPDFRenderer.Request.defaultMaximumPixels))
        }
        // A rejected edit commits no draft or canvas state.
        XCTAssertEqual(model.profile, before)
    }

    func testDistinctManualWorkflowsCanBeSavedInTheSameImmutableStore() async throws {
        let profileStore = try store()
        let first = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: fixture("letter-one"),
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        let second = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: fixture("a4-one"),
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        XCTAssertNotEqual(first.profile.id, second.profile.id)
        XCTAssertEqual(first.profile.revision, 1)
        XCTAssertEqual(second.profile.revision, 1)
        try first.setSelectedRegionMillimeters(left: 20, top: 20, width: 101.6, height: 152.4)
        try second.setSelectedRegionMillimeters(left: 10, top: 30, width: 101.6, height: 152.4)
        try first.save()
        try first.save() // Identical save remains idempotent.
        try second.save()
        XCTAssertEqual(try profileStore.load(profileID: first.profile.id, revision: 1), first.profile)
        XCTAssertEqual(try profileStore.load(profileID: second.profile.id, revision: 1), second.profile)
        XCTAssertThrowsError(try first.approveForUnattendedUse())
        XCTAssertThrowsError(try second.approveForUnattendedUse())
    }

    func testExplicitManualBorderlessLetterRemainsUnqualifiedAndRendersOriginal() async throws {
        let source = try borderlessNativePDF(width: 612, height: 792)
        let profileStore = try store()
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), deadlineSeconds: 5)
            XCTFail("assisted opening guessed a borderless crop")
        } catch {
            XCTAssertEqual(error as? WorkflowEditorBootstrap.Error, .noBorderCandidate(page: 1))
        }
        let manual = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
            store: profileStore, workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
        XCTAssertTrue(manual.isManualDraft)
        XCTAssertFalse(manual.isSaved)
        XCTAssertEqual(manual.regions.first?.normalizedRect,
            try NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(manual.profile.outputStock.width.value, 101.6, accuracy: 0.001)
        XCTAssertEqual(manual.profile.pageRules[0].expectedInput.uprightPhysicalSize.width.value, 215.9, accuracy: 0.001)
        XCTAssertTrue(manual.profile.pageRules.allSatisfy { $0.structuralAnchors.isEmpty })
        try manual.setSelectedRegionMillimeters(left: 20, top: 20, width: 101.6, height: 152.4)
        await manual.refreshPreviewInWorker(workerExecutable: try worker())
        let preview = try XCTUnwrap(manual.preview)
        XCTAssertEqual(preview.previewPBM, preview.bitmap.pbmData())
        try manual.save()
        let reloaded = try profileStore.load(profileID: manual.profile.id, revision: manual.profile.revision)
        XCTAssertEqual(reloaded, manual.profile, "Edited profile must survive exact persistence round trip")
        XCTAssertThrowsError(try manual.approveForUnattendedUse()) {
            XCTAssertEqual($0 as? UnattendedWorkflowQualification.Error, .missingStructuralChecks(page: 1),
                           "Unexpected qualification rejection: \($0)")
        }
        XCTAssertNil(try? profileStore.qualification(for: manual.profile))
    }

    func testManualAmbiguousAndMixedPagesNeverGuessOrDiscard() async throws {
        for name in ["ambiguous-region", "mixed-pages", "non-label-pages"] {
            let source = try fixture(name)
            let manual = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: store(), workerExecutable: worker(), deadlineSeconds: 5, mode: .manual)
            let count = try QuartzPDFRenderer.documentPageBoxes(originalPDF: source).count
            XCTAssertEqual(manual.profile.pageRules.map(\.sourcePage), Array(1...count))
            XCTAssertEqual(manual.regions.count, count)
            XCTAssertTrue(manual.profile.pageRules.allSatisfy { $0.structuralAnchors.isEmpty })
            XCTAssertTrue(manual.regions.allSatisfy {
                $0.normalizedRect.x == 0 && $0.normalizedRect.y == 0 &&
                $0.normalizedRect.width == 1 && $0.normalizedRect.height == 1
            })
        }
    }

    private func worker() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let url = root.appending(path: "Packages/LabelMac/.build/\(configuration)/label-render-worker")
        return try XCTUnwrap(FileManager.default.isExecutableFile(atPath: url.path) ? url : nil)
    }

    func testRealWorkerBootstrapMatchesAllThreeReferenceProfiles() async throws {
        for name in ["native-vector", "letter-one", "a4-one"] {
            let source = try fixture(name)
            let profileStore = try store()
            let expected = try WorkflowEditorBootstrap.makeModel(originalPDF: source, store: profileStore)
            let actual = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), deadlineSeconds: 5)
            XCTAssertEqual(actual.profile, expected.profile)
            XCTAssertFalse(actual.isSaved)
        }
    }

    func testWorkerBootstrapRetainsPageLimitAndCancellation() async throws {
        let source = try fixture("native-vector")
        let profileStore = try store()
        let cancellation = OfflineRenderWorkerCancellation()
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(
                originalPDF: fixture("mixed-pages"), store: profileStore,
                workerExecutable: worker(), maximumPages: 1, deadlineSeconds: 5)
            XCTFail("oversized page count succeeded")
        } catch {
            XCTAssertEqual(error as? OfflineRenderWorkerProcess.Error, .jobRejected(code: .limitExceeded))
        }
        cancellation.cancel()
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), cancellation: cancellation)
            XCTFail("pre-cancelled bootstrap succeeded")
        } catch {
            XCTAssertEqual(error as? OfflineRenderWorkerProcess.Error, .cancelled)
        }
        do {
            _ = try await WorkflowEditorBootstrap.makeModelUsingWorker(originalPDF: source,
                store: profileStore, workerExecutable: worker(), maximumPages: 33)
            XCTFail("raised editor page cap succeeded")
        } catch {
            XCTAssertEqual(error as? QuartzStructuralAnalyzer.Error, .invalidLimits)
        }
    }

    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appending(path: "Fixtures/generated/\(name).pdf"))
    }

    private func store() throws -> WorkflowProfileStore {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "WorkflowEditorBootstrapTests-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try WorkflowProfileStore(root: root)
    }

    private func borderlessNativePDF(width: Double = 288, height: Double = 432) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw TestError.unavailable
        }
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw TestError.unavailable
        }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 120, y: 210, width: 48, height: 12))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    func testLetterFixtureCreatesUnsavedEditableProfileAndExactPreview() throws {
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("letter-one"), store: try store()
        )
        XCTAssertEqual(model.profile.id, "letter-to-4x6-local")
        XCTAssertEqual(model.profile.revision, 1)
        XCTAssertEqual(model.regions.count, 1)
        XCTAssertFalse(model.isSaved)
        XCTAssertEqual(model.regions[0].normalizedRect.x, 46.0 / 612.0, accuracy: 0.01)
        XCTAssertEqual(model.regions[0].normalizedRect.y, 190.0 / 792.0, accuracy: 0.01)
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.previewPBM, model.preview?.bitmap.pbmData())
    }

    func testA4FixtureUsesA4ReferenceWithoutChangingPhysicalStock() throws {
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("a4-one"), store: try store()
        )
        XCTAssertEqual(model.profile.id, "a4-to-4x6-local")
        XCTAssertEqual(model.profile.outputStock.width.value, 101.6, accuracy: 0.001)
        XCTAssertEqual(model.profile.outputStock.height.value, 152.4, accuracy: 0.001)
        XCTAssertEqual(model.regions.count, 1)
    }

    func testAmbiguousLandscapeSheetRequiresReviewInsteadOfChoosingOneLabel() throws {
        XCTAssertThrowsError(try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("ambiguous-region"), store: try store()
        )) {
            XCTAssertEqual(
                $0 as? WorkflowEditorBootstrap.Error,
                .ambiguousBorderCandidates(page: 1)
            )
        }
    }

    func testMixedGeometryAndUnexpectedPageCannotBeSilentlyDiscarded() throws {
        for name in ["mixed-pages", "non-label-pages"] {
            XCTAssertThrowsError(try WorkflowEditorBootstrap.makeModel(
                originalPDF: fixture(name), store: try store()
            )) {
                XCTAssertEqual($0 as? WorkflowEditorBootstrap.Error, .mixedReferenceGeometry)
            }
        }
    }

    func testSourcePageLimitIsAppliedBeforeCreatingDraft() throws {
        XCTAssertThrowsError(try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("mixed-pages"), store: try store(), maximumPages: 1
        )) {
            XCTAssertEqual(
                $0 as? QuartzPDFRenderer.Error,
                .sourcePageLimitExceeded(actual: 2, limit: 1)
            )
        }
    }

    func testNativeFixtureStillRequiresExplicitSaveAndApproval() throws {
        let store = try store()
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: fixture("native-vector"), store: store
        )
        XCTAssertEqual(model.profile.id, "native-4x6-local")
        XCTAssertEqual(model.regions.first?.normalizedRect, try NormalizedRect(
            x: 0, y: 0, width: 1, height: 1
        ))
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(try? store.qualification(for: model.profile))
    }

    func testNativePageDoesNotRequireAnArtificialBorder() throws {
        let model = try WorkflowEditorBootstrap.makeModel(
            originalPDF: borderlessNativePDF(), store: try store()
        )
        XCTAssertEqual(model.profile.id, "native-4x6-local")
        XCTAssertEqual(model.profile.pageRules.first?.structuralAnchors, [])
        XCTAssertEqual(model.regions.first?.normalizedRect, try NormalizedRect(
            x: 0, y: 0, width: 1, height: 1
        ))
    }
}
