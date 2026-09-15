/// Pure label-order expansion. Source-page filtering precedes copy expansion.
/// No implicit deduplication and no device ^PQ instructions.
public enum LabelOrderPlan {
    public struct Label: Equatable, Hashable, Sendable {
        public let sourcePage: Int
        public let region: Int
        public init(sourcePage: Int, region: Int) { self.sourcePage = sourcePage; self.region = region }
    }
    public enum CopyPolicy: Equatable, Sendable {
        case engine(copies: Int, collated: Bool)
        /// Upstream already expanded copies. Preserve exactly the labels received.
        case alreadyExpanded
    }
    public enum PlanError: Error, Equatable, Sendable {
        case invalidLimit, invalidLabel, invalidSelection, invalidCopies, tooManyLabels
    }
    public static func make(labels: [Label], selectedSourcePages: Set<Int>? = nil,
                            copyPolicy: CopyPolicy, maxOutputLabels: Int = 10_000) throws -> [Label] {
        guard maxOutputLabels > 0 else { throw PlanError.invalidLimit }
        guard labels.allSatisfy({ $0.sourcePage > 0 && $0.region >= 0 }) else { throw PlanError.invalidLabel }
        var selected = labels
        if let pages = selectedSourcePages {
            let available = Set(labels.map(\.sourcePage))
            guard pages.allSatisfy({ $0 > 0 }), pages.isSubset(of: available) else { throw PlanError.invalidSelection }
            selected = labels.filter { pages.contains($0.sourcePage) }
        }
        let copies: Int
        let collated: Bool
        switch copyPolicy {
        case .alreadyExpanded: copies = 1; collated = true
        case let .engine(n, c): copies = n; collated = c
        }
        guard copies > 0 else { throw PlanError.invalidCopies }
        let (count, overflow) = selected.count.multipliedReportingOverflow(by: copies)
        guard !overflow, count <= maxOutputLabels else { throw PlanError.tooManyLabels }
        // Avoid a huge loop over an empty selection and arbitrarily large copy count.
        guard !selected.isEmpty else { return [] }
        var output: [Label] = []
        output.reserveCapacity(count)
        if collated {
            for _ in 0..<copies { output.append(contentsOf: selected) }
        } else {
            for label in selected { for _ in 0..<copies { output.append(label) } }
        }
        return output
    }
}
