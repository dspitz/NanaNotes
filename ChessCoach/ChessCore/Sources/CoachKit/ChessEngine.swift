import Foundation
import ChessKit

/// Alpha-beta search with a transposition table, killer/history move ordering and
/// a quiescence search.
///
/// It is not trying to be Stockfish. It is trying to be strong enough that its
/// verdicts are trustworthy for coaching, fast enough to answer while you are
/// still looking at the board, and *legible* — every number it produces can be
/// traced back to a term in `Evaluator`.
public final class ChessEngine {
    public struct Configuration: Sendable {
        /// Hard ceiling on iterative deepening.
        public var maxDepth: Int
        /// Wall-clock budget. The search always finishes the depth it is on if it
        /// can, and otherwise returns the deepest completed iteration.
        public var timeLimit: TimeInterval
        /// How many distinct root lines to report. Above 1 the root is searched
        /// with a full window so every candidate gets a real score.
        public var multiPV: Int
        /// 0 (beginner sparring partner) to 20 (plays its best move).
        public var skillLevel: Int

        public init(maxDepth: Int = 8, timeLimit: TimeInterval = 1.2, multiPV: Int = 1, skillLevel: Int = 20) {
            self.maxDepth = maxDepth
            self.timeLimit = timeLimit
            self.multiPV = multiPV
            self.skillLevel = skillLevel
        }

        /// Analysis preset: multiple candidate moves, no deliberate weakening.
        public static func analysis(depth: Int = 7, timeLimit: TimeInterval = 1.5, candidates: Int = 4) -> Configuration {
            return Configuration(maxDepth: depth, timeLimit: timeLimit, multiPV: candidates, skillLevel: 20)
        }

        /// Opponent preset for a given rating band.
        ///
        /// A weakened opponent needs real scores for every root move so it can
        /// pick a *slightly* worse one on purpose, which means searching the root
        /// with a full window rather than alpha-beta bounds.
        public static func opponent(strength: OpponentStrength) -> Configuration {
            return Configuration(
                maxDepth: strength.searchDepth,
                timeLimit: strength.timeLimit,
                multiPV: strength.skillLevel < 20 ? 3 : 1,
                skillLevel: strength.skillLevel
            )
        }
    }

    /// A principal variation with its score.
    public struct Line: Sendable, Hashable {
        public let moves: [Move]
        /// Always White-relative, like every other evaluation in CoachKit.
        public let evaluation: Evaluation
        public let depth: Int

        public var firstMove: Move? { return moves.first }
    }

    public struct SearchResult: Sendable {
        public let lines: [Line]
        public let depth: Int
        public let nodes: Int
        public let elapsed: TimeInterval

        public var best: Line? { return lines.first }
        public var bestMove: Move? { return lines.first?.firstMove }
        public var evaluation: Evaluation { return lines.first?.evaluation ?? .equal }
    }

    // MARK: - Internals

    private static let mateValue = 30000
    private static let infinity = 100000
    private static let maximumPly = 64

    private enum Bound: UInt8 {
        case exact = 0
        case lower = 1
        case upper = 2
    }

    private struct TranspositionEntry {
        var key: UInt64 = 0
        var depth: Int16 = -1
        var bound: Bound = .exact
        var score: Int32 = 0
        var move: Move?
    }

    private let evaluator = Evaluator()
    private let tableSize = 1 << 18
    private var table: [TranspositionEntry]
    private var killers: [[Move?]]
    private var historyScores: [[Int]]
    private var searchPath: [UInt64] = []
    private var gameKeys: Set<UInt64> = []
    private var nodeCount = 0
    private var deadline: DispatchTime = .now()
    private var aborted = false
    private let cancellationLock = NSLock()
    private var cancellationRequested = false
    private var randomGenerator = SystemRandomNumberGenerator()

    public init() {
        table = Array(repeating: TranspositionEntry(), count: tableSize)
        killers = Array(repeating: [nil, nil], count: ChessEngine.maximumPly + 8)
        historyScores = Array(repeating: Array(repeating: 0, count: 128), count: 128)
    }

