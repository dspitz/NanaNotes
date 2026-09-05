import Foundation
import Combine
import SwiftUI
import ChessKit
import CoachKit

/// A promotion the board is waiting on the player to choose.
struct PromotionRequest: Identifiable {
    let id = UUID()
    let from: Square
    let to: Square
}

/// Owns the game, the sandbox, and every request made of the coach.
///
/// The rule this class exists to enforce: the board never blocks. Every engine
/// call is a `Task`, results are dropped on the floor if the position has moved
/// on, and the only thing the UI reads is already-computed state.
@MainActor
final class GameViewModel: ObservableObject {
    // MARK: - Game state

    @Published private(set) var game = Game()
    @Published private(set) var isThinking = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var report: PositionReport?
    @Published private(set) var commentary: CoachCommentary?
    @Published private(set) var lastReview: MoveReview?
    @Published private(set) var gameReview: GameReview?
    @Published private(set) var reviewProgress: Double = 0

    // MARK: - Board interaction

    @Published var selectedSquare: Square?
    @Published private(set) var destinationSquares: Set<Square> = []
    @Published var promotionRequest: PromotionRequest?
    @Published var boardOrientation: PieceColor = .white
    @Published var showCoachHighlights = true
    /// Squares the coach is currently pointing at.
    @Published private(set) var coachHighlights: Set<Square> = []

    // MARK: - Sandbox

    @Published private(set) var exploration: ExplorationTree?
    @Published var explorationMode: ExplorationMode = .againstBestPlay

    // MARK: - Hints

    @Published private(set) var revealedHints: [CoachHint] = []

    // MARK: - Settings

    @Published var playerColor: PieceColor = .white
    @Published var opponentStrength: OpponentStrength = .club {
        didSet { Settings.store(opponentStrength.rawValue, for: .opponentStrength) }
    }
    @Published var coachLevel: CoachLevel = .improver {
        didSet {
            Settings.store(coachLevel.rawValue, for: .coachLevel)
            refreshCommentary()
        }
    }
    @Published var coachVerbosity: CoachVerbosity = .keyMoments {
        didSet { Settings.store(coachVerbosity.rawValue, for: .coachVerbosity) }
    }

    private let service = CoachService()
    /// Bumped on every analysis request so stale answers can be dropped.
    private var analysisGeneration = 0

    init() {
        opponentStrength = Settings.load(.opponentStrength).flatMap(OpponentStrength.init(rawValue:)) ?? .club
        coachLevel = Settings.load(.coachLevel).flatMap(CoachLevel.init(rawValue:)) ?? .improver
        coachVerbosity = Settings.load(.coachVerbosity).flatMap(CoachVerbosity.init(rawValue:)) ?? .keyMoments
    }

    // MARK: - Derived state

    /// The position the board is showing: the sandbox line if one is open,
    /// otherwise the real game.
    var activePosition: Position {
        return exploration?.currentPosition ?? game.position
    }

    var isExploring: Bool { return exploration != nil }

    var lastMove: Move? {
        if let exploration = exploration {
            return exploration.current.move
        }
        return game.history.last?.move
    }

    var checkedKingSquare: Square? {
        let position = activePosition
        guard position.isCheck else { return nil }
        return position.kingSquare(of: position.sideToMove)
    }

    var evaluation: Evaluation {
        return report?.evaluation ?? .equal
    }

    var winProbability: WinProbability {
        return report?.winProbability ?? WinProbability.from(evaluation: .equal)
    }

    var statusText: String {
        if let result = game.result, !isExploring { return result.headline }
        if isThinking { return "\(playerColor.opponent.name) is thinking..." }
        if isExploring {
            return activePosition.sideToMove == playerColor ? "Sandbox: your move" : "Sandbox: their move"
        }
        return activePosition.sideToMove == playerColor ? "Your move" : "\(activePosition.sideToMove.name) to move"
    }

    /// True when the human is allowed to move the piece on `square` right now.
    func canPickUp(_ square: Square) -> Bool {
        let position = activePosition
        guard let piece = position.piece(at: square), piece.color == position.sideToMove else { return false }
        if isExploring {
            return explorationMode == .bothSides || piece.color == playerColor
        }
        return !game.isOver && !isThinking && piece.color == playerColor
    }

    // MARK: - Board interaction

