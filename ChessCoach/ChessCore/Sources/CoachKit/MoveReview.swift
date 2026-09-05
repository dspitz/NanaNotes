import Foundation
import ChessKit

public enum MoveQuality: String, Sendable, Hashable, CaseIterable {
    case brilliant
    case best
    case excellent
    case good
    case inaccuracy
    case mistake
    case blunder

    public var displayName: String {
        switch self {
        case .brilliant: return "Brilliant"
        case .best: return "Best move"
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        }
    }

    public var symbol: String {
        switch self {
        case .brilliant: return "!!"
        case .best: return "!"
        case .excellent: return ""
        case .good: return ""
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        }
    }

    public var isRegrettable: Bool {
        switch self {
        case .inaccuracy, .mistake, .blunder: return true
        default: return false
        }
    }
}

/// The verdict on one played move.
public struct MoveReview: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let move: Move
    public let san: String
    public let color: PieceColor
    public let moveNumber: Int
    public let quality: MoveQuality
    /// How much the move cost its player, in centipawns. Never negative.
    public let centipawnLoss: Int
    /// Drop in winning chances, 0...1.
    public let winProbabilityDrop: Double
    public let evaluationBefore: Evaluation
    public let evaluationAfter: Evaluation
    public let bestMoveSAN: String?
    public let bestLineSAN: String?
    public let explanation: String
    public let missedMotifs: [TacticalMotif]
    /// The move the opponent should now play to punish this one.
    public let refutationSAN: String?

    public var wasBest: Bool { return quality == .best || quality == .brilliant }
}

/// Grades played moves and explains what was missed.
public struct MoveReviewer {
    private let engine: ChessEngine
    private let evaluator: Evaluator

    public init(engine: ChessEngine = ChessEngine(), evaluator: Evaluator = Evaluator()) {
        self.engine = engine
        self.evaluator = evaluator
    }

    /// - Parameter cachedBefore: pass the analysis you already ran on the position
    ///   before the move to avoid searching it twice.
    public func review(move: Move,
                       in positionBefore: Position,
                       configuration: ChessEngine.Configuration = .analysis(depth: 6, timeLimit: 1.0, candidates: 3),
                       cachedBefore: ChessEngine.SearchResult? = nil) -> MoveReview {
        let mover = positionBefore.sideToMove
        let legal = positionBefore.legalMoves
        let san = positionBefore.san(for: move, legalMoves: legal)

        let beforeResult = cachedBefore ?? engine.search(positionBefore, configuration: configuration)
        let evaluationBefore = beforeResult.evaluation

        var positionAfter = positionBefore
        positionAfter.make(move)

        let afterConfiguration = ChessEngine.Configuration(maxDepth: configuration.maxDepth,
                                                           timeLimit: configuration.timeLimit,
                                                           multiPV: 2,
                                                           skillLevel: 20)
        let afterResult = engine.search(positionAfter, configuration: afterConfiguration)
        let evaluationAfter = afterResult.evaluation

        let phase = evaluator.gamePhase(positionBefore)
        let probabilityBefore = WinProbability.from(evaluation: evaluationBefore, phase: phase).chance(for: mover)
        let probabilityAfter = WinProbability.from(evaluation: evaluationAfter, phase: phase).chance(for: mover)
        let probabilityDrop = max(0, probabilityBefore - probabilityAfter)

        let loss = max(0, (evaluationBefore.centipawns - evaluationAfter.centipawns) * mover.sign)
        let playedBest = beforeResult.bestMove.map { $0 == move } ?? false
        let quality = grade(loss: loss,
                            probabilityDrop: probabilityDrop,
                            playedBest: playedBest,
                            move: move,
                            positionBefore: positionBefore,
                            evaluationAfter: evaluationAfter,
                            mover: mover)

        let bestLine = beforeResult.lines.first
        let bestSAN = bestLine?.firstMove.map { positionBefore.san(for: $0, legalMoves: legal) }
        let bestLineSAN = bestLine.map { positionBefore.sanLine(for: $0.moves) }
        let missed = bestLine?.firstMove.map { Tactics.motifs(createdBy: $0, in: positionBefore) } ?? []
        let refutation = afterResult.bestMove.map { positionAfter.san(for: $0) }

        let explanation = explain(quality: quality,
                                  san: san,
                                  loss: loss,
                                  bestSAN: playedBest ? nil : bestSAN,
                                  bestLineSAN: playedBest ? nil : bestLineSAN,
                                  refutationSAN: refutation,
                                  missedMotifs: playedBest ? [] : missed,
                                  positionBefore: positionBefore,
                                  positionAfter: positionAfter,
                                  mover: mover)

        return MoveReview(
            id: UUID(),
            move: move,
            san: san,
            color: mover,
            moveNumber: positionBefore.fullmoveNumber,
            quality: quality,
            centipawnLoss: loss,
            winProbabilityDrop: probabilityDrop,
            evaluationBefore: evaluationBefore,
            evaluationAfter: evaluationAfter,
            bestMoveSAN: bestSAN,
            bestLineSAN: bestLineSAN,
            explanation: explanation,
            missedMotifs: playedBest ? [] : missed,
            refutationSAN: playedBest ? nil : refutation
        )
    }