    /// Drops learned state. Call between games so one game's history heuristics
    /// do not colour the next.
    public func reset() {
        table = Array(repeating: TranspositionEntry(), count: tableSize)
        killers = Array(repeating: [nil, nil], count: ChessEngine.maximumPly + 8)
        historyScores = Array(repeating: Array(repeating: 0, count: 128), count: 128)
    }

    /// Asks the running search to stop as soon as it can.
    public func cancel() {
        cancellationLock.lock()
        cancellationRequested = true
        cancellationLock.unlock()
    }

    private func consumeCancellation() -> Bool {
        cancellationLock.lock()
        let value = cancellationRequested
        cancellationLock.unlock()
        return value
    }

    // MARK: - Public search

    /// - Parameter positionKeys: Zobrist keys already seen in the game, so the
    ///   search can treat a repetition as a draw instead of walking into one.
    public func search(_ position: Position,
                       configuration: Configuration = Configuration(),
                       positionKeys: [UInt64] = []) -> SearchResult {
        cancellationLock.lock()
        cancellationRequested = false
        cancellationLock.unlock()

        nodeCount = 0
        aborted = false
        gameKeys = Set(positionKeys)
        searchPath = []
        deadline = DispatchTime.now() + configuration.timeLimit

        let started = DispatchTime.now()
        var root = position
        var rootMoves = root.generateLegalMoves()
        guard !rootMoves.isEmpty else {
            // Checkmate or stalemate: there is nothing to search, only to report.
            let terminal: Evaluation
            if root.isCheck {
                let winner = root.sideToMove.opponent
                terminal = Evaluation(centipawns: winner.sign * 10000, mateInMoves: nil)
            } else {
                terminal = .equal
            }
            return SearchResult(lines: [Line(moves: [], evaluation: terminal, depth: 0)],
                                depth: 0,
                                nodes: 0,
                                elapsed: 0)
        }

        var bestLines: [Line] = []
        var completedDepth = 0
        var previousScores: [Move: Int] = [:]
        let useFullWindowAtRoot = configuration.multiPV > 1

        for depth in 1...max(1, configuration.maxDepth) {
            // Search the previous iteration's best moves first.
            rootMoves.sort { (previousScores[$0] ?? Int.min) > (previousScores[$1] ?? Int.min) }

            var iterationScores: [Move: Int] = [:]
            var iterationLines: [Line] = []
            var alpha = -ChessEngine.infinity
            var completedThisIteration = true

            for move in rootMoves {
                let undo = root.make(move)
                searchPath.append(root.zobristKey)
                var childLine: [Move] = []
                let window = useFullWindowAtRoot ? -ChessEngine.infinity : alpha
                let score = -negamax(&root,
                                     depth: depth - 1,
                                     alpha: -ChessEngine.infinity,
                                     beta: -window,
                                     ply: 1,
                                     pv: &childLine)
                searchPath.removeLast()
                root.unmake(undo)

                if aborted {
                    completedThisIteration = false
                    break
                }

                iterationScores[move] = score
                iterationLines.append(Line(moves: [move] + childLine,
                                           evaluation: evaluation(fromRelativeScore: score, sideToMove: position.sideToMove),
                                           depth: depth))
                if !useFullWindowAtRoot && score > alpha {
                    alpha = score
                }
            }

            if completedThisIteration && !iterationLines.isEmpty {
                let ordering = iterationScores
                iterationLines.sort { (ordering[$0.moves[0]] ?? Int.min) > (ordering[$1.moves[0]] ?? Int.min) }
                bestLines = iterationLines
                previousScores = iterationScores
                completedDepth = depth
            }

            if aborted || DispatchTime.now() >= deadline { break }
            if let best = bestLines.first, best.evaluation.isMate { break }
        }

        if bestLines.isEmpty {
            // The very first iteration ran out of time. Never return "no move":
            // fall back to a static pick so the caller always has something legal.
            let mover = root.sideToMove
            let scored = rootMoves.map { move -> (move: Move, score: Int) in
                (move, evaluator.staticEvaluation(root.making(move)) * mover.sign)
            }
            let fallback = scored.max { $0.score < $1.score } ?? (move: rootMoves[0], score: 0)
            bestLines = [Line(moves: [fallback.move],
                              evaluation: Evaluation(centipawns: fallback.score * mover.sign),
                              depth: 0)]
        }

        let selected = applySkill(to: bestLines, skillLevel: configuration.skillLevel)
        let keep = max(1, configuration.multiPV)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000_000.0
        return SearchResult(lines: Array(selected.prefix(keep)),
                            depth: completedDepth,
                            nodes: nodeCount,
                            elapsed: elapsed)
    }