    func tap(_ square: Square) {
        let position = activePosition

        if let selected = selectedSquare {
            if selected == square {
                clearSelection()
                return
            }
            if destinationSquares.contains(square) {
                if position.requiresPromotionChoice(from: selected, to: square) {
                    promotionRequest = PromotionRequest(from: selected, to: square)
                    clearSelection()
                    return
                }
                if let move = position.legalMove(from: selected, to: square) {
                    perform(move)
                }
                return
            }
        }

        if canPickUp(square) {
            selectedSquare = square
            destinationSquares = Set(position.legalMoves(from: square).map { $0.to })
        } else {
            clearSelection()
        }
    }

    func completePromotion(_ kind: PieceKind) {
        guard let request = promotionRequest else { return }
        promotionRequest = nil
        guard let move = activePosition.legalMove(from: request.from, to: request.to, promotion: kind) else { return }
        perform(move)
    }

    func clearSelection() {
        selectedSquare = nil
        destinationSquares = []
    }

    private func perform(_ move: Move) {
        clearSelection()
        revealedHints = []
        coachHighlights = []
        if isExploring {
            playInSandbox(move)
        } else {
            playInGame(move)
        }
    }

    // MARK: - The real game

    private func playInGame(_ move: Move) {
        guard let record = game.play(move) else { return }
        lastReview = nil
        Task { await self.continueGame(after: record) }
    }

    private func continueGame(after record: MoveRecord) async {
        if coachVerbosity != .onRequest {
            let review = await service.review(move: record.move, in: record.positionBefore)
            // Only surface it if the game has not moved on underneath us.
            if game.history.last?.id == record.id || coachVerbosity == .everyMove {
                if coachVerbosity == .everyMove || review.quality.isRegrettable {
                    lastReview = review
                }
            }
        }

        guard !game.isOver else {
            await refreshAnalysis()
            return
        }

        if game.sideToMove != playerColor {
            isThinking = true
            let move = await service.opponentMove(for: game.position,
                                                  strength: opponentStrength,
                                                  positionKeys: game.positionKeys)
            isThinking = false
            if let move = move {
                game.play(move)
            }
        }
        await refreshAnalysis()
    }

    func startNewGame(as color: PieceColor, strength: OpponentStrength) {
        service.cancelCurrentWork()
        service.resetForNewGame()
        game = Game()
        playerColor = color
        opponentStrength = strength
        boardOrientation = color
        exploration = nil
        report = nil
        commentary = nil
        lastReview = nil
        gameReview = nil
        revealedHints = []
        clearSelection()
        Task {
            if color == .black {
                isThinking = true
                let move = await service.opponentMove(for: game.position, strength: strength, positionKeys: game.positionKeys)
                isThinking = false
                if let move = move { game.play(move) }
            }
            await refreshAnalysis()
        }
    }

    /// Takes back the player's last move and the engine's reply with it.
    func takeBackMove() {
        guard !isThinking, !isExploring else { return }
        service.cancelCurrentWork()
        if game.history.last?.color != playerColor {
            game.undoLastMove()
        }
        game.undoLastMove()
        lastReview = nil
        revealedHints = []
        clearSelection()
        Task { await refreshAnalysis() }
    }

    func resign() {
        guard !isExploring else { return }
        game.resign(playerColor)
    }

    // MARK: - Sandbox

    /// Freezes the current position and opens a branch you can play out.
    func enterExploration() {
        guard exploration == nil else { return }
        service.cancelCurrentWork()
        exploration = ExplorationTree(anchor: game.position,
                                      anchorPly: game.ply,
                                      perspective: playerColor,
                                      mode: explorationMode)
        clearSelection()
        revealedHints = []
        Task { await refreshAnalysis() }
    }

    /// Throws the sandbox away and puts the real game back on the board.
    func exitExploration() {
        exploration = nil
        service.cancelCurrentWork()
        clearSelection()
        revealedHints = []
        Task { await refreshAnalysis() }
    }

    private func playInSandbox(_ move: Move) {
        guard var tree = exploration else { return }
        let positionBefore = tree.currentPosition
        guard let node = tree.play(move) else { return }
        exploration = tree

        Task {
            let review = await service.review(move: move, in: positionBefore)
            if var tree = self.exploration {
                tree.annotate(node.id, review: review, note: review.explanation)
                self.exploration = tree
            }
            await self.sandboxReplyIfNeeded()
            await self.refreshAnalysis()
        }
    }

