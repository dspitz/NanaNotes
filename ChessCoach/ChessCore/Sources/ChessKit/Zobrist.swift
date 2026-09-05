import Foundation

/// Deterministic Zobrist keys. Positions hash to the same value across launches,
/// which lets the transposition table and repetition detection stay simple.
enum Zobrist {
    /// `[color][kind][compactSquare]`
    static let pieces: [[[UInt64]]] = {
        var generator = SplitMix64(seed: 0x9E3779B97F4A7C15)
        var table: [[[UInt64]]] = []
        for _ in 0..<2 {
            var perColor: [[UInt64]] = []
            for _ in 0..<6 {
                var perKind: [UInt64] = []
                for _ in 0..<64 {
                    perKind.append(generator.next())
                }
                perColor.append(perKind)
            }
            table.append(perColor)
        }
        return table
    }()

    static let sideToMove: UInt64 = {
        var generator = SplitMix64(seed: 0xD1B54A32D192ED03)
        return generator.next()
    }()

    /// Indexed by the raw value of `CastlingRights` (16 combinations).
    static let castling: [UInt64] = {
        var generator = SplitMix64(seed: 0xA0761D6478BD642F)
        return (0..<16).map { _ in generator.next() }
    }()

    /// Indexed by the file of the en-passant square.
    static let enPassantFile: [UInt64] = {
        var generator = SplitMix64(seed: 0xE7037ED1A0B428DB)
        return (0..<8).map { _ in generator.next() }
    }()

    static func piece(_ piece: Piece, at square: Square) -> UInt64 {
        return pieces[Int(piece.color.rawValue)][Int(piece.kind.rawValue)][square.compactIndex]
    }
}

/// A tiny, self-contained PRNG so key generation never depends on the platform's
/// random number generator (which would change hashes between runs).
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
