import Foundation
import LabelCore

public enum WorkflowOpeningMode: Equatable, Sendable {
    case assisted
    /// Explicit user-selected editing, never an automatic failed-match fallback.
    case manual
}

@MainActor
public enum WorkflowEditorBootstrap {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedPageGeometry(page: Int)
        case noBorderCandidate(page: Int)
        case ambiguousBorderCandidates(page: Int)
        case mixedReferenceGeometry
        case unsupportedOutputStock
        case unsupportedLayoutDetector
    }

    public static func makeModel(
        originalPDF: Data,
        store: WorkflowProfileStore,
        maximumPages: Int = 32
    ) throws -> WorkflowEditorModel {
        guard (1...32).contains(maximumPages) else {
            throw QuartzStructuralAnalyzer.Error.invalidLimits
        }
        let boxes = try QuartzPDFRenderer.documentPageBoxes(
            originalPDF: originalPDF,
            maximumSourcePages: maximumPages
        )
        let analyzed = try boxes.indices.map { index in
            try QuartzStructuralAnalyzer.analyzeBorders(
                originalPDF: originalPDF,
                pageNumber: index + 1,
                maximumSourcePages: maximumPages
            )
        }
        return try makeModel(originalPDF: originalPDF, store: store,
                             analyzedPages: analyzed, maximumPages: maximumPages)
    }

    public static func makeModelUsingWorker(
        originalPDF: Data, store: WorkflowProfileStore, workerExecutable: URL,
        maximumPages: Int = 32, deadlineSeconds: Double = 60,
        cancellation: OfflineRenderWorkerCancellation = .init(),
        mode: WorkflowOpeningMode = .assisted,
        savedProfile: WorkflowProfile? = nil
    ) async throws -> WorkflowEditorModel {
        guard (1...32).contains(maximumPages) else { throw QuartzStructuralAnalyzer.Error.invalidLimits }
        guard deadlineSeconds.isFinite, deadlineSeconds > 0, deadlineSeconds <= 60 else {
            throw OfflineRenderWorkerProcess.Error.invalidDeadline
        }
        if let savedProfile {
            let reference = try ReferenceWorkflowDefinition.gc420dInitialSet()[0]
            // Only the currently configured 4x6 setup is wired into this UI.
            // Permit floating-point representation differences, not another stock.
            guard savedProfile.outputStockID == reference.outputStockID,
                  abs(savedProfile.outputStock.width.value - reference.outputStock.width.value) <= 1e-6,
                  abs(savedProfile.outputStock.height.value - reference.outputStock.height.value) <= 1e-6 else {
                throw Error.unsupportedOutputStock
            }
            guard savedProfile.pageRules.allSatisfy({ rule in
                rule.structuralAnchors.allSatisfy { $0.kind == .border || $0.kind == .barcodeLike }
            }) else { throw Error.unsupportedLayoutDetector }
        }
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(deadlineSeconds * 1e9)))
        let preparation = try await withTaskCancellationHandler {
            try await Task.detached {
                let correction = try savedProfile.map { try store.correctionDraft(for: $0) }
                let parts = ContinuousClock.now.duration(to: deadline).components
                let remaining = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
                guard remaining > 0 else { throw OfflineRenderWorkerProcess.Error.timedOut }
                let structuralPages = savedProfile?.pageRules.filter { !$0.structuralAnchors.isEmpty }
                    .map(\.sourcePage).sorted() ?? []
                let analyzed = try OfflineLayoutWorker.analyze(originalPDF: originalPDF, structuralPages: structuralPages,
                    workerExecutable: workerExecutable, maximumSourcePages: maximumPages,
                    analyzeAllPages: savedProfile == nil && mode == .assisted,
                    barcodePages: savedProfile?.pageRules.filter { rule in
                        rule.structuralAnchors.contains { $0.kind == .barcodeLike }
                    }.map(\.sourcePage) ?? [],
                    deadlineSeconds: min(remaining, 60), cancellation: cancellation)
                return (analyzed, correction)
            }.value
        } onCancel: {
            cancellation.cancel()
        }
        try Task.checkCancellation()
        guard !cancellation.isCancelled else { throw OfflineRenderWorkerProcess.Error.cancelled }
        let (analyzed, correction) = preparation
        let model: WorkflowEditorModel
        if let savedProfile {
            _ = try ExtractionPlanner.plan(analyzedPages: analyzed, profile: savedProfile)
            let canvas = try DotCanvas(physicalSize: savedProfile.outputStock,
                resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8))
            guard let correction else { throw WorkflowProfileStore.Error.profileIdentityMismatch }
            model = WorkflowEditorModel(draft: correction,
                originalPDF: originalPDF, analyzedPages: analyzed, canvas: canvas, store: store,
                isManualDraft: savedProfile.pageRules.contains { $0.structuralAnchors.isEmpty },
                isReopenedWorkflow: true)
        } else {
            model = try makeModel(originalPDF: originalPDF, store: store,
                analyzedPages: analyzed, maximumPages: maximumPages, mode: mode)
        }
        guard ContinuousClock.now < deadline else { throw OfflineRenderWorkerProcess.Error.timedOut }
        return model
    }

    private static func makeModel(originalPDF: Data, store: WorkflowProfileStore,
                                  analyzedPages analyzed: [AnalyzedSourcePage],
                                  maximumPages: Int, mode: WorkflowOpeningMode = .assisted) throws -> WorkflowEditorModel {
        guard !analyzed.isEmpty, analyzed.count <= maximumPages else {
            throw QuartzStructuralAnalyzer.Error.invalidLimits
        }
        let boxes = analyzed.map(\.pageBox)
        let references = try ReferenceWorkflowDefinition.gc420dInitialSet()
        if mode == .manual {
            guard let reference = references.first else { throw Error.mixedReferenceGeometry }
            let rules = try analyzed.enumerated().map { index, page in
                try WorkflowPageRule(sourcePage: index + 1,
                    expectedInput: ExpectedInputPage(uprightPhysicalSize: page.pageBox.effectivePhysicalSize()),
                    disposition: .extract([try ExtractionRegion(
                        id: String(format: "page-%03d-label", index + 1),
                        normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                        outputOrder: index)]))
            }
            return try editorModel(originalPDF: originalPDF, store: store, analyzed: analyzed,
                reference: reference, rules: rules,
                id: "manual-to-4x6-\(UUID().uuidString.lowercased())", manual: true)
        }
        let matches = try boxes.enumerated().map { index, box -> ReferenceWorkflowDefinition in
            let size = try box.effectivePhysicalSize()
            guard let match = references.first(where: {
                let expected = $0.expectedInput.uprightPhysicalSize
                let sameOrientation = abs(expected.width.value - size.width.value) <= 0.5 &&
                    abs(expected.height.value - size.height.value) <= 0.5
                let rotatedOrientation = abs(expected.width.value - size.height.value) <= 0.5 &&
                    abs(expected.height.value - size.width.value) <= 0.5
                return sameOrientation || rotatedOrientation
            }) else { throw Error.unsupportedPageGeometry(page: index + 1) }
            return match
        }
        guard let reference = matches.first,
              matches.allSatisfy({ $0.id == reference.id }) else {
            throw Error.mixedReferenceGeometry
        }
        let rules = try analyzed.enumerated().map { index, page -> WorkflowPageRule in
            let observedInput = try ExpectedInputPage(
                uprightPhysicalSize: try page.pageBox.effectivePhysicalSize()
            )
            if reference.id == "native-4x6" {
                return try WorkflowPageRule(
                    sourcePage: index + 1,
                    expectedInput: observedInput,
                    disposition: .extract([try ExtractionRegion(
                        id: String(format: "page-%03d-label", index + 1),
                        normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                        outputOrder: index
                    )])
                )
            }
            let borders = page.anchors?.filter { $0.kind == .border } ?? []
            let orderedBorders = borders.sorted {
                $0.normalizedRect.width * $0.normalizedRect.height >
                    $1.normalizedRect.width * $1.normalizedRect.height
            }
            guard let border = orderedBorders.first else {
                throw Error.noBorderCandidate(page: index + 1)
            }
            if orderedBorders.count > 1 {
                let principalArea = border.normalizedRect.width * border.normalizedRect.height
                let alternateArea = orderedBorders[1].normalizedRect.width * orderedBorders[1].normalizedRect.height
                if alternateArea >= principalArea * 0.9 {
                    throw Error.ambiguousBorderCandidates(page: index + 1)
                }
            }
            return try WorkflowPageRule(
                sourcePage: index + 1,
                expectedInput: observedInput,
                disposition: .extract([try ExtractionRegion(
                    id: String(format: "page-%03d-label", index + 1),
                    normalizedRect: border.normalizedRect,
                    outputOrder: index
                )]),
                structuralAnchors: [try StructuralAnchorExpectation(
                    id: String(format: "page-%03d-border", index + 1),
                    kind: .border,
                    normalizedRect: border.normalizedRect
                )]
            )
        }
        return try editorModel(originalPDF: originalPDF, store: store, analyzed: analyzed,
            reference: reference, rules: rules, id: "\(reference.id)-local", manual: false)
    }

    private static func editorModel(originalPDF: Data, store: WorkflowProfileStore,
        analyzed: [AnalyzedSourcePage], reference: ReferenceWorkflowDefinition,
        rules: [WorkflowPageRule], id: String, manual: Bool) throws -> WorkflowEditorModel {
        let profile = try WorkflowProfile(
            id: id,
            revision: 1,
            outputStockID: reference.outputStockID,
            outputStock: reference.outputStock,
            monochromeConversion: .textAndBarcodeThreshold(cutoff: 128),
            pageRules: rules
        )
        let canvas = try DotCanvas(
            physicalSize: reference.outputStock,
            resolution: DotResolution(xDotsPerMillimeter: 8, yDotsPerMillimeter: 8)
        )
        return WorkflowEditorModel(
            draft: WorkflowProfileDraft(profile: profile),
            originalPDF: originalPDF,
            analyzedPages: analyzed,
            canvas: canvas,
            store: store,
            isManualDraft: manual
        )
    }
}
