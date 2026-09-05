import Foundation
import ChessKit

/// A move the engine considered, with the reasoning attached.
public struct CandidateMove: Sendable, Hashable, Identifiable {
    public let move: Move
    public let san: String
    /// White-relative, like every evaluation in CoachKit.
    public let evaluation: Evaluation
    public let line: [Move]
    public let lineSAN: String
    public let motifs: [TacticalMotif]
    public let rationale: String
    /// How much worse than the best move, in centipawns, for the mover.
    public let centipawnsBehindBest: Int

    public var id: String { return move.uci }
    public var isBest: Bool { return centipawnsBehindBest == 0 }
}

/// Something the opponent is threatening to do.
public struct ThreatItem: Sendable, Hashable, Identifiable {
    public let san: String
    public let summary: String
    public let detail: String
    /// Centipawns the coached player stands to lose if this is ignored.
    public let severity: Int
    public let squares: [Square]
    public let motifs: [TacticalMotif]

    public var id: String { return san + summary }

    public var isCritical: Bool { return severity >= 200 }
}

/// A durable, non-tactical feature of the position worth naming.
public struct StrategicTheme: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case material
        case kingSafety
        case pawnStructure
        case pieceActivity
        case openFile
        case space
        case bishopPair
        case passedPawn
        case development
        case initiative
    }

    public let kind: Kind
    /// Which side the theme favours, or nil when it is a shared feature.
    public let favours: PieceColor?
    public let title: String
    public let detail: String
    public let importance: Int
    public let squares: [Square]

    public var id: String { return kind.rawValue + title }
}

/// A concrete thing to try to do over the next several moves.
public struct PlanIdea: Sendable, Hashable, Identifiable {
    public let title: String
    public let detail: String
    public let priority: Int
    public let squares: [Square]

    public var id: String { return title }
}

/// Everything the coach knows about one position.
public struct PositionReport: Sendable {
    public let position: Position
    /// The player being coached. All "you"/"they" language is relative to this.
    public let perspective: PieceColor
    public let phase: GamePhase
    public let evaluation: Evaluation
    public let winProbability: WinProbability
    public let breakdown: EvaluationBreakdown
    public let features: PositionFeatures
    /// Positive means the coached player is up material, in centipawns.
    public let materialBalance: Int
    public let candidateMoves: [CandidateMove]
    public let opponentThreats: [ThreatItem]
    public let yourLoosePieces: [HangingPiece]
    public let theirLoosePieces: [HangingPiece]
    public let themes: [StrategicTheme]
    public let yourPlans: [PlanIdea]
    public let theirPlans: [PlanIdea]
    public let searchDepth: Int
    public let nodes: Int

    public var isYourMove: Bool { return position.sideToMove == perspective }
    public var bestMove: CandidateMove? { return candidateMoves.first }
    public var evaluationForYou: Evaluation { return evaluation.advantage(for: perspective) }
}

/// Turns a position into a `PositionReport`: search for the numbers, static
/// inspection for the reasons, and heuristics for the plans.
public struct PositionAnalyzer {
    private let engine: ChessEngine
    private let evaluator: Evaluator

    public init(engine: ChessEngine = ChessEngine(), evaluator: Evaluator = Evaluator()) {
        self.engine = engine
        self.evaluator = evaluator
    }

    public func analyze(_ position: Position,
                        perspective: PieceColor,
                        configuration: ChessEngine.Configuration = .analysis(),
                        positionKeys: [UInt64] = []) -> PositionReport {
        let features = PositionFeatures.analyze(position, evaluator: evaluator)
        let breakdown = evaluator.breakdown(position)
        let phase = features.phase

        let result = engine.search(position, configuration: configuration, positionKeys: positionKeys)
        let evaluation = result.evaluation
        let candidates = buildCandidates(from: result, in: position)

        let yourLoose = Tactics.hangingPieces(for: perspective, in: position)
        let theirLoose = Tactics.hangingPieces(for: perspective.opponent, in: position)

        let threats = detectThreats(in: position,
                                    perspective: perspective,
                                    currentEvaluation: evaluation,
                                    configuration: configuration)

        let themes = buildThemes(position: position, features: features, breakdown: breakdown, phase: phase)
        let yourPlans = buildPlans(for: perspective, position: position, features: features, phase: phase, evaluation: evaluation)
        let theirPlans = buildPlans(for: perspective.opponent, position: position, features: features, phase: phase, evaluation: evaluation)

        return PositionReport(
            position: position,
            perspective: perspective,
            phase: phase,
            evaluation: evaluation,
            winProbability: WinProbability.from(evaluation: evaluation, phase: phase),
            breakdown: breakdown,
            features: features,
            materialBalance: (features.side(perspective).material - features.side(perspective.opponent).material),
            candidateMoves: candidates,
            opponentThreats: threats,
            yourLoosePieces: yourLoose,
            theirLoosePieces: theirLoose,
            themes: themes,
            yourPlans: yourPlans,
            theirPlans: theirPlans,
            searchDepth: result.depth,
            nodes: result.nodes
        )
    }

