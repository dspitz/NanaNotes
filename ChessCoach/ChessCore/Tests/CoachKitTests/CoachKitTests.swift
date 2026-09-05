import XCTest
import ChessKit
@testable import CoachKit

final class EvaluatorTests: XCTestCase {
    func testStartingPositionIsRoughlyBalanced() {
        let breakdown = Evaluator().breakdown(.standard)
        // Only the tempo bonus should separate the sides at move one.
        XCTAssertEqual(breakdown.material, 0)
        XCTAssertEqual(breakdown.placement, 0)
        XCTAssertLessThan(abs(breakdown.total), 40)
    }

    func testMaterialDominatesEvaluation() {
        // White is a whole queen up.
        let position = Position(fen: "4k3/8/8/8/8/8/8/3QK3 w - - 0 1")!
        XCTAssertGreaterThan(Evaluator().staticEvaluation(position), 700)
    }

    func testPhaseDetection() {
        let evaluator = Evaluator()
        XCTAssertEqual(evaluator.gamePhase(.standard), .opening)
        let endgame = Position(fen: "8/5k2/8/8/8/8/3K4/6R1 w - - 0 40")!
        XCTAssertEqual(evaluator.gamePhase(endgame), .endgame)
    }

    func testPassedPawnIsRewarded() {
        let evaluator = Evaluator()
        let passed = Position(fen: "7k/8/8/3P4/8/8/8/7K w - - 0 1")!
        let blocked = Position(fen: "7k/3p4/8/3P4/8/8/8/7K w - - 0 1")!
        XCTAssertGreaterThan(evaluator.breakdown(passed).passedPawns, evaluator.breakdown(blocked).passedPawns)
    }
}

final class WinProbabilityTests: XCTestCase {
    func testLevelPositionIsSymmetrical() {
        let probability = WinProbability.from(evaluation: .equal)
        XCTAssertEqual(probability.white, probability.black, accuracy: 0.001)
        XCTAssertGreaterThan(probability.draw, 0.2)
    }

    func testProbabilitiesSumToOne() {
        for centipawns in [-900, -250, -40, 0, 40, 250, 900] {
            let probability = WinProbability.from(evaluation: Evaluation(centipawns: centipawns))
            XCTAssertEqual(probability.white + probability.draw + probability.black, 1.0, accuracy: 0.0001)
        }
    }

    func testAdvantageIncreasesWinningChances() {
        let level = WinProbability.from(evaluation: .equal).chance(for: .white)
        let ahead = WinProbability.from(evaluation: Evaluation(centipawns: 300)).chance(for: .white)
        XCTAssertGreaterThan(ahead, level)
    }

    func testForcedMateIsCertain() {
        let probability = WinProbability.from(evaluation: Evaluation(centipawns: 10000, mateInMoves: 3))
        XCTAssertEqual(probability.white, 1.0, accuracy: 0.0001)
    }
}

final class TacticsTests: XCTestCase {
    func testHangingPieceIsFound() {
        // The black knight on e5 is attacked by a pawn and defended by nothing.
        let position = Position(fen: "4k3/8/8/4n3/3P4/8/8/4K3 w - - 0 1")!
        let hanging = Tactics.hangingPieces(for: .black, in: position)
        XCTAssertEqual(hanging.first?.square, Square(algebraic: "e5"))
        XCTAssertTrue(hanging.first?.isUndefended == true)
        XCTAssertGreaterThan(hanging.first?.materialAtRisk ?? 0, 200)
    }

    func testAdequatelyDefendedPieceIsNotHanging() {
        // The knight on e5 is defended by the f6 pawn and attacked only by a
        // bishop, so Bxe5 fxe5 loses material rather than winning it.
        let position = Position(fen: "4k3/8/5p2/4n3/8/2B5/8/4K3 w - - 0 1")!
        XCTAssertTrue(Tactics.hangingPieces(for: .black, in: position).isEmpty)
        XCTAssertEqual(Tactics.exchangeGain(on: Square(algebraic: "e5")!, initiatedBy: .white, in: position), 0)
    }

