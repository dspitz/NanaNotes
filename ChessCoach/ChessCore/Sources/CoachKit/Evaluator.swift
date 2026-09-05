import Foundation
import ChessKit

public enum GamePhase: String, Sendable, Hashable {
    case opening
    case middlegame
    case endgame

    public var displayName: String {
        switch self {
        case .opening: return "Opening"
        case .middlegame: return "Middlegame"
        case .endgame: return "Endgame"
        }
    }
}

/// Every term the evaluator used, in centipawns and from White's point of view.
/// The coach reads this to say *why* one side stands better, not just by how much.
public struct EvaluationBreakdown: Sendable, Hashable {
    public var material = 0
    public var placement = 0
    public var mobility = 0
    public var pawnStructure = 0
    public var passedPawns = 0
    public var kingSafety = 0
    public var bishopPair = 0
    public var rookActivity = 0
    public var centerControl = 0
    public var tempo = 0

    public var total: Int {
        return material + placement + mobility + pawnStructure + passedPawns
            + kingSafety + bishopPair + rookActivity + centerControl + tempo
    }

    /// Named terms, biggest absolute contribution first. Material is excluded
    /// because the UI shows it separately as a piece count.
    public var rankedPositionalTerms: [(name: String, value: Int)] {
        let terms: [(String, Int)] = [
            ("King safety", kingSafety),
            ("Piece activity", placement),
            ("Mobility", mobility),
            ("Pawn structure", pawnStructure),
            ("Passed pawns", passedPawns),
            ("Bishop pair", bishopPair),
            ("Rook activity", rookActivity),
            ("Central control", centerControl)
        ]
        return terms
            .filter { abs($0.1) >= 10 }
            .sorted { abs($0.1) > abs($1.1) }
            .map { (name: $0.0, value: $0.1) }
    }
}

/// Hand-written positional evaluation.
///
/// Deliberately explainable: every term maps to something a coach can name.
/// Scores are centipawns, positive meaning White is better.
public struct Evaluator: Sendable {
    public static let shared = Evaluator()

    public init() {}

    // Tunable weights, kept as named constants so the coach can quote them.
    private static let doubledPawnPenalty = -12
    private static let isolatedPawnPenalty = -18
    private static let bishopPairBonus = 40
    private static let rookOpenFileBonus = 20
    private static let rookSemiOpenFileBonus = 10
    private static let rookOnSeventhBonus = 22
    private static let passedPawnBonusByRank = [0, 8, 18, 34, 62, 104, 160, 0]
    private static let mobilityWeight = 3
    private static let tempoBonus = 12
    private static let centerSquares: [Int] = [0x33, 0x34, 0x43, 0x44] // d4 e4 d5 e5

    // MARK: - Phase

    /// 24 at the start of the game, 0 with only kings and pawns left.
    public func phaseValue(_ position: Position) -> Int {
        var value = 0
        for square in Square.all {
            guard let piece = position.piece(at: square) else { continue }
            switch piece.kind {
            case .knight, .bishop: value += 1
            case .rook: value += 2
            case .queen: value += 4
            default: break
            }
        }
        return min(value, 24)
    }

    /// 0.0 in the opening, 1.0 in a bare-bones endgame.
    public func endgameWeight(_ position: Position) -> Double {
        return 1.0 - Double(phaseValue(position)) / 24.0
    }

    public func gamePhase(_ position: Position) -> GamePhase {
        let value = phaseValue(position)
        if value <= 8 { return .endgame }
        if value >= 21 && position.fullmoveNumber <= 14 { return .opening }
        return .middlegame
    }

    // MARK: - Evaluation

    /// White-relative score in centipawns.
    public func staticEvaluation(_ position: Position) -> Int {
        return breakdown(position).total
    }

    /// Score from the point of view of the side to move (what search wants).
    public func relativeEvaluation(_ position: Position) -> Int {
        return staticEvaluation(position) * position.sideToMove.sign
    }