    // MARK: - Candidates

    private func buildCandidates(from result: ChessEngine.SearchResult, in position: Position) -> [CandidateMove] {
        guard let best = result.lines.first else { return [] }
        let mover = position.sideToMove
        let bestScore = best.evaluation.centipawns * mover.sign
        let legal = position.legalMoves

        return result.lines.compactMap { line in
            guard let move = line.moves.first else { return nil }
            let san = position.san(for: move, legalMoves: legal)
            let motifs = Tactics.motifs(createdBy: move, in: position)
            let score = line.evaluation.centipawns * mover.sign
            let behind = max(0, bestScore - score)
            return CandidateMove(
                move: move,
                san: san,
                evaluation: line.evaluation,
                line: line.moves,
                lineSAN: position.sanLine(for: line.moves),
                motifs: motifs,
                rationale: rationale(for: move, san: san, motifs: motifs, in: position),
                centipawnsBehindBest: behind
            )
        }
    }

    /// One sentence on why a move is worth playing, built from what it does on
    /// the board rather than from the score alone.
    private func rationale(for move: Move, san: String, motifs: [TacticalMotif], in position: Position) -> String {
        if let motif = motifs.first {
            return motif.headline + "."
        }
        var after = position
        after.make(move)
        if after.isCheckmate { return "Checkmate." }
        if after.isCheck { return "Checks the king and gains time." }

        let mover = position.piece(at: move.from)
        if move.isCastle {
            return "Tucks the king away and connects the rooks."
        }
        if move.isPromotion, let promotion = move.promotion {
            return "Promotes to a \(promotion.name)."
        }
        if move.isCapture, let victim = position.piece(at: move.to) {
            let gain = Tactics.exchangeGain(on: move.to, initiatedBy: position.sideToMove, in: position)
            if gain > 0 { return "Wins material by taking the \(victim.kind.name)." }
            return "Trades off the \(victim.kind.name)."
        }
        if let mover = mover {
            let before = evaluator.mobilityCount(for: mover, on: move.from, in: position)
            let afterMobility = evaluator.mobilityCount(for: mover, on: move.to, in: after)
            if afterMobility > before + 2 {
                return "Improves the \(mover.kind.name), which gets \(afterMobility - before) more squares."
            }
            if mover.kind == .pawn {
                return "Gains space and fixes the pawn structure."
            }
            if mover.kind == .rook {
                return "Puts the rook on a more useful file."
            }
            return "A solid developing move for the \(mover.kind.name)."
        }
        return "Keeps the position under control."
    }

    // MARK: - Threats

    /// What does the opponent do if you pass? That, minus what the position is
    /// worth now, is exactly the set of things you have to answer.
    private func detectThreats(in position: Position,
                               perspective: PieceColor,
                               currentEvaluation: Evaluation,
                               configuration: ChessEngine.Configuration) -> [ThreatItem] {
        guard position.sideToMove == perspective else {
            // It is already the opponent's move: their best moves *are* the threats.
            let result = engine.search(position, configuration: configuration)
            return result.lines.prefix(2).compactMap { line in
                threatItem(from: line, in: position, perspective: perspective, baseline: currentEvaluation)
            }
        }
        guard !position.isCheck else {
            return [ThreatItem(san: "",
                               summary: "You are in check",
                               detail: "Deal with the check first: move the king, block the line, or capture the checking piece.",
                               severity: 400,
                               squares: position.kingSquare(of: perspective).map { [$0] } ?? [],
                               motifs: [])]
        }

        var passed = position
        _ = passed.makeNullMove()
        guard !passed.legalMoves.isEmpty else { return [] }

        var threatConfiguration = configuration
        threatConfiguration.maxDepth = max(2, configuration.maxDepth - 2)
        threatConfiguration.timeLimit = configuration.timeLimit * 0.6
        threatConfiguration.multiPV = 2
        let result = engine.search(passed, configuration: threatConfiguration)

        return result.lines.prefix(2).compactMap { line in
            threatItem(from: line, in: passed, perspective: perspective, baseline: currentEvaluation)
        }
        .filter { $0.severity >= 60 }
    }

