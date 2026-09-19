import CoreGraphics
import Combine
import Foundation
import LabelCore
import SwiftUI

public struct WorkflowEditorRegion: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourcePage: Int
    public let normalizedRect: NormalizedRect
    public let rotation: ExtractionRotation
    public let outputOrder: Int
}

/// In-memory displayed edit context, not authorization or a persisted schema.
public struct WorkflowEditorEditBinding: Equatable, Sendable {
    public let regionID: String
    public let editGeneration: UInt64
    public init(regionID: String, editGeneration: UInt64) {
        self.regionID = regionID
        self.editGeneration = editGeneration
    }
}

@MainActor
public final class WorkflowEditorModel: ObservableObject {
    public enum Error: Swift.Error, Equatable, Sendable {
        case previewRequired
        case savedRevisionRequired
        case regionReviewRequired
        case reviewSnapshotChanged
        case editSequenceExhausted
        case editSnapshotChanged
    }
    @Published public private(set) var draft: WorkflowProfileDraft
    @Published public var selectedRegionID: String? {
        didSet { if selectedRegionID != oldValue { cancelPreview(); cancelSourcePreview() } }
    }
    @Published public private(set) var preview: PreparedExtractionLabel?
    @Published public private(set) var lastError: String?
    @Published public private(set) var isSaved = false
    @Published public private(set) var isPreparingPreview = false
    @Published public private(set) var sourcePreview: WorkflowSourcePagePreview?
    @Published public private(set) var sourcePreviewError: String?
    @Published public private(set) var isPreparingSourcePreview = false
    @Published private var reviewedProfile: WorkflowProfile?
    @Published private var reviewedRegionIDs: Set<String> = []
    @Published public private(set) var editGeneration: UInt64 = 0

    private var sourceRequest: UUID?
    private var sourceCancellation: OfflineRenderWorkerCancellation?

    private var previewRequest: UUID?
    private var previewCancellation: OfflineRenderWorkerCancellation?

    private let originalPDF: Data
    private let analyzedPages: [AnalyzedSourcePage]
    private var canvas: DotCanvas
    private let store: WorkflowProfileStore
    public let isManualDraft: Bool
    public let isReopenedWorkflow: Bool

    public init(
        draft: WorkflowProfileDraft,
        originalPDF: Data,
        analyzedPages: [AnalyzedSourcePage],
        canvas: DotCanvas,
        store: WorkflowProfileStore,
        isManualDraft: Bool = false,
        isReopenedWorkflow: Bool = false
    ) {
        self.draft = draft
        self.originalPDF = originalPDF
        self.analyzedPages = analyzedPages
        self.canvas = canvas
        self.store = store
        self.isManualDraft = isManualDraft
        self.isReopenedWorkflow = isReopenedWorkflow
        self.selectedRegionID = Self.regions(in: draft.profile).first?.id
    }

    public var profile: WorkflowProfile { draft.validatedProfile() }
    public var regions: [WorkflowEditorRegion] { Self.regions(in: profile) }

    /// Review is session-local and exact-profile bound. Every newly opened
    /// editor starts unreviewed, so saving/reopening cannot bypass the UI gate.
    public var unreviewedRegionCount: Int {
        reviewedProfile == profile
            ? regions.filter { !reviewedRegionIDs.contains($0.id) }.count : regions.count
    }

    /// Rendered here rather than inline in a view so the plural form is testable.
    ///
    /// The view interpolated the count into a fixed plural sentence, so a single
    /// outstanding region read "1 regions require review".
    public var unreviewedRegionSummary: String {
        unreviewedRegionCount == 1
            ? String(localized: "1 region requires review before unattended approval.")
            : String(localized: "\(unreviewedRegionCount) regions require review before unattended approval.")
    }

    /// Per-page region count for the page list, in the model for the same reason.
    public static func labelRegionSummary(page: Int, regions: Int) -> String {
        regions == 1
            ? String(localized: "Page \(page): 1 label region")
            : String(localized: "Page \(page): \(regions) label regions")
    }

    public var canConfirmSelectedBoundsAndPreview: Bool {
        guard !isPreparingPreview, let selectedRegionID,
              let region = regions.first(where: { $0.id == selectedRegionID }), let preview else { return false }
        return preview.regionID == region.id && preview.sourcePage == region.sourcePage
            && preview.profileID == profile.id && preview.profileRevision == profile.revision
    }

    public var canApproveForUnattendedUse: Bool {
        isSaved && unreviewedRegionCount == 0 && !profile.pageRules.contains { $0.structuralAnchors.isEmpty }
    }

    public func confirmSelectedBoundsAndPreviewReviewed(expectedProfile: WorkflowProfile,
                                                        expectedPreview: PreparedExtractionLabel?,
                                                        expectedEditGeneration: UInt64) throws {
        guard profile == expectedProfile, preview == expectedPreview,
              editGeneration == expectedEditGeneration else { throw Error.reviewSnapshotChanged }
        guard canConfirmSelectedBoundsAndPreview, let selectedRegionID else { throw Error.previewRequired }
        if reviewedProfile != profile { reviewedRegionIDs = []; reviewedProfile = profile }
        reviewedRegionIDs.insert(selectedRegionID)
    }

    public func select(_ id: String) { selectedRegionID = id }

    public func cancelSourcePreview() {
        sourceCancellation?.cancel()
        sourceCancellation = nil
        sourceRequest = nil
        sourcePreview = nil
        sourcePreviewError = nil
        isPreparingSourcePreview = false
    }

