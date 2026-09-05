import Foundation
import ChessKit

/// A piece the opponent can profitably take.
public struct HangingPiece: Sendable, Hashable, Identifiable {
    public let square: Square
    public let piece: Piece
    /// Centipawns lost if the exchange plays out with best captures on both sides.
    public let materialAtRisk: Int
    public let attackers: [Square]
    public let defenders: [Square]

    public var id: Int { return square.index }
    public var isUndefended: Bool { return defenders.isEmpty }

    public var description: String {
        if isUndefended {
            return "Your \(piece.kind.name) on \(square.name) is undefended and attacked."
        }
        return "Your \(piece.kind.name) on \(square.name) loses material if the pieces come off (\(materialAtRisk) centipawns)."
    }
}

/// Named tactical patterns. The coach turns these into sentences; the analyser
/// uses them to decide what is worth mentioning at all.
public enum TacticalMotif: Sendable, Hashable {
    case fork(by: Square, piece: PieceKind, targets: [Square])
    case pin(pinned: Square, by: Square, against: Square)
    case skewer(front: Square, by: Square, behind: Square)
    case discoveredAttack(by: Square, target: Square)
    case hangingPiece(square: Square, piece: PieceKind)
    case backRankWeakness(color: PieceColor)
    case forcedMate(inMoves: Int)
    case passedPawnRun(square: Square)

    public var headline: String {
        switch self {
        case .fork(let by, let piece, let targets):
            let list = targets.map { $0.name }.joined(separator: " and ")
            return "\(piece.name.capitalized) on \(by.name) forks \(list)"
        case .pin(let pinned, let by, let against):
            return "Piece on \(pinned.name) is pinned by \(by.name) against \(against.name)"
        case .skewer(let front, let by, let behind):
            return "\(by.name) skewers \(front.name) and \(behind.name)"
        case .discoveredAttack(let by, let target):
            return "Discovered attack from \(by.name) onto \(target.name)"
        case .hangingPiece(let square, let piece):
            return "\(piece.name.capitalized) on \(square.name) is hanging"
        case .backRankWeakness(let color):
            return "\(color.name)'s back rank is weak"
        case .forcedMate(let moves):
            return "Forced mate in \(moves)"
        case .passedPawnRun(let square):
            return "Passed pawn on \(square.name) is ready to run"
        }
    }

    /// Rough importance, used to decide what the coach leads with.
    public var weight: Int {
        switch self {
        case .forcedMate: return 100
        case .fork: return 70
        case .skewer: return 60
        case .pin: return 50
        case .discoveredAttack: return 55
        case .hangingPiece: return 65
        case .backRankWeakness: return 40
        case .passedPawnRun: return 35
        }
    }
}

/// Static tactical inspection of a position. No search — these are the things
/// you should be able to see by looking.
public enum Tactics {
    // MARK: - Static exchange evaluation

    /// Material `side` wins by starting a capture sequence on `target`,
    /// assuming both sides always recapture with their least valuable piece.
    ///
    /// Re-querying the attackers after every capture means x-ray attackers
    /// (a rook behind a rook, a queen behind a bishop) are handled for free.
    public static func exchangeGain(on target: Square, initiatedBy side: PieceColor, in position: Position) -> Int {
        guard let victim = position.piece(at: target), victim.color != side else { return 0 }
        var working = position
        if working.sideToMove != side {
            _ = working.makeNullMove()
        }
        return recursiveGain(on: target, in: &working)
    }

    private static func recursiveGain(on target: Square, in position: inout Position) -> Int {
        guard let victim = position.piece(at: target) else { return 0 }
        let side = position.sideToMove
        guard victim.color != side else { return 0 }

        let attackerSquares = position.attackers(of: target, by: side).sorted {
            (position.piece(at: $0)?.kind.value ?? 0) < (position.piece(at: $1)?.kind.value ?? 0)
        }

        for from in attackerSquares {
            let promotesHere = position.piece(at: from)?.kind == .pawn && target.rank == side.promotionRank
            guard let move = position.legalMove(from: from, to: target, promotion: promotesHere ? .queen : nil) else {
                continue   // Pinned attacker: try the next cheapest one.
            }
            let undo = position.make(move)
            let gain = victim.kind.value - recursiveGain(on: target, in: &position)
            position.unmake(undo)
            // Captures are optional: nobody starts a losing exchange.
            return max(0, gain)
        }
        return 0
    }