    private func threatItem(from line: ChessEngine.Line,
                            in position: Position,
                            perspective: PieceColor,
                            baseline: Evaluation) -> ThreatItem? {
        guard let move = line.moves.first else { return nil }
        let san = position.san(for: move)
        let motifs = Tactics.motifs(createdBy: move, in: position)
        let severity = (baseline.centipawns - line.evaluation.centipawns) * perspective.sign

        var summary: String
        var detail: String
        var after = position
        after.make(move)

        if after.isCheckmate {
            summary = "\(san) is mate"
            detail = "If you do nothing, \(san) ends the game."
        } else if let motif = motifs.first {
            summary = motif.headline
            detail = "They are ready to play \(san). \(motif.headline)."
        } else if move.isCapture, let victim = position.piece(at: move.to) {
            summary = "\(san) wins the \(victim.kind.name) on \(move.to.name)"
            detail = "\(san) takes the \(victim.kind.name) and you cannot recapture favourably."
        } else if after.isCheck {
            summary = "\(san) comes with check"
            detail = "\(san) checks your king and gains time for their attack."
        } else {
            summary = "\(san) improves their position"
            detail = "Their plan runs through \(san)."
        }

        var squares: [Square] = [move.from, move.to]
        for motif in motifs {
            switch motif {
            case .fork(_, _, let targets): squares.append(contentsOf: targets)
            case .pin(let pinned, _, let against): squares.append(contentsOf: [pinned, against])
            case .skewer(let front, _, let behind): squares.append(contentsOf: [front, behind])
            case .discoveredAttack(_, let target): squares.append(target)
            case .hangingPiece(let square, _): squares.append(square)
            default: break
            }
        }

        return ThreatItem(san: san,
                          summary: summary,
                          detail: detail,
                          severity: max(0, severity),
                          squares: Array(Set(squares)),
                          motifs: motifs)
    }

    // MARK: - Themes

