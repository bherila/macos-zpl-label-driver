import Foundation

/// Portable, immutable sheet-extraction planning. Rendering remains a native
/// responsibility and must use `sourceRect` against the original PDF page.
public enum ExtractionRotation: Int, Equatable, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270
}

public enum ExtractionScalePolicy: String, Equatable, Sendable {
    /// Version one never stretches labels independently by axis.
    case uniformFit
}

public struct ExtractionRegion: Equatable, Sendable {
    public let id: String
    public let normalizedRect: NormalizedRect
    public let rotation: ExtractionRotation
    public let scalePolicy: ExtractionScalePolicy
    public let outputOrder: Int

    public init(
        id: String,
        normalizedRect: NormalizedRect,
        rotation: ExtractionRotation = .degrees0,
        scalePolicy: ExtractionScalePolicy = .uniformFit,
        outputOrder: Int
    ) throws {
        guard WorkflowProfile.isSafeIdentifier(id), outputOrder >= 0 else {
            throw ExtractionPlanError.invalidProfile
        }
        self.id = id
        self.normalizedRect = normalizedRect
        self.rotation = rotation
        self.scalePolicy = scalePolicy
        self.outputOrder = outputOrder
    }
}

public enum NonLabelPageReason: String, Equatable, Sendable {
    case instructions
    case customsForm
    case explicitlyIgnored
}

public enum WorkflowPageDisposition: Equatable, Sendable {
    case extract([ExtractionRegion])
    case skip(NonLabelPageReason)
}

/// Local analysis facts used only to validate a workflow layout. They contain
/// no decoded barcode value or document payload and never become render input.
public enum StructuralAnchorKind: String, Equatable, Sendable {
    case barcodeLike
    case border
    case darkBlock
}

public struct StructuralAnchorExpectation: Equatable, Sendable {
    public let id: String
    public let kind: StructuralAnchorKind
    public let normalizedRect: NormalizedRect
    public let maximumCoordinateDeviation: Double

    public init(
        id: String,
        kind: StructuralAnchorKind,
        normalizedRect: NormalizedRect,
        maximumCoordinateDeviation: Double = 0.02
    ) throws {
        guard WorkflowProfile.isSafeIdentifier(id), maximumCoordinateDeviation.isFinite,
              (0...0.25).contains(maximumCoordinateDeviation) else {
            throw ExtractionPlanError.invalidProfile
        }
        self.id = id
        self.kind = kind
        self.normalizedRect = normalizedRect
        self.maximumCoordinateDeviation = maximumCoordinateDeviation
    }
}

public struct ObservedPageAnchor: Equatable, Sendable {
    public let kind: StructuralAnchorKind
    public let normalizedRect: NormalizedRect

    public init(kind: StructuralAnchorKind, normalizedRect: NormalizedRect) {
        self.kind = kind
        self.normalizedRect = normalizedRect
    }
}

public struct AnalyzedSourcePage: Equatable, Sendable {
    public let pageBox: PDFPageBox
    /// `nil` means analysis was not performed; an empty array is an observed
    /// page with no candidates. Those states have distinct mismatch errors.
    public let anchors: [ObservedPageAnchor]?

    public init(pageBox: PDFPageBox, anchors: [ObservedPageAnchor]?) throws {
        guard anchors.map({ $0.count <= 256 }) ?? true else {
            throw ExtractionPlanError.invalidAnalysis
        }
        self.pageBox = pageBox
        self.anchors = anchors
    }
}

public struct ExpectedInputPage: Equatable, Sendable {
    public let uprightPhysicalSize: PhysicalSize
    public let toleranceMillimeters: Double

    public init(uprightPhysicalSize: PhysicalSize, toleranceMillimeters: Double = 0.5) throws {
        guard toleranceMillimeters.isFinite, toleranceMillimeters >= 0, toleranceMillimeters <= 10 else {
            throw ExtractionPlanError.invalidProfile
        }
        self.uprightPhysicalSize = uprightPhysicalSize
        self.toleranceMillimeters = toleranceMillimeters
    }

    fileprivate func matches(_ actual: PhysicalSize) -> Bool {
        abs(actual.width.value - uprightPhysicalSize.width.value) <= toleranceMillimeters &&
            abs(actual.height.value - uprightPhysicalSize.height.value) <= toleranceMillimeters
    }
}

public struct WorkflowPageRule: Equatable, Sendable {
    /// Shared admission limit for typed construction, editing and JSON import.
    public static let maximumRegionsPerPage = 256
    public let sourcePage: Int
    public let expectedInput: ExpectedInputPage
    public let disposition: WorkflowPageDisposition
    public let structuralAnchors: [StructuralAnchorExpectation]