    func testExchangeGainAccountsForRecaptures() {
        // Pawn takes knight, pawn recaptures: 320 back for 100 is still a win.
        let position = Position(fen: "4k3/8/5p2/4n3/3P4/8/8/4K3 w - - 0 1")!
        let square = Square(algebraic: "e5")!
        XCTAssertEqual(Tactics.exchangeGain(on: square, initiatedBy: .white, in: position), 220)
    }

    func testPinIsDetected() {
        // The white rook on e1 pins the black knight on e5 against the king on e8.
        let position = Position(fen: "4k3/8/8/4n3/8/8/8/4RK2 w - - 0 1")!
        let motifs = Tactics.alignmentMotifs(for: .white, in: position)
        let pins = motifs.compactMap { motif -> Square? in
            if case .pin(let pinned, _, _) = motif { return pinned }
            return nil
        }
        XCTAssertEqual(pins, [Square(algebraic: "e5")])
    }

    func testBackRankWeakness() {
        let weak = Position(fen: "6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1")!
        XCTAssertTrue(Tactics.hasBackRankWeakness(for: .black, in: weak))
        let safe = Position(fen: "6k1/5pp1/7p/8/8/8/8/4R1K1 w - - 0 1")!
        XCTAssertFalse(Tactics.hasBackRankWeakness(for: .black, in: safe))
    }
}

final class ChessEngineTests: XCTestCase {
    func testFindsMateInOne() {
        // Back-rank mate: Re8#.
        let position = Position(fen: "6k1/5ppp/8/8/8/8/8/4R1K1 w - - 0 1")!
        let result = ChessEngine().search(position, configuration: ChessEngine.Configuration(maxDepth: 3, timeLimit: 3.0))
        XCTAssertEqual(result.bestMove.map { position.san(for: $0) }, "Re8#")
        XCTAssertEqual(result.evaluation.mateInMoves, 1)
    }

    func testTakesFreeMaterial() {
        // The black queen on d5 is undefended and White's knight can take it.
        let position = Position(fen: "4k3/8/8/3q4/8/4N3/8/4K3 w - - 0 1")!
        let result = ChessEngine().search(position, configuration: ChessEngine.Configuration(maxDepth: 4, timeLimit: 3.0))
        XCTAssertEqual(result.bestMove?.to, Square(algebraic: "d5"))
    }

    func testDoesNotHangItsQueen() {
        // Qd5 would drop the queen to exd5. The engine must find something else.
        let position = Position(fen: "4k3/8/4p3/8/8/8/8/3QK3 w - - 0 1")!
        let result = ChessEngine().search(position, configuration: ChessEngine.Configuration(maxDepth: 4, timeLimit: 3.0))
        XCTAssertNotEqual(result.bestMove?.to, Square(algebraic: "d5"))
    }

    func testReportsMultiplePrincipalVariations() {
        let result = ChessEngine().search(.standard, configuration: .analysis(depth: 4, timeLimit: 4.0, candidates: 4))
        XCTAssertEqual(result.lines.count, 4)
        // Best first: scores must be non-increasing from White's point of view.
        let scores = result.lines.map { $0.evaluation.centipawns }
        XCTAssertEqual(scores, scores.sorted(by: >))
    }
}

final class AnalysisTests: XCTestCase {
    private let configuration = ChessEngine.Configuration(maxDepth: 4, timeLimit: 2.0, multiPV: 3)

    func testReportDescribesOpeningPosition() {
        let report = PositionAnalyzer().analyze(.standard, perspective: .white, configuration: configuration)
        XCTAssertEqual(report.phase, .opening)
        XCTAssertTrue(report.isYourMove)
        XCTAssertFalse(report.candidateMoves.isEmpty)
        XCTAssertEqual(report.candidateMoves.first?.centipawnsBehindBest, 0)
        XCTAssertTrue(report.yourPlans.contains { $0.title.contains("develop") || $0.title.contains("Castle") || $0.title.contains("centre") })
    }

