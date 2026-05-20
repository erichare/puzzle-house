import Foundation

public enum RawScore: Hashable, Sendable, Codable {
    case guesses(used: Int, outOf: Int, solved: Bool)
    case mistakes(count: Int, maxAllowed: Int, solved: Bool)
    case hints(count: Int, solved: Bool)
    case custom(value: Double, solved: Bool)

    public var solved: Bool {
        switch self {
        case .guesses(_, _, let solved),
             .mistakes(_, _, let solved),
             .hints(_, let solved),
             .custom(_, let solved):
            return solved
        }
    }

    /// "Goodness" — higher is better. Used by combined-score normalization.
    /// Each game converts its own raw score onto a small ordinal scale.
    public var goodness: Double {
        switch self {
        case .guesses(let used, let outOf, let solved):
            return solved ? Double(outOf - used + 1) : 0
        case .mistakes(let count, let maxAllowed, let solved):
            return solved ? Double(maxAllowed - count + 1) : 0
        case .hints(let count, let solved):
            return solved ? max(0, 5 - Double(count)) : 0
        case .custom(let value, _):
            return value
        }
    }
}
