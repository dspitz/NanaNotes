import Foundation

extension Position {
    /// Standard Algebraic Notation for a legal move in this position.
    public func san(for move: Move) -> String {
        return san(for: move, legalMoves: legalMoves)
    }

    /// SAN for every legal move, sharing one move-generation pass.
    public func annotatedLegalMoves() -> [(move: Move, san: String)] {
        let moves = legalMoves
        return moves.map { (move: $0, san: san(for: $0, legalMoves: moves)) }
    }

    /// SAN for a move when the caller has already generated the legal moves —
    /// avoids regenerating them once per move when rendering a whole list.
    public func san(for move: Move, legalMoves moves: [Move]) -> String {
        if move.isKingsideCastle { return "O-O" + checkSuffix(after: move) }
        if move.isQueensideCastle { return "O-O-O" + checkSuffix(after: move) }

        guard let mover = piece(at: move.from) else { return move.uci }
        var text = ""

        if mover.kind == .pawn {
            if move.isCapture {
                text += move.from.fileName + "x"
            }
            text += move.to.name
            if let promotion = move.promotion {
                text += "=" + String(promotion.symbol)
            }
        } else {
            text.append(mover.kind.symbol)
            text += disambiguator(for: move, mover: mover, legalMoves: moves)
            if move.isCapture { text += "x" }
            text += move.to.name
        }

        return text + checkSuffix(after: move)
    }

    private func disambiguator(for move: Move, mover: Piece, legalMoves moves: [Move]) -> String {
        let rivals = moves.filter { candidate in
            candidate.to == move.to
                && candidate.from != move.from
                && piece(at: candidate.from).map { $0.color == mover.color && $0.kind == mover.kind } == true
        }
        if rivals.isEmpty { return "" }
        if !rivals.contains(where: { $0.from.file == move.from.file }) {
            return move.from.fileName
        }
        if !rivals.contains(where: { $0.from.rank == move.from.rank }) {
            return String(move.from.rank + 1)
        }
        return move.from.name
    }

    private func checkSuffix(after move: Move) -> String {
        var next = self
        next.make(move)
        if next.isCheck {
            return next.legalMoves.isEmpty ? "#" : "+"
        }
        return ""
    }

    /// Parses SAN (or UCI, as a convenience) against this position.
    public func move(san text: String) -> Move? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let normalized = Position.normalizeSAN(cleaned)
        let moves = legalMoves
        for move in moves where Position.normalizeSAN(san(for: move, legalMoves: moves)) == normalized {
            return move
        }
        // Fall back to UCI so callers can paste engine output straight in.
        if let parsed = Move.parseUCI(cleaned) {
            return moves.first { $0.matches(parsed) }
        }
        return nil
    }

    /// Strips decorations that do not change which move is meant.
    private static func normalizeSAN(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "0-0-0", with: "O-O-O")
        result = result.replacingOccurrences(of: "0-0", with: "O-O")
        result = result.replacingOccurrences(of: "e.p.", with: "")
        let decorations: Set<Character> = ["+", "#", "!", "?"]
        result.removeAll { decorations.contains($0) }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Renders a principal variation as SAN, e.g. "12. Nf3 Bg4 13. h3".
    public func sanLine(for moves: [Move], includeMoveNumbers: Bool = true) -> String {
        var position = self
        var parts: [String] = []
        for (offset, move) in moves.enumerated() {
            let legal = position.legalMoves
            guard legal.contains(where: { $0 == move }) else { break }
            let text = position.san(for: move, legalMoves: legal)
            if includeMoveNumbers {
                if position.sideToMove == .white {
                    parts.append("\(position.fullmoveNumber). \(text)")
                } else if offset == 0 {
                    parts.append("\(position.fullmoveNumber)... \(text)")
                } else {
                    parts.append(text)
                }
            } else {
                parts.append(text)
            }
            position.make(move)
        }
        return parts.joined(separator: " ")
    }
}