    public func breakdown(_ position: Position) -> EvaluationBreakdown {
        var result = EvaluationBreakdown()
        let endgame = endgameWeight(position)

        // Pawn counts per file, used by several terms.
        var pawnsPerFile = [[Int]](repeating: [Int](repeating: 0, count: 8), count: 2)
        var mostAdvancedPawnRank = [[Int]](repeating: [Int](repeating: -1, count: 8), count: 2)
        var bishopCount = [0, 0]

        for square in Square.all {
            guard let piece = position.piece(at: square) else { continue }
            let colorIndex = Int(piece.color.rawValue)
            if piece.kind == .pawn {
                pawnsPerFile[colorIndex][square.file] += 1
                let relative = square.relativeRank(for: piece.color)
                if relative > mostAdvancedPawnRank[colorIndex][square.file] {
                    mostAdvancedPawnRank[colorIndex][square.file] = relative
                }
            }
            if piece.kind == .bishop { bishopCount[colorIndex] += 1 }
        }

        for square in Square.all {
            guard let piece = position.piece(at: square) else { continue }
            let sign = piece.color.sign
            let colorIndex = Int(piece.color.rawValue)
            let enemyIndex = 1 - colorIndex

            result.material += sign * piece.kind.value
            result.placement += sign * PieceSquareTables.value(for: piece, on: square, endgameWeight: endgame)

            switch piece.kind {
            case .pawn:
                let file = square.file
                if pawnsPerFile[colorIndex][file] > 1 {
                    result.pawnStructure += sign * Evaluator.doubledPawnPenalty
                }
                let leftCount = file > 0 ? pawnsPerFile[colorIndex][file - 1] : 0
                let rightCount = file < 7 ? pawnsPerFile[colorIndex][file + 1] : 0
                if leftCount == 0 && rightCount == 0 {
                    result.pawnStructure += sign * Evaluator.isolatedPawnPenalty
                }
                // Backward pawns are deliberately left out of the fast path:
                // detecting them costs a board scan per pawn, and this runs at
                // every leaf node. `PositionFeatures` reports them for coaching.

                if isPassed(square, color: piece.color, mostAdvanced: mostAdvancedPawnRank[enemyIndex], in: position) {
                    let relative = square.relativeRank(for: piece.color)
                    result.passedPawns += sign * Evaluator.passedPawnBonusByRank[relative]
                }

            case .knight, .bishop, .queen:
                result.mobility += sign * mobilityCount(for: piece, on: square, in: position) * Evaluator.mobilityWeight

            case .rook:
                result.mobility += sign * mobilityCount(for: piece, on: square, in: position) * Evaluator.mobilityWeight
                let ownPawns = pawnsPerFile[colorIndex][square.file]
                let enemyPawns = pawnsPerFile[enemyIndex][square.file]
                if ownPawns == 0 && enemyPawns == 0 {
                    result.rookActivity += sign * Evaluator.rookOpenFileBonus
                } else if ownPawns == 0 {
                    result.rookActivity += sign * Evaluator.rookSemiOpenFileBonus
                }
                if square.relativeRank(for: piece.color) == 6 {
                    result.rookActivity += sign * Evaluator.rookOnSeventhBonus
                }

            case .king:
                result.kingSafety += sign * kingSafety(for: piece.color, on: square, pawnsPerFile: pawnsPerFile, in: position, endgameWeight: endgame)
            }
        }

        for color in PieceColor.allCases where bishopCount[Int(color.rawValue)] >= 2 {
            result.bishopPair += color.sign * Evaluator.bishopPairBonus
        }

        for index in Evaluator.centerSquares {
            guard let square = Square(index: index) else { continue }
            let whiteAttackers = position.attackerCount(of: square, by: .white)
            let blackAttackers = position.attackerCount(of: square, by: .black)
            result.centerControl += (whiteAttackers - blackAttackers) * 6
        }

        result.tempo = position.sideToMove.sign * Evaluator.tempoBonus
        return result
    }

    // MARK: - Term helpers

