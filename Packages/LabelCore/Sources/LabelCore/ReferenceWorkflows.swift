/// The three initial application-facing workflows share one physical stock but
/// do not pretend that an arbitrary Letter or A4 sheet has a known label crop.
public enum ReferenceWorkflowReadiness: Equatable, Sendable {
    case ready(WorkflowProfile)
    case requiresTeachOnce
}

public struct ReferenceWorkflowDefinition: Equatable, Sendable {
    public let id: String
    public let expectedInput: ExpectedInputPage
    public let outputStockID: String
    public let outputStock: PhysicalSize
    public let readiness: ReferenceWorkflowReadiness

    private init(
        id: String,
        expectedInput: ExpectedInputPage,
        outputStockID: String,
        outputStock: PhysicalSize,
        readiness: ReferenceWorkflowReadiness
    ) {
        self.id = id
        self.expectedInput = expectedInput
        self.outputStockID = outputStockID
        self.outputStock = outputStock
        self.readiness = readiness
    }

    public static func gc420dInitialSet(revision: Int = 1) throws -> [ReferenceWorkflowDefinition] {
        guard revision > 0 else { throw ExtractionPlanError.invalidProfile }
        let stock = PhysicalSize(
            width: try Millimeters.inches(4),
            height: try Millimeters.inches(6)
        )
        let stockID = "gc420d-4x6-precut"
        let nativeInput = try ExpectedInputPage(uprightPhysicalSize: stock)
        let nativeProfile = try WorkflowProfile(
            id: "native-4x6",
            revision: revision,
            outputStockID: stockID,
            outputStock: stock,
            monochromeConversion: .textAndBarcodeThreshold(cutoff: 128),
            pageRules: [
                try WorkflowPageRule(
                    sourcePage: 1,
                    expectedInput: nativeInput,
                    disposition: .extract([
                        try ExtractionRegion(
                            id: "full-page",
                            normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
                            outputOrder: 0
                        ),
                    ])
                ),
            ]
        )
        return [
            ReferenceWorkflowDefinition(
                id: "native-4x6",
                expectedInput: nativeInput,
                outputStockID: stockID,
                outputStock: stock,
                readiness: .ready(nativeProfile)
            ),
            ReferenceWorkflowDefinition(
                id: "letter-to-4x6",
                expectedInput: try ExpectedInputPage(uprightPhysicalSize: PhysicalSize(
                    width: try Millimeters.inches(8.5),
                    height: try Millimeters.inches(11)
                )),
                outputStockID: stockID,
                outputStock: stock,
                readiness: .requiresTeachOnce
            ),
            ReferenceWorkflowDefinition(
                id: "a4-to-4x6",
                expectedInput: try ExpectedInputPage(uprightPhysicalSize: PhysicalSize(
                    width: try Millimeters(210),
                    height: try Millimeters(297)
                )),
                outputStockID: stockID,
                outputStock: stock,
                readiness: .requiresTeachOnce
            ),
        ]
    }

    /// Only a complete definition can plan automatically. Incomplete sheet
    /// workflows fail before producing a region, bitmap, or delivery payload.
    public func plan(
        sourcePages: [PDFPageBox],
        copyPolicy: LabelOrderPlan.CopyPolicy = .alreadyExpanded,
        maximumOutputLabels: Int = 10_000
    ) throws -> ExtractionPlan {
        guard case let .ready(profile) = readiness else {
            throw ReferenceWorkflowError.requiresTeachOnce(workflowID: id)
        }
        return try ExtractionPlanner.plan(
            sourcePages: sourcePages,
            profile: profile,
            copyPolicy: copyPolicy,
            maximumOutputLabels: maximumOutputLabels
        )
    }
}

public enum ReferenceWorkflowError: Error, Equatable, Sendable, RedactedDiagnosticValue {
    case requiresTeachOnce(workflowID: String)

    public var description: String { "ReferenceWorkflowError.requiresTeachOnce(workflowID: redacted)" }
}
