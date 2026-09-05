import Foundation
import ChessKit

/// A position assessment: centipawns, or a forced mate.
///
/// Always stored from White's point of view, the way engines and books quote it.
/// Ask for `advantage(for:)` when you need it from a player's side.
public struct Evaluation: Hashable, Sendable {
    /// Positive means White is better. Clamped to +/- 10000 when mate is forced.
    public let centipawns: Int
    /// Positive means White mates in this many moves; negative means Black does.
    public let mateInMoves: Int?

    public init(centipawns: Int, mateInMoves: Int? = nil) {
        self.centipawns = centipawns
        self.mateInMoves = mateInMoves
    }

    public static let equal = Evaluation(centipawns: 0)

    public var isMate: Bool { return mateInMoves != nil }

    /// Score in pawns, e.g. 1.25.
    public var pawns: Double { return Double(centipawns) / 100.0 }

    /// White-relative text in the usual "+0.83" / "M4" style.
    public var formatted: String {
        if let mate = mateInMoves {
            return mate > 0 ? "M\(mate)" : "-M\(abs(mate))"
        }
        let value = pawns
        let sign = value > 0 ? "+" : (value < 0 ? "\u{2212}" : "")
        return sign + String(format: "%.2f", abs(value))
    }

    /// The same score flipped into `color`'s frame: positive is always good for them.
    public func advantage(for color: PieceColor) -> Evaluation {
        return Evaluation(centipawns: centipawns * color.sign, mateInMoves: mateInMoves.map { $0 * color.sign })
    }

    /// Coarse verbal label, the vocabulary a coach uses out loud.
    public var descriptor: String {
        if let mate = mateInMoves {
            return mate > 0 ? "White has forced mate" : "Black has forced mate"
        }
        let magnitude = abs(centipawns)
        let leader = centipawns > 0 ? "White" : "Black"
        switch magnitude {
        case 0..<30: return "Level"
        case 30..<80: return "\(leader) is slightly better"
        case 80..<160: return "\(leader) is clearly better"
        case 160..<300: return "\(leader) has a large advantage"
        case 300..<600: return "\(leader) is winning"
        default: return "\(leader) is completely winning"
        }
    }

    /// How much better `color` is, as a short phrase.
    public func descriptor(for color: PieceColor) -> String {
        if let mate = mateInMoves {
            let mateIsForUs = (mate > 0) == (color == .white)
            return mateIsForUs ? "You have forced mate" : "You are getting mated"
        }
        let relative = centipawns * color.sign
        switch relative {
        case ..<(-600): return "You are completely lost"
        case (-600)..<(-300): return "You are losing"
        case (-300)..<(-160): return "You are much worse"
        case (-160)..<(-80): return "You are clearly worse"
        case (-80)..<(-30): return "You are slightly worse"
        case (-30)..<30: return "The game is balanced"
        case 30..<80: return "You are slightly better"
        case 80..<160: return "You are clearly better"
        case 160..<300: return "You have a large advantage"
        case 300..<600: return "You are winning"
        default: return "You are completely winning"
        }
    }
}

/// Win / draw / loss shares, all from White's point of view and summing to 1.
public struct WinProbability: Hashable, Sendable {
    public let white: Double
    public let draw: Double
    public let black: Double

    public init(white: Double, draw: Double, black: Double) {
        self.white = white
        self.draw = draw
        self.black = black
    }

    public func chance(for color: PieceColor) -> Double {
        return color == .white ? white : black
    }

    /// Expected score for `color`, counting a draw as half a point.
    public func expectedScore(for color: PieceColor) -> Double {
        return chance(for: color) + draw / 2.0
    }

    public func percentText(for color: PieceColor) -> String {
        return "\(Int((chance(for: color) * 100).rounded()))%"
    }

    /// Maps an evaluation onto win/draw/loss shares.
    ///
    /// The win curve is the logistic fit Lichess uses for its evaluation bar; the
    /// draw share is widest when the game is level and narrows as one side pulls
    /// ahead, and is stretched in the endgame where level positions peter out.
    public static func from(evaluation: Evaluation, phase: GamePhase = .middlegame) -> WinProbability {
        if let mate = evaluation.mateInMoves {
            return mate > 0
                ? WinProbability(white: 1.0, draw: 0.0, black: 0.0)
                : WinProbability(white: 0.0, draw: 0.0, black: 1.0)
        }

        let centipawns = Double(max(-2000, min(2000, evaluation.centipawns)))
        let expectedWhiteScore = 1.0 / (1.0 + exp(-0.00368208 * centipawns))

        let maximumDraw: Double
        switch phase {
        case .opening: maximumDraw = 0.40
        case .middlegame: maximumDraw = 0.36
        case .endgame: maximumDraw = 0.52
        }
        let spread = centipawns / 320.0
        var draw = maximumDraw * exp(-spread * spread)

        var white = expectedWhiteScore - draw / 2.0
        var black = 1.0 - expectedWhiteScore - draw / 2.0
        if white < 0 {
            draw += white
            white = 0
        }
        if black < 0 {
            draw += black
            black = 0
        }
        draw = max(0, draw)
        let total = white + draw + black
        guard total > 0 else { return WinProbability(white: 0.5, draw: 0.0, black: 0.5) }
        return WinProbability(white: white / total, draw: draw / total, black: black / total)
    }
}
