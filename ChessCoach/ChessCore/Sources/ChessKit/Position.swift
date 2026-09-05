import Foundation

/// Record of everything `make` destroys, so `unmake` can put it back.
public struct MoveUndo: Sendable {
    public let move: Move
    let movingPiece: Piece
    let capturedPiece: Piece?
    let capturedSquare: Square?
    let castlingRights: CastlingRights
    let enPassantSquare: Square?
    let halfmoveClock: Int
    let fullmoveNumber: Int
    let zobristKey: UInt64
}

/// A complete chess position plus the rules that act on it.
///
/// The board is a 0x88 mailbox: correctness first, but still fast enough for the
/// several-hundred-thousand nodes a second the coach's search needs on device.
public struct Position: Hashable, Sendable {
    public static let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// 128 entries; only those with `index & 0x88 == 0` are real squares.
    private var board: [Piece?]
    public private(set) var sideToMove: PieceColor
    public private(set) var castlingRights: CastlingRights
    public private(set) var enPassantSquare: Square?
    /// Plies since the last capture or pawn move (fifty-move rule).
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int
    private var kingSquares: [Square?]
    public private(set) var zobristKey: UInt64

    // MARK: - Construction

    public init() {
        self.board = Array(repeating: nil, count: 128)
        self.sideToMove = .white
        self.castlingRights = []
        self.enPassantSquare = nil
        self.halfmoveClock = 0
        self.fullmoveNumber = 1
        self.kingSquares = [nil, nil]
        self.zobristKey = 0
    }

    public static var standard: Position {
        // The starting position is a known-good FEN, so the force-unwrap is safe.
        return Position(fen: Position.startingFEN)!
    }

    public init?(fen: String) {
        self.init()
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 2 else { return nil }

        // 1. Piece placement, from rank 8 down to rank 1.
        var rank = 7
        var file = 0
        for character in fields[0] {
            if character == "/" {
                guard file == 8 else { return nil }
                rank -= 1
                file = 0
                guard rank >= 0 else { return nil }
            } else if let emptyCount = character.wholeNumberValue, emptyCount >= 1, emptyCount <= 8 {
                file += emptyCount
                guard file <= 8 else { return nil }
            } else if let piece = Piece.fromFENSymbol(character) {
                guard let square = Square(file: file, rank: rank) else { return nil }
                setPiece(piece, at: square)
                file += 1
            } else {
                return nil
            }
        }
        guard rank == 0, file == 8 else { return nil }

        // 2. Side to move.
        switch fields[1].lowercased() {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: return nil
        }

        // 3. Castling rights.
        castlingRights = fields.count > 2 ? CastlingRights.parse(fen: fields[2]) : []

        // 4. En passant target square.
        if fields.count > 3, fields[3] != "-" {
            guard let square = Square(algebraic: fields[3]) else { return nil }
            enPassantSquare = square
        }

        // 5 & 6. Clocks.
        halfmoveClock = fields.count > 4 ? (Int(fields[4]) ?? 0) : 0
        fullmoveNumber = fields.count > 5 ? (Int(fields[5]) ?? 1) : 1

        zobristKey = computeZobristKey()
    }

    public var fen: String {
        var placement = ""
        for rank in stride(from: 7, through: 0, by: -1) {
            var emptyRun = 0
            for file in 0..<8 {
                let square = Square(unchecked: rank * 16 + file)
                if let piece = board[square.index] {
                    if emptyRun > 0 {
                        placement += String(emptyRun)
                        emptyRun = 0
                    }
                    placement.append(piece.fenSymbol)
                } else {
                    emptyRun += 1
                }
            }
            if emptyRun > 0 { placement += String(emptyRun) }
            if rank > 0 { placement += "/" }
        }
        let side = sideToMove == .white ? "w" : "b"
        let enPassant = enPassantSquare?.name ?? "-"
        return "\(placement) \(side) \(castlingRights.fenString) \(enPassant) \(halfmoveClock) \(fullmoveNumber)"
    }

    // MARK: - Board access

    public func piece(at square: Square) -> Piece? {
        return board[square.index]
    }

    public func isEmpty(_ square: Square) -> Bool {
        return board[square.index] == nil
    }

    public func kingSquare(of color: PieceColor) -> Square? {
        return kingSquares[Int(color.rawValue)]
    }

    /// Every occupied square, optionally filtered by colour and kind.
    public func squares(of color: PieceColor? = nil, kind: PieceKind? = nil) -> [Square] {
        var result: [Square] = []
        result.reserveCapacity(32)
        for square in Square.all {
            guard let piece = board[square.index] else { continue }
            if let color = color, piece.color != color { continue }
            if let kind = kind, piece.kind != kind { continue }
            result.append(square)
        }
        return result
    }