    func testWarnsAboutAThreatWhenItIsYourMove() {
        // It is White's move, but Black is threatening to take the rook on h1.
        let position = Position(fen: "4k3/8/8/8/8/8/6q1/4K2R w - - 0 1")!
        let report = PositionAnalyzer().analyze(position, perspective: .white, configuration: configuration)
        XCTAssertTrue(report.isYourMove)
        XCTAssertFalse(report.opponentThreats.isEmpty)
        XCTAssertGreaterThan(report.opponentThreats.first?.severity ?? 0, 200)
    }

    func testListsOpponentIdeasWhenItIsTheirMove() {
        let position = Position(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")!
        let report = PositionAnalyzer().analyze(position, perspective: .white, configuration: configuration)
        XCTAssertFalse(report.isYourMove)
        XCTAssertFalse(report.opponentThreats.isEmpty)
    }

    func testCoachCommentaryIsProduced() {
        let report = PositionAnalyzer().analyze(.standard, perspective: .white, configuration: configuration)
        let commentary = CoachNarrator(level: .improver).commentary(for: report)
        XCTAssertFalse(commentary.headline.isEmpty)
        XCTAssertFalse(commentary.assessment.isEmpty)
        XCTAssertFalse(commentary.hints.isEmpty)
        // Hints must get progressively more specific.
        let depths = commentary.hints.map { $0.depth.rawValue }
        XCTAssertEqual(depths, depths.sorted())
        XCTAssertNotNil(commentary.suggestedMoveSAN)
    }

    func testBlunderIsGraded() {
        // 1. e4 e5 2. Nf3 and now 2... Qh4 hangs a piece to Nxh4.
        var game = Game()
        for text in ["e4", "e5", "Nf3"] { game.play(san: text) }
        let before = game.position
        let blunder = before.move(san: "Qh4")!
        let review = MoveReviewer().review(move: blunder,
                                           in: before,
                                           configuration: ChessEngine.Configuration(maxDepth: 4, timeLimit: 2.0, multiPV: 2))
        XCTAssertEqual(review.san, "Qh4")
        XCTAssertTrue(review.quality.isRegrettable, "expected a mistake, got \(review.quality)")
        XCTAssertGreaterThan(review.centipawnLoss, 100)
        XCTAssertFalse(review.explanation.isEmpty)
    }
}

final class ExplorationTreeTests: XCTestCase {
    func testPlayingAndRewinding() {
        var tree = ExplorationTree(anchor: .standard, anchorPly: 0, perspective: .white)
        XCTAssertTrue(tree.isAtRoot)
        XCTAssertNotNil(tree.play(san: "e4"))
        XCTAssertNotNil(tree.play(san: "e5"))
        XCTAssertEqual(tree.currentLine.map { $0.san }, ["e4", "e5"])
        XCTAssertEqual(tree.currentLineSAN, "1. e4 e5")

        tree.goBack()
        XCTAssertEqual(tree.currentLine.map { $0.san }, ["e4"])
        XCTAssertTrue(tree.canGoForward)

        // A different second move creates a sibling branch, not a replacement.
        XCTAssertNotNil(tree.play(san: "c5"))
        XCTAssertEqual(tree.branches.count, 2)

        tree.returnToStart()
        XCTAssertTrue(tree.isAtRoot)
        XCTAssertEqual(tree.currentPosition, .standard)
    }

    func testReplayingTheSameMoveReusesTheBranch() {
        var tree = ExplorationTree(anchor: .standard, anchorPly: 0, perspective: .white)
        let first = tree.play(san: "d4")
        tree.goBack()
        let second = tree.play(san: "d4")
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(tree.branches.count, 1)
    }

    func testIllegalMovesAreRejected() {
        var tree = ExplorationTree(anchor: .standard, anchorPly: 0, perspective: .white)
        XCTAssertNil(tree.play(san: "e5"))
        XCTAssertTrue(tree.isAtRoot)
    }

    func testDeletingABranch() {
        var tree = ExplorationTree(anchor: .standard, anchorPly: 0, perspective: .white)
        tree.play(san: "e4")
        tree.play(san: "e5")
        tree.deleteCurrentBranch()
        XCTAssertEqual(tree.currentLine.map { $0.san }, ["e4"])
        XCTAssertFalse(tree.canGoForward)
    }
}