    // MARK: - Negamax

    private func negamax(_ position: inout Position, depth: Int, alpha: Int, beta: Int, ply: Int, pv: inout [Move]) -> Int {
        pv.removeAll(keepingCapacity: true)

        nodeCount += 1
        if nodeCount & 0x7FF == 0 {
            if DispatchTime.now() >= deadline || consumeCancellation() { aborted = true }
        }
        if aborted { return 0 }

        // Draw detection before anything else.
        if ply > 0 {
            if position.halfmoveClock >= 100 { return 0 }
            if position.hasInsufficientMaterial { return 0 }
            let key = position.zobristKey
            if searchPath.dropLast().contains(key) || gameKeys.contains(key) { return 0 }
        }

        if depth <= 0 {
            return quiescence(&position, alpha: alpha, beta: beta, ply: ply)
        }

        var alpha = alpha
        let originalAlpha = alpha
        let key = position.zobristKey
        let slot = Int(key % UInt64(tableSize))
        var tableMove: Move?

        let entry = table[slot]
        if entry.key == key {
            tableMove = entry.move
            if Int(entry.depth) >= depth {
                let score = Int(entry.score)
                switch entry.bound {
                case .exact:
                    if let move = entry.move { pv = [move] }
                    return score
                case .lower:
                    if score >= beta { return score }
                case .upper:
                    if score <= alpha { return score }
                }
            }
        }

        var moves = position.generateLegalMoves()
        if moves.isEmpty {
            return position.isCheck ? -(ChessEngine.mateValue - ply) : 0
        }

        orderMoves(&moves, position: position, tableMove: tableMove, ply: ply)

        var bestScore = -ChessEngine.infinity
        var bestMove: Move?
        let inCheck = position.isCheck

        for (index, move) in moves.enumerated() {
            let undo = position.make(move)
            searchPath.append(position.zobristKey)

            // Late move reduction: quiet moves far down the ordering get a
            // shallower first look and are re-searched only if they beat alpha.
            var childPV: [Move] = []
            var score: Int
            let quiet = !move.isCapture && !move.isPromotion && !inCheck
            if depth >= 3 && index >= 4 && quiet {
                score = -negamax(&position, depth: depth - 2, alpha: -alpha - 1, beta: -alpha, ply: ply + 1, pv: &childPV)
                if score > alpha {
                    score = -negamax(&position, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, pv: &childPV)
                }
            } else {
                score = -negamax(&position, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, pv: &childPV)
            }

            searchPath.removeLast()
            position.unmake(undo)
            if aborted { return bestScore == -ChessEngine.infinity ? 0 : bestScore }

            if score > bestScore {
                bestScore = score
                bestMove = move
                if score > alpha {
                    alpha = score
                    pv = [move] + childPV
                }
            }
            if alpha >= beta {
                if quiet {
                    recordKiller(move, ply: ply)
                    historyScores[move.from.index][move.to.index] += depth * depth
                }
                break
            }
        }

        let bound: Bound
        if bestScore <= originalAlpha {
            bound = .upper
        } else if bestScore >= beta {
            bound = .lower
        } else {
            bound = .exact
        }
        if !aborted, Int(table[slot].depth) <= depth || table[slot].key != key {
            table[slot] = TranspositionEntry(key: key, depth: Int16(depth), bound: bound, score: Int32(bestScore), move: bestMove)
        }
        return bestScore
    }

