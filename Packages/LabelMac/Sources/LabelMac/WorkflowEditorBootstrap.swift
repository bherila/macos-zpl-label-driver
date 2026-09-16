import Foundation
import LabelCore

@MainActor
public enum WorkflowEditorBootstrap {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unsupportedPageGeometry(page: Int)
        case noBorderCandidate(page: Int)
        case ambiguousBorderCandidates(page: Int)
        case mixedReferenceGeometry
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
        let references = try ReferenceWorkflowDefinition.gc420dInitialSet()
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
        let profile = try WorkflowProfile(
            id: "\(reference.id)-local",
            revision: 1,
            outputStockID: reference.outputStockID,
            outputStock: reference.outputStock,
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
            conversion: .textAndBarcodeThreshold(cutoff: 128),
            store: store
        )
    }
}
