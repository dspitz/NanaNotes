import Foundation

public enum GameTermination: String, Sendable, Hashable {
    case checkmate
    case stalemate
    case insufficientMaterial
    case fiftyMoveRule
    case threefoldRepetition
    case resignation
    case agreedDraw

    public var describedReason: String {
        switch self {
        case .checkmate: return "checkmate"
        case .stalemate: return "stalemate"
        case .insufficientMaterial: return "insufficient material"
        case .fiftyMoveRule: return "the fifty-move rule"
        case .threefoldRepetition: return "threefold repetition"
        case .resignation: return "resignation"
        case .agreedDraw: return "agreement"
        }
    }
}

public enum GameResult: Sendable, Hashable {
    case win(PieceColor, GameTermination)
    case draw(GameTermination)

    public var pgnString: String {
        switch self {
        case .win(let color, _): return color == .white ? "1-0" : "0-1"
        case .draw: return "1/2-1/2"
        }
    }

    public var headline: String {
        switch self {
        case .win(let color, let termination):
            return "\(color.name) wins by \(termination.describedReason)."
        case .draw(let termination):
            return "Draw by \(termination.describedReason)."
        }
    }
}

/// One played move, with everything the UI and the coach need to talk about it.
public struct MoveRecord: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let move: Move
    public let san: String
    public let positionBefore: Position
    public let positionAfter: Position
    /// 0-based ply index within the game.
    public let ply: Int

    public init(move: Move, san: String, positionBefore: Position, positionAfter: Position, ply: Int) {
        self.id = UUID()
        self.move = move
        self.san = san
        self.positionBefore = positionBefore
        self.positionAfter = positionAfter
        self.ply = ply
    }

    public var color: PieceColor { return positionBefore.sideToMove }

    /// The move number a human would say out loud, e.g. 12 in "12... Nf6".
    public var moveNumber: Int { return positionBefore.fullmoveNumber }
}

/// A game in progress: the move list, the current position, and result detection.
public struct Game: Sendable {
    public private(set) var initialPosition: Position
    public private(set) var position: Position
    public private(set) var history: [MoveRecord]
    public private(set) var result: GameResult?
    /// Zobrist keys seen so far, for threefold repetition.
    private var repetitionKeys: [UInt64]

    public init(position: Position = .standard) {
        self.initialPosition = position
        self.position = position
        self.history = []
        self.result = nil
        self.repetitionKeys = [position.zobristKey]
    }

    public var isOver: Bool { return result != nil }

    public var sideToMove: PieceColor { return position.sideToMove }

    public var ply: Int { return history.count }

    @discardableResult
    public mutating func play(_ move: Move) -> MoveRecord? {
        guard result == nil else { return nil }
        let legal = position.legalMoves
        guard legal.contains(where: { $0 == move }) else { return nil }
        let text = position.san(for: move, legalMoves: legal)
        let before = position
        position.make(move)
        let record = MoveRecord(move: move, san: text, positionBefore: before, positionAfter: position, ply: history.count)
        history.append(record)
        repetitionKeys.append(position.zobristKey)
        result = detectResult()
        return record
    }

    @discardableResult
    public mutating func play(san text: String) -> MoveRecord? {
        guard let move = position.move(san: text) else { return nil }
        return play(move)
    }

    @discardableResult
    public mutating func undoLastMove() -> MoveRecord? {
        guard let record = history.popLast() else { return nil }
        position = record.positionBefore
        repetitionKeys.removeLast()
        result = nil
        return record
    }

    public mutating func resign(_ color: PieceColor) {
        result = .win(color.opponent, .resignation)
    }

    public mutating func agreeDraw() {
        result = .draw(.agreedDraw)
    }

    /// Zobrist keys of every position reached so far, oldest first. Hand these
    /// to the engine so it can treat a repetition as the draw it is.
    public var positionKeys: [UInt64] {
        return repetitionKeys
    }

    public func repetitionCount(of key: UInt64) -> Int {
        return repetitionKeys.filter { $0 == key }.count
    }

    private func detectResult() -> GameResult? {
        if position.legalMoves.isEmpty {
            if position.isCheck {
                return .win(position.sideToMove.opponent, .checkmate)
            }
            return .draw(.stalemate)
        }
        if position.hasInsufficientMaterial { return .draw(.insufficientMaterial) }
        if position.halfmoveClock >= 100 { return .draw(.fiftyMoveRule) }
        if repetitionCount(of: position.zobristKey) >= 3 { return .draw(.threefoldRepetition) }
        return nil
    }

    /// Move list grouped into full moves, ready for a two-column move table.
    public var movePairs: [MovePair] {
        var pairs: [MovePair] = []
        for record in history {
            if record.color == .white {
                pairs.append(MovePair(number: record.moveNumber, white: record, black: nil))
            } else if var last = pairs.popLast() {
                last.black = record
                pairs.append(last)
            } else {
                pairs.append(MovePair(number: record.moveNumber, white: nil, black: record))
            }
        }
        return pairs
    }

    public func pgn(event: String = "ChessCoach training game") -> String {
        var lines: [String] = []
        lines.append("[Event \"\(event)\"]")
        lines.append("[Date \"\(Game.pgnDateFormatter.string(from: Date()))\"]")
        if initialPosition != Position.standard {
            lines.append("[SetUp \"1\"]")
            lines.append("[FEN \"\(initialPosition.fen)\"]")
        }
        lines.append("[Result \"\(result?.pgnString ?? "*")\"]")
        lines.append("")

        var movetext: [String] = []
        for record in history {
            if record.color == .white {
                movetext.append("\(record.moveNumber). \(record.san)")
            } else if movetext.isEmpty {
                movetext.append("\(record.moveNumber)... \(record.san)")
            } else {
                movetext.append(record.san)
            }
        }
        movetext.append(result?.pgnString ?? "*")
        lines.append(movetext.joined(separator: " "))
        return lines.joined(separator: "\n")
    }

    private static let pgnDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// One row of the move table.
public struct MovePair: Identifiable, Sendable, Hashable {
    public var number: Int
    public var white: MoveRecord?
    public var black: MoveRecord?

    public var id: Int { return number }

    public init(number: Int, white: MoveRecord?, black: MoveRecord?) {
        self.number = number
        self.white = white
        self.black = black
    }
}
