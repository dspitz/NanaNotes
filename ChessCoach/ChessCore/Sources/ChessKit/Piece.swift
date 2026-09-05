import Foundation

/// The two armies.
public enum PieceColor: UInt8, Sendable, Hashable, CaseIterable {
    case white = 0
    case black = 1

    public var opponent: PieceColor {
        return self == .white ? .black : .white
    }

    public var name: String {
        return self == .white ? "White" : "Black"
    }

    /// `+1` for White, `-1` for Black. Used to flip White-relative scores.
    public var sign: Int {
        return self == .white ? 1 : -1
    }

    /// How many ranks a pawn of this colour advances by.
    public var pawnDirection: Int {
        return self == .white ? 1 : -1
    }

    /// The rank a pawn of this colour starts on (0-indexed).
    public var pawnStartRank: Int {
        return self == .white ? 1 : 6
    }

    /// The rank a pawn of this colour promotes on (0-indexed).
    public var promotionRank: Int {
        return self == .white ? 7 : 0
    }

    /// The rank this colour's king and rooks start on (0-indexed).
    public var backRank: Int {
        return self == .white ? 0 : 7
    }
}

public enum PieceKind: UInt8, Sendable, Hashable, CaseIterable {
    case pawn = 0
    case knight = 1
    case bishop = 2
    case rook = 3
    case queen = 4
    case king = 5

    /// Uppercase SAN letter. Pawns are "P" here even though SAN omits the letter.
    public var symbol: Character {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    public var name: String {
        switch self {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }

    /// Rough trading value in centipawns. The evaluator uses its own tapered
    /// values; this one is for move ordering, SEE and coach-facing phrasing.
    public var value: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 20000
        }
    }

    public var isSlider: Bool {
        return self == .bishop || self == .rook || self == .queen
    }

    public static func fromSymbol(_ character: Character) -> PieceKind? {
        switch Character(character.uppercased()) {
        case "P": return .pawn
        case "N": return .knight
        case "B": return .bishop
        case "R": return .rook
        case "Q": return .queen
        case "K": return .king
        default: return nil
        }
    }
}

public struct Piece: Hashable, Sendable {
    public let color: PieceColor
    public let kind: PieceKind

    public init(_ color: PieceColor, _ kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    public init(color: PieceColor, kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    /// FEN letter: uppercase for White, lowercase for Black.
    public var fenSymbol: Character {
        return color == .white ? kind.symbol : Character(kind.symbol.lowercased())
    }

    /// The figurine used by the board view.
    public var unicodeSymbol: String {
        switch (color, kind) {
        case (.white, .king): return "\u{2654}"
        case (.white, .queen): return "\u{2655}"
        case (.white, .rook): return "\u{2656}"
        case (.white, .bishop): return "\u{2657}"
        case (.white, .knight): return "\u{2658}"
        case (.white, .pawn): return "\u{2659}"
        case (.black, .king): return "\u{265A}"
        case (.black, .queen): return "\u{265B}"
        case (.black, .rook): return "\u{265C}"
        case (.black, .bishop): return "\u{265D}"
        case (.black, .knight): return "\u{265E}"
        case (.black, .pawn): return "\u{265F}"
        }
    }

    public static func fromFENSymbol(_ character: Character) -> Piece? {
        guard let kind = PieceKind.fromSymbol(character) else { return nil }
        return Piece(character.isUppercase ? .white : .black, kind)
    }
}
