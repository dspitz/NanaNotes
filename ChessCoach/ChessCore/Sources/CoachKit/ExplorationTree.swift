import Foundation
import ChessKit

/// One node of a "what if" tree: a position reached by a move from its parent.
public struct VariationNode: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// nil at the root, which is the frozen position you branched from.
    public let move: Move?
    public let san: String
    public let position: Position
    public internal(set) var childIDs: [UUID]
    public let parentID: UUID?
    /// Filled in lazily once the coach has graded the move.
    public var review: MoveReview?
    public var coachNote: String?

    /// 0 at the root, 1 for its children, and so on.
    public let depth: Int
}

/// How the sandbox behaves while you explore.
public enum ExplorationMode: String, CaseIterable, Sendable, Identifiable, Hashable {
    /// You move both sides. Nothing answers back.
    case bothSides
    /// You move; the engine replies as the opponent at the chosen strength.
    case versusEngine
    /// You move; the engine replies with the *best* move, so you see the refutation.
    case againstBestPlay

    public var id: String { return rawValue }

    public var displayName: String {
        switch self {
        case .bothSides: return "Move both sides"
        case .versusEngine: return "Opponent replies"
        case .againstBestPlay: return "Play the toughest defence"
        }
    }

    public var summary: String {
        switch self {
        case .bothSides: return "Push the pieces around freely to see how a plan would look."
        case .versusEngine: return "The engine answers at the strength you are playing against."
        case .againstBestPlay: return "The engine always finds the best defence, so nothing works by accident."
        }
    }
}

/// The branching tree behind the "freeze the game and play it out" mode.
///
/// The real game is never touched: the tree owns its own positions, and
/// `anchorPly` remembers where to return to.
public struct ExplorationTree: Sendable {
    public private(set) var nodes: [UUID: VariationNode]
    public let rootID: UUID
    public private(set) var currentID: UUID
    /// Ply index in the real game where the position was frozen.
    public let anchorPly: Int
    /// Which side the player is coaching from inside the sandbox.
    public var perspective: PieceColor
    public var mode: ExplorationMode

    public init(anchor: Position, anchorPly: Int, perspective: PieceColor, mode: ExplorationMode = .againstBestPlay) {
        let root = VariationNode(id: UUID(),
                                 move: nil,
                                 san: "start",
                                 position: anchor,
                                 childIDs: [],
                                 parentID: nil,
                                 review: nil,
                                 coachNote: nil,
                                 depth: 0)
        self.nodes = [root.id: root]
        self.rootID = root.id
        self.currentID = root.id
        self.anchorPly = anchorPly
        self.perspective = perspective
        self.mode = mode
    }

    public var rootPosition: Position {
        return nodes[rootID]?.position ?? .standard
    }

    public var current: VariationNode {
        // The current id always exists; the root is the fallback of last resort.
        return nodes[currentID] ?? nodes[rootID]!
    }

    public var currentPosition: Position {
        return current.position
    }

    public var isAtRoot: Bool {
        return currentID == rootID
    }

    public var canGoBack: Bool {
        return current.parentID != nil
    }

    public var canGoForward: Bool {
        return !current.childIDs.isEmpty
    }

    /// Plays a move from the current node, reusing an existing branch when the
    /// same move has been tried before.
    @discardableResult
    public mutating func play(_ move: Move) -> VariationNode? {
        guard var parent = nodes[currentID] else { return nil }
        let legal = parent.position.legalMoves
        guard legal.contains(where: { $0 == move }) else { return nil }

        if let existing = parent.childIDs.compactMap({ nodes[$0] }).first(where: { $0.move == move }) {
            currentID = existing.id
            return existing
        }

        let san = parent.position.san(for: move, legalMoves: legal)
        var next = parent.position
        next.make(move)
        let node = VariationNode(id: UUID(),
                                 move: move,
                                 san: san,
                                 position: next,
                                 childIDs: [],
                                 parentID: parent.id,
                                 review: nil,
                                 coachNote: nil,
                                 depth: parent.depth + 1)
        nodes[node.id] = node
        parent.childIDs.append(node.id)
        nodes[parent.id] = parent
        currentID = node.id
        return node
    }

    @discardableResult
    public mutating func play(san text: String) -> VariationNode? {
        guard let move = currentPosition.move(san: text) else { return nil }
        return play(move)
    }

    public mutating func goBack() {
        if let parentID = current.parentID { currentID = parentID }
    }

    /// Steps forward along the branch you were last on.
    public mutating func goForward() {
        if let firstChild = current.childIDs.first { currentID = firstChild }
    }

    public mutating func goTo(_ id: UUID) {
        if nodes[id] != nil { currentID = id }
    }

    public mutating func returnToStart() {
        currentID = rootID
    }

    /// Deletes the current branch and steps back to its parent.
    public mutating func deleteCurrentBranch() {
        guard let node = nodes[currentID], let parentID = node.parentID else { return }
        removeSubtree(node.id)
        if var parent = nodes[parentID] {
            parent.childIDs.removeAll { $0 == node.id }
            nodes[parentID] = parent
        }
        currentID = parentID
    }

    private mutating func removeSubtree(_ id: UUID) {
        guard let node = nodes[id] else { return }
        for child in node.childIDs { removeSubtree(child) }
        nodes[id] = nil
    }

    public mutating func annotate(_ id: UUID, review: MoveReview?, note: String?) {
        guard var node = nodes[id] else { return }
        if let review = review { node.review = review }
        if let note = note { node.coachNote = note }
        nodes[id] = node
    }

    /// Root-to-current path, root first, excluding the root itself.
    public var currentLine: [VariationNode] {
        var line: [VariationNode] = []
        var cursor: UUID? = currentID
        while let id = cursor, let node = nodes[id], node.move != nil {
            line.append(node)
            cursor = node.parentID
        }
        return line.reversed()
    }

    public var currentLineSAN: String {
        return rootPosition.sanLine(for: currentLine.compactMap { $0.move })
    }

    /// Every leaf reachable from the root, longest line first. Drives the
    /// "variations you tried" list.
    public var branches: [[VariationNode]] {
        var results: [[VariationNode]] = []
        func walk(_ id: UUID, path: [VariationNode]) {
            guard let node = nodes[id] else { return }
            let extended = node.move == nil ? path : path + [node]
            if node.childIDs.isEmpty {
                if !extended.isEmpty { results.append(extended) }
                return
            }
            for child in node.childIDs { walk(child, path: extended) }
        }
        walk(rootID, path: [])
        return results.sorted { $0.count > $1.count }
    }
}