    private func sandboxReplyIfNeeded() async {
        guard let tree = exploration, tree.mode != .bothSides else { return }
        let position = tree.currentPosition
        guard position.sideToMove != playerColor, !position.legalMoves.isEmpty else { return }
        isThinking = true
        let strength: OpponentStrength = tree.mode == .againstBestPlay ? .maximum : opponentStrength
        let reply = await service.opponentMove(for: position, strength: strength)
        isThinking = false
        // The player may have rewound while the engine was thinking.
        guard let reply = reply, var current = exploration, current.currentPosition == position else { return }
        current.play(reply)
        exploration = current
    }

    func sandboxBack() {
        guard var tree = exploration else { return }
        tree.goBack()
        exploration = tree
        clearSelection()
        Task { await refreshAnalysis() }
    }

    func sandboxForward() {
        guard var tree = exploration else { return }
        tree.goForward()
        exploration = tree
        clearSelection()
        Task { await refreshAnalysis() }
    }

    func sandboxReset() {
        guard var tree = exploration else { return }
        tree.returnToStart()
        exploration = tree
        clearSelection()
        Task { await refreshAnalysis() }
    }

    func sandboxGo(to id: UUID) {
        guard var tree = exploration else { return }
        tree.goTo(id)
        exploration = tree
        clearSelection()
        Task { await refreshAnalysis() }
    }

    func setExplorationMode(_ mode: ExplorationMode) {
        explorationMode = mode
        guard var tree = exploration else { return }
        tree.mode = mode
        exploration = tree
    }

    // MARK: - Coaching

    func refreshAnalysis() async {
        let position = activePosition
        guard !position.legalMoves.isEmpty else {
            report = nil
            commentary = nil
            isAnalyzing = false
            return
        }
        if isAnalyzing {
            // An older analysis is still running; it is no longer wanted.
            service.cancelCurrentWork()
        }
        analysisGeneration += 1
        let generation = analysisGeneration
        isAnalyzing = true

        let keys = isExploring ? [] : game.positionKeys
        let newReport = await service.analyze(position,
                                              perspective: playerColor,
                                              configuration: .analysis(depth: 7, timeLimit: 1.4, candidates: 4),
                                              positionKeys: keys)

        // Drop answers the player has already moved past.
        guard generation == analysisGeneration, newReport.position == activePosition else { return }
        isAnalyzing = false
        report = newReport
        commentary = service.commentary(for: newReport, level: coachLevel)
    }

    private func refreshCommentary() {
        guard let report = report else { return }
        commentary = service.commentary(for: report, level: coachLevel)
    }

    /// Reveals one more layer of the hint ladder.
    func revealNextHint() {
        guard let commentary = commentary, !commentary.hints.isEmpty else { return }
        let nextIndex = revealedHints.count
        guard nextIndex < commentary.hints.count else { return }
        let hint = commentary.hints[nextIndex]
        revealedHints.append(hint)
        if showCoachHighlights {
            coachHighlights = Set(hint.highlightSquares)
        }
    }

    func hideHints() {
        revealedHints = []
        coachHighlights = []
    }

    var hasMoreHints: Bool {
        guard let commentary = commentary else { return false }
        return revealedHints.count < commentary.hints.count
    }

    func highlight(_ squares: [Square]) {
        coachHighlights = Set(squares)
    }

    /// Runs a full-game review for the post-game screen.
    func reviewWholeGame() {
        guard !game.history.isEmpty else { return }
        reviewProgress = 0
        Task {
            let review = await service.reviewGame(game) { progress in
                Task { @MainActor in self.reviewProgress = progress }
            }
            self.gameReview = review
        }
    }

    func flipBoard() {
        boardOrientation = boardOrientation.opponent
    }
}

/// Thin wrapper over UserDefaults so the settings code stays out of the way.
enum Settings {
    enum Key: String {
        case opponentStrength = "coach.opponentStrength"
        case coachLevel = "coach.level"
        case coachVerbosity = "coach.verbosity"
    }

    static func store(_ value: String, for key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    static func load(_ key: Key) -> String? {
        return UserDefaults.standard.string(forKey: key.rawValue)
    }
}