    /// A pawn is passed when no enemy pawn can stop it on its file or either neighbour.
    func isPassed(_ square: Square, color: PieceColor, mostAdvanced enemyMostAdvanced: [Int], in position: Position) -> Bool {
        let relativeRank = square.relativeRank(for: color)
        for file in max(0, square.file - 1)...min(7, square.file + 1) {
            let enemyRelative = enemyMostAdvanced[file]
            guard enemyRelative >= 0 else { continue }
            // Enemy ranks are measured from their own side, so a pawn ahead of
            // ours has (7 - enemyRelative) > relativeRank in our frame.
            if (7 - enemyRelative) > relativeRank { return false }
        }
        return true
    }

    /// A pawn is backward when no friendly pawn can support it from behind and
    /// the square in front is covered by an enemy pawn.
    func isBackward(_ square: Square, color: PieceColor, in position: Position) -> Bool {
        let relativeRank = square.relativeRank(for: color)
        for file in [square.file - 1, square.file + 1] where file >= 0 && file < 8 {
            for rank in 0..<8 {
                guard let neighbour = Square(file: file, rank: rank),
                      let piece = position.piece(at: neighbour),
                      piece.color == color, piece.kind == .pawn else { continue }
                if neighbour.relativeRank(for: color) <= relativeRank { return false }
            }
        }
        guard let ahead = square.offset(file: 0, rank: color.pawnDirection) else { return false }
        return position.attackers(of: ahead, by: color.opponent)
            .contains { position.piece(at: $0)?.kind == .pawn }
    }

    /// Cheap mobility: how many squares this piece could move to, ignoring pins.
    func mobilityCount(for piece: Piece, on square: Square, in position: Position) -> Int {
        var count = 0
        switch piece.kind {
        case .knight:
            for offset in Position.knightOffsets {
                let index = square.index + offset
                guard Square.isValidIndex(index) else { continue }
                let target = Square(unchecked: index)
                if position.piece(at: target)?.color != piece.color { count += 1 }
            }
        case .bishop, .rook, .queen:
            let directions: [Int]
            if piece.kind == .bishop {
                directions = Position.bishopDirections
            } else if piece.kind == .rook {
                directions = Position.rookDirections
            } else {
                directions = Position.queenDirections
            }
            for direction in directions {
                var index = square.index + direction
                while Square.isValidIndex(index) {
                    let target = Square(unchecked: index)
                    if let occupant = position.piece(at: target) {
                        if occupant.color != piece.color { count += 1 }
                        break
                    }
                    count += 1
                    index += direction
                }
            }
        default:
            break
        }
        return count
    }

    /// Pawn shelter and open lines in front of the king, faded out in the endgame
    /// where the king is a fighting piece rather than a liability.
    func kingSafety(for color: PieceColor, on square: Square, pawnsPerFile: [[Int]], in position: Position, endgameWeight: Double) -> Int {
        var score = 0
        let colorIndex = Int(color.rawValue)
        let enemyIndex = 1 - colorIndex

        for file in max(0, square.file - 1)...min(7, square.file + 1) {
            let ownPawns = pawnsPerFile[colorIndex][file]
            if ownPawns == 0 {
                score -= 22
                if pawnsPerFile[enemyIndex][file] == 0 {
                    score -= 14   // Fully open file pointing at the king.
                }
            }
        }

        // A shelter pawn directly in front is worth more than one two ranks away.
        for file in max(0, square.file - 1)...min(7, square.file + 1) {
            for step in 1...2 {
                guard let shelter = Square(file: file, rank: square.rank + color.pawnDirection * step),
                      let piece = position.piece(at: shelter),
                      piece.color == color, piece.kind == .pawn else { continue }
                score += step == 1 ? 12 : 6
                break
            }
        }

        // Heavy enemy pieces make an exposed king much more dangerous.
        let enemyQueens = position.count(of: color.opponent, kind: .queen)
        if enemyQueens > 0 && score < 0 {
            score = score * 3 / 2
        }

        return Int(Double(score) * (1.0 - endgameWeight))
    }
}