    public func count(of color: PieceColor, kind: PieceKind) -> Int {
        var total = 0
        for square in Square.all {
            if let piece = board[square.index], piece.color == color, piece.kind == kind {
                total += 1
            }
        }
        return total
    }

    private mutating func setPiece(_ piece: Piece?, at square: Square) {
        if let existing = board[square.index], existing.kind == .king {
            kingSquares[Int(existing.color.rawValue)] = nil
        }
        board[square.index] = piece
        if let piece = piece, piece.kind == .king {
            kingSquares[Int(piece.color.rawValue)] = square
        }
    }

    private func computeZobristKey() -> UInt64 {
        var key: UInt64 = 0
        for square in Square.all {
            if let piece = board[square.index] {
                key ^= Zobrist.piece(piece, at: square)
            }
        }
        if sideToMove == .black { key ^= Zobrist.sideToMove }
        key ^= Zobrist.castling[Int(castlingRights.rawValue) & 15]
        if let enPassant = enPassantSquare {
            key ^= Zobrist.enPassantFile[enPassant.file]
        }
        return key
    }

    // MARK: - Attack detection

    public static let knightOffsets = [-33, -31, -18, -14, 14, 18, 31, 33]
    public static let kingOffsets = [-17, -16, -15, -1, 1, 15, 16, 17]
    public static let bishopDirections = [-17, -15, 15, 17]
    public static let rookDirections = [-16, -1, 1, 16]
    public static let queenDirections = [-17, -16, -15, -1, 1, 15, 16, 17]

    private static func isOnBoard(_ index: Int) -> Bool {
        return Square.isValidIndex(index)
    }

    private func hasPawn(of color: PieceColor, at index: Int) -> Bool {
        guard Square.isValidIndex(index) else { return false }
        guard let piece = board[index] else { return false }
        return piece.color == color && piece.kind == .pawn
    }

    /// Is `square` attacked by any piece of `color`?
    public func isSquareAttacked(_ square: Square, by color: PieceColor) -> Bool {
        let target = square.index

        // Pawns. A white pawn attacking `target` sits at target-15 or target-17.
        // Written out rather than looped: this runs several times per generated
        // move, and an array literal here allocates on every call.
        let pawnStep = color == .white ? -16 : 16
        if hasPawn(of: color, at: target + pawnStep - 1) { return true }
        if hasPawn(of: color, at: target + pawnStep + 1) { return true }

        for offset in Position.knightOffsets {
            let origin = target + offset
            guard Position.isOnBoard(origin) else { continue }
            if let piece = board[origin], piece.color == color, piece.kind == .knight {
                return true
            }
        }

        for offset in Position.kingOffsets {
            let origin = target + offset
            guard Position.isOnBoard(origin) else { continue }
            if let piece = board[origin], piece.color == color, piece.kind == .king {
                return true
            }
        }

        for direction in Position.bishopDirections {
            var cursor = target + direction
            while Position.isOnBoard(cursor) {
                if let piece = board[cursor] {
                    if piece.color == color && (piece.kind == .bishop || piece.kind == .queen) {
                        return true
                    }
                    break
                }
                cursor += direction
            }
        }

        for direction in Position.rookDirections {
            var cursor = target + direction
            while Position.isOnBoard(cursor) {
                if let piece = board[cursor] {
                    if piece.color == color && (piece.kind == .rook || piece.kind == .queen) {
                        return true
                    }
                    break
                }
                cursor += direction
            }
        }

        return false
    }

    /// How many of `color`'s pieces attack `square`. Allocation-free, unlike
    /// `attackers(of:by:)` — the evaluator calls this on every leaf node.
    public func attackerCount(of square: Square, by color: PieceColor) -> Int {
        var count = 0
        let target = square.index
        let pawnStep = color == .white ? -16 : 16
        if hasPawn(of: color, at: target + pawnStep - 1) { count += 1 }
        if hasPawn(of: color, at: target + pawnStep + 1) { count += 1 }

        for offset in Position.knightOffsets {
            let origin = target + offset
            guard Position.isOnBoard(origin) else { continue }
            if let piece = board[origin], piece.color == color, piece.kind == .knight { count += 1 }
        }
        for offset in Position.kingOffsets {
            let origin = target + offset
            guard Position.isOnBoard(origin) else { continue }
            if let piece = board[origin], piece.color == color, piece.kind == .king { count += 1 }
        }
        for direction in Position.bishopDirections {
            var cursor = target + direction
            while Position.isOnBoard(cursor) {
                if let piece = board[cursor] {
                    if piece.color == color && (piece.kind == .bishop || piece.kind == .queen) { count += 1 }
                    break
                }
                cursor += direction
            }
        }
        for direction in Position.rookDirections {
            var cursor = target + direction
            while Position.isOnBoard(cursor) {
                if let piece = board[cursor] {
                    if piece.color == color && (piece.kind == .rook || piece.kind == .queen) { count += 1 }
                    break
                }
                cursor += direction
            }
        }
        return count
    }

