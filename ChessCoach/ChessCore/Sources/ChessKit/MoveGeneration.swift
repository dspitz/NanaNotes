import Foundation

extension Position {
    /// Every legal move for the side to move.
    public var legalMoves: [Move] {
        var copy = self
        return copy.generateLegalMoves()
    }

    /// Legal moves, computed in place so the caller can reuse one buffer.
    public mutating func generateLegalMoves(capturesOnly: Bool = false) -> [Move] {
        let candidates = generatePseudoLegalMoves(capturesOnly: capturesOnly)
        var result: [Move] = []
        result.reserveCapacity(candidates.count)
        let mover = sideToMove
        for move in candidates {
            let undo = make(move)
            if !isInCheck(mover) {
                result.append(move)
            }
            unmake(undo)
        }
        return result
    }

    /// Moves that obey piece movement rules but may leave the king in check.
    /// `capturesOnly` also keeps promotions, because quiescence search needs them.
    public func generatePseudoLegalMoves(capturesOnly: Bool = false) -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(capturesOnly ? 16 : 48)
        let color = sideToMove

        for square in Square.all {
            guard let piece = piece(at: square), piece.color == color else { continue }
            switch piece.kind {
            case .pawn:
                generatePawnMoves(from: square, color: color, capturesOnly: capturesOnly, into: &moves)
            case .knight:
                generateStepMoves(from: square, color: color, offsets: Position.knightOffsets, capturesOnly: capturesOnly, into: &moves)
            case .king:
                generateStepMoves(from: square, color: color, offsets: Position.kingOffsets, capturesOnly: capturesOnly, into: &moves)
            case .bishop:
                generateSlidingMoves(from: square, color: color, directions: Position.bishopDirections, capturesOnly: capturesOnly, into: &moves)
            case .rook:
                generateSlidingMoves(from: square, color: color, directions: Position.rookDirections, capturesOnly: capturesOnly, into: &moves)
            case .queen:
                generateSlidingMoves(from: square, color: color, directions: Position.queenDirections, capturesOnly: capturesOnly, into: &moves)
            }
        }

