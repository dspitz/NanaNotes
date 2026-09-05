import Foundation
import ChessKit

/// A hint you can peel open one layer at a time, so the coach never spoils the
/// position before you have had a chance to find it yourself.
public struct CoachHint: Sendable, Hashable, Identifiable {
    public enum Depth: Int, Sendable, Hashable, Comparable, CaseIterable {
        /// "Something is wrong with your king."
        case nudge = 0
        /// "Look at the kingside."
        case area = 1
        /// "Look at your knight on f6."
        case piece = 2
        /// "Play Nxe4."
        case move = 3
        /// The full variation and why it works.
        case line = 4

        public static func < (lhs: Depth, rhs: Depth) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        public var label: String {
            switch self {
            case .nudge: return "Nudge"
            case .area: return "Warmer"
            case .piece: return "Which piece"
            case .move: return "The move"
            case .line: return "The whole line"
            }
        }
    }

    public let depth: Depth
    public let text: String
    public let highlightSquares: [Square]

    public var id: Int { return depth.rawValue }
}

/// Everything the coach wants to say about one position.
public struct CoachCommentary: Sendable, Hashable {
    public let headline: String
    public let assessment: String
    /// The main explanation, a few short paragraphs.
    public let paragraphs: [String]
    public let watchOut: [String]
    public let yourPlan: [String]
    public let theirPlan: [String]
    public let hints: [CoachHint]
    public let suggestedMoveSAN: String?

    public var spokenSummary: String {
        return ([headline, assessment] + paragraphs).joined(separator: " ")
    }
}

/// Turns a `PositionReport` into coaching in words.
///
/// Everything here is deterministic and offline: the same position always gets
/// the same explanation, and nothing leaves the device. `CoachCommentary` is a
/// plain value, so a language model can be layered on later to rephrase it
/// without any of the analysis moving off this path.
public struct CoachNarrator: Sendable {
    public var level: CoachLevel

    public init(level: CoachLevel = .improver) {
        self.level = level
    }

    public func commentary(for report: PositionReport) -> CoachCommentary {
        let you = report.perspective
        let headline = self.headline(for: report)
        let assessment = self.assessment(for: report)

        var paragraphs: [String] = []
        paragraphs.append(contentsOf: materialAndStructureParagraphs(for: report))
        if let activity = activityParagraph(for: report) { paragraphs.append(activity) }
        if let candidate = report.bestMove, report.isYourMove {
            paragraphs.append(candidateParagraph(for: candidate, report: report))
        }

        var watchOut: [String] = []
        for loose in report.yourLoosePieces.prefix(2) {
            watchOut.append(loose.description)
        }
        for threat in report.opponentThreats.prefix(2) {
            watchOut.append(threat.detail)
        }
        if Tactics.hasBackRankWeakness(for: you, in: report.position) {
            watchOut.append("Your back rank is loose — a check on the eighth rank could be mate. Consider making luft for the king.")
        }

        return CoachCommentary(
            headline: headline,
            assessment: assessment,
            paragraphs: paragraphs,
            watchOut: watchOut,
            yourPlan: report.yourPlans.prefix(3).map { "\($0.title): \($0.detail)" },
            theirPlan: report.theirPlans.prefix(2).map { "\($0.title): \($0.detail)" },
            hints: hints(for: report),
            suggestedMoveSAN: report.isYourMove ? report.bestMove?.san : nil
        )
    }

    // MARK: - Pieces of the commentary

    private func headline(for report: PositionReport) -> String {
        let you = report.perspective
        let evaluation = report.evaluation
        if let mate = evaluation.mateInMoves {
            let yours = (mate > 0) == (you == .white)
            return yours ? "You have mate in \(abs(mate))." : "You are being mated in \(abs(mate))."
        }
        let chance = report.winProbability.chance(for: you)
        let percent = Int((chance * 100).rounded())
        return "\(evaluation.descriptor(for: you)) — about \(percent)% to win from here."
    }

    private func assessment(for report: PositionReport) -> String {
        let phase = report.phase.displayName.lowercased()
        let depth = report.searchDepth
        let terms = report.breakdown.rankedPositionalTerms.prefix(2)
        guard !terms.isEmpty else {
            return "A quiet \(phase) position; nothing is decided yet (searched \(depth) ply deep)."
        }
        let described = terms.map { term -> String in
            let owner: PieceColor = term.value > 0 ? .white : .black
            let side = owner == report.perspective ? "you" : "them"
            return "\(term.name.lowercased()) favours \(side)"
        }
        return "In this \(phase), \(described.joined(separator: ", and ")). (Depth \(depth).)"
    }