    private func buildThemes(position: Position, features: PositionFeatures, breakdown: EvaluationBreakdown, phase: GamePhase) -> [StrategicTheme] {
        var themes: [StrategicTheme] = []

        let materialDifference = features.white.material - features.black.material
        if abs(materialDifference) >= 100 {
            let leader: PieceColor = materialDifference > 0 ? .white : .black
            themes.append(StrategicTheme(
                kind: .material,
                favours: leader,
                title: "Material: \(leader.name) is up \(Self.materialText(abs(materialDifference)))",
                detail: "Trading pieces (not pawns) favours the side that is ahead.",
                importance: min(100, abs(materialDifference) / 10),
                squares: []
            ))
        }

        if abs(breakdown.kingSafety) >= 25 {
            let safer: PieceColor = breakdown.kingSafety > 0 ? .white : .black
            let exposed = safer.opponent
            let kingSquare = features.side(exposed).kingSquare
            themes.append(StrategicTheme(
                kind: .kingSafety,
                favours: safer,
                title: "\(exposed.name)'s king is the loose one",
                detail: features.side(exposed).kingIsExposed
                    ? "\(exposed.name)'s king has almost no pawn cover, so lines opened near it are dangerous."
                    : "\(exposed.name)'s king is a little draughty; heavy pieces coming to that side matter.",
                importance: min(100, abs(breakdown.kingSafety) / 2),
                squares: kingSquare.map { [$0] } ?? []
            ))
        }

        for color in PieceColor.allCases {
            let side = features.side(color)
            let weaknesses = side.isolatedPawns + side.backwardPawns + side.doubledPawns
            if weaknesses.count >= 2 {
                themes.append(StrategicTheme(
                    kind: .pawnStructure,
                    favours: color.opponent,
                    title: "\(color.name) has weak pawns on \(weaknesses.prefix(3).map { $0.name }.joined(separator: ", "))",
                    detail: "Fixed pawn weaknesses are permanent targets: pile up on them and \(color.name) has to defend passively.",
                    importance: 40 + weaknesses.count * 5,
                    squares: weaknesses
                ))
            }
            if !side.passedPawns.isEmpty {
                themes.append(StrategicTheme(
                    kind: .passedPawn,
                    favours: color,
                    title: "\(color.name) has a passed pawn on \(side.passedPawns.map { $0.name }.joined(separator: ", "))",
                    detail: phase == .endgame
                        ? "In the endgame a passed pawn is often the whole game. Push it, and put a rook behind it."
                        : "Passed pawns grow in value as pieces come off. Keep it defended and think about trading down.",
                    importance: phase == .endgame ? 80 : 45,
                    squares: side.passedPawns
                ))
            }
            if !side.rooksOnOpenFiles.isEmpty {
                themes.append(StrategicTheme(
                    kind: .openFile,
                    favours: color,
                    title: "\(color.name) owns an open file",
                    detail: "Rooks on open files eventually reach the seventh rank. Double up if you can.",
                    importance: 35,
                    squares: side.rooksOnOpenFiles
                ))
            }
            if !side.outposts.isEmpty {
                themes.append(StrategicTheme(
                    kind: .pieceActivity,
                    favours: color,
                    title: "\(color.name) has an outpost on \(side.outposts.map { $0.name }.joined(separator: ", "))",
                    detail: "A knight on a square no pawn can attack is worth more than the material count suggests.",
                    importance: 40,
                    squares: side.outposts
                ))
            }
            if side.hasBishopPair && !features.side(color.opponent).hasBishopPair {
                themes.append(StrategicTheme(
                    kind: .bishopPair,
                    favours: color,
                    title: "\(color.name) has the bishop pair",
                    detail: "Open the position and keep both bishops: they get stronger as pawns disappear.",
                    importance: 30,
                    squares: []
                ))
            }
            if phase == .opening && side.undevelopedMinorPieces.count >= 2 {
                themes.append(StrategicTheme(
                    kind: .development,
                    favours: color.opponent,
                    title: "\(color.name) still has \(side.undevelopedMinorPieces.count) pieces at home",
                    detail: "Development is a race. Every move a piece spends on its starting square is a move given away.",
                    importance: 50,
                    squares: side.undevelopedMinorPieces
                ))
            }
        }

        let spaceDifference = features.white.spaceCount - features.black.spaceCount
        if abs(spaceDifference) >= 2 {
            let leader: PieceColor = spaceDifference > 0 ? .white : .black
            themes.append(StrategicTheme(
                kind: .space,
                favours: leader,
                title: "\(leader.name) has more space",
                detail: "The side with more space should avoid trades and keep the opponent cramped.",
                importance: 25 + abs(spaceDifference) * 3,
                squares: []
            ))
        }

        return themes.sorted { $0.importance > $1.importance }
    }

    static func materialText(_ centipawns: Int) -> String {
        let pawns = Double(centipawns) / 100.0
        if abs(pawns - pawns.rounded()) < 0.05 {
            let whole = Int(pawns.rounded())
            return whole == 1 ? "a pawn" : "\(whole) pawns"
        }
        return String(format: "%.1f pawns", pawns)
    }

    // MARK: - Plans

