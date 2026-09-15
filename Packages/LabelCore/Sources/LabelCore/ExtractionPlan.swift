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
    public let sourcePage: Int
    public let expectedInput: ExpectedInputPage
    public let disposition: WorkflowPageDisposition

    public init(sourcePage: Int, expectedInput: ExpectedInputPage, disposition: WorkflowPageDisposition) throws {
        guard sourcePage > 0 else { throw ExtractionPlanError.invalidProfile }
        if case let .extract(regions) = disposition, regions.isEmpty {
            throw ExtractionPlanError.invalidProfile
        }
        self.sourcePage = sourcePage
        self.expectedInput = expectedInput
        self.disposition = disposition
    }
}

public struct WorkflowProfile: Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let revision: Int
    public let outputStockID: String
    public let outputStock: PhysicalSize
    public let pageRules: [WorkflowPageRule]

    public init(
        schemaVersion: Int = 1,
        id: String,
        revision: Int,
        outputStockID: String,
        outputStock: PhysicalSize,
        pageRules: [WorkflowPageRule]
    ) throws {
        guard schemaVersion == 1, revision > 0,
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
    case invalidCopyPolicy
    case invalidOutputLimit
    case tooManyOutputLabels
}

public struct PlannedExtractionLabel: Equatable, Sendable {
    public let sourcePage: Int
    public let regionIndex: Int
    public let regionID: String
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
        copyPolicy: LabelOrderPlan.CopyPolicy = .alreadyExpanded,
        maximumOutputLabels: Int = 10_000
    ) throws -> ExtractionPlan {
        guard !sourcePages.isEmpty, sourcePages.count <= 1_000 else {
            throw ExtractionPlanError.invalidSourcePageCount
        }
        guard maximumOutputLabels > 0 else { throw ExtractionPlanError.invalidOutputLimit }

        let rules = Dictionary(uniqueKeysWithValues: profile.pageRules.map { ($0.sourcePage, $0) })
        for page in 1...sourcePages.count where rules[page] == nil {
            throw ExtractionPlanError.unaccountedSourcePage(page)
        }
        if let missing = rules.keys.filter({ $0 > sourcePages.count }).min() {
            throw ExtractionPlanError.missingSourcePage(missing)
        }

        var definitions: [LabelOrderPlan.Label: (ExtractionRegion, PDFSourceRect)] = [:]
        var ordered: [(Int, LabelOrderPlan.Label)] = []
        var skipped: [AccountedNonLabelPage] = []
        for page in 1...sourcePages.count {
            let source = sourcePages[page - 1]
            guard let rule = rules[page] else { preconditionFailure("page accounting checked") }
            guard rule.expectedInput.matches(try source.effectivePhysicalSize()) else {
                throw ExtractionPlanError.inputGeometryMismatch(page: page)
            }
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
            sourcePageCount: sourcePages.count,
            outputLabels: labels,
            skippedPages: skipped,
            profileID: profile.id,
            profileRevision: profile.revision
        )
    }
}