    private func materialAndStructureParagraphs(for report: PositionReport) -> [String] {
        var paragraphs: [String] = []

        if abs(report.materialBalance) >= 100 {
            let text = PositionAnalyzer.materialText(abs(report.materialBalance))
            paragraphs.append(report.materialBalance > 0
                ? "You are up \(text). That is not a reason to relax — it is a reason to trade pieces and simplify towards an endgame."
                : "You are down \(text). Keep pieces on, avoid straight trades, and look for the sharpest continuation that gives them a chance to go wrong.")
        }

        let themes = report.themes.prefix(level == .newcomer ? 2 : 3)
        for theme in themes {
            let owner = theme.favours
            let attribution: String
            if owner == report.perspective {
                attribution = "In your favour: "
            } else if owner == report.perspective.opponent {
                attribution = "In their favour: "
            } else {
                attribution = ""
            }
            paragraphs.append(attribution + theme.title + ". " + theme.detail)
        }
        return paragraphs
    }

    private func activityParagraph(for report: PositionReport) -> String? {
        let mine = report.features.side(report.perspective)
        let theirs = report.features.side(report.perspective.opponent)
        let difference = mine.totalMobility - theirs.totalMobility
        guard abs(difference) >= 6 else { return nil }
        if difference > 0 {
            return "Your pieces have \(difference) more available squares than theirs. Activity like that is temporary — use it before they untangle."
        }
        return "Their pieces cover \(abs(difference)) more squares than yours. Before you attack anything, get your pieces breathing: find the one with the fewest squares and improve it."
    }

    private func candidateParagraph(for candidate: CandidateMove, report: PositionReport) -> String {
        let alternatives = report.candidateMoves.dropFirst().prefix(2)
        var text = "The engine's first choice is \(candidate.san). \(candidate.rationale)"
        if level != .newcomer, !candidate.lineSAN.isEmpty {
            let clipped = Self.clip(line: candidate.lineSAN, plies: level.maximumLineLength)
            text += " It expects \(clipped)."
        }
        if !alternatives.isEmpty {
            let described = alternatives.map { "\($0.san) (\(Self.signedPawns($0.centipawnsBehindBest)))" }
            text += " Also playable: \(described.joined(separator: ", "))."
        }
        return text
    }

    // MARK: - Hints

    public func hints(for report: PositionReport) -> [CoachHint] {
        guard report.isYourMove, let best = report.bestMove else { return [] }
        var hints: [CoachHint] = []

        // 1. What kind of move is called for?
        let nudge: String
        if let threat = report.opponentThreats.first, threat.isCritical {
            nudge = "You are being threatened. Find the move that deals with it before you do anything constructive."
        } else if !report.theirLoosePieces.isEmpty {
            nudge = "Something of theirs is loose. Count attackers and defenders across the whole board."
        } else if best.motifs.contains(where: { if case .forcedMate = $0 { return true } else { return false } }) {
            nudge = "There is a forcing sequence here. Look at every check and capture."
        } else if let plan = report.yourPlans.first {
            nudge = "No fireworks needed. \(plan.title): \(plan.detail)"
        } else {
            nudge = "Improve your worst-placed piece and keep an eye on their ideas."
        }
        hints.append(CoachHint(depth: .nudge, text: nudge, highlightSquares: []))

        // 2. Where on the board?
        let area = Self.areaName(for: best.move.to)
        hints.append(CoachHint(depth: .area,
                               text: "The move you want is on the \(area).",
                               highlightSquares: report.opponentThreats.first?.squares ?? []))

        // 3. Which piece?
        if let piece = report.position.piece(at: best.move.from) {
            hints.append(CoachHint(depth: .piece,
                                   text: "It is your \(piece.kind.name) on \(best.move.from.name) that wants to move.",
                                   highlightSquares: [best.move.from]))
        }

        // 4. The move.
        hints.append(CoachHint(depth: .move,
                               text: "Play \(best.san). \(best.rationale)",
                               highlightSquares: [best.move.from, best.move.to]))

        // 5. The whole line.
        if !best.lineSAN.isEmpty {
            hints.append(CoachHint(depth: .line,
                                   text: "\(best.san) and then \(Self.clip(line: best.lineSAN, plies: 8)). Evaluation after the line: \(best.evaluation.formatted) (White's point of view).",
                                   highlightSquares: best.line.flatMap { [$0.from, $0.to] }))
        }
        return hints
    }

    // MARK: - Formatting helpers

    static func areaName(for square: Square) -> String {
        if square.file <= 2 { return "queenside" }
        if square.file >= 5 { return "kingside" }
        return "centre"
    }

    static func signedPawns(_ centipawnsBehind: Int) -> String {
        if centipawnsBehind == 0 { return "equal" }
        return String(format: "\u{2212}%.2f", Double(centipawnsBehind) / 100.0)
    }

    /// Trims a SAN variation to a readable number of plies.
    static func clip(line: String, plies: Int) -> String {
        let tokens = line.split(separator: " ").map(String.init)
        var kept: [String] = []
        var moveCount = 0
        for token in tokens {
            kept.append(token)
            if !token.hasSuffix(".") && !token.hasSuffix("...") {
                moveCount += 1
            }
            if moveCount >= plies { break }
        }
        return kept.joined(separator: " ")
    }
}
