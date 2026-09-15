/// An explicit user-confirmed qualification for one exact immutable workflow
/// profile value. Profile JSON cannot encode this wrapper.
public struct UnattendedWorkflowQualification: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case missingStructuralChecks(page: Int)
    }

    fileprivate let confirmedProfile: WorkflowProfile

    /// Call only at the user-confirmation boundary after reviewing the source,
    /// regions, page dispositions, preview, and structural checks.
    public init(userConfirmed profile: WorkflowProfile) throws {
        if let unsafePage = profile.pageRules.first(where: { $0.structuralAnchors.isEmpty }) {
            throw Error.missingStructuralChecks(page: unsafePage.sourcePage)
        }
        self.confirmedProfile = profile
    }

    public var profileID: String { confirmedProfile.id }
    public var profileRevision: Int { confirmedProfile.revision }
}

public enum WorkflowMatchResult: Equatable, Sendable {
    /// The document matches structurally, but this exact immutable profile has
    /// not been confirmed for unattended use.
    case confirmationRequired(ExtractionPlan)
    /// The document and the exact confirmed profile both match.
    case qualified(ExtractionPlan)

    public var plan: ExtractionPlan {
        switch self {
        case let .confirmationRequired(plan), let .qualified(plan): plan
        }
    }
}

public enum WorkflowMatcher {
    /// Structural or geometry errors are thrown before confirmation is
    /// considered. A qualification can never turn a mismatch into a plan.
    public static func match(
        analyzedPages: [AnalyzedSourcePage],
        profile: WorkflowProfile,
        qualification: UnattendedWorkflowQualification? = nil,
        copyPolicy: LabelOrderPlan.CopyPolicy = .alreadyExpanded,
        maximumOutputLabels: Int = 10_000
    ) throws -> WorkflowMatchResult {
        let plan = try ExtractionPlanner.plan(
            analyzedPages: analyzedPages,
            profile: profile,
            copyPolicy: copyPolicy,
            maximumOutputLabels: maximumOutputLabels
        )
        guard qualification?.confirmedProfile == profile else {
            return .confirmationRequired(plan)
        }
        return .qualified(plan)
    }
}