    public func refreshSourcePageInWorker(workerExecutable: URL, deadlineSeconds: Double = 60) async {
        await refreshSourcePageInWorker(workerExecutable: workerExecutable,
            deadlineSeconds: deadlineSeconds, afterPreparation: {})
    }

    func refreshSourcePageInWorker(workerExecutable: URL, deadlineSeconds: Double,
        afterPreparation: @escaping @Sendable () async -> Void) async {
        cancelSourcePreview()
        let selection = selectedRegionID
        let request = UUID()
        let cancellation = OfflineRenderWorkerCancellation()
        sourceRequest = request
        sourceCancellation = cancellation
        isPreparingSourcePreview = true
        defer {
            if sourceRequest == request {
                sourceRequest = nil
                sourceCancellation = nil
                isPreparingSourcePreview = false
            }
        }
        do {
            guard let region = regions.first(where: { $0.id == selection }),
                  analyzedPages.indices.contains(region.sourcePage - 1) else {
                throw WorkflowProfileDraft.Error.regionNotFound(selection ?? "")
            }
            let source = originalPDF
            let box = analyzedPages[region.sourcePage - 1].pageBox
            let result = try await withTaskCancellationHandler {
                try await Task.detached {
                    try WorkflowSourcePagePreview.render(originalPDF: source,
                        sourcePage: region.sourcePage, pageBox: box,
                        workerExecutable: workerExecutable, deadlineSeconds: deadlineSeconds,
                        cancellation: cancellation)
                }.value
            } onCancel: { cancellation.cancel() }
            await afterPreparation()
            guard sourceRequest == request, selectedRegionID == selection,
                  !Task.isCancelled, !cancellation.isCancelled else { return }
            sourcePreview = result
        } catch {
            guard sourceRequest == request, selectedRegionID == selection,
                  !Task.isCancelled, !cancellation.isCancelled else { return }
            sourcePreviewError = String(localized: "Source reference could not be prepared.")
        }
    }