        if !capturesOnly {
            generateCastlingMoves(color: color, into: &moves)
        }
        return moves
    }

    private func generateStepMoves(from square: Square, color: PieceColor, offsets: [Int], capturesOnly: Bool, into moves: inout [Move]) {
        for offset in offsets {
            let targetIndex = square.index + offset
            guard Square.isValidIndex(targetIndex) else { continue }
            let target = Square(unchecked: targetIndex)
            if let occupant = piece(at: target) {
                if occupant.color != color {
                    moves.append(Move(from: square, to: target, flags: .capture))
                }
            } else if !capturesOnly {
                moves.append(Move(from: square, to: target))
            }
        }
    }

    private func generateSlidingMoves(from square: Square, color: PieceColor, directions: [Int], capturesOnly: Bool, into moves: inout [Move]) {
        for direction in directions {
            var targetIndex = square.index + direction
            while Square.isValidIndex(targetIndex) {
                let target = Square(unchecked: targetIndex)
                if let occupant = piece(at: target) {
                    if occupant.color != color {
                        moves.append(Move(from: square, to: target, flags: .capture))
                    }
                    break
                }
                if !capturesOnly {
                    moves.append(Move(from: square, to: target))
                }
                targetIndex += direction
            }
        }
    }

    private func generatePawnMoves(from square: Square, color: PieceColor, capturesOnly: Bool, into moves: inout [Move]) {
        let forward = color == .white ? 16 : -16
        let promotionRank = color.promotionRank

        // Pushes.
        let oneStepIndex = square.index + forward
        if Square.isValidIndex(oneStepIndex), piece(at: Square(unchecked: oneStepIndex)) == nil {
            let oneStep = Square(unchecked: oneStepIndex)
            if oneStep.rank == promotionRank {
                appendPromotions(from: square, to: oneStep, flags: [], into: &moves)
            } else if !capturesOnly {
                moves.append(Move(from: square, to: oneStep))
                let twoStepIndex = square.index + 2 * forward
                if square.rank == color.pawnStartRank,
                   Square.isValidIndex(twoStepIndex),
                   piece(at: Square(unchecked: twoStepIndex)) == nil {
                    moves.append(Move(from: square, to: Square(unchecked: twoStepIndex), flags: .doublePawnPush))
                }
            }
        }

        // Captures, including en passant. Unrolled to keep the generator free of
        // per-call array allocations.
        generatePawnCapture(from: square, toIndex: square.index + forward - 1, color: color, promotionRank: promotionRank, into: &moves)
        generatePawnCapture(from: square, toIndex: square.index + forward + 1, color: color, promotionRank: promotionRank, into: &moves)
    }

    private func generatePawnCapture(from square: Square, toIndex: Int, color: PieceColor, promotionRank: Int, into moves: inout [Move]) {
        guard Square.isValidIndex(toIndex) else { return }
        let target = Square(unchecked: toIndex)
        if let occupant = piece(at: target) {
            guard occupant.color != color else { return }
            if target.rank == promotionRank {
                appendPromotions(from: square, to: target, flags: .capture, into: &moves)
            } else {
                moves.append(Move(from: square, to: target, flags: .capture))
            }
        } else if let enPassant = enPassantSquare, enPassant == target {
            moves.append(Move(from: square, to: target, flags: [.capture, .enPassant]))
        }
    }

    private static let promotionKinds: [PieceKind] = [.queen, .rook, .bishop, .knight]

    private func appendPromotions(from: Square, to: Square, flags: Move.Flags, into moves: inout [Move]) {
        for kind in Position.promotionKinds {
            moves.append(Move(from: from, to: to, promotion: kind, flags: flags.union(.promotion)))
        }
    }

    private func generateCastlingMoves(color: PieceColor, into moves: inout [Move]) {
        let backRank = color.backRank
        guard let kingSquare = kingSquare(of: color), kingSquare.index == backRank * 16 + 4 else { return }
        guard !isSquareAttacked(kingSquare, by: color.opponent) else { return }

        if castlingRights.contains(CastlingRights.kingside(color)) {
            let rookSquare = Square(unchecked: backRank * 16 + 7)
            let f = Square(unchecked: backRank * 16 + 5)
            let g = Square(unchecked: backRank * 16 + 6)
            if let rook = piece(at: rookSquare), rook.color == color, rook.kind == .rook,
               piece(at: f) == nil, piece(at: g) == nil,
               !isSquareAttacked(f, by: color.opponent),
               !isSquareAttacked(g, by: color.opponent) {
                moves.append(Move(from: kingSquare, to: g, flags: .kingsideCastle))
            }
        }

        if castlingRights.contains(CastlingRights.queenside(color)) {
            let rookSquare = Square(unchecked: backRank * 16 + 0)
            let b = Square(unchecked: backRank * 16 + 1)
            let c = Square(unchecked: backRank * 16 + 2)
            let d = Square(unchecked: backRank * 16 + 3)
            if let rook = piece(at: rookSquare), rook.color == color, rook.kind == .rook,
               piece(at: b) == nil, piece(at: c) == nil, piece(at: d) == nil,
               !isSquareAttacked(d, by: color.opponent),
               !isSquareAttacked(c, by: color.opponent) {
                moves.append(Move(from: kingSquare, to: c, flags: .queensideCastle))
            }
        }
    }

    // MARK: - Convenience

    /// Legal moves that start on `square`. Drives the board view's move dots.
    public func legalMoves(from square: Square) -> [Move] {
        return legalMoves.filter { $0.from == square }
    }

    /// Finds the fully-flagged legal move matching a bare from/to (plus promotion).
    /// This is how taps and drags on the board turn into real moves.
    public func legalMove(from: Square, to: Square, promotion: PieceKind? = nil) -> Move? {
        let candidates = legalMoves.filter { $0.from == from && $0.to == to }
        if let promotion = promotion {
            return candidates.first { $0.promotion == promotion }
        }
        if candidates.count > 1, candidates.allSatisfy({ $0.isPromotion }) {
            // Caller has to pick a promotion piece; default to a queen.
            return candidates.first { $0.promotion == .queen } ?? candidates.first
        }
        return candidates.first
    }

    public func legalMove(uci: String) -> Move? {
        guard let parsed = Move.parseUCI(uci) else { return nil }
        return legalMoves.first { $0.matches(parsed) }
    }

    /// True when the move needs the user to choose a promotion piece.
    public func requiresPromotionChoice(from: Square, to: Square) -> Bool {
        return legalMoves.contains { $0.from == from && $0.to == to && $0.isPromotion }
    }

    public var isCheckmate: Bool {
        return isCheck && legalMoves.isEmpty
    }

    public var isStalemate: Bool {
        return !isCheck && legalMoves.isEmpty
    }

    /// Positions where no sequence of legal moves can produce checkmate.
    ///
    /// Called at every search node, so it is written to bail out on the first
    /// pawn or heavy piece and never to allocate.
    public var hasInsufficientMaterial: Bool {
        var minorCount = 0
        var whiteBishop: Square?
        var blackBishop: Square?
        var whiteKnights = 0
        var blackKnights = 0

        for square in Square.all {
            guard let piece = piece(at: square) else { continue }
            switch piece.kind {
            case .king:
                continue
            case .pawn, .rook, .queen:
                return false
            case .bishop:
                minorCount += 1
                if minorCount > 2 { return false }
                if piece.color == .white { whiteBishop = square } else { blackBishop = square }
            case .knight:
                minorCount += 1
                if minorCount > 2 { return false }
                if piece.color == .white { whiteKnights += 1 } else { blackKnights += 1 }
            }
        }

        if minorCount <= 1 { return true }
        // King and bishop against king and bishop is drawn when both bishops
        // stand on the same colour squares. Two knights cannot force mate either,
        // but the position is not dead drawn, so it is not claimed here.
        if let white = whiteBishop, let black = blackBishop, whiteKnights == 0, blackKnights == 0 {
            return white.isLight == black.isLight
        }
        return false
    }

    /// Counts leaf nodes at a fixed depth. Used by the tests to prove the move
    /// generator matches the published perft numbers.
    public mutating func perft(depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = generateLegalMoves()
        if depth == 1 { return moves.count }
        var total = 0
        for move in moves {
            let undo = make(move)
            total += perft(depth: depth - 1)
            unmake(undo)
        }
        return total
    }
}