    public init(
        sourcePage: Int,
        expectedInput: ExpectedInputPage,
        disposition: WorkflowPageDisposition,
        structuralAnchors: [StructuralAnchorExpectation] = []
    ) throws {
        guard sourcePage > 0, structuralAnchors.count <= 64,
              Set(structuralAnchors.map(\.id)).count == structuralAnchors.count else {
            throw ExtractionPlanError.invalidProfile
        }
        if case let .extract(regions) = disposition,
           regions.isEmpty || regions.count > Self.maximumRegionsPerPage {
            throw ExtractionPlanError.invalidProfile
        }
        self.sourcePage = sourcePage
        self.expectedInput = expectedInput
        self.disposition = disposition
        self.structuralAnchors = structuralAnchors
    }
}

public struct WorkflowProfile: Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let revision: Int
    public let outputStockID: String
    public let outputStock: PhysicalSize
    /// The deterministic one-bit conversion used for every output label in
    /// this immutable workflow revision. Mixed-content workflows require a
    /// future explicit region policy rather than an ambient caller choice.
    public let monochromeConversion: MonochromeConversion
    public let pageRules: [WorkflowPageRule]

    public init(
        schemaVersion: Int = 2,
        id: String,
        revision: Int,
        outputStockID: String,
        outputStock: PhysicalSize,
        monochromeConversion: MonochromeConversion = .textAndBarcodeThreshold(cutoff: 128),
        pageRules: [WorkflowPageRule]
    ) throws {
        guard schemaVersion == 2, revision > 0,
              Self.isSafeIdentifier(id), Self.isSafeIdentifier(outputStockID),
              !pageRules.isEmpty, pageRules.count <= 1_000 else {
            throw ExtractionPlanError.invalidProfile
        }
        let pages = pageRules.map(\.sourcePage)
        guard Set(pages).count == pages.count else { throw ExtractionPlanError.invalidProfile }
        let orders = pageRules.flatMap { rule -> [Int] in
            if case let .extract(regions) = rule.disposition { return regions.map(\.outputOrder) }
            return []
        }
        let regionIDs = pageRules.flatMap { rule -> [String] in
            if case let .extract(regions) = rule.disposition { return regions.map(\.id) }
            return []
        }
        guard !orders.isEmpty, Set(orders).count == orders.count,
              Set(regionIDs).count == regionIDs.count else {
            throw ExtractionPlanError.invalidProfile
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.outputStockID = outputStockID
        self.outputStock = outputStock
        self.monochromeConversion = monochromeConversion
        self.pageRules = pageRules
    }

    fileprivate static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
        }
    }
}

public enum ExtractionPlanError: Error, Equatable, Sendable {
    case invalidProfile
    case invalidSourcePageCount
    case unaccountedSourcePage(Int)
    case missingSourcePage(Int)
    case inputGeometryMismatch(page: Int)
    case analysisRequired(page: Int)
    case missingAnchor(page: Int, anchorID: String)
    case ambiguousAnchor(page: Int, anchorID: String)
    case invalidAnalysis
    case invalidCopyPolicy
    case invalidPageSelection
    case invalidOutputLimit
    case tooManyOutputLabels
}

public struct PlannedExtractionLabel: Equatable, Sendable {
    public let sourcePage: Int
    public let regionIndex: Int
    public let regionID: String
    public let normalizedRect: NormalizedRect
    public let sourceRect: PDFSourceRect
    public let rotation: ExtractionRotation
    public let scalePolicy: ExtractionScalePolicy
    public let outputStockID: String
    public let outputStock: PhysicalSize
    public let profileID: String
    public let profileRevision: Int
}

public struct AccountedNonLabelPage: Equatable, Sendable {
    public let sourcePage: Int
    public let reason: NonLabelPageReason
}

public struct ExtractionPlan: Equatable, Sendable {
    public let sourcePageCount: Int
    public let outputLabels: [PlannedExtractionLabel]
    public let skippedPages: [AccountedNonLabelPage]
    public let profileID: String
    public let profileRevision: Int
}

public enum ExtractionPlanner {
    public static func plan(
        sourcePages: [PDFPageBox],
        profile: WorkflowProfile,
        selectedSourcePages: Set<Int>? = nil,
        copyPolicy: LabelOrderPlan.CopyPolicy = .alreadyExpanded,
        maximumOutputLabels: Int = 10_000
    ) throws -> ExtractionPlan {
        let analyzed = try sourcePages.map { try AnalyzedSourcePage(pageBox: $0, anchors: nil) }
        return try plan(
            analyzedPages: analyzed,
            profile: profile,
            selectedSourcePages: selectedSourcePages,
            copyPolicy: copyPolicy,
            maximumOutputLabels: maximumOutputLabels
        )
    }