    // MARK: - Grading

    /// Grades on lost winning chances rather than raw centipawns: dropping 100cp
    /// when you are already winning by a rook barely matters, and dropping 60cp in
    /// a level position is a real mistake.
    private func grade(loss: Int,
                       probabilityDrop: Double,
                       playedBest: Bool,
                       move: Move,
                       positionBefore: Position,
                       evaluationAfter: Evaluation,
                       mover: PieceColor) -> MoveQuality {
        if playedBest && isSacrifice(move, in: positionBefore) && evaluationAfter.centipawns * mover.sign >= 0 {
            return .brilliant
        }
        if playedBest { return .best }
        switch probabilityDrop {
        case ..<0.02: return .excellent
        case 0.02..<0.06: return .good
        case 0.06..<0.12: return .inaccuracy
        case 0.12..<0.22: return .mistake
        default: return .blunder
        }
    }

    /// True when the move deliberately gives material away in the short term.
    private func isSacrifice(_ move: Move, in position: Position) -> Bool {
        let mover = position.sideToMove
        var after = position
        after.make(move)
        // Would the opponent win material by capturing on the arrival square?
        let recapture = Tactics.exchangeGain(on: move.to, initiatedBy: mover.opponent, in: after)
        return recapture >= PieceKind.knight.value - 40
    }

    // MARK: - Explanation

    private func explain(quality: MoveQuality,
                         san: String,
                         loss: Int,
                         bestSAN: String?,
                         bestLineSAN: String?,
                         refutationSAN: String?,
                         missedMotifs: [TacticalMotif],
                         positionBefore: Position,
                         positionAfter: Position,
                         mover: PieceColor) -> String {
        switch quality {
        case .brilliant:
            return "\(san) gives material back to get something bigger, and it holds up. This is the kind of move engines find and humans remember."
        case .best:
            return "\(san) is the best move here. \(bestLineSAN.map { "The line runs \($0)." } ?? "")"
        case .excellent:
            return "\(san) is fine — practically as good as the top choice."
        case .good:
            return "\(san) keeps everything under control. \(bestSAN.map { "\($0) was a touch sharper." } ?? "")"
        case .inaccuracy, .mistake, .blunder:
            var parts: [String] = []
            let cost = PositionAnalyzer.materialText(loss)
            parts.append("\(san) costs about \(cost).")
            if let refutation = refutationSAN {
                if positionAfter.isCheckmate {
                    parts.append("It allows mate.")
                } else {
                    parts.append("They can answer \(refutation).")
                }
            }
            if let motif = missedMotifs.first {
                parts.append("You missed it: \(motif.headline.lowercased()).")
            }
            if let best = bestSAN {
                parts.append("\(best) was the move\(bestLineSAN.map { ", with the line \($0)" } ?? "").")
            }
            return parts.joined(separator: " ")
        }
    }
}

/// Whole-game summary for the post-game screen.
public struct GameReview: Sendable {
    public let reviews: [MoveReview]

    public init(reviews: [MoveReview]) {
        self.reviews = reviews
    }

    public func reviews(for color: PieceColor) -> [MoveReview] {
        return reviews.filter { $0.color == color }
    }

    public func averageCentipawnLoss(for color: PieceColor) -> Int {
        let moves = reviews(for: color)
        guard !moves.isEmpty else { return 0 }
        return moves.reduce(0) { $0 + $1.centipawnLoss } / moves.count
    }

    /// A 0-100 score that behaves the way players expect: near-perfect play sits
    /// in the high nineties, and a couple of blunders pull it down hard.
    public func accuracy(for color: PieceColor) -> Int {
        let moves = reviews(for: color)
        guard !moves.isEmpty else { return 100 }
        let averageDrop = moves.reduce(0.0) { $0 + $1.winProbabilityDrop } / Double(moves.count)
        let accuracy = 100.0 * exp(-6.0 * averageDrop)
        return max(0, min(100, Int(accuracy.rounded())))
    }

    public func count(of quality: MoveQuality, for color: PieceColor) -> Int {
        return reviews(for: color).filter { $0.quality == quality }.count
    }

    /// The moments most worth revisiting: the biggest swings, worst first.
    public func turningPoints(for color: PieceColor, limit: Int = 3) -> [MoveReview] {
        return reviews(for: color)
            .filter { $0.quality.isRegrettable }
            .sorted { $0.winProbabilityDrop > $1.winProbabilityDrop }
            .prefix(limit)
            .map { $0 }
    }
}