    private func buildPlans(for color: PieceColor,
                            position: Position,
                            features: PositionFeatures,
                            phase: GamePhase,
                            evaluation: Evaluation) -> [PlanIdea] {
        var plans: [PlanIdea] = []
        let side = features.side(color)
        let enemy = features.side(color.opponent)
        let relativeScore = evaluation.centipawns * color.sign

        switch phase {
        case .opening:
            if !side.undevelopedMinorPieces.isEmpty {
                plans.append(PlanIdea(
                    title: "Finish developing",
                    detail: "Bring out the \(side.undevelopedMinorPieces.map { position.piece(at: $0)?.kind.name ?? "piece" }.joined(separator: " and ")) before starting anything sharp.",
                    priority: 90,
                    squares: side.undevelopedMinorPieces
                ))
            }
            if !side.hasCastled {
                plans.append(PlanIdea(
                    title: "Castle",
                    detail: "Get the king off the centre file before the position opens up.",
                    priority: 85,
                    squares: side.kingSquare.map { [$0] } ?? []
                ))
            }
            plans.append(PlanIdea(
                title: "Fight for the centre",
                detail: "Aim a pawn or a piece at d4/e4/d5/e5. Central control decides where the pieces belong later.",
                priority: 60,
                squares: ["d4", "e4", "d5", "e5"].compactMap { Square(algebraic: $0) }
            ))

        case .middlegame:
            if enemy.kingIsExposed {
                plans.append(PlanIdea(
                    title: "Attack the king",
                    detail: "Their king has thin cover. Bring a third attacker towards it and open a line with a pawn.",
                    priority: 88,
                    squares: enemy.kingSquare.map { [$0] } ?? []
                ))
            }
            let enemyWeaknesses = enemy.isolatedPawns + enemy.backwardPawns
            if !enemyWeaknesses.isEmpty {
                plans.append(PlanIdea(
                    title: "Target the weak pawns",
                    detail: "Pile up on \(enemyWeaknesses.prefix(2).map { $0.name }.joined(separator: " and ")). They cannot be defended by other pawns.",
                    priority: 75,
                    squares: enemyWeaknesses
                ))
            }
            if !features.fullyOpenFiles.isEmpty && side.rooksOnOpenFiles.isEmpty {
                let fileNames = features.fullyOpenFiles.map { String(Character(UnicodeScalar(UInt8(97 + $0)))) }
                plans.append(PlanIdea(
                    title: "Claim the open file",
                    detail: "The \(fileNames.joined(separator: "- and ")) file is open. Whoever puts a rook there first usually keeps it.",
                    priority: 70,
                    squares: []
                ))
            }
            if let worst = side.leastActivePiece, worst.mobility <= 3 {
                plans.append(PlanIdea(
                    title: "Improve your worst piece",
                    detail: "The \(worst.piece.kind.name) on \(worst.square.name) has only \(worst.mobility) squares. Find it a better home before anything else.",
                    priority: 65,
                    squares: [worst.square]
                ))
            }
            if relativeScore >= 150 {
                plans.append(PlanIdea(
                    title: "Trade pieces, not pawns",
                    detail: "You are up material. Every pair of pieces that comes off makes your advantage bigger.",
                    priority: 60,
                    squares: []
                ))
            } else if relativeScore <= -150 {
                plans.append(PlanIdea(
                    title: "Keep pieces on and complicate",
                    detail: "You are worse, so simplifying only helps them. Look for the sharpest move that keeps tension.",
                    priority: 60,
                    squares: []
                ))
            }

        case .endgame:
            if let king = side.kingSquare, king.distanceFromCenter >= 2 {
                plans.append(PlanIdea(
                    title: "Activate the king",
                    detail: "In the endgame the king is a strong piece. March it towards the centre or the pawns.",
                    priority: 85,
                    squares: [king]
                ))
            }
            if !side.passedPawns.isEmpty {
                plans.append(PlanIdea(
                    title: "Push the passed pawn",
                    detail: "Escort \(side.passedPawns.map { $0.name }.joined(separator: " and ")) forward. A rook belongs behind it.",
                    priority: 90,
                    squares: side.passedPawns
                ))
            }
            if !enemy.passedPawns.isEmpty {
                plans.append(PlanIdea(
                    title: "Blockade their passer",
                    detail: "Put a piece squarely in front of \(enemy.passedPawns.map { $0.name }.joined(separator: " and ")) so it cannot advance.",
                    priority: 82,
                    squares: enemy.passedPawns
                ))
            }
            plans.append(PlanIdea(
                title: "Create a passed pawn",
                detail: "Look for the pawn majority you can mobilise. Push the candidate pawn — the one with no enemy pawn in front — first.",
                priority: 55,
                squares: []
            ))
        }

        return plans.sorted { $0.priority > $1.priority }
    }
}