    /// Every square of `color`'s pieces that currently attacks `square`.
    public func attackers(of square: Square, by color: PieceColor) -> [Square] {
        var result: [Square] = []
        let target = square.index

        let pawnStep = color == .white ? -16 : 16
        for origin in [target + pawnStep - 1, target + pawnStep + 1] where hasPawn(of: color, at: origin) {
            result.append(Square(unchecked: origin))
        }

        for offset in Position.knightOffsets {
            let origin = target + offset
            guard Position.isOnBoard(origin) else { continue }
            if let piece = board[origin], piece.color == color, piece.kind == .knight {
                result.append(Square(unchecked: origin))
            }
        }

        for offset in Position.kingOffsets {
            let origin = target + offset
            guard Position.isOnBoard(origin) else { continue }
            if let piece = board[origin], piece.color == color, piece.kind == .king {
                result.append(Square(unchecked: origin))
            }
        }

        for direction in Position.bishopDirections {
            var cursor = target + direction
            while Position.isOnBoard(cursor) {
                if let piece = board[cursor] {
                    if piece.color == color && (piece.kind == .bishop || piece.kind == .queen) {
                        result.append(Square(unchecked: cursor))
                    }
                    break
                }
                cursor += direction
            }
        }

        for direction in Position.rookDirections {
            var cursor = target + direction
            while Position.isOnBoard(cursor) {
                if let piece = board[cursor] {
                    if piece.color == color && (piece.kind == .rook || piece.kind == .queen) {
                        result.append(Square(unchecked: cursor))
                    }
                    break
                }
                cursor += direction
            }
        }

        return result
    }

    public func isInCheck(_ color: PieceColor) -> Bool {
        guard let king = kingSquares[Int(color.rawValue)] else { return false }
        return isSquareAttacked(king, by: color.opponent)
    }

    public var isCheck: Bool {
        return isInCheck(sideToMove)
    }

    // MARK: - Making and unmaking moves

    @discardableResult
    public mutating func make(_ move: Move) -> MoveUndo {
        let mover = board[move.from.index] ?? Piece(sideToMove, .pawn)
        let previousCastlingRights = castlingRights
        let previousEnPassant = enPassantSquare
        let previousKey = zobristKey

        var capturedPiece: Piece?
        var capturedSquare: Square?
        if move.isEnPassant {
            let offset = sideToMove == .white ? -16 : 16
            let square = Square(unchecked: move.to.index + offset)
            capturedPiece = board[square.index]
            capturedSquare = square
        } else if let occupant = board[move.to.index] {
            capturedPiece = occupant
            capturedSquare = move.to
        }

        let undo = MoveUndo(
            move: move,
            movingPiece: mover,
            capturedPiece: capturedPiece,
            capturedSquare: capturedSquare,
            castlingRights: previousCastlingRights,
            enPassantSquare: previousEnPassant,
            halfmoveClock: halfmoveClock,
            fullmoveNumber: fullmoveNumber,
            zobristKey: previousKey
        )

        // Lift the captured piece (which may not be on the destination square).
        if let captured = capturedPiece, let square = capturedSquare {
            zobristKey ^= Zobrist.piece(captured, at: square)
            setPiece(nil, at: square)
        }

        // Move the piece, promoting if asked.
        zobristKey ^= Zobrist.piece(mover, at: move.from)
        setPiece(nil, at: move.from)
        let landingPiece = move.promotion.map { Piece(mover.color, $0) } ?? mover
        zobristKey ^= Zobrist.piece(landingPiece, at: move.to)
        setPiece(landingPiece, at: move.to)

        // Castling also moves a rook.
        if move.isCastle {
            let backRank = mover.color.backRank
            let rookFrom = Square(unchecked: backRank * 16 + (move.isKingsideCastle ? 7 : 0))
            let rookTo = Square(unchecked: backRank * 16 + (move.isKingsideCastle ? 5 : 3))
            if let rook = board[rookFrom.index] {
                zobristKey ^= Zobrist.piece(rook, at: rookFrom)
                setPiece(nil, at: rookFrom)
                zobristKey ^= Zobrist.piece(rook, at: rookTo)
                setPiece(rook, at: rookTo)
            }
        }

        // Castling rights: moving a king or rook, or capturing a rook, revokes them.
        var rights = castlingRights
        if mover.kind == .king {
            rights.subtract(CastlingRights.both(mover.color))
        }
        if mover.kind == .rook {
            rights.subtract(Position.castlingRight(forRookOn: move.from))
        }
        if let square = capturedSquare, capturedPiece?.kind == .rook {
            rights.subtract(Position.castlingRight(forRookOn: square))
        }
        if rights != castlingRights {
            zobristKey ^= Zobrist.castling[Int(castlingRights.rawValue) & 15]
            zobristKey ^= Zobrist.castling[Int(rights.rawValue) & 15]
            castlingRights = rights
        }

        // En passant target.
        if let previous = previousEnPassant {
            zobristKey ^= Zobrist.enPassantFile[previous.file]
        }
        if move.isDoublePawnPush {
            let offset = mover.color == .white ? -16 : 16
            let square = Square(unchecked: move.to.index + offset)
            enPassantSquare = square
            zobristKey ^= Zobrist.enPassantFile[square.file]
        } else {
            enPassantSquare = nil
        }

        // Clocks.
        if mover.kind == .pawn || capturedPiece != nil {
            halfmoveClock = 0
        } else {
            halfmoveClock += 1
        }
        if sideToMove == .black {
            fullmoveNumber += 1
        }

        sideToMove = sideToMove.opponent
        zobristKey ^= Zobrist.sideToMove

        return undo
    }

