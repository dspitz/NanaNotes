import Foundation
import ChessKit

/// How hard the built-in opponent tries.
public enum OpponentStrength: String, CaseIterable, Sendable, Identifiable, Hashable {
    case beginner
    case casual
    case club
    case strong
    case maximum

    public var id: String { return rawValue }

    public var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .casual: return "Casual"
        case .club: return "Club player"
        case .strong: return "Strong"
        case .maximum: return "Full strength"
        }
    }

    public var approximateRating: String {
        switch self {
        case .beginner: return "~600"
        case .casual: return "~1000"
        case .club: return "~1400"
        case .strong: return "~1800"
        case .maximum: return "2000+"
        }
    }

    public var summary: String {
        switch self {
        case .beginner: return "Leaves pieces hanging and misses simple tactics. A safe place to practise."
        case .casual: return "Plays sensible moves but overlooks two-move combinations."
        case .club: return "Punishes loose pieces and knows basic plans."
        case .strong: return "Calculates several moves ahead and defends stubbornly."
        case .maximum: return "Plays the best move it can find in the time it has."
        }
    }

    var searchDepth: Int {
        switch self {
        case .beginner: return 2
        case .casual: return 3
        case .club: return 5
        case .strong: return 7
        case .maximum: return 9
        }
    }

    var timeLimit: TimeInterval {
        switch self {
        case .beginner: return 0.15
        case .casual: return 0.3
        case .club: return 0.8
        case .strong: return 1.5
        case .maximum: return 3.0
        }
    }

    var skillLevel: Int {
        switch self {
        case .beginner: return 1
        case .casual: return 6
        case .club: return 12
        case .strong: return 17
        case .maximum: return 20
        }
    }
}

/// How much chess vocabulary the coach assumes you have.
public enum CoachLevel: String, CaseIterable, Sendable, Identifiable, Hashable {
    case newcomer
    case improver
    case advanced

    public var id: String { return rawValue }

    public var displayName: String {
        switch self {
        case .newcomer: return "New to chess"
        case .improver: return "Improving"
        case .advanced: return "Advanced"
        }
    }

    public var summary: String {
        switch self {
        case .newcomer: return "Plain language, one idea at a time, always says which piece is in danger."
        case .improver: return "Names plans and motifs, and shows short concrete lines."
        case .advanced: return "Terse, assumes the vocabulary, leads with the critical variation."
        }
    }

    /// Longest variation the coach will quote at this level.
    var maximumLineLength: Int {
        switch self {
        case .newcomer: return 2
        case .improver: return 4
        case .advanced: return 8
        }
    }
}

/// How much the coach volunteers while you are playing.
public enum CoachVerbosity: String, CaseIterable, Sendable, Identifiable, Hashable {
    /// Nothing unless you ask.
    case onRequest
    /// Speaks up only when something important changes.
    case keyMoments
    /// Comments on every move.
    case everyMove

    public var id: String { return rawValue }

    public var displayName: String {
        switch self {
        case .onRequest: return "Only when I ask"
        case .keyMoments: return "At key moments"
        case .everyMove: return "Every move"
        }
    }
}