    // MARK: - Loose pieces

    /// Pieces of `color` the opponent can win material from right now.
    public static func hangingPieces(for color: PieceColor, in position: Position) -> [HangingPiece] {
        var result: [HangingPiece] = []
        for square in position.squares(of: color) {
            guard let piece = position.piece(at: square), piece.kind != .king else { continue }
            let attackers = position.attackers(of: square, by: color.opponent)
            guard !attackers.isEmpty else { continue }
            let defenders = position.attackers(of: square, by: color)
            let risk = exchangeGain(on: square, initiatedBy: color.opponent, in: position)
            guard risk > 0 else { continue }
            result.append(HangingPiece(square: square, piece: piece, materialAtRisk: risk, attackers: attackers, defenders: defenders))
        }
        return result.sorted { $0.materialAtRisk > $1.materialAtRisk }
    }

    // MARK: - Patterns

    /// Motifs that exist in `position` for `color`, ignoring whose turn it is.
    public static func motifs(for color: PieceColor, in position: Position) -> [TacticalMotif] {
        var motifs: [TacticalMotif] = []
        motifs.append(contentsOf: alignmentMotifs(for: color, in: position))
        for hanging in hangingPieces(for: color.opponent, in: position) where hanging.materialAtRisk >= 100 {
            motifs.append(.hangingPiece(square: hanging.square, piece: hanging.piece.kind))
        }
        if hasBackRankWeakness(for: color.opponent, in: position) {
            motifs.append(.backRankWeakness(color: color.opponent))
        }
        for square in position.squares(of: color, kind: .pawn) where isPassedAndRunning(square, color: color, in: position) {
            motifs.append(.passedPawnRun(square: square))
        }
        return motifs.sorted { $0.weight > $1.weight }
    }

    /// Motifs `move` creates. Used to explain why the engine likes a move.
    public static func motifs(createdBy move: Move, in position: Position) -> [TacticalMotif] {
        let mover = position.sideToMove
        var after = position
        after.make(move)

        var motifs: [TacticalMotif] = []

        if after.isCheckmate {
            motifs.append(.forcedMate(inMoves: 1))
        }

        // Fork: the piece that just moved now hits two things worth hitting.
        if let piece = after.piece(at: move.to) {
            let targets = attackedTargetsWorthTaking(from: move.to, piece: piece, in: after)
            if targets.count >= 2 {
                motifs.append(.fork(by: move.to, piece: piece.kind, targets: targets))
            }
        }

        // Discovered attack: some other friendly piece gained a target.
        let before = threatenedSquares(for: mover, in: position, excluding: move.from)
        let now = threatenedSquares(for: mover, in: after, excluding: move.to)
        for (attacker, target) in now where !before.contains(where: { $0 == (attacker, target) }) {
            if attacker != move.to {
                motifs.append(.discoveredAttack(by: attacker, target: target))
            }
        }

        motifs.append(contentsOf: alignmentMotifs(for: mover, in: after))
        return Array(Set(motifs)).sorted { $0.weight > $1.weight }
    }

