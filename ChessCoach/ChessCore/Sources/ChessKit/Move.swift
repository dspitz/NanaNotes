import Foundation

public struct Move: Hashable, Sendable, CustomStringConvertible {
    public struct Flags: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let capture = Flags(rawValue: 1 << 0)
        public static let doublePawnPush = Flags(rawValue: 1 << 1)
        public static let enPassant = Flags(rawValue: 1 << 2)
        public static let kingsideCastle = Flags(rawValue: 1 << 3)
        public static let queensideCastle = Flags(rawValue: 1 << 4)
        public static let promotion = Flags(rawValue: 1 << 5)

        public static let castle: Flags = [.kingsideCastle, .queensideCastle]
    }

    public let from: Square
    public let to: Square
    public let promotion: PieceKind?
    public let flags: Flags

    public init(from: Square, to: Square, promotion: PieceKind? = nil, flags: Flags = []) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.flags = promotion == nil ? flags : flags.union(.promotion)
    }

    public var isCapture: Bool { return flags.contains(.capture) }
    public var isEnPassant: Bool { return flags.contains(.enPassant) }
    public var isPromotion: Bool { return promotion != nil }
    public var isCastle: Bool { return !flags.isDisjoint(with: .castle) }
    public var isKingsideCastle: Bool { return flags.contains(.kingsideCastle) }
    public var isQueensideCastle: Bool { return flags.contains(.queensideCastle) }
    public var isDoublePawnPush: Bool { return flags.contains(.doublePawnPush) }

    /// Long algebraic / UCI form, e.g. "e2e4" or "e7e8q".
    public var uci: String {
        var result = from.name + to.name
        if let promotion = promotion {
            result += promotion.symbol.lowercased()
        }
        return result
    }

    public var description: String { return uci }

    /// Parses UCI notation. The flags are filled in by `Position.move(matchingUCI:)`;
    /// a bare parse produces a flagless move suitable only for lookup.
    public static func parseUCI(_ text: String) -> Move? {
        let characters = Array(text.trimmingCharacters(in: .whitespaces))
        guard characters.count == 4 || characters.count == 5 else { return nil }
        guard let from = Square(algebraic: String(characters[0...1])),
              let to = Square(algebraic: String(characters[2...3])) else { return nil }
        var promotion: PieceKind?
        if characters.count == 5 {
            guard let kind = PieceKind.fromSymbol(characters[4]) else { return nil }
            promotion = kind
        }
        return Move(from: from, to: to, promotion: promotion)
    }

    /// Two moves refer to the same board action when their squares and promotion
    /// match; flags are derived state and are deliberately ignored here.
    public func matches(_ other: Move) -> Bool {
        return from == other.from && to == other.to && promotion == other.promotion
    }
}