    public func setSelectedRegionMillimeters(
        left: Double, top: Double, width: Double, height: Double,
        expectedBinding: WorkflowEditorEditBinding? = nil
    ) throws {
        try validateEditBinding(expectedBinding)
        guard let selectedRegionID,
              let region = regions.first(where: { $0.id == selectedRegionID }),
              let rule = profile.pageRules.first(where: { $0.sourcePage == region.sourcePage }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID ?? "")
        }
        let size = rule.expectedInput.uprightPhysicalSize
        let rect = try NormalizedRect(
            x: left / size.width.value,
            y: top / size.height.value,
            width: width / size.width.value,
            height: height / size.height.value
        )
        try updateSelectedRegion(rect, expectedRegionID: selectedRegionID)
    }

    /// A stale drawing cannot edit whichever region happens to be selected now.
    public func updateSelectedRegion(_ rect: NormalizedRect, expectedRegionID: String,
                                     expectedBinding: WorkflowEditorEditBinding? = nil) throws {
        try validateEditBinding(expectedBinding)
        guard selectedRegionID == expectedRegionID,
              let region = regions.first(where: { $0.id == expectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(expectedRegionID)
        }
        // Storing the identical rectangle is not a mutation, so it must not
        // invalidate review or cancel the reviewed preview. Moving focus through
        // a bounds field committed the value already displayed, which destroyed
        // a reviewed exact preview with nothing changed.
        //
        // This does not weaken `replaceDraft`'s contract that a successful
        // mutation invalidates review even when values are later undone. That
        // defends a sequence of real edits, and each call in such a sequence
        // still changes the draft and still invalidates.
        //
        // The comparison has to happen here, before `editableDraft()`. On a
        // saved revision that returns `store.correctionDraft(for:)` at revision
        // latest + 1, so a value-identical commit legitimately yields a
        // different draft and comparing drafts afterwards can never detect the
        // no-op -- it would instead fork a revision and clear `isSaved`.
        // `NormalizedRect` stores its Doubles verbatim and `updateRegion` writes
        // the rectangle through unchanged, so `==` here is exact: no rounding or
        // normalization can make an equal input store differently. Rotation is
        // not part of this decision; it is passed through unchanged below and is
        // edited by `setSelectedRotation`.
        guard rect != region.normalizedRect else { return }
        var next = try editableDraft()
        try next.updateRegion(id: expectedRegionID, normalizedRect: rect, rotation: region.rotation)
        try replaceDraft(next)
        cancelPreview()
        isSaved = false
    }

    /// Edits candidate destination geometry without changing source sheet rules.
    /// All fallible preparation precedes committing draft/canvas and invalidating review.
    public func setOutputStock(id: String, size: PhysicalSize,
                               expectedBinding: WorkflowEditorEditBinding? = nil) throws {
        try validateEditBinding(expectedBinding)
        let nextCanvas = try canvas.replacingPhysicalSize(size)
        // A canvas can satisfy DotCanvas and still exceed the renderer's pixel
        // budget, which would save a revision that can never preview.
        try QuartzPDFRenderer.admitRenderableCanvas(nextCanvas)
        var next = try editableDraft()
        try next.setOutputStock(id: id, size: size)
        // The stock is not a surrogate for the source; validate the labels the
        // renderer will actually place, as bootstrap admission does.
        try QuartzPDFRenderer.admitPlannedLabels(
            try ExtractionPlanner.plan(analyzedPages: analyzedPages, profile: next.validatedProfile()),
            analyzedPages: analyzedPages, canvas: nextCanvas)
        try replaceDraft(next)
        canvas = nextCanvas
        cancelPreview()
        isSaved = false
    }

    /// Reserved blank area is part of the immutable candidate, not a preview-only setting.
    public func setOutputMargins(_ margins: OutputMargins,
                                 expectedBinding: WorkflowEditorEditBinding? = nil) throws {
        try validateEditBinding(expectedBinding)
        var next = try editableDraft()
        try next.setOutputMargins(margins)
        try QuartzPDFRenderer.admitPlannedLabels(
            try ExtractionPlanner.plan(analyzedPages: analyzedPages, profile: next.validatedProfile()),
            analyzedPages: analyzedPages, canvas: canvas)
        try replaceDraft(next)
        cancelPreview()
        isSaved = false
    }

    public func setSelectedRotation(_ rotation: ExtractionRotation,
                                    expectedBinding: WorkflowEditorEditBinding? = nil) throws {
        try validateEditBinding(expectedBinding)
        guard let selectedRegionID,
              let region = regions.first(where: { $0.id == selectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID ?? "")
        }
        var next = try editableDraft()
        try next.updateRegion(
            id: selectedRegionID,
            normalizedRect: region.normalizedRect,
            rotation: rotation
        )
        try replaceDraft(next)
        cancelPreview()
        isSaved = false
    }

    public func moveSelected(by offset: Int, expectedBinding: WorkflowEditorEditBinding? = nil) throws {
        try validateEditBinding(expectedBinding)
        guard let selectedRegionID,
              let current = regions.firstIndex(where: { $0.id == selectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID ?? "")
        }
        let (destination, overflow) = current.addingReportingOverflow(offset)
        guard !overflow else { throw WorkflowProfileDraft.Error.invalidDestination }
        var next = try editableDraft()
        try next.moveRegion(id: selectedRegionID, to: destination)
        try replaceDraft(next)
        cancelPreview()
        isSaved = false
    }

    public func addRegionOnSelectedPage(expectedBinding: WorkflowEditorEditBinding? = nil) throws {
        try validateEditBinding(expectedBinding)
        guard let selectedRegionID else { throw WorkflowProfileDraft.Error.regionNotFound("") }
        let newID = "region-" + UUID().uuidString.lowercased()
        var next = try editableDraft()
        try next.duplicateRegion(id: selectedRegionID, newID: newID)
        try replaceDraft(next)
        isSaved = false
        self.selectedRegionID = newID
    }

    public func removeSelectedRegion(expectedBinding: WorkflowEditorEditBinding? = nil) throws {
        try validateEditBinding(expectedBinding)
        guard let selectedRegionID,
              let selected = regions.first(where: { $0.id == selectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID ?? "")
        }
        var next = try editableDraft()
        try next.removeRegion(id: selectedRegionID)
        try replaceDraft(next)
        isSaved = false
        self.selectedRegionID = regions.first(where: { $0.sourcePage == selected.sourcePage })?.id
    }

    public func refreshPreview() throws {
        cancelPreview()
        guard let selectedRegionID else {
            throw WorkflowProfileDraft.Error.regionNotFound("")
        }
        let plan = try ExtractionPlanner.plan(analyzedPages: analyzedPages, profile: profile)
        guard let label = plan.outputLabels.first(where: { $0.regionID == selectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID)
        }
        preview = try QuartzPlannedExtraction.prepare(
            originalPDF: originalPDF,
            label: label,
            canvas: canvas,
            conversion: profile.monochromeConversion
        )
        lastError = nil
    }

    /// A confirmation captured for an earlier revision cannot discard current crops.
    public func skipPage(_ sourcePage: Int, reason: NonLabelPageReason,
                         expectedProfile: WorkflowProfile) throws {
        guard profile == expectedProfile else { throw WorkflowProfileDraft.Error.invalidPageDisposition }
        var next = try editableDraft()
        try next.skipPage(sourcePage, reason: reason)
        try replaceDraft(next)
        isSaved = false
        cancelPreview()
        cancelSourcePreview()
        if !regions.contains(where: { $0.id == selectedRegionID }) {
            selectedRegionID = regions.first?.id
        }
    }

    public func restorePage(_ sourcePage: Int) throws {
        let newID = "region-" + UUID().uuidString.lowercased()
        var next = try editableDraft()
        try next.restorePage(sourcePage, newRegionID: newID)
        try replaceDraft(next)
        isSaved = false
        cancelPreview()
        cancelSourcePreview()
        selectedRegionID = newID
    }

    public func cancelPreview() {
        previewCancellation?.cancel()
        previewCancellation = nil
        previewRequest = nil
        isPreparingPreview = false
        preview = nil
    }

    /// Product UI rendering runs in the bounded child, outside the main actor.
    /// Obsolete success and failure cannot replace newer editor state.
    public func refreshPreviewInWorker(workerExecutable: URL,
                                       deadlineSeconds: Double = 60) async {
        await refreshPreviewInWorker(workerExecutable: workerExecutable,
            deadlineSeconds: deadlineSeconds, afterPreparation: {})
    }

    /// Internal finite barrier permits deterministic stale-completion regressions
    /// with the real worker, rather than replacing rendering with a fake bitmap.
    func refreshPreviewInWorker(workerExecutable: URL, deadlineSeconds: Double,
                                afterPreparation: @escaping @Sendable () async -> Void) async {
        cancelPreview()
        let snapshot = profile
        let selection = selectedRegionID
        let request = UUID()
        let cancellation = OfflineRenderWorkerCancellation()
        previewRequest = request
        previewCancellation = cancellation
        isPreparingPreview = true
        lastError = nil
        defer {
            if previewRequest == request {
                previewRequest = nil
                previewCancellation = nil
                isPreparingPreview = false
            }
        }
        do {
            let plan = try ExtractionPlanner.plan(analyzedPages: analyzedPages, profile: snapshot)
            guard let label = plan.outputLabels.first(where: { $0.regionID == selection }) else {
                throw WorkflowProfileDraft.Error.regionNotFound(selection ?? "")
            }
            let source = originalPDF
            let canvas = canvas
            let result = try await withTaskCancellationHandler {
                try await Task.detached {
                    let bitmap = try OfflineExtractionWorker.render(originalPDF: source,
                        label: label, canvas: canvas, conversion: snapshot.monochromeConversion,
                        workerExecutable: workerExecutable, deadlineSeconds: deadlineSeconds,
                        cancellation: cancellation)
                    return PreparedExtractionLabel(bitmap: bitmap,
                        zpl: try ZPLGraphicEncoder().diagnosticFormat(bitmap),
                        sourcePage: label.sourcePage, regionID: label.regionID,
                        profileID: label.profileID, profileRevision: label.profileRevision)
                }.value
            } onCancel: {
                cancellation.cancel()
            }
            await afterPreparation()
            guard previewRequest == request, selectedRegionID == selection,
                  profile == snapshot, !Task.isCancelled, !cancellation.isCancelled else { return }
            preview = result
        } catch {
            guard previewRequest == request, selectedRegionID == selection,
                  profile == snapshot else { return }
            if !Task.isCancelled && !cancellation.isCancelled {
                lastError = String(localized: "Preview could not be prepared.")
            }
        }
    }

    public func save() throws {
        let (following, overflow) = editGeneration.addingReportingOverflow(isSaved ? 0 : 1)
        guard !overflow else { throw Error.editSequenceExhausted }
        // Per-edit admission only validates the regions that exist at that
        // moment, so a later crop or rotation can still invalidate an already
        // admitted canvas. This is the boundary that persists a revision, so
        // the invariant belongs here: nothing is stored whose own exact preview
        // would reject it, whatever sequence of edits produced it.
        // The precondition for an exact preview is the canvas and the placement
        // of every label, so both belong here. Checking placement alone let a
        // canvas rebuilt by reloadForCorrection be persisted unrenderable.
        try QuartzPDFRenderer.admitRenderableCanvas(canvas)
        try QuartzPDFRenderer.admitPlannedLabels(
            try ExtractionPlanner.plan(analyzedPages: analyzedPages, profile: profile),
            analyzedPages: analyzedPages, canvas: canvas)
        try store.save(profile)
        // A successful draft-to-saved boundary invalidates displayed draft callbacks.
        editGeneration = following
        isSaved = true
        lastError = nil
    }

    private func editableDraft() throws -> WorkflowProfileDraft {
        isSaved ? try store.correctionDraft(for: profile) : draft
    }

    private func validateEditBinding(_ binding: WorkflowEditorEditBinding?) throws {
        guard let binding else { return } // Trusted immediate current-selection API.
        guard selectedRegionID == binding.regionID, editGeneration == binding.editGeneration else {
            throw Error.editSnapshotChanged
        }
    }

    /// Successful mutations invalidate review even when values are later undone.
    private func replaceDraft(_ next: WorkflowProfileDraft) throws {
        let (following, overflow) = editGeneration.addingReportingOverflow(1)
        guard !overflow else { throw Error.editSequenceExhausted }
        reviewedProfile = nil
        reviewedRegionIDs = []
        editGeneration = following
        draft = next
    }

    public func approveForUnattendedUse() throws {
        _ = try UnattendedWorkflowQualification(userConfirmed: profile)
        guard isSaved else { throw Error.savedRevisionRequired }
        guard unreviewedRegionCount == 0 else { throw Error.regionReviewRequired }
        try store.confirmForUnattendedUse(profile)
        lastError = nil
    }

    public func reloadForCorrection(profileID: String, revision: Int) throws {
        let stored = try store.load(profileID: profileID, revision: revision)
        let nextCanvas = try canvas.replacingPhysicalSize(stored.outputStock)
        // A stored profile can be schema-valid yet exceed the renderer or
        // encoder bounds. Reject before committing the draft, so a reload
        // cannot install a canvas whose every exact preview fails.
        try QuartzPDFRenderer.admitRenderableCanvas(nextCanvas)
        try replaceDraft(store.correctionDraft(for: stored))
        canvas = nextCanvas
        cancelPreview()
        selectedRegionID = Self.regions(in: draft.profile).first?.id
        preview = nil
        isSaved = false
        lastError = nil
    }

    /// User-facing failures use fixed vocabulary, never arbitrary descriptions.
    /// Reporting does not change draft/review/save state or authorize a retry.
    public func report(_ error: Swift.Error) {
        if let editorError = error as? Error {
            lastError = switch editorError {
            case .previewRequired: String(localized: "Prepare the exact preview before reviewing these bounds.")
            case .savedRevisionRequired: String(localized: "Save this revision before approving unattended use.")
            case .regionReviewRequired: String(localized: "Review every region and its exact preview before approving unattended use.")
            case .reviewSnapshotChanged: String(localized: "The preview or draft changed. Prepare a current preview and review it again.")
            case .editSequenceExhausted: String(localized: "This editing session cannot accept more changes. Reopen the saved revision to continue.")
            case .editSnapshotChanged: String(localized: "The draft changed. Review the current values before editing again.")
            }
        } else if let draftError = error as? WorkflowProfileDraft.Error {
            lastError = switch draftError {
            case .revisionOverflow: String(localized: "This profile cannot create another revision.")
            case .regionNotFound: String(localized: "The selected region is no longer available. Select a current region.")
            case .invalidDestination: String(localized: "Choose a position within the current region order.")
            case .lastRegionOnPage: String(localized: "Keep one region on this page, or explicitly mark the page as skipped.")
            case .pageNotFound: String(localized: "The selected page is no longer available. Select a current page.")
            case .invalidPageDisposition: String(localized: "This page cannot use the selected extraction or skip rule.")
            case .lastOutputPage: String(localized: "Keep at least one page that produces labels.")
            }
        } else if let storeError = error as? WorkflowProfileStore.Error {
            lastError = switch storeError {
            case .commitUncertain: String(localized: "Save completion is uncertain. Preserve the current draft and review saved revisions before retrying.")
            case .publicationBusy: String(localized: "Another save is in progress. Wait for it to finish before saving again.")
            case .profileConflict: String(localized: "This revision already exists with different content. Reopen it for correction instead of overwriting it.")
            case .catalogCapacityReached: String(localized: "The saved profile catalog is full. Review existing revisions before saving another.")
            case .cannotCreateStore, .cannotOpenStore, .unsafeStoreDirectory:
                String(localized: "The saved profile catalog could not be opened safely.")
            case .cannotRead: String(localized: "The saved revision could not be read.")
            case .cannotWrite: String(localized: "The revision could not be saved. Preserve the current draft.")
            case .profileIdentityMismatch, .malformedQualification, .qualificationMismatch:
                String(localized: "The saved revision or its approval does not match. Reopen the current revision and review it again.")
            }
        } else if error is PageGeometryError || error is PhysicalGeometryError {
            lastError = String(localized: "Enter finite, positive dimensions and keep the region within its source page.")
        } else {
            lastError = String(localized: "This edit could not be completed. Review the current draft before continuing.")
        }
    }

    private static func regions(in profile: WorkflowProfile) -> [WorkflowEditorRegion] {
        profile.pageRules.flatMap { rule -> [WorkflowEditorRegion] in
            guard case let .extract(regions) = rule.disposition else { return [] }
            return regions.map {
                WorkflowEditorRegion(
                    id: $0.id, sourcePage: rule.sourcePage,
                    normalizedRect: $0.normalizedRect,
                    rotation: $0.rotation, outputOrder: $0.outputOrder
                )
            }
        }.sorted { $0.outputOrder < $1.outputOrder }
    }
}

