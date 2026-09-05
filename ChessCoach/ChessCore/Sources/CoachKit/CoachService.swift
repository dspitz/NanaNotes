import Foundation
import ChessKit

/// The app-facing front door to CoachKit.
///
/// All engine work runs on one serial background queue, so the UI thread never
/// blocks and two requests can never trample each other's search state.
/// `cancelCurrentWork()` is safe to call from anywhere, including while a search
/// is running.
public final class CoachService {
    private let queue = DispatchQueue(label: "com.chesscoach.engine", qos: .userInitiated)
    private let engine: ChessEngine
    private let evaluator: Evaluator
    private let analyzer: PositionAnalyzer
    private let reviewer: MoveReviewer

    public init() {
        let engine = ChessEngine()
        let evaluator = Evaluator()
        self.engine = engine
        self.evaluator = evaluator
        self.analyzer = PositionAnalyzer(engine: engine, evaluator: evaluator)
        self.reviewer = MoveReviewer(engine: engine, evaluator: evaluator)
    }

    /// Interrupts whatever the engine is doing. The in-flight call still returns,
    /// with the best result it had reached.
    public func cancelCurrentWork() {
        engine.cancel()
    }

    /// Clears search state. Call when starting a new game.
    public func resetForNewGame() {
        queue.async { [engine] in
            engine.reset()
        }
    }

    // MARK: - Analysis

    public func analyze(_ position: Position,
                        perspective: PieceColor,
                        configuration: ChessEngine.Configuration = .analysis(),
                        positionKeys: [UInt64] = []) async -> PositionReport {
        return await withCheckedContinuation { continuation in
            queue.async { [analyzer] in
                let report = analyzer.analyze(position,
                                              perspective: perspective,
                                              configuration: configuration,
                                              positionKeys: positionKeys)
                continuation.resume(returning: report)
            }
        }
    }

    /// A quick, shallow read for the evaluation bar while you are still thinking.
    public func quickEvaluation(_ position: Position) async -> Evaluation {
        return await withCheckedContinuation { continuation in
            queue.async { [engine] in
                let result = engine.search(position, configuration: ChessEngine.Configuration(maxDepth: 4, timeLimit: 0.25, multiPV: 1))
                continuation.resume(returning: result.evaluation)
            }
        }
    }

    // MARK: - Opponent

    public func opponentMove(for position: Position,
                             strength: OpponentStrength,
                             positionKeys: [UInt64] = []) async -> Move? {
        return await withCheckedContinuation { continuation in
            queue.async { [engine] in
                let result = engine.search(position,
                                           configuration: .opponent(strength: strength),
                                           positionKeys: positionKeys)
                continuation.resume(returning: result.bestMove)
            }
        }
    }

    // MARK: - Review

    public func review(move: Move,
                       in position: Position,
                       configuration: ChessEngine.Configuration = .analysis(depth: 6, timeLimit: 0.8, candidates: 3)) async -> MoveReview {
        return await withCheckedContinuation { continuation in
            queue.async { [reviewer] in
                let review = reviewer.review(move: move, in: position, configuration: configuration)
                continuation.resume(returning: review)
            }
        }
    }

    /// Reviews a finished game one move at a time, reporting progress as it goes
    /// so the UI can show a bar instead of a spinner.
    public func reviewGame(_ game: Game,
                           configuration: ChessEngine.Configuration = .analysis(depth: 6, timeLimit: 0.5, candidates: 2),
                           progress: (@Sendable (Double) -> Void)? = nil) async -> GameReview {
        return await withCheckedContinuation { continuation in
            queue.async { [reviewer] in
                var reviews: [MoveReview] = []
                let total = max(1, game.history.count)
                for (index, record) in game.history.enumerated() {
                    let review = reviewer.review(move: record.move, in: record.positionBefore, configuration: configuration)
                    reviews.append(review)
                    progress?(Double(index + 1) / Double(total))
                }
                continuation.resume(returning: GameReview(reviews: reviews))
            }
        }
    }

    // MARK: - Coaching text

    public func commentary(for report: PositionReport, level: CoachLevel) -> CoachCommentary {
        return CoachNarrator(level: level).commentary(for: report)
    }
}
