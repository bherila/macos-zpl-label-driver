/// Mutable-by-value editing state for a future teach-once UI. Every operation
/// rebuilds the typed immutable contract; invalid edits leave the draft intact.
public struct WorkflowProfileDraft: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case revisionOverflow
        case regionNotFound(String)
        case invalidDestination
    }

    public private(set) var profile: WorkflowProfile

    public init(profile: WorkflowProfile) {
        self.profile = profile
    }

    public init(nextRevisionOf profile: WorkflowProfile) throws {
        guard profile.revision < Int.max else { throw Error.revisionOverflow }
        self.profile = try WorkflowProfile(
            id: profile.id,
            revision: profile.revision + 1,
            outputStockID: profile.outputStockID,
            outputStock: profile.outputStock,
            monochromeConversion: profile.monochromeConversion,
            pageRules: profile.pageRules
        )
    }

    public mutating func updateRegion(
        id: String,
        normalizedRect: NormalizedRect,
        rotation: ExtractionRotation
    ) throws {
        var found = false
        let rules = try profile.pageRules.map { rule -> WorkflowPageRule in
            guard case let .extract(regions) = rule.disposition else { return rule }
            let updated = try regions.map { region -> ExtractionRegion in
                guard region.id == id else { return region }
                found = true
                return try ExtractionRegion(
                    id: region.id,
                    normalizedRect: normalizedRect,
                    rotation: rotation,
                    scalePolicy: region.scalePolicy,
                    outputOrder: region.outputOrder
                )
            }
            return try replacing(rule, disposition: .extract(updated))
        }
        guard found else { throw Error.regionNotFound(id) }
        profile = try replacingProfile(pageRules: rules)
    }

    /// Moves a region in the one global output sequence and rewrites contiguous
    /// output orders without changing source-page membership or coordinates.
    public mutating func moveRegion(id: String, to destination: Int) throws {
        var ordered = profile.pageRules.flatMap { rule -> [ExtractionRegion] in
            guard case let .extract(regions) = rule.disposition else { return [] }
            return regions
        }.sorted { $0.outputOrder < $1.outputOrder }
        guard let source = ordered.firstIndex(where: { $0.id == id }) else {
            throw Error.regionNotFound(id)
        }
        guard destination >= 0, destination < ordered.count else { throw Error.invalidDestination }
        let moving = ordered.remove(at: source)
        ordered.insert(moving, at: destination)
        let orders = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        let rules = try profile.pageRules.map { rule -> WorkflowPageRule in
            guard case let .extract(regions) = rule.disposition else { return rule }
            let updated = try regions.map { region in
                try ExtractionRegion(
                    id: region.id,
                    normalizedRect: region.normalizedRect,
                    rotation: region.rotation,
                    scalePolicy: region.scalePolicy,
                    outputOrder: orders[region.id]!
                )
            }
            return try replacing(rule, disposition: .extract(updated))
        }
        profile = try replacingProfile(pageRules: rules)
    }

    public func validatedProfile() -> WorkflowProfile { profile }

    private func replacingProfile(pageRules: [WorkflowPageRule]) throws -> WorkflowProfile {
        try WorkflowProfile(
            id: profile.id,
            revision: profile.revision,
            outputStockID: profile.outputStockID,
            outputStock: profile.outputStock,
            monochromeConversion: profile.monochromeConversion,
            pageRules: pageRules
        )
    }

    private func replacing(
        _ rule: WorkflowPageRule,
        disposition: WorkflowPageDisposition
    ) throws -> WorkflowPageRule {
        try WorkflowPageRule(
            sourcePage: rule.sourcePage,
            expectedInput: rule.expectedInput,
            disposition: disposition,
            structuralAnchors: rule.structuralAnchors
        )
    }
}