public struct WorkflowEditorView: View {
    @ObservedObject private var model: WorkflowEditorModel
    private let workerExecutable: URL?
    private struct PendingSkip {
        let page: Int
        let reason: NonLabelPageReason
        let profile: WorkflowProfile
    }
    @State private var pendingSkip: PendingSkip?
    @State private var confirmingSkip = false
    @State private var skipReason: NonLabelPageReason = .instructions

    public init(model: WorkflowEditorModel, workerExecutable: URL? = nil) {
        self.model = model
        self.workerExecutable = workerExecutable
    }

    public var body: some View {
        HSplitView {
            List(model.regions, selection: $model.selectedRegionID) { region in
                Text("\(region.outputOrder + 1). \(region.id)")
                    .tag(region.id)
            }
            .frame(minWidth: 180)
            .accessibilityLabel("Label regions in output order")

            // The approval cluster is pinned below the scrolling content instead
            // of being the last thing inside it.
            //
            // This pane is hard-capped at 720 points (see the frame below) and
            // sits inside the setup window's own ScrollView, so widening or
            // zooming the window grants it no extra height. `previewView` had no
            // maximum height around a scaledToFit 4x6 bitmap, so a wider pane made
            // the preview taller; once the source reference was showing too, the
            // content above these controls exceeded the viewport and pushed
            // Confirm, Save Revision and Approve out of reach. A reviewed draft
            // then could not be confirmed, saved or approved at all.
            //
            // Controls that commit a revision must not depend on scroll position.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        mediaSummary
                        pageHandling
                        if model.isReopenedWorkflow {
                            Text("Saved workflow reopened for correction as a new revision. Review this PDF and the exact label previews before saving. Earlier revisions and their qualifications are unchanged.")
                                .accessibilityLabel("Reopened workflow requires review of its new revision")
                        } else if model.isManualDraft {
                            Text("Manual extraction: no label crop was chosen automatically. Each starting region covers its full source page. Set the label bounds and review the exact preview; this draft has no unattended qualification.")
                                .accessibilityLabel("Manual extraction requires region and preview review")
                        }
                        if let region = selectedRegion { regionControls(region) }
                        sourceReferenceView
                        previewView
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    previewReviewControls
                    if let error = model.lastError {
                        Text(error).foregroundStyle(.red).accessibilityLabel("Editor error: \(error)")
                    }
                    HStack {
                        Button("Preview") {
                            if let workerExecutable {
                                Task { await model.refreshPreviewInWorker(workerExecutable: workerExecutable) }
                            }
                        }
                            .keyboardShortcut("p", modifiers: [.command])
                            .disabled(workerExecutable == nil || model.isPreparingPreview)
                        if model.isPreparingPreview {
                            ProgressView().accessibilityLabel("Preparing exact bitmap preview")
                            Button("Cancel Preview") { model.cancelPreview() }
                        }
                        Button("Save Revision") { perform(model.save) }
                            .keyboardShortcut("s", modifiers: [.command])
                        Button("Approve for Unattended Use") { perform(model.approveForUnattendedUse) }
                            .disabled(!model.canApproveForUnattendedUse)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 480)
        }
        // NSSplitView has no intrinsic vertical extent. In the setup's outer
        // ScrollView it otherwise reserves zero height and paints over siblings.
        // Both panes stay in this viewport; details scroll independently.
        .frame(height: 720)
        .onDisappear { model.cancelPreview(); model.cancelSourcePreview() }
        .confirmationDialog("Mark this source page as non-label?", isPresented: $confirmingSkip,
                            titleVisibility: .visible) {
            if let pendingSkip {
                Button("Confirm Non-Label Page", role: .destructive) {
                    perform { try model.skipPage(pendingSkip.page, reason: pendingSkip.reason,
                                                 expectedProfile: pendingSkip.profile) }
                    self.pendingSkip = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingSkip = nil }
        } message: {
            if let pendingSkip {
                Text("Page \(pendingSkip.page) will produce no labels for reason \(pendingSkip.reason.rawValue). All its crop definitions are removed from this draft. The page remains accounted for and layout-validated. Restoring starts with a new full-page region requiring review; earlier saved revisions are unchanged.")
            }
        }
    }

    private var selectedRegion: WorkflowEditorRegion? {
        model.regions.first { $0.id == model.selectedRegionID }
    }

    private var previewReviewControls: some View {
        let displayedProfile = model.profile
        let displayedPreview = model.preview
        let displayedGeneration = model.editGeneration
        return HStack {
            Button("Confirm Bounds and Exact Preview Reviewed") {
                perform { try model.confirmSelectedBoundsAndPreviewReviewed(
                    expectedProfile: displayedProfile, expectedPreview: displayedPreview,
                    expectedEditGeneration: displayedGeneration) }
            }.disabled(!model.canConfirmSelectedBoundsAndPreview)
            Text(model.unreviewedRegionSummary)
                .font(.caption)
        }
    }

    private var mediaSummary: some View {
        let stock = model.profile.outputStock
        let margins = model.profile.outputMargins
        let binding = model.selectedRegionID.map {
            WorkflowEditorEditBinding(regionID: $0, editGeneration: model.editGeneration)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Input sheet geometry is configured per source page.")
            GroupBox("Output stock dimensions") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        measurementField("Stock width (mm)", value: stock.width.value) { value in
                            try model.setOutputStock(id: "custom-stock", size: PhysicalSize(
                                width: Millimeters(value), height: stock.height), expectedBinding: binding)
                        }
                        measurementField("Stock height (mm)", value: stock.height.value) { value in
                            try model.setOutputStock(id: "custom-stock", size: PhysicalSize(
                                width: stock.width, height: Millimeters(value)), expectedBinding: binding)
                        }
                    }
                    Text("These dimensions change this workflow's label previews. Verify the physical stock and printer limits separately before printing.")
                        .font(.caption)
                }
            }
            GroupBox("Reserved output margins") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        measurementField("Left margin (mm)", value: margins.left) { value in
                            try model.setOutputMargins(OutputMargins(left: value, top: margins.top,
                                right: margins.right, bottom: margins.bottom), expectedBinding: binding)
                        }
                        measurementField("Top margin (mm)", value: margins.top) { value in
                            try model.setOutputMargins(OutputMargins(left: margins.left, top: value,
                                right: margins.right, bottom: margins.bottom), expectedBinding: binding)
                        }
                    }
                    HStack {
                        measurementField("Right margin (mm)", value: margins.right) { value in
                            try model.setOutputMargins(OutputMargins(left: margins.left, top: margins.top,
                                right: value, bottom: margins.bottom), expectedBinding: binding)
                        }
                        measurementField("Bottom margin (mm)", value: margins.bottom) { value in
                            try model.setOutputMargins(OutputMargins(left: margins.left, top: margins.top,
                                right: margins.right, bottom: value), expectedBinding: binding)
                        }
                    }
                    Text("Margins reserve blank space inside the output stock. Review a new exact preview after changing them; printer calibration must be verified separately.")
                        .font(.caption)
                }.disabled(binding == nil)
            }
        }
    }

    private var pageHandling: some View {
        GroupBox("Source page accounting") {
            VStack(alignment: .leading) {
                Picker("Non-label reason", selection: $skipReason) {
                    Text("Instructions").tag(NonLabelPageReason.instructions)
                    Text("Customs form").tag(NonLabelPageReason.customsForm)
                    Text("Explicitly ignored").tag(NonLabelPageReason.explicitlyIgnored)
                }
                ForEach(model.profile.pageRules.sorted { $0.sourcePage < $1.sourcePage }, id: \.sourcePage) { rule in
                    HStack {
                        switch rule.disposition {
                        case let .extract(regions):
                            Text(WorkflowEditorModel.labelRegionSummary(
                                page: rule.sourcePage, regions: regions.count))
                            Button("Mark Page \(rule.sourcePage) Non-Label…") {
                                pendingSkip = PendingSkip(page: rule.sourcePage, reason: skipReason,
                                                          profile: model.profile)
                                confirmingSkip = true
                            }.disabled(model.regions.allSatisfy { $0.sourcePage == rule.sourcePage })
                        case let .skip(reason):
                            Text("Page \(rule.sourcePage): skipped — \(reason.rawValue)")
                            Button("Restore Page \(rule.sourcePage) as Full-Page Region") {
                                perform { try model.restorePage(rule.sourcePage) }
                            }.accessibilityHint("Appends a new full-page region. Set its bounds and review the exact preview.")
                        }
                    }
                }
                Text("Every source page remains listed. Unexpected pages still fail validation. At least one page must produce labels; a customs form is not printed separately by this workflow.")
                    .font(.caption)
            }
        }
    }

    private func regionControls(_ region: WorkflowEditorRegion) -> some View {
        let rule = model.profile.pageRules.first { $0.sourcePage == region.sourcePage }!
        let size = rule.expectedInput.uprightPhysicalSize
        let binding = WorkflowEditorEditBinding(regionID: region.id, editGeneration: model.editGeneration)
        return VStack(alignment: .leading) {
            Text("Region \(region.id) — source page \(region.sourcePage)").font(.headline)
            HStack {
                measurementField("Left (mm)", value: region.normalizedRect.x * size.width.value) { left in
                    try update(region, size: size, expectedBinding: binding, left: left)
                }
                measurementField("Top (mm)", value: region.normalizedRect.y * size.height.value) { top in
                    try update(region, size: size, expectedBinding: binding, top: top)
                }
                measurementField("Width (mm)", value: region.normalizedRect.width * size.width.value) { width in
                    try update(region, size: size, expectedBinding: binding, width: width)
                }
                measurementField("Height (mm)", value: region.normalizedRect.height * size.height.value) { height in
                    try update(region, size: size, expectedBinding: binding, height: height)
                }
            }
            Picker("Rotation", selection: Binding(
                get: { region.rotation },
                set: { value in perform { try model.setSelectedRotation(value, expectedBinding: binding) } }
            )) {
                Text("0°").tag(ExtractionRotation.degrees0)
                Text("90°").tag(ExtractionRotation.degrees90)
                Text("180°").tag(ExtractionRotation.degrees180)
                Text("270°").tag(ExtractionRotation.degrees270)
            }.pickerStyle(.segmented)
            HStack {
                Button("Add Region on This Page") { perform { try model.addRegionOnSelectedPage(expectedBinding: binding) } }
                    .accessibilityHint("Starts with the selected bounds. Set the new label bounds before printing.")
                Button("Remove Region") { perform { try model.removeSelectedRegion(expectedBinding: binding) } }
                    .disabled(model.regions.filter { $0.sourcePage == region.sourcePage }.count <= 1)
            }
            Text("Each region produces a label. Added regions start with these bounds; adjust them explicitly. A page's last region requires a separate page-handling policy.")
                .font(.caption)
            HStack {
                Button("Move Earlier") { perform { try model.moveSelected(by: -1, expectedBinding: binding) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                    .disabled(region.outputOrder == 0)
                Button("Move Later") { perform { try model.moveSelected(by: 1, expectedBinding: binding) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command])
                    .disabled(region.outputOrder == model.regions.count - 1)
            }
        }
    }

    private var previewView: some View {
        Group {
            if let bitmap = model.preview?.bitmap, let image = Self.image(bitmap) {
                Image(image, scale: 1, label: Text("Exact packed label preview"))
                    .resizable().interpolation(.none).scaledToFit()
            } else {
                ContentUnavailableView("Preview not generated", systemImage: "doc.viewfinder")
            }
        // Capped like the source reference below. Without a maximum, a
        // scaledToFit 4x6 bitmap grows with the pane width and can exceed the
        // pane's whole 720-point allocation on a wide display.
        }.frame(maxWidth: .infinity, minHeight: 240, maxHeight: 300)
    }

    private var sourceReferenceView: some View {
        VStack(alignment: .leading) {
            Text("Monochrome source-page reference — not the print preview").font(.caption)
            if let source = model.sourcePreview, let image = Self.image(source.bitmap) {
                Image(image, scale: 1, label: Text("Source page \(source.sourcePage) reference"))
                    .resizable().interpolation(.none)
                    .aspectRatio(CGFloat(source.canvas.width) / CGFloat(source.canvas.height), contentMode: .fit)
                    .overlay {
                        GeometryReader { geometry in
                            if let region = selectedRegion, region.sourcePage == source.sourcePage {
                                SourceSelectionOverlay(binding: WorkflowEditorEditBinding(regionID: region.id,
                                                       editGeneration: model.editGeneration), rect: region.normalizedRect,
                                                       viewport: geometry.size) { owner, rect in
                                    guard model.sourcePreview?.sourcePage == source.sourcePage else { return }
                                    perform { try model.updateSelectedRegion(rect, expectedRegionID: owner.regionID,
                                                                             expectedBinding: owner) }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
            }
            // The label was a fixed literal and the action only ever re-rendered,
            // so it never read as showing and there was no way to dismiss the
            // reference: once shown it stayed until a different region was
            // selected or the document was reopened. Hiding is inert -- it clears
            // a rendered image and performs no device or worker work.
            Button(model.sourcePreview == nil ? "Show Source Page" : "Hide Source Page") {
                if model.sourcePreview != nil {
                    model.cancelSourcePreview()
                } else if let workerExecutable {
                    Task { await model.refreshSourcePageInWorker(workerExecutable: workerExecutable) }
                }
            }.disabled((workerExecutable == nil && model.sourcePreview == nil)
                       || model.isPreparingSourcePreview)
            if model.isPreparingSourcePreview {
                ProgressView("Preparing source reference…")
                Button("Cancel Source Reference") { model.cancelSourcePreview() }
            }
            if let error = model.sourcePreviewError { Text(error).accessibilityLabel(error) }
        }
    }

    private func measurementField(
        _ title: String, value: Double, update: @escaping (Double) throws -> Void
    ) -> some View {
        MeasurementField(title: title, value: value) { newValue in
            perform { try update(newValue) }
        }
    }

    private func update(
        _ region: WorkflowEditorRegion,
        size: PhysicalSize, expectedBinding: WorkflowEditorEditBinding,
        left: Double? = nil, top: Double? = nil,
        width: Double? = nil, height: Double? = nil
    ) throws {
        try model.setSelectedRegionMillimeters(
            left: left ?? region.normalizedRect.x * size.width.value,
            top: top ?? region.normalizedRect.y * size.height.value,
            width: width ?? region.normalizedRect.width * size.width.value,
            height: height ?? region.normalizedRect.height * size.height.value,
            expectedBinding: expectedBinding
        )
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { model.report(error) }
    }

    private static func image(_ bitmap: MonochromeBitmap) -> CGImage? {
        let preview = bitmap.grayscalePreview()
        guard let provider = CGDataProvider(data: Data(preview.pixels) as CFData) else { return nil }
        return CGImage(
            width: preview.width, height: preview.height,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: preview.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

/// Display coordinates only. Final rendering continues to consume the original PDF.
/// A millimetre field that commits on submit or focus loss, never per keystroke.
///
/// `TextField(value:format:)` over a `Binding` whose `set` committed on every
/// successful parse made each keystroke a committed edit. Typing "101.6"
/// committed 101 at "101"; at "101." the parse still yielded 101, the `get` then
/// re-rendered the field from the model as "101", and the pending fraction was
/// discarded, so the value had to be typed twice. The same mechanism is why
/// every keystroke invalidated review and why the documented workaround was to
/// shrink width and height before setting them.
///
/// Parsing and formatting both go through one locale-aware style, so a viewer
/// whose locale uses a decimal comma reads and writes the same text as before.
private struct MeasurementField: View {
    let title: String
    let value: Double
    let commit: (Double) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private static let style = FloatingPointFormatStyle<Double>()
        .precision(.fractionLength(0...2))

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
                .focused($isFocused)
                .onSubmit { commitText() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitText() }
                }
                // Never clobber in-progress typing; resync only while idle.
                .onChange(of: value) { _, updated in
                    if !isFocused { text = updated.formatted(Self.style) }
                }
                .onAppear { text = value.formatted(Self.style) }
        }
    }

    private func commitText() {
        // An untouched field commits nothing. The model-level guard in
        // `updateSelectedRegion` compares rectangles exactly, and the millimetre
        // round trip does not preserve that: the field displays a value rounded
        // to two fraction digits, so re-committing the displayed text can yield a
        // rectangle differing from the stored one in its last bits. Comparing the
        // text against what the model currently formats to answers the question
        // that actually matters -- was this field edited at all -- and keeps a
        // focus change from invalidating a reviewed preview.
        guard text != value.formatted(Self.style) else { return }
        guard let parsed = try? Double(text, format: Self.style) else {
            // Unparseable input is not a value. Restore what the model holds
            // rather than committing a guess.
            text = value.formatted(Self.style)
            return
        }
        commit(parsed)
    }
}

private struct SourceSelectionOverlay: View {
    let binding: WorkflowEditorEditBinding
    let rect: NormalizedRect
    let viewport: CGSize
    let commit: (WorkflowEditorEditBinding, NormalizedRect) -> Void
    @State private var owner: WorkflowEditorEditBinding?
    @State private var startingViewport: CGSize?
    @State private var pending: NormalizedRect?

    var body: some View {
        let displayed = pending ?? rect
        Rectangle().fill(.clear)
            .contentShape(Rectangle())
            .overlay {
                Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                    .frame(width: viewport.width * displayed.width,
                           height: viewport.height * displayed.height)
                    .position(x: viewport.width * (displayed.x + displayed.width / 2),
                              y: viewport.height * (displayed.y + displayed.height / 2))
                    .allowsHitTesting(false)
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if owner == nil { owner = binding; startingViewport = viewport }
                    guard owner == binding, startingViewport == viewport else {
                        pending = nil
                        return
                    }
                    pending = selection(value)
                }
                .onEnded { value in
                    defer { owner = nil; startingViewport = nil; pending = nil }
                    guard let owner, owner == binding, startingViewport == viewport,
                          let selection = selection(value) else { return }
                    commit(owner, selection)
                })
            .accessibilityLabel("Draw extraction bounds on the source page, or use the millimeter fields")
    }

    private func selection(_ value: DragGesture.Value) -> NormalizedRect? {
        try? SourceRegionSelection.rectangle(
            viewportWidth: viewport.width, viewportHeight: viewport.height,
            startX: value.startLocation.x, startY: value.startLocation.y,
            endX: value.location.x, endY: value.location.y
        )
    }
}