    /// Pins and skewers: two enemy pieces lined up on one of our sliders' rays.
    public static func alignmentMotifs(for color: PieceColor, in position: Position) -> [TacticalMotif] {
        var motifs: [TacticalMotif] = []
        for square in position.squares(of: color) {
            guard let piece = position.piece(at: square), piece.kind.isSlider else { continue }
            let directions: [Int]
            switch piece.kind {
            case .bishop: directions = Position.bishopDirections
            case .rook: directions = Position.rookDirections
            default: directions = Position.queenDirections
            }
            for direction in directions {
                guard let (front, behind) = firstTwoPieces(from: square, direction: direction, in: position) else { continue }
                guard let frontPiece = position.piece(at: front), let behindPiece = position.piece(at: behind) else { continue }
                guard frontPiece.color == color.opponent, behindPiece.color == color.opponent else { continue }
                if behindPiece.kind == .king || behindPiece.kind.value > frontPiece.kind.value {
                    motifs.append(.pin(pinned: front, by: square, against: behind))
                } else if frontPiece.kind.value > behindPiece.kind.value {
                    motifs.append(.skewer(front: front, by: square, behind: behind))
                }
            }
        }
        return motifs
    }

    public static func hasBackRankWeakness(for color: PieceColor, in position: Position) -> Bool {
        guard let king = position.kingSquare(of: color) else { return false }
        guard king.rank == color.backRank else { return false }
        // Every escape square in front of the king blocked by its own pawns.
        var escapeSquares = 0
        var blocked = 0
        for fileOffset in -1...1 {
            guard let square = king.offset(file: fileOffset, rank: color.pawnDirection) else { continue }
            escapeSquares += 1
            if let piece = position.piece(at: square), piece.color == color {
                blocked += 1
            }
        }
        guard escapeSquares > 0, blocked == escapeSquares else { return false }
        // Only a real weakness if the opponent still has a rook or queen.
        let heavyPieces = position.count(of: color.opponent, kind: .rook) + position.count(of: color.opponent, kind: .queen)
        return heavyPieces > 0
    }

    // MARK: - Helpers

    private static func isPassedAndRunning(_ square: Square, color: PieceColor, in position: Position) -> Bool {
        guard square.relativeRank(for: color) >= 4 else { return false }
        for file in max(0, square.file - 1)...min(7, square.file + 1) {
            for rank in 0..<8 {
                guard let candidate = Square(file: file, rank: rank),
                      let piece = position.piece(at: candidate),
                      piece.color == color.opponent, piece.kind == .pawn else { continue }
                if candidate.relativeRank(for: color) > square.relativeRank(for: color) { return false }
            }
        }
        return true
    }

    private static func firstTwoPieces(from square: Square, direction: Int, in position: Position) -> (Square, Square)? {
        var found: [Square] = []
        var index = square.index + direction
        while Square.isValidIndex(index) {
            let candidate = Square(unchecked: index)
            if position.piece(at: candidate) != nil {
                found.append(candidate)
                if found.count == 2 { return (found[0], found[1]) }
            }
            index += direction
        }
        return nil
    }

    /// Enemy pieces attacked from `square` that are worth attacking: the king,
    /// anything more valuable than the attacker, or anything undefended.
    private static func attackedTargetsWorthTaking(from square: Square, piece: Piece, in position: Position) -> [Square] {
        var targets: [Square] = []
        for candidate in position.squares(of: piece.color.opponent) {
            guard position.attackers(of: candidate, by: piece.color).contains(square) else { continue }
            guard let target = position.piece(at: candidate) else { continue }
            if target.kind == .king {
                targets.append(candidate)
            } else if target.kind.value > piece.kind.value {
                targets.append(candidate)
            } else if position.attackers(of: candidate, by: piece.color.opponent).isEmpty {
                targets.append(candidate)
            }
        }
        return targets
    }

    private static func threatenedSquares(for color: PieceColor, in position: Position, excluding: Square?) -> [(Square, Square)] {
        var pairs: [(Square, Square)] = []
        for target in position.squares(of: color.opponent) {
            guard let piece = position.piece(at: target), piece.kind.value >= PieceKind.knight.value else { continue }
            for attacker in position.attackers(of: target, by: color) {
                guard attacker != excluding else { continue }
                guard let attackingPiece = position.piece(at: attacker), attackingPiece.kind.isSlider else { continue }
                pairs.append((attacker, target))
            }
        }
        return pairs
    }
}
