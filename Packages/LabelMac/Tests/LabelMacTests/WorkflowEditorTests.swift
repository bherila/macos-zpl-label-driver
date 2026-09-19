import CoreGraphics
import Foundation
import XCTest
import LabelCore
@testable import LabelMac

@MainActor
final class WorkflowEditorTests: XCTestCase {
    private enum TestError: Error { case unavailable }

    func testActionErrorsUsePrivateSafeMessagesWithoutChangingDraftOrSaveState() throws {
        let (model, _) = try makeModel()
        let profile = model.profile
        let generation = model.editGeneration
        let saved = model.isSaved
        let identity = ImmutablePublicationIdentity(id: "synthetic-private-identifier",
            schemaVersion: 1, revision: 1, sha256: String(repeating: "a", count: 64))
        let cases: [(any Swift.Error, String)] = [
            (NSError(domain: "synthetic-private.example.test", code: 1,
                userInfo: [NSFilePathErrorKey: "/private/synthetic-private-input.pdf",
                           NSLocalizedDescriptionKey: "synthetic-private-label"]),
             String(localized: "This edit could not be completed. Review the current draft before continuing.")),
            (WorkflowProfileDraft.Error.regionNotFound("synthetic-private-identifier"),
             String(localized: "The selected region is no longer available. Select a current region.")),
            (WorkflowEditorModel.Error.editSnapshotChanged,
             String(localized: "The draft changed. Review the current values before editing again.")),
            (WorkflowProfileStore.Error.commitUncertain(identity),
             String(localized: "Save completion is uncertain. Preserve the current draft and review saved revisions before retrying.")),
            // The geometry branch had no coverage anywhere in the suite, and it
            // is the branch that produced a raw `invalidNormalizedRegion` in the
            // UI before the mapping landed.
            (PageGeometryError.invalidNormalizedRegion,
             String(localized: "Enter finite, positive dimensions and keep the region within its source page.")),
            (PageGeometryError.nonFiniteValue,
             String(localized: "Enter finite, positive dimensions and keep the region within its source page.")),
            (PhysicalGeometryError.nonPositiveLength,
             String(localized: "Enter finite, positive dimensions and keep the region within its source page.")),
        ]
        for (error, expected) in cases {
            model.report(error)
            XCTAssertEqual(model.lastError, expected)
            XCTAssertFalse(model.lastError?.contains("synthetic-private") ?? true)
            XCTAssertEqual(model.profile, profile)
            XCTAssertEqual(model.editGeneration, generation)
            XCTAssertEqual(model.isSaved, saved)
        }
    }
    func testOutputStockMutationBindsPreviewAndPreservesRejectedEditState() throws {
        let (model, store) = try makeModel()
        try model.save()
        let saved = model.profile
        try model.refreshPreview()
        try confirmReview(model)
        let oldBinding = WorkflowEditorEditBinding(regionID: "selected", editGeneration: model.editGeneration)
        let stock = PhysicalSize(width: try Millimeters(7.055555555555555),
                                 height: try Millimeters(3.5277777777777777))
        try model.setOutputStock(id: "candidate-stock", size: stock, expectedBinding: oldBinding)
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.unreviewedRegionCount, model.regions.count)
        XCTAssertEqual(model.profile.pageRules, saved.pageRules)
        XCTAssertEqual(model.profile.revision, saved.revision + 1)
        XCTAssertEqual(try store.load(profileID: saved.id, revision: saved.revision), saved)
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.bitmap.layout.width, 20)
        XCTAssertEqual(model.preview?.bitmap.layout.height, 10)
        let current = model.profile
        let preview = model.preview
        let generation = model.editGeneration
        XCTAssertThrowsError(try model.setOutputStock(id: "stale-stock", size: saved.outputStock,
                                                     expectedBinding: oldBinding))
        XCTAssertThrowsError(try model.setOutputStock(id: "invalid stock", size: saved.outputStock))
        XCTAssertThrowsError(try model.setOutputStock(id: "oversized-stock", size: PhysicalSize(
            width: try Millimeters(10_000), height: try Millimeters(10))))
        XCTAssertEqual(model.profile, current)
        XCTAssertEqual(model.preview, preview)
        XCTAssertEqual(model.editGeneration, generation)
        try model.reloadForCorrection(profileID: saved.id, revision: saved.revision)
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.bitmap.layout.width, 10)
        XCTAssertEqual(model.preview?.bitmap.layout.height, 10)
    }

    func testMarginMutationBindsReviewRevisionAndRejectsEmptyDotAreaAtomically() throws {
        let (model, store) = try makeModel()
        try model.save()
        let saved = model.profile
        try model.refreshPreview()
        try confirmReview(model)
        let oldBinding = WorkflowEditorEditBinding(regionID: "selected", editGeneration: model.editGeneration)
        let unit = saved.outputStock.width.value / 10
        let margins = try OutputMargins(left: unit, top: 2 * unit, right: 3 * unit, bottom: unit)
        try model.setOutputMargins(margins, expectedBinding: oldBinding)
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.unreviewedRegionCount, model.regions.count)
        XCTAssertEqual(model.profile.schemaVersion, 3)
        XCTAssertEqual(model.profile.revision, saved.revision + 1)
        XCTAssertEqual(model.profile.pageRules, saved.pageRules)
        XCTAssertEqual(try store.load(profileID: saved.id, revision: saved.revision), saved)
        try model.refreshPreview()
        try confirmReview(model)
        let current = model.profile
        let preview = model.preview
        let generation = model.editGeneration
        XCTAssertThrowsError(try model.setOutputMargins(.zero, expectedBinding: oldBinding))
        XCTAssertThrowsError(try model.setOutputMargins(OutputMargins(left: saved.outputStock.width.value - 0.01, top: 0, right: 0, bottom: 0)))
        XCTAssertThrowsError(try model.setOutputStock(id: "empty-inset", size: PhysicalSize(
            width: Millimeters(4 * unit + 0.01), height: saved.outputStock.height)))
        XCTAssertEqual(model.profile, current)
        XCTAssertEqual(model.preview, preview)
        XCTAssertEqual(model.editGeneration, generation)
        XCTAssertEqual(model.unreviewedRegionCount, 0)
        try model.save()
        try model.reloadForCorrection(profileID: current.id, revision: current.revision)
        XCTAssertEqual(model.profile.outputMargins, margins)
        XCTAssertEqual(model.profile.schemaVersion, 3)
    }

    func testCompletedOldMarginWorkerCannotReplaceNewMarginPreview() async throws {
        let (model, _) = try makeModel()
        let executable = try worker()
        let barrier = PreviewBarrier()
        let obsolete = Task {
            await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5,
                afterPreparation: { await barrier.pause() })
        }
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await barrier.arrived) && ContinuousClock.now < limit { await Task.yield() }
        let arrived = await barrier.arrived
        XCTAssertTrue(arrived)
        try model.setOutputMargins(OutputMargins(left: 0.5, top: 0.5, right: 0.5, bottom: 0.5))
        await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5)
        let prepared = model.preview
        await barrier.release()
        await obsolete.value
        let current = try XCTUnwrap(prepared)
        XCTAssertEqual(model.preview, current)
        XCTAssertEqual(current.bitmap.layout.width, 10)
        XCTAssertFalse(model.isPreparingPreview)
        XCTAssertNil(model.lastError)
    }

    // MARK: - Editor UI defect regressions

    func testCommittingTheIdenticalRegionKeepsReviewAndTheExactPreview() async throws {
        let (model, _) = try makeModel()
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        try confirmReview(model)
        let reviewedProfile = model.profile
        let reviewedPreview = try XCTUnwrap(model.preview)
        let reviewedGeneration = model.editGeneration
        XCTAssertEqual(model.unreviewedRegionCount, 0)

        let region = try XCTUnwrap(model.regions.first { $0.id == model.selectedRegionID })
        // Exactly what a focus change through a bounds field commits: the value
        // already stored, unchanged.
        try model.updateSelectedRegion(region.normalizedRect, expectedRegionID: region.id)

        XCTAssertEqual(model.editGeneration, reviewedGeneration, "a no-op must not bump the edit generation")
        XCTAssertEqual(model.profile, reviewedProfile)
        XCTAssertEqual(model.preview, reviewedPreview, "a no-op must not cancel the reviewed preview")
        XCTAssertEqual(model.unreviewedRegionCount, 0, "a no-op must not invalidate review")
    }

    func testANoOpCommitDoesNotForkARevisionOrClearSavedState() throws {
        let (model, _) = try makeModel()
        try model.save()
        XCTAssertTrue(model.isSaved)
        let savedProfile = model.profile
        let savedGeneration = model.editGeneration

        let region = try XCTUnwrap(model.regions.first { $0.id == model.selectedRegionID })
        try model.updateSelectedRegion(region.normalizedRect, expectedRegionID: region.id)

        // editableDraft() would return correctionDraft(for:) at revision + 1 here,
        // so without the guard this silently forks a revision.
        XCTAssertTrue(model.isSaved, "a no-op must not clear saved state")
        XCTAssertEqual(model.profile, savedProfile)
        XCTAssertEqual(model.editGeneration, savedGeneration)
    }

    func testARealEditStillInvalidatesReviewAfterTheNoOpGuard() async throws {
        let (model, _) = try makeModel()
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        try confirmReview(model)
        let generation = model.editGeneration
        XCTAssertEqual(model.unreviewedRegionCount, 0)

        let region = try XCTUnwrap(model.regions.first { $0.id == model.selectedRegionID })
        let moved = try NormalizedRect(
            x: region.normalizedRect.x, y: region.normalizedRect.y,
            width: region.normalizedRect.width / 2, height: region.normalizedRect.height)
        try model.updateSelectedRegion(moved, expectedRegionID: region.id)

        XCTAssertEqual(model.editGeneration, generation + 1)
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.unreviewedRegionCount, 1)
    }

    func testANoOpCommitStillRejectsAStaleEditBinding() throws {
        let (model, _) = try makeModel()
        let region = try XCTUnwrap(model.regions.first { $0.id == model.selectedRegionID })
        let stale = WorkflowEditorEditBinding(regionID: region.id, editGeneration: model.editGeneration)
        let moved = try NormalizedRect(
            x: region.normalizedRect.x, y: region.normalizedRect.y,
            width: region.normalizedRect.width / 2, height: region.normalizedRect.height)
        try model.updateSelectedRegion(moved, expectedRegionID: region.id)
        // The guard must not short-circuit the snapshot check that precedes it.
        XCTAssertThrowsError(try model.updateSelectedRegion(
            region.normalizedRect, expectedRegionID: region.id, expectedBinding: stale)) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .editSnapshotChanged)
        }
    }

    func testRegionCountSummariesAgreeWithTheirCount() throws {
        let (model, _) = try makeModel()
        XCTAssertEqual(WorkflowEditorModel.labelRegionSummary(page: 1, regions: 1),
                       String(localized: "Page 1: 1 label region"))
        XCTAssertEqual(WorkflowEditorModel.labelRegionSummary(page: 2, regions: 3),
                       String(localized: "Page 2: 3 label regions"))
        XCTAssertEqual(WorkflowEditorModel.labelRegionSummary(page: 1, regions: 0),
                       String(localized: "Page 1: 0 label regions"))
        // Never the ungrammatical "1 regions" the view produced.
        XCTAssertFalse(WorkflowEditorModel.labelRegionSummary(page: 1, regions: 1).contains("1 label regions"))
        XCTAssertFalse(model.unreviewedRegionSummary.isEmpty)
    }

    func testUnreviewedSummaryUsesTheSingularForOneRegion() async throws {
        let (model, _) = try makeModel()
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        try confirmReview(model)
        XCTAssertEqual(model.unreviewedRegionCount, 0)
        XCTAssertEqual(model.unreviewedRegionSummary,
                       String(localized: "0 regions require review before unattended approval."))
        try model.setSelectedRotation(.degrees90)
        XCTAssertEqual(model.unreviewedRegionCount, 1)
        XCTAssertEqual(model.unreviewedRegionSummary,
                       String(localized: "1 region requires review before unattended approval."))
        XCTAssertFalse(model.unreviewedRegionSummary.contains("1 regions"))
    }

    private func confirmReview(_ model: WorkflowEditorModel) throws {
        try model.confirmSelectedBoundsAndPreviewReviewed(expectedProfile: model.profile, expectedPreview: model.preview,
            expectedEditGeneration: model.editGeneration)
    }

    func testStaleDisplayedMeasurementCannotEditNewlySelectedRegion() throws {
        let (model, _) = try makeModel()
        try model.addRegionOnSelectedPage()
        let otherID = try XCTUnwrap(model.selectedRegionID)
        model.selectedRegionID = "selected"
        let binding = WorkflowEditorEditBinding(regionID: "selected", editGeneration: model.editGeneration)
        let displayedCallback = {
            try model.setSelectedRegionMillimeters(left: 0.2, top: 0.2, width: 2, height: 2,
                expectedBinding: binding)
        }
        let displayedGeneration = model.editGeneration
        model.selectedRegionID = otherID
        let before = model.profile
        XCTAssertEqual(model.editGeneration, displayedGeneration)
        XCTAssertThrowsError(try displayedCallback())
        XCTAssertEqual(model.profile, before)
        XCTAssertEqual(model.editGeneration, displayedGeneration)
    }

    func testSavingInvalidatesDisplayedDraftCallbackWithoutCreatingCorrection() throws {
        let (model, store) = try makeModel()
        let original = model.profile
        let binding = WorkflowEditorEditBinding(regionID: "selected", editGeneration: model.editGeneration)
        try model.save()
        let savedGeneration = model.editGeneration
        XCTAssertEqual(savedGeneration, binding.editGeneration + 1)
        XCTAssertThrowsError(try model.setSelectedRegionMillimeters(
            left: 0.2, top: 0.2, width: 2, height: 2, expectedBinding: binding)) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .editSnapshotChanged)
        }
        XCTAssertTrue(model.isSaved)
        XCTAssertEqual(model.profile, original)
        XCTAssertEqual(model.editGeneration, savedGeneration)
        XCTAssertEqual(try store.load(profileID: original.id, revision: original.revision), original)
        try model.save()
        XCTAssertEqual(model.editGeneration, savedGeneration)
    }

    func testDisplayedEditGenerationRejectsUndoAndStaleRegionActionsWithoutMutation() throws {
        let (model, _) = try makeModel()
        let old = WorkflowEditorEditBinding(regionID: "selected", editGeneration: model.editGeneration)
        let initial = model.profile
        try model.setSelectedRotation(.degrees90)
        try model.setSelectedRotation(.degrees0)
        XCTAssertEqual(model.profile, initial)
        let generation = model.editGeneration
        let rect = try NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        let actions: [() throws -> Void] = [
            { try model.setSelectedRotation(.degrees270, expectedBinding: old) },
            { try model.moveSelected(by: 0, expectedBinding: old) },
            { try model.addRegionOnSelectedPage(expectedBinding: old) },
            { try model.removeSelectedRegion(expectedBinding: old) },
            { try model.updateSelectedRegion(rect, expectedRegionID: "selected", expectedBinding: old) }
        ]
        for action in actions {
            XCTAssertThrowsError(try action()) {
                XCTAssertEqual($0 as? WorkflowEditorModel.Error, .editSnapshotChanged)
            }
            XCTAssertEqual(model.profile, initial)
            XCTAssertEqual(model.editGeneration, generation)
            XCTAssertEqual(model.selectedRegionID, "selected")
        }
        let current = WorkflowEditorEditBinding(regionID: "selected", editGeneration: generation)
        try model.setSelectedRotation(.degrees90, expectedBinding: current)
        XCTAssertEqual(model.regions.first?.rotation, .degrees90)
        XCTAssertEqual(model.editGeneration, generation + 1)
    }

    func testSavedDrawAndNumericalEditsPublishNewRevisionWithoutOverwriting() throws {
        let (model, store) = try makeModel()
        let original = model.profile
        try model.save()
        XCTAssertThrowsError(try model.setSelectedRegionMillimeters(left: -1, top: 0, width: 1, height: 1))
        XCTAssertThrowsError(try model.moveSelected(by: Int.max))
        let rect = try SourceRegionSelection.rectangle(viewportWidth: 200, viewportHeight: 100,
            startX: 20, startY: 10, endX: 100, endY: 50)
        XCTAssertThrowsError(try model.updateSelectedRegion(rect, expectedRegionID: "stale-selection"))
        XCTAssertEqual(model.profile, original)
        XCTAssertTrue(model.isSaved)
        try model.updateSelectedRegion(rect, expectedRegionID: "selected")
        XCTAssertEqual(model.profile.revision, original.revision + 1)
        XCTAssertFalse(model.isSaved)
        try model.setSelectedRotation(.degrees90)
        XCTAssertEqual(model.profile.revision, original.revision + 1)
        try model.save()
        let second = model.profile
        XCTAssertEqual(try store.load(profileID: original.id, revision: original.revision), original)
        XCTAssertEqual(try store.load(profileID: second.id, revision: second.revision), second)
        try model.setSelectedRegionMillimeters(left: 0.2, top: 0.2, width: 2, height: 2)
        XCTAssertEqual(model.profile.revision, original.revision + 2)
        try model.save()
        XCTAssertEqual(try store.load(profileID: second.id, revision: second.revision), second)
    }

    private func pdf(pages: Int = 1) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw TestError.unavailable }
        var box = CGRect(x: 0, y: 0, width: 20, height: 10)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw TestError.unavailable }
        for _ in 0..<pages {
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    func testAddRemoveEditAndSaveMultipleLabelsFromOriginalSource() async throws {
        let (model, store) = try makeModel()
        try model.save()
        let original = model.profile
        XCTAssertThrowsError(try model.removeSelectedRegion())
        XCTAssertTrue(model.isSaved)
        try model.addRegionOnSelectedPage()
        let addedID = try XCTUnwrap(model.selectedRegionID)
        XCTAssertNotEqual(addedID, "selected")
        XCTAssertEqual(model.regions.map(\.sourcePage), [1, 1])
        XCTAssertEqual(model.profile.revision, original.revision + 1)
        let size = model.profile.pageRules[0].expectedInput.uprightPhysicalSize
        try model.setSelectedRegionMillimeters(left: size.width.value / 2, top: 0,
            width: size.width.value / 2, height: size.height.value)
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.preview?.bitmap.bytes, Array(repeating: [0x00, 0x00], count: 10).flatMap { $0 })
        XCTAssertEqual(model.preview?.previewPBM, model.preview?.bitmap.pbmData())
        try model.moveSelected(by: -1)
        XCTAssertEqual(model.regions.map(\.id), [addedID, "selected"])
        try model.save()
        XCTAssertEqual(try store.load(profileID: model.profile.id, revision: model.profile.revision), model.profile)
        XCTAssertEqual(try store.load(profileID: original.id, revision: original.revision), original)
        try model.removeSelectedRegion()
        XCTAssertEqual(model.selectedRegionID, "selected")
        XCTAssertEqual(model.regions.count, 1)
        XCTAssertEqual(model.profile.revision, original.revision + 2)
        XCTAssertNil(model.preview)
    }

    func testExplicitPagePolicyPreservesSavedRevisionAndRejectsStaleConfirmation() async throws {
        let (reference, store) = try makeModel()
        let originalRule = reference.profile.pageRules[0]
        let region = try ExtractionRegion(id: "second", normalizedRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1),
            outputOrder: 1)
        let profile = try WorkflowProfile(id: reference.profile.id, revision: reference.profile.revision,
            outputStockID: reference.profile.outputStockID, outputStock: reference.profile.outputStock,
            pageRules: [originalRule, WorkflowPageRule(sourcePage: 2, expectedInput: originalRule.expectedInput,
                disposition: .extract([region]), structuralAnchors: originalRule.structuralAnchors)])
        let source = try PDFPageBox(originX: 0, originY: 0, width: 20, height: 10)
        let analyzed = try AnalyzedSourcePage(pageBox: source, anchors: originalRule.structuralAnchors.map {
            ObservedPageAnchor(kind: $0.kind, normalizedRect: $0.normalizedRect)
        })
        let canvas = try DotCanvas(physicalSize: profile.outputStock,
            resolution: DotResolution(xDotsPerMillimeter: 72 / 25.4, yDotsPerMillimeter: 72 / 25.4))
        let model = WorkflowEditorModel(draft: WorkflowProfileDraft(profile: profile), originalPDF: try pdf(pages: 2),
            analyzedPages: [analyzed, analyzed], canvas: canvas, store: store)
        try model.save()
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertNotNil(model.preview)
        try model.skipPage(1, reason: .instructions, expectedProfile: profile)
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.selectedRegionID, "second")
        XCTAssertEqual(model.profile.revision, profile.revision + 1)
        XCTAssertEqual(model.profile.pageRules[0].disposition, .skip(.instructions))
        let skipped = model.profile
        XCTAssertThrowsError(try model.skipPage(2, reason: .customsForm, expectedProfile: profile))
        XCTAssertThrowsError(try model.skipPage(2, reason: .customsForm, expectedProfile: skipped)) {
            XCTAssertEqual($0 as? WorkflowProfileDraft.Error, .lastOutputPage)
        }
        XCTAssertEqual(model.profile, skipped)
        try model.save()
        try model.restorePage(1)
        let restoredID = try XCTUnwrap(model.selectedRegionID)
        XCTAssertNotEqual(restoredID, "selected")
        XCTAssertEqual(model.regions.map(\.sourcePage), [2, 1])
        XCTAssertEqual(model.regions.last?.normalizedRect, try NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(model.profile.revision, profile.revision + 2)
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.preview?.regionID, restoredID)
        XCTAssertEqual(model.preview?.previewPBM, model.preview?.bitmap.pbmData())
        try model.save()
        XCTAssertEqual(model.unreviewedRegionCount, 2)
        XCTAssertThrowsError(try model.approveForUnattendedUse()) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .regionReviewRequired)
        }
        try confirmReview(model)
        XCTAssertEqual(model.unreviewedRegionCount, 1)
        XCTAssertFalse(model.canApproveForUnattendedUse)
        model.select("second")
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        try confirmReview(model)
        XCTAssertTrue(model.canApproveForUnattendedUse)
        try model.approveForUnattendedUse()
        let qualified = model.profile
        try model.reloadForCorrection(profileID: qualified.id, revision: qualified.revision)
        try model.save()
        XCTAssertEqual(model.unreviewedRegionCount, 2)
        XCTAssertThrowsError(try model.approveForUnattendedUse()) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .regionReviewRequired)
        }
        XCTAssertNil(try store.qualification(for: model.profile))
        XCTAssertNotNil(try store.qualification(for: qualified))
        XCTAssertEqual(try store.load(profileID: profile.id, revision: profile.revision), profile)
        XCTAssertEqual(try store.load(profileID: skipped.id, revision: skipped.revision), skipped)
    }

    func testExactPreviewReviewIsExplicitAndCannotSurviveProfileEdits() async throws {
        let (model, store) = try makeModel()
        try model.save()
        XCTAssertThrowsError(try confirmReview(model)) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .previewRequired)
        }
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertEqual(model.unreviewedRegionCount, 1)
        XCTAssertFalse(model.canApproveForUnattendedUse)
        try confirmReview(model)
        XCTAssertEqual(model.unreviewedRegionCount, 0)
        try model.approveForUnattendedUse()
        let original = model.profile
        try model.setSelectedRotation(.degrees90)
        XCTAssertEqual(model.unreviewedRegionCount, 1)
        XCTAssertNil(model.preview)
        XCTAssertThrowsError(try confirmReview(model))
        try model.save()
        XCTAssertThrowsError(try model.approveForUnattendedUse()) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .regionReviewRequired)
        }
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        try confirmReview(model)
        try model.approveForUnattendedUse()
        XCTAssertNotNil(try store.qualification(for: original))
        XCTAssertNotNil(try store.qualification(for: model.profile))
    }

    func testStaleDisplayedPreviewCannotAcknowledgeNewSelectionOrProfile() async throws {
        let (model, _) = try makeModel()
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        let displayedProfile = model.profile
        let displayedPreview = try XCTUnwrap(model.preview)
        let displayedGeneration = model.editGeneration
        try model.addRegionOnSelectedPage()
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertThrowsError(try model.confirmSelectedBoundsAndPreviewReviewed(
            expectedProfile: displayedProfile, expectedPreview: displayedPreview,
            expectedEditGeneration: displayedGeneration)) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .reviewSnapshotChanged)
        }
        XCTAssertEqual(model.unreviewedRegionCount, 2)
        let currentProfile = model.profile
        let currentPreview = try XCTUnwrap(model.preview)
        let currentGeneration = model.editGeneration
        model.select("selected")
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertThrowsError(try model.confirmSelectedBoundsAndPreviewReviewed(
            expectedProfile: currentProfile, expectedPreview: currentPreview,
            expectedEditGeneration: currentGeneration)) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .reviewSnapshotChanged)
        }
        XCTAssertEqual(model.unreviewedRegionCount, 2)
        try confirmReview(model)
        XCTAssertEqual(model.unreviewedRegionCount, 1)
    }

    func testUnsavedUndoCannotResurrectReviewOrAcceptAnOldDisplayedGeneration() async throws {
        let (model, store) = try makeModel()
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        try confirmReview(model)
        let original = model.profile
        let oldPreview = try XCTUnwrap(model.preview)
        let oldGeneration = model.editGeneration
        XCTAssertEqual(model.unreviewedRegionCount, 0)
        XCTAssertFalse(model.isSaved)
        try model.setSelectedRotation(.degrees90)
        try model.setSelectedRotation(.degrees0)
        XCTAssertEqual(model.profile, original)
        XCTAssertEqual(model.editGeneration, oldGeneration + 2)
        XCTAssertEqual(model.unreviewedRegionCount, 1)
        XCTAssertNil(model.preview)
        try model.save()
        XCTAssertFalse(model.canApproveForUnattendedUse)
        XCTAssertThrowsError(try model.approveForUnattendedUse())
        XCTAssertNil(try store.qualification(for: original))
        await model.refreshPreviewInWorker(workerExecutable: try worker())
        XCTAssertEqual(model.preview, oldPreview)
        XCTAssertThrowsError(try model.confirmSelectedBoundsAndPreviewReviewed(expectedProfile: original,
            expectedPreview: oldPreview, expectedEditGeneration: oldGeneration)) {
            XCTAssertEqual($0 as? WorkflowEditorModel.Error, .reviewSnapshotChanged)
        }
        XCTAssertEqual(model.unreviewedRegionCount, 1)
        try confirmReview(model)
        try model.approveForUnattendedUse()
        let generation = model.editGeneration
        XCTAssertThrowsError(try model.setSelectedRegionMillimeters(left: -1, top: 0, width: 1, height: 1))
        XCTAssertEqual(model.editGeneration, generation)
        XCTAssertTrue(model.canApproveForUnattendedUse)
    }

    // Pins Observation 4 of docs/validation/M5-OFFLINE-GUI-SECTION-A-2026-09-18.md.
    // Keyboard focus entering or leaving a bounds field makes the view's
    // TextField(value:format:) commit the value it already displays, so the model
    // receives a set-to-the-current-value call. That call changes nothing in the
    // draft, so it must not discard the reviewed exact preview, the recorded region
    // review, or the edit generation the other displayed fields are bound to.
    func testFocusOnlyBoundsCommitKeepsReviewedPreviewAndEditGeneration() throws {
        let (model, _) = try makeModel()
        try model.refreshPreview()
        try confirmReview(model)
        XCTAssertEqual(model.unreviewedRegionCount, 0)
        let before = model.draft
        let preview = try XCTUnwrap(model.preview)
        let generation = model.editGeneration
        let displayed = try displayedBoundsMillimeters(model)
        try model.setSelectedRegionMillimeters(left: displayed.left, top: displayed.top,
            width: displayed.width, height: displayed.height)
        // The millimeter round trip is exact for this fixture, so an inequality here
        // would mean the commit changed geometry rather than merely invalidating.
        XCTAssertEqual(model.draft, before)
        XCTAssertEqual(model.editGeneration, generation)
        XCTAssertEqual(model.preview, preview)
        XCTAssertEqual(model.unreviewedRegionCount, 0)
    }

    // Also Observation 4 of docs/validation/M5-OFFLINE-GUI-SECTION-A-2026-09-18.md.
    // All four bounds fields of one render pass capture the same edit generation, so
    // a focus-only commit that advances it strands the other three. The next real
    // edit typed into any of them then fails with editSnapshotChanged, which is the
    // state the operator reached by tabbing without changing a value.
    func testFocusOnlyBoundsCommitDoesNotStrandSiblingFieldBindings() throws {
        let (model, _) = try makeModel()
        let region = try XCTUnwrap(model.regions.first)
        let displayedBinding = WorkflowEditorEditBinding(regionID: region.id,
            editGeneration: model.editGeneration)
        let displayed = try displayedBoundsMillimeters(model)
        try model.setSelectedRegionMillimeters(left: displayed.left, top: displayed.top,
            width: displayed.width, height: displayed.height, expectedBinding: displayedBinding)
        XCTAssertNoThrow(try model.setSelectedRegionMillimeters(left: displayed.left,
            top: displayed.top, width: displayed.width / 2, height: displayed.height,
            expectedBinding: displayedBinding))
        let updated = try XCTUnwrap(model.regions.first)
        XCTAssertEqual(updated.normalizedRect.width, region.normalizedRect.width / 2,
                       accuracy: 1e-12)
    }

    // The four millimeter values WorkflowEditorView.regionControls displays for the
    // selected region, derived exactly as that view derives them.
    private func displayedBoundsMillimeters(_ model: WorkflowEditorModel) throws
        -> (left: Double, top: Double, width: Double, height: Double) {
        let region = try XCTUnwrap(model.regions.first(where: { $0.id == model.selectedRegionID }))
        let rule = try XCTUnwrap(model.profile.pageRules.first(where: { $0.sourcePage == region.sourcePage }))
        let size = rule.expectedInput.uprightPhysicalSize
        return (left: region.normalizedRect.x * size.width.value,
                top: region.normalizedRect.y * size.height.value,
                width: region.normalizedRect.width * size.width.value,
                height: region.normalizedRect.height * size.height.value)
    }

    private func makeModel() throws -> (WorkflowEditorModel, WorkflowProfileStore) {
        let source = try PDFPageBox(originX: 0, originY: 0, width: 20, height: 10)
        let sourceSize = try source.effectivePhysicalSize()
        let stock = PhysicalSize(
            width: try Millimeters(10 * 25.4 / 72),
            height: try Millimeters(10 * 25.4 / 72)
        )
        let selected = try NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        let anchor = try NormalizedRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
        let profile = try WorkflowProfile(
            id: "editor-fixture", revision: 1,
            outputStockID: "test-stock", outputStock: stock,
            pageRules: [try WorkflowPageRule(
                sourcePage: 1,
                expectedInput: ExpectedInputPage(uprightPhysicalSize: sourceSize),
                disposition: .extract([try ExtractionRegion(
                    id: "selected", normalizedRect: selected, outputOrder: 0
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: "layout", kind: .border, normalizedRect: anchor
                )]
            )]
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "WorkflowEditorTests-\(UUID().uuidString)"
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try WorkflowProfileStore(root: root)
        let canvas = try DotCanvas(
            physicalSize: stock,
            resolution: DotResolution(
                xDotsPerMillimeter: 72 / 25.4,
                yDotsPerMillimeter: 72 / 25.4
            )
        )
        return (WorkflowEditorModel(
            draft: try WorkflowProfileDraft(nextRevisionOf: profile),
            originalPDF: try pdf(),
            analyzedPages: [try AnalyzedSourcePage(
                pageBox: source,
                anchors: [.init(kind: .border, normalizedRect: anchor)]
            )],
            canvas: canvas,
            store: store
        ), store)
    }

    func testPreviewUsesExactPackedOutputAndMillimeterCorrection() throws {
        let (model, _) = try makeModel()
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.bitmap.bytes, Array(repeating: [0xFF, 0xC0], count: 10).flatMap { $0 })
        XCTAssertEqual(model.preview?.previewPBM, model.preview?.bitmap.pbmData())

        let pageWidth = model.profile.pageRules[0].expectedInput.uprightPhysicalSize.width.value
        let pageHeight = model.profile.pageRules[0].expectedInput.uprightPhysicalSize.height.value
        try model.setSelectedRegionMillimeters(
            left: pageWidth / 2, top: 0, width: pageWidth / 2, height: pageHeight
        )
        XCTAssertNil(model.preview)
        try model.refreshPreview()
        XCTAssertEqual(model.preview?.bitmap.bytes, Array(repeating: [0x00, 0x00], count: 10).flatMap { $0 })
    }

    func testSaveApprovalReloadAndCorrectionUseDistinctRevisions() throws {
        let (model, store) = try makeModel()
        XCTAssertEqual(model.profile.revision, 2)
        XCTAssertFalse(model.isSaved)
        try model.save()
        XCTAssertTrue(model.isSaved)
        XCTAssertNil(try store.qualification(for: model.profile))
        try model.refreshPreview()
        try confirmReview(model)
        try model.approveForUnattendedUse()
        XCTAssertNotNil(try store.qualification(for: model.profile))

        try model.reloadForCorrection(profileID: model.profile.id, revision: 2)
        XCTAssertEqual(model.profile.revision, 3)
        XCTAssertFalse(model.isSaved)
        XCTAssertNil(model.preview)
        XCTAssertNil(try? store.qualification(for: model.profile))
    }

    func testInvalidMillimeterEditLeavesDraftAndPreviewUnchanged() throws {
        let (model, _) = try makeModel()
        try model.refreshPreview()
        let before = model.draft
        let preview = model.preview
        XCTAssertThrowsError(try model.setSelectedRegionMillimeters(
            left: -1, top: 0, width: 1, height: 1
        ))
        XCTAssertEqual(model.draft, before)
        XCTAssertEqual(model.preview, preview)
    }

    func testNativeViewCanBeConstructedFromModel() throws {
        let (model, _) = try makeModel()
        _ = WorkflowEditorView(model: model)
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

    func testWorkerPreviewMatchesExactOriginalPackedOutput() async throws {
        let (model, _) = try makeModel()
        try model.refreshPreview()
        let expected = try XCTUnwrap(model.preview)
        await model.refreshPreviewInWorker(workerExecutable: try worker(), deadlineSeconds: 5)
        XCTAssertEqual(model.preview, expected)
        XCTAssertEqual(model.preview?.previewPBM, expected.bitmap.pbmData())
        XCTAssertFalse(model.isPreparingPreview)
        XCTAssertNil(model.lastError)
    }

    func testEditsCancelObsoletePreviewWithoutInstallingItsResultOrError() async throws {
        let (model, _) = try makeModel()
        let task = Task { await model.refreshPreviewInWorker(
            workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"), deadlineSeconds: 5) }
        let limit = ContinuousClock.now.advanced(by: .seconds(1))
        while !model.isPreparingPreview && ContinuousClock.now < limit { await Task.yield() }
        XCTAssertTrue(model.isPreparingPreview)
        try model.setSelectedRotation(.degrees90)
        await task.value
        XCTAssertNil(model.preview)
        XCTAssertNil(model.lastError)
        XCTAssertFalse(model.isPreparingPreview)
        await model.refreshPreviewInWorker(workerExecutable: try worker(), deadlineSeconds: 5)
        XCTAssertNotNil(model.preview)
        XCTAssertNil(model.lastError)
    }

    func testSelectionAndTaskCancellationRejectPendingPreview() async throws {
        let (model, _) = try makeModel()
        for cancelTask in [false, true] {
            model.selectedRegionID = "selected"
            let task = Task { await model.refreshPreviewInWorker(
                workerExecutable: URL(fileURLWithPath: "/usr/bin/yes"), deadlineSeconds: 5) }
            let limit = ContinuousClock.now.advanced(by: .seconds(1))
            while !model.isPreparingPreview && ContinuousClock.now < limit { await Task.yield() }
            XCTAssertTrue(model.isPreparingPreview)
            if cancelTask { task.cancel() } else { model.selectedRegionID = nil }
            await task.value
            XCTAssertNil(model.preview)
            XCTAssertNil(model.lastError)
            XCTAssertFalse(model.isPreparingPreview)
        }
    }

    func testUnavailableWorkerFailsWithoutInProcessFallback() async throws {
        let (model, _) = try makeModel()
        await model.refreshPreviewInWorker(workerExecutable: URL(fileURLWithPath: "/nonexistent-worker"))
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.lastError, "Preview could not be prepared.")
        XCTAssertFalse(model.isPreparingPreview)
    }

    private actor PreviewBarrier {
        var arrived = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func pause() async {
            arrived = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    func testCompletedOldStockWorkerCannotReplaceResizedPreview() async throws {
        let (model, _) = try makeModel()
        let executable = try worker()
        let barrier = PreviewBarrier()
        let obsolete = Task {
            await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5,
                afterPreparation: { await barrier.pause() })
        }
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await barrier.arrived) && ContinuousClock.now < limit { await Task.yield() }
        let arrived = await barrier.arrived
        XCTAssertTrue(arrived)
        XCTAssertNoThrow(try model.setOutputStock(id: "resized-stock", size: PhysicalSize(
            width: try Millimeters(7.055555555555555), height: try Millimeters(3.5277777777777777))))
        await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5)
        let current = model.preview
        await barrier.release()
        await obsolete.value
        XCTAssertEqual(current?.bitmap.layout.width, 20)
        XCTAssertEqual(current?.bitmap.layout.height, 10)
        XCTAssertEqual(model.preview, current)
        XCTAssertFalse(model.isPreparingPreview)
        XCTAssertNil(model.lastError)
    }

    func testCompletedObsoleteWorkerCannotReplaceNewerPreview() async throws {
        let (model, _) = try makeModel()
        let executable = try worker()
        let barrier = PreviewBarrier()
        let obsolete = Task {
            await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5,
                afterPreparation: { await barrier.pause() })
        }
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await barrier.arrived) && ContinuousClock.now < limit { await Task.yield() }
        let arrived = await barrier.arrived
        XCTAssertTrue(arrived)
        XCTAssertNoThrow(try model.setSelectedRotation(.degrees90))
        await model.refreshPreviewInWorker(workerExecutable: executable, deadlineSeconds: 5)
        let current = model.preview
        await barrier.release()
        await obsolete.value
        XCTAssertNotNil(current)
        XCTAssertEqual(model.preview, current)
        XCTAssertFalse(model.isPreparingPreview)
        XCTAssertNil(model.lastError)
    }
}
