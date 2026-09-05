import Foundation

/// A board square, stored as a 0x88 index.
///
/// 0x88 lays the board out as 8 ranks of 16 files: the left half is the real
/// board and the right half is off-board padding, so `index & 0x88 != 0` is a
/// one-instruction "did I fall off the edge" test during move generation.
public struct Square: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// 0x88 index. `0` is a1, `7` is h1, `112` is a8, `119` is h8.
    public let index: Int

    public init?(index: Int) {
        guard index >= 0, index < 128, (index & 0x88) == 0 else { return nil }
        self.index = index
    }

    /// Unchecked initialiser for hot paths that have already validated the index
    /// with `Square.isValidIndex(_:)`. Passing an off-board index is a programmer error.
    public init(unchecked index: Int) {
        self.index = index
    }

    /// - Parameters:
    ///   - file: 0 = a-file ... 7 = h-file.
    ///   - rank: 0 = rank 1 ... 7 = rank 8.
    public init?(file: Int, rank: Int) {
        guard file >= 0, file < 8, rank >= 0, rank < 8 else { return nil }
        self.index = rank * 16 + file
    }

    public init?(algebraic: String) {
        let characters = Array(algebraic.lowercased())
        guard characters.count == 2 else { return nil }
        guard let fileScalar = characters[0].asciiValue, let rankScalar = characters[1].asciiValue else { return nil }
        let file = Int(fileScalar) - 97       // "a"
        let rank = Int(rankScalar) - 49       // "1"
        self.init(file: file, rank: rank)
    }

    /// 0 = a-file ... 7 = h-file.
    /// True when a raw 0x88 index refers to a real square.
    public static func isValidIndex(_ index: Int) -> Bool {
        return index >= 0 && index < 128 && (index & 0x88) == 0
    }

    public var file: Int { return index & 7 }

    /// 0 = rank 1 ... 7 = rank 8.
    public var rank: Int { return index >> 4 }

    /// Index into a compact 64-square array (a1 = 0, h8 = 63).
    public var compactIndex: Int { return rank * 8 + file }

    public init(compactIndex: Int) {
        self.index = (compactIndex / 8) * 16 + (compactIndex % 8)
    }

    public var name: String {
        let fileCharacter = Character(UnicodeScalar(UInt8(97 + file)))
        return "\(fileCharacter)\(rank + 1)"
    }

    public var description: String { return name }

    public var fileName: String {
        return String(Character(UnicodeScalar(UInt8(97 + file))))
    }

    /// Squares are alternately light and dark; a1 is dark.
    public var isLight: Bool { return (file + rank) % 2 == 1 }

    public func offset(file deltaFile: Int, rank deltaRank: Int) -> Square? {
        return Square(file: file + deltaFile, rank: rank + deltaRank)
    }

    /// Chebyshev distance — the number of king moves between two squares.
    public func distance(to other: Square) -> Int {
        return max(abs(file - other.file), abs(rank - other.rank))
    }

    /// How far this square is from the centre of the board, in king moves.
    public var distanceFromCenter: Int {
        let fileDistance = min(abs(file - 3), abs(file - 4))
        let rankDistance = min(abs(rank - 3), abs(rank - 4))
        return max(fileDistance, rankDistance)
    }

    /// Rank as seen by `color`: 0 is that colour's back rank, 7 is promotion.
    public func relativeRank(for color: PieceColor) -> Int {
        return color == .white ? rank : 7 - rank
    }

    public static func < (lhs: Square, rhs: Square) -> Bool {
        return lhs.index < rhs.index
    }

    /// All 64 real squares, a1 first, h8 last.
    public static let all: [Square] = (0..<64).map { Square(compactIndex: $0) }
}
