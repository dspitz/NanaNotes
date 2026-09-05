import Foundation
import ChessKit

/// Descriptive facts about a position, in the vocabulary a coach uses.
///
/// `Evaluator` turns some of these into numbers; the narrator turns them into
/// sentences. Keeping them in one place means the score and the explanation can
/// never disagree about what is on the board.
public struct PositionFeatures: Sendable {
    public struct Side: Sendable {
        public var color: PieceColor
        public var material: Int
        public var pawnCount: Int
        public var doubledPawns: [Square] = []
        public var isolatedPawns: [Square] = []
        public var backwardPawns: [Square] = []
        public var passedPawns: [Square] = []
        public var hasBishopPair = false
        public var undevelopedMinorPieces: [Square] = []
        public var hasCastled = false
        public var kingSquare: Square?
        public var kingShelterPawns = 0
        public var kingIsExposed = false
        public var rooksOnOpenFiles: [Square] = []
        public var rooksOnSemiOpenFiles: [Square] = []
        public var openFiles: [Int] = []
        public var semiOpenFiles: [Int] = []
        public var spaceCount = 0
        public var outposts: [Square] = []
        /// Lowest-mobility minor piece — the classic "improve your worst piece".
        public var leastActivePiece: LeastActivePiece?
        public var totalMobility = 0
    }

    public struct LeastActivePiece: Sendable, Hashable {
        public let square: Square
        public let piece: Piece
        public let mobility: Int
    }

    public var white: Side
    public var black: Side
    public var phase: GamePhase
    /// Files with no pawns of either colour.
    public var fullyOpenFiles: [Int]

    public func side(_ color: PieceColor) -> Side {
        return color == .white ? white : black
    }

    public static func analyze(_ position: Position, evaluator: Evaluator = Evaluator()) -> PositionFeatures {
        var white = Side(color: .white, material: 0, pawnCount: 0)
        var black = Side(color: .black, material: 0, pawnCount: 0)
        var pawnsPerFile = [[Int]](repeating: [Int](repeating: 0, count: 8), count: 2)
        var mostAdvanced = [[Int]](repeating: [Int](repeating: -1, count: 8), count: 2)

        for square in Square.all {
            guard let piece = position.piece(at: square) else { continue }
            let index = Int(piece.color.rawValue)
            if piece.kind == .pawn {
                pawnsPerFile[index][square.file] += 1
                mostAdvanced[index][square.file] = max(mostAdvanced[index][square.file], square.relativeRank(for: piece.color))
            }
        }

        for square in Square.all {
            guard let piece = position.piece(at: square) else { continue }
            let colorIndex = Int(piece.color.rawValue)
            let enemyIndex = 1 - colorIndex
            var side = piece.color == .white ? white : black

            if piece.kind != .king {
                side.material += piece.kind.value
            }

            switch piece.kind {
            case .pawn:
                side.pawnCount += 1
                if pawnsPerFile[colorIndex][square.file] > 1 { side.doubledPawns.append(square) }
                let left = square.file > 0 ? pawnsPerFile[colorIndex][square.file - 1] : 0
                let right = square.file < 7 ? pawnsPerFile[colorIndex][square.file + 1] : 0
                if left == 0 && right == 0 {
                    side.isolatedPawns.append(square)
                } else if evaluator.isBackward(square, color: piece.color, in: position) {
                    side.backwardPawns.append(square)
                }
                if evaluator.isPassed(square, color: piece.color, mostAdvanced: mostAdvanced[enemyIndex], in: position) {
                    side.passedPawns.append(square)
                }
                if square.relativeRank(for: piece.color) >= 3 { side.spaceCount += 1 }

            case .knight, .bishop:
                if square.rank == piece.color.backRank { side.undevelopedMinorPieces.append(square) }
                let mobility = evaluator.mobilityCount(for: piece, on: square, in: position)
                side.totalMobility += mobility
                if mobility < (side.leastActivePiece?.mobility ?? Int.max) {
                    side.leastActivePiece = LeastActivePiece(square: square, piece: piece, mobility: mobility)
                }
                if isOutpost(square, color: piece.color, pawnsPerFile: pawnsPerFile, in: position) {
                    side.outposts.append(square)
                }

            case .rook:
                let own = pawnsPerFile[colorIndex][square.file]
                let enemy = pawnsPerFile[enemyIndex][square.file]
                if own == 0 && enemy == 0 {
                    side.rooksOnOpenFiles.append(square)
                } else if own == 0 {
                    side.rooksOnSemiOpenFiles.append(square)
                }
                side.totalMobility += evaluator.mobilityCount(for: piece, on: square, in: position)

            case .queen:
                side.totalMobility += evaluator.mobilityCount(for: piece, on: square, in: position)

            case .king:
                side.kingSquare = square
                side.hasCastled = square.rank == piece.color.backRank && (square.file <= 2 || square.file >= 6)
                for file in max(0, square.file - 1)...min(7, square.file + 1) {
                    for step in 1...2 {
                        guard let shelter = Square(file: file, rank: square.rank + piece.color.pawnDirection * step),
                              let shelterPiece = position.piece(at: shelter),
                              shelterPiece.color == piece.color, shelterPiece.kind == .pawn else { continue }
                        side.kingShelterPawns += 1
                        break
                    }
                }
                side.kingIsExposed = side.kingShelterPawns <= 1
            }

            if piece.color == .white { white = side } else { black = side }
        }

        white.hasBishopPair = position.count(of: .white, kind: .bishop) >= 2
        black.hasBishopPair = position.count(of: .black, kind: .bishop) >= 2

        var fullyOpen: [Int] = []
        for file in 0..<8 {
            let whitePawns = pawnsPerFile[0][file]
            let blackPawns = pawnsPerFile[1][file]
            if whitePawns == 0 && blackPawns == 0 { fullyOpen.append(file) }
            if whitePawns == 0 {
                white.openFiles.append(file)
                if blackPawns > 0 { white.semiOpenFiles.append(file) }
            }
            if blackPawns == 0 {
                black.openFiles.append(file)
                if whitePawns > 0 { black.semiOpenFiles.append(file) }
            }
        }

        return PositionFeatures(white: white, black: black, phase: evaluator.gamePhase(position), fullyOpenFiles: fullyOpen)
    }

    /// A square a minor piece can sit on that no enemy pawn can ever challenge.
    private static func isOutpost(_ square: Square, color: PieceColor, pawnsPerFile: [[Int]], in position: Position) -> Bool {
        guard square.relativeRank(for: color) >= 3, square.relativeRank(for: color) <= 5 else { return false }
        // Defended by one of our own pawns.
        let defenders = position.attackers(of: square, by: color)
        guard defenders.contains(where: { position.piece(at: $0)?.kind == .pawn }) else { return false }
        // No enemy pawn can ever attack it.
        for file in [square.file - 1, square.file + 1] where file >= 0 && file < 8 {
            for rank in 0..<8 {
                guard let candidate = Square(file: file, rank: rank),
                      let piece = position.piece(at: candidate),
                      piece.color == color.opponent, piece.kind == .pawn else { continue }
                if candidate.relativeRank(for: color) > square.relativeRank(for: color) { return false }
            }
        }
        return true
    }
}
