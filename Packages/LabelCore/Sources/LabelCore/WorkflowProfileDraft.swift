/// Mutable-by-value editing state for a future teach-once UI. Every operation
/// rebuilds the typed immutable contract; invalid edits leave the draft intact.
public struct WorkflowProfileDraft: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case revisionOverflow
        case regionNotFound(String)
        case invalidDestination
        case lastRegionOnPage
        case pageNotFound(Int)
        case invalidPageDisposition
        case lastOutputPage
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

    /// An explicit starting copy for another label on the same sheet. The user
    /// must set its bounds; overlap is not interpreted as automatic detection.
    public mutating func duplicateRegion(id: String, newID: String) throws {
        var ordered = orderedRegions
        guard let index = ordered.firstIndex(where: { $0.id == id }) else {
            throw Error.regionNotFound(id)
        }
        guard !ordered.contains(where: { $0.id == newID }) else {
            throw ExtractionPlanError.invalidProfile
        }
        let original = ordered[index]
        let copy = try ExtractionRegion(id: newID, normalizedRect: original.normalizedRect,
            rotation: original.rotation, scalePolicy: original.scalePolicy, outputOrder: 0)
        ordered.insert(copy, at: index + 1)
        let rules = try profile.pageRules.map { rule -> WorkflowPageRule in
            guard case let .extract(regions) = rule.disposition,
                  regions.contains(where: { $0.id == id }) else { return rule }
            // Match the public profile decoder's per-page region bound.
            guard regions.count < 256 else { throw ExtractionPlanError.invalidProfile }
            return try replacing(rule, disposition: .extract(regions + [copy]))
        }
        let next = try replacingProfile(pageRules: assigningOrders(rules, ordered: ordered))
        _ = try WorkflowProfileJSON.encode(next)
        profile = next
    }

    /// Removing a last region must never silently convert a page into a skip.
    public mutating func removeRegion(id: String) throws {
        guard orderedRegions.contains(where: { $0.id == id }) else {
            throw Error.regionNotFound(id)
        }
        let rules = try profile.pageRules.map { rule -> WorkflowPageRule in
            guard case let .extract(regions) = rule.disposition,
                  regions.contains(where: { $0.id == id }) else { return rule }
            guard regions.count > 1 else { throw Error.lastRegionOnPage }
            return try replacing(rule, disposition: .extract(regions.filter { $0.id != id }))
        }
        profile = try replacingProfile(pageRules: assigningOrders(rules,
            ordered: orderedRegions.filter { $0.id != id }))
    }

    private var orderedRegions: [ExtractionRegion] {
        profile.pageRules.flatMap { rule -> [ExtractionRegion] in
            if case let .extract(regions) = rule.disposition { return regions }
            return []
        }.sorted { $0.outputOrder < $1.outputOrder }
    }

    /// Explicit page policy, never a consequence of deleting a last region.
    /// Geometry and structural expectations continue to validate skipped pages.
    public mutating func skipPage(_ sourcePage: Int, reason: NonLabelPageReason) throws {
        guard let rule = profile.pageRules.first(where: { $0.sourcePage == sourcePage }) else {
            throw Error.pageNotFound(sourcePage)
        }
        guard case .extract = rule.disposition else { throw Error.invalidPageDisposition }
        let remaining = profile.pageRules.filter { $0.sourcePage != sourcePage }.flatMap { rule -> [ExtractionRegion] in
            if case let .extract(regions) = rule.disposition { return regions }
            return []
        }.sorted { $0.outputOrder < $1.outputOrder }
        guard !remaining.isEmpty else { throw Error.lastOutputPage }
        let rules = try profile.pageRules.map { rule in
            rule.sourcePage == sourcePage ? try replacing(rule, disposition: .skip(reason)) : rule
        }
        let next = try replacingProfile(pageRules: assigningOrders(rules, ordered: remaining))
        _ = try WorkflowProfileJSON.encode(next)
        profile = next
    }

    /// Restoration intentionally starts with a full-page region at the end of
    /// output order. Removed crop definitions are not guessed or reconstructed.
    public mutating func restorePage(_ sourcePage: Int, newRegionID: String) throws {
        guard let rule = profile.pageRules.first(where: { $0.sourcePage == sourcePage }) else {
            throw Error.pageNotFound(sourcePage)
        }
        guard case .skip = rule.disposition else { throw Error.invalidPageDisposition }
        guard !orderedRegions.contains(where: { $0.id == newRegionID }) else {
            throw ExtractionPlanError.invalidProfile
        }
        let region = try ExtractionRegion(id: newRegionID,
            normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            outputOrder: orderedRegions.count)
        let rules = try profile.pageRules.map { rule in
            rule.sourcePage == sourcePage ? try replacing(rule, disposition: .extract([region])) : rule
        }
        let next = try replacingProfile(pageRules: assigningOrders(rules, ordered: orderedRegions + [region]))
        _ = try WorkflowProfileJSON.encode(next)
        profile = next
    }

    private func assigningOrders(_ rules: [WorkflowPageRule], ordered: [ExtractionRegion]) throws -> [WorkflowPageRule] {
        let orders = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        return try rules.map { rule in
            guard case let .extract(regions) = rule.disposition else { return rule }
            return try replacing(rule, disposition: .extract(regions.map { region in
                try ExtractionRegion(id: region.id, normalizedRect: region.normalizedRect,
                    rotation: region.rotation, scalePolicy: region.scalePolicy,
                    outputOrder: orders[region.id]!)
            }))
        }
    }

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