    public static func plan(
        analyzedPages: [AnalyzedSourcePage],
        profile: WorkflowProfile,
        selectedSourcePages: Set<Int>? = nil,
        copyPolicy: LabelOrderPlan.CopyPolicy = .alreadyExpanded,
        maximumOutputLabels: Int = 10_000
    ) throws -> ExtractionPlan {
        guard !analyzedPages.isEmpty, analyzedPages.count <= 1_000 else {
            throw ExtractionPlanError.invalidSourcePageCount
        }
        guard maximumOutputLabels > 0 else { throw ExtractionPlanError.invalidOutputLimit }
        if let selectedSourcePages {
            guard !selectedSourcePages.isEmpty,
                  selectedSourcePages.allSatisfy({ (1...analyzedPages.count).contains($0) }) else {
                throw ExtractionPlanError.invalidPageSelection
            }
        }

        let rules = Dictionary(uniqueKeysWithValues: profile.pageRules.map { ($0.sourcePage, $0) })
        for page in 1...analyzedPages.count where rules[page] == nil {
            throw ExtractionPlanError.unaccountedSourcePage(page)
        }
        if let missing = rules.keys.filter({ $0 > analyzedPages.count }).min() {
            throw ExtractionPlanError.missingSourcePage(missing)
        }

        var definitions: [LabelOrderPlan.Label: (ExtractionRegion, PDFSourceRect)] = [:]
        var ordered: [(Int, LabelOrderPlan.Label)] = []
        var skipped: [AccountedNonLabelPage] = []
        for page in 1...analyzedPages.count {
            let analyzed = analyzedPages[page - 1]
            let source = analyzed.pageBox
            guard let rule = rules[page] else { preconditionFailure("page accounting checked") }
            guard rule.expectedInput.matches(try source.effectivePhysicalSize()) else {
                throw ExtractionPlanError.inputGeometryMismatch(page: page)
            }
            try validateAnchors(rule.structuralAnchors, observed: analyzed.anchors, page: page)
            switch rule.disposition {
            case let .extract(regions):
                for (index, region) in regions.enumerated() {
                    let identity = LabelOrderPlan.Label(sourcePage: page, region: index)
                    definitions[identity] = (region, source.sourceRect(for: region.normalizedRect))
                    ordered.append((region.outputOrder, identity))
                }
            case let .skip(reason):
                skipped.append(AccountedNonLabelPage(sourcePage: page, reason: reason))
            }
        }

        let base = ordered.sorted { $0.0 < $1.0 }.map(\.1)
        let expanded: [LabelOrderPlan.Label]
        do {
            expanded = try LabelOrderPlan.make(
                labels: base,
                selectedSourcePages: selectedSourcePages.map { $0.intersection(Set(base.map(\.sourcePage))) },
                copyPolicy: copyPolicy,
                maxOutputLabels: maximumOutputLabels
            )
        } catch let error as LabelOrderPlan.PlanError {
            switch error {
            case .invalidCopies:
                throw ExtractionPlanError.invalidCopyPolicy
            case .tooManyLabels:
                throw ExtractionPlanError.tooManyOutputLabels
            case .invalidLimit:
                throw ExtractionPlanError.invalidOutputLimit
            case .invalidLabel, .invalidSelection:
                throw ExtractionPlanError.invalidProfile
            }
        }
        let labels = expanded.map { identity -> PlannedExtractionLabel in
            guard let (region, sourceRect) = definitions[identity] else {
                preconditionFailure("ordered region must have a definition")
            }
            return PlannedExtractionLabel(
                sourcePage: identity.sourcePage,
                regionIndex: identity.region,
                regionID: region.id,
                normalizedRect: region.normalizedRect,
                sourceRect: sourceRect,
                rotation: region.rotation,
                scalePolicy: region.scalePolicy,
                outputStockID: profile.outputStockID,
                outputStock: profile.outputStock,
                profileID: profile.id,
                profileRevision: profile.revision
            )
        }
        return ExtractionPlan(
            sourcePageCount: analyzedPages.count,
            outputLabels: labels,
            skippedPages: skipped.filter { selectedSourcePages?.contains($0.sourcePage) ?? true },
            profileID: profile.id,
            profileRevision: profile.revision
        )
    }

    private static func validateAnchors(
        _ expected: [StructuralAnchorExpectation],
        observed: [ObservedPageAnchor]?,
        page: Int
    ) throws {
        guard !expected.isEmpty else { return }
        guard let observed else { throw ExtractionPlanError.analysisRequired(page: page) }
        var available = Set(observed.indices)
        for anchor in expected {
            let candidates = available.filter { index in
                let candidate = observed[index]
                return candidate.kind == anchor.kind && rectanglesMatch(
                    candidate.normalizedRect,
                    anchor.normalizedRect,
                    tolerance: anchor.maximumCoordinateDeviation
                )
            }
            guard !candidates.isEmpty else {
                throw ExtractionPlanError.missingAnchor(page: page, anchorID: anchor.id)
            }
            guard candidates.count == 1, let match = candidates.first else {
                throw ExtractionPlanError.ambiguousAnchor(page: page, anchorID: anchor.id)
            }
            available.remove(match)
        }
    }

    private static func rectanglesMatch(
        _ lhs: NormalizedRect,
        _ rhs: NormalizedRect,
        tolerance: Double
    ) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