    /// Plays out the captures so the evaluation is never taken in the middle of a
    /// trade — the single biggest source of nonsense advice in a naive engine.
    private func quiescence(_ position: inout Position, alpha: Int, beta: Int, ply: Int) -> Int {
        nodeCount += 1
        if nodeCount & 0x7FF == 0 {
            if DispatchTime.now() >= deadline || consumeCancellation() { aborted = true }
        }
        if aborted { return 0 }
        if ply >= ChessEngine.maximumPly { return evaluator.relativeEvaluation(position) }

        var alpha = alpha
        let standPat = evaluator.relativeEvaluation(position)
        if standPat >= beta { return standPat }
        if standPat > alpha { alpha = standPat }

        var captures = position.generateLegalMoves(capturesOnly: true)
        if captures.isEmpty { return alpha }
        orderMoves(&captures, position: position, tableMove: nil, ply: ply)

        for move in captures {
            // Delta pruning: skip captures that cannot rescue a lost position.
            if let victim = capturedPiece(for: move, in: position) {
                if standPat + victim.kind.value + 200 < alpha && !move.isPromotion { continue }
            }
            let undo = position.make(move)
            let score = -quiescence(&position, alpha: -beta, beta: -alpha, ply: ply + 1)
            position.unmake(undo)
            if aborted { return alpha }
            if score >= beta { return score }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    // MARK: - Move ordering

    private func orderMoves(_ moves: inout [Move], position: Position, tableMove: Move?, ply: Int) {
        let killerA = killers[min(ply, killers.count - 1)][0]
        let killerB = killers[min(ply, killers.count - 1)][1]
        // Score once per move, then sort: the comparator runs O(n log n) times.
        var scored = moves.map { move in
            (move: move, score: moveScore(move, position: position, tableMove: tableMove, killerA: killerA, killerB: killerB))
        }
        scored.sort { $0.score > $1.score }
        moves = scored.map { $0.move }
    }

    private func moveScore(_ move: Move, position: Position, tableMove: Move?, killerA: Move?, killerB: Move?) -> Int {
        if let tableMove = tableMove, move == tableMove { return 1_000_000 }
        if move.isCapture, let victim = capturedPiece(for: move, in: position) {
            let attackerValue = position.piece(at: move.from)?.kind.value ?? 0
            // Most Valuable Victim / Least Valuable Attacker.
            return 500_000 + victim.kind.value * 16 - attackerValue
        }
        if let promotion = move.promotion { return 400_000 + promotion.value }
        if let killerA = killerA, move == killerA { return 300_000 }
        if let killerB = killerB, move == killerB { return 299_000 }
        return historyScores[move.from.index][move.to.index]
    }

    private func recordKiller(_ move: Move, ply: Int) {
        let index = min(ply, killers.count - 1)
        if killers[index][0] != move {
            killers[index][1] = killers[index][0]
            killers[index][0] = move
        }
    }

    private func capturedPiece(for move: Move, in position: Position) -> Piece? {
        if move.isEnPassant {
            return Piece(position.sideToMove.opponent, .pawn)
        }
        return position.piece(at: move.to)
    }

    // MARK: - Skill

    /// Weakens play on purpose by sometimes choosing a slightly worse move.
    /// A coaching app needs an opponent you can actually beat.
    private func applySkill(to lines: [Line], skillLevel: Int) -> [Line] {
        guard skillLevel < 20, lines.count > 1 else { return lines }
        // At skill 0 the engine tolerates roughly a 250cp drop; at 19, about 10cp.
        let tolerance = max(10, (20 - skillLevel) * 13)
        guard let bestScore = lines.first?.evaluation.centipawns else { return lines }
        let acceptable = lines.filter { abs($0.evaluation.centipawns - bestScore) <= tolerance && !$0.evaluation.isMate }
        guard acceptable.count > 1, let choice = acceptable.randomElement(using: &randomGenerator) else { return lines }
        var reordered = lines
        if let index = reordered.firstIndex(where: { $0.moves == choice.moves }) {
            reordered.remove(at: index)
            reordered.insert(choice, at: 0)
        }
        return reordered
    }

    // MARK: - Score conversion

    private func evaluation(fromRelativeScore score: Int, sideToMove: PieceColor) -> Evaluation {
        let whiteRelative = score * sideToMove.sign
        if abs(score) >= ChessEngine.mateValue - ChessEngine.maximumPly * 2 {
            let pliesToMate = ChessEngine.mateValue - abs(score)
            let movesToMate = max(1, (pliesToMate + 1) / 2)
            let mateSign = whiteRelative > 0 ? 1 : -1
            return Evaluation(centipawns: mateSign * 10000, mateInMoves: mateSign * movesToMate)
        }
        return Evaluation(centipawns: whiteRelative)
    }
}