    public mutating func unmake(_ undo: MoveUndo) {
        let move = undo.move
        sideToMove = sideToMove.opponent

        // Put the moving piece back (undoing any promotion).
        setPiece(nil, at: move.to)
        setPiece(undo.movingPiece, at: move.from)

        if let captured = undo.capturedPiece, let square = undo.capturedSquare {
            setPiece(captured, at: square)
        }

        if move.isCastle {
            let backRank = undo.movingPiece.color.backRank
            let rookFrom = Square(unchecked: backRank * 16 + (move.isKingsideCastle ? 7 : 0))
            let rookTo = Square(unchecked: backRank * 16 + (move.isKingsideCastle ? 5 : 3))
            if let rook = board[rookTo.index] {
                setPiece(nil, at: rookTo)
                setPiece(rook, at: rookFrom)
            }
        }

        castlingRights = undo.castlingRights
        enPassantSquare = undo.enPassantSquare
        halfmoveClock = undo.halfmoveClock
        fullmoveNumber = undo.fullmoveNumber
        zobristKey = undo.zobristKey
    }

    /// Non-mutating make, for call sites that want a fresh position.
    public func making(_ move: Move) -> Position {
        var copy = self
        copy.make(move)
        return copy
    }

    private static func castlingRight(forRookOn square: Square) -> CastlingRights {
        switch square.index {
        case 0: return .whiteQueenside
        case 7: return .whiteKingside
        case 112: return .blackQueenside
        case 119: return .blackKingside
        default: return []
        }
    }

    /// A null move — hand the turn over without playing anything. Used by the
    /// analyser to ask "what would my opponent do if I passed?", which is how the
    /// coach finds the threats you need to answer.
    public mutating func makeNullMove() -> MoveUndo {
        let undo = MoveUndo(
            move: Move(from: Square(unchecked: 0), to: Square(unchecked: 0)),
            movingPiece: Piece(sideToMove, .king),
            capturedPiece: nil,
            capturedSquare: nil,
            castlingRights: castlingRights,
            enPassantSquare: enPassantSquare,
            halfmoveClock: halfmoveClock,
            fullmoveNumber: fullmoveNumber,
            zobristKey: zobristKey
        )
        if let enPassant = enPassantSquare {
            zobristKey ^= Zobrist.enPassantFile[enPassant.file]
        }
        enPassantSquare = nil
        halfmoveClock += 1
        sideToMove = sideToMove.opponent
        zobristKey ^= Zobrist.sideToMove
        return undo
    }

    public mutating func unmakeNullMove(_ undo: MoveUndo) {
        sideToMove = sideToMove.opponent
        castlingRights = undo.castlingRights
        enPassantSquare = undo.enPassantSquare
        halfmoveClock = undo.halfmoveClock
        fullmoveNumber = undo.fullmoveNumber
        zobristKey = undo.zobristKey
    }

    // MARK: - Equatable / Hashable

    public static func == (lhs: Position, rhs: Position) -> Bool {
        return lhs.zobristKey == rhs.zobristKey
            && lhs.sideToMove == rhs.sideToMove
            && lhs.castlingRights == rhs.castlingRights
            && lhs.enPassantSquare == rhs.enPassantSquare
            && lhs.board == rhs.board
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(zobristKey)
    }
}
