import SwiftUI
import ChessKit
import CoachKit

/// Maps squares to points for a board of a given size and orientation.
struct BoardGeometry {
    let size: CGFloat
    let orientation: PieceColor

    var squareSize: CGFloat { return size / 8 }

    /// Column/row on screen, 0-indexed from the top-left corner.
    func displayCoordinates(for square: Square) -> (column: Int, row: Int) {
        let column = orientation == .white ? square.file : 7 - square.file
        let row = orientation == .white ? 7 - square.rank : square.rank
        return (column, row)
    }

    func center(of square: Square) -> CGPoint {
        let coordinates = displayCoordinates(for: square)
        return CGPoint(x: (CGFloat(coordinates.column) + 0.5) * squareSize,
                       y: (CGFloat(coordinates.row) + 0.5) * squareSize)
    }

    /// The squares in the order they should be laid out, row by row.
    var orderedSquares: [[Square]] {
        let files = orientation == .white ? Array(0..<8) : Array((0..<8).reversed())
        let ranks = orientation == .white ? Array((0..<8).reversed()) : Array(0..<8)
        return ranks.map { rank in
            files.compactMap { file in Square(file: file, rank: rank) }
        }
    }
}

struct BoardView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = BoardGeometry(size: side, orientation: viewModel.boardOrientation)

            ZStack(alignment: .topLeading) {
                squares(geometry: geometry)
                pieces(geometry: geometry)
                coachArrow(geometry: geometry)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(viewModel.isExploring ? Theme.sandbox : Theme.boardBorder,
                            lineWidth: viewModel.isExploring ? 3 : 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Layers

    private func squares(geometry: BoardGeometry) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(geometry.orderedSquares.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.index) { square in
                        SquareView(square: square,
                                   size: geometry.squareSize,
                                   state: state(for: square),
                                   showsFileLabel: showsFileLabel(square),
                                   showsRankLabel: showsRankLabel(square))
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.tap(square) }
                    }
                }
            }
        }
    }

    private func pieces(geometry: BoardGeometry) -> some View {
        let position = viewModel.activePosition
        return ForEach(Square.all, id: \.index) { square in
            if let piece = position.piece(at: square) {
                PieceView(piece: piece, size: geometry.squareSize)
                    .position(geometry.center(of: square))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    /// The coach's suggested move, drawn as an arrow once you have asked for it.
    @ViewBuilder
    private func coachArrow(geometry: BoardGeometry) -> some View {
        if viewModel.showCoachHighlights,
           viewModel.revealedHints.contains(where: { $0.depth >= .move }),
           let move = viewModel.report?.bestMove?.move {
            ArrowShape(start: geometry.center(of: move.from),
                       end: geometry.center(of: move.to),
                       thickness: geometry.squareSize * 0.16)
                .fill(Theme.coachAccent.opacity(0.75))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Square state

    private func state(for square: Square) -> SquareView.Highlights {
        var state = SquareView.Highlights()
        state.isSelected = viewModel.selectedSquare == square
        state.isDestination = viewModel.destinationSquares.contains(square)
        state.isCaptureTarget = state.isDestination && viewModel.activePosition.piece(at: square) != nil
        if let move = viewModel.lastMove {
            state.isLastMove = move.from == square || move.to == square
        }
        state.isCheck = viewModel.checkedKingSquare == square
        state.isCoachHighlighted = viewModel.showCoachHighlights && viewModel.coachHighlights.contains(square)
        return state
    }

    private func showsFileLabel(_ square: Square) -> Bool {
        return viewModel.boardOrientation == .white ? square.rank == 0 : square.rank == 7
    }

    private func showsRankLabel(_ square: Square) -> Bool {
        return viewModel.boardOrientation == .white ? square.file == 0 : square.file == 7
    }
}

struct SquareView: View {
    struct Highlights {
        var isSelected = false
        var isDestination = false
        var isCaptureTarget = false
        var isLastMove = false
        var isCheck = false
        var isCoachHighlighted = false
    }

    let square: Square
    let size: CGFloat
    let state: Highlights
    let showsFileLabel: Bool
    let showsRankLabel: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(square.isLight ? Theme.lightSquare : Theme.darkSquare)

            if state.isLastMove {
                Rectangle().fill(Theme.lastMove.opacity(0.45))
            }
            if state.isSelected {
                Rectangle().fill(Theme.selection.opacity(0.55))
            }
            if state.isCheck {
                RadialGradient(colors: [Theme.checkGlow.opacity(0.85), Theme.checkGlow.opacity(0.0)],
                               center: .center,
                               startRadius: 0,
                               endRadius: size * 0.6)
            }
            if state.isCoachHighlighted {
                Rectangle()
                    .stroke(Theme.coachAccent, lineWidth: max(2, size * 0.06))
            }
            if state.isDestination {
                if state.isCaptureTarget {
                    Circle()
                        .stroke(Color.black.opacity(0.35), lineWidth: max(3, size * 0.09))
                        .padding(size * 0.06)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: size * 0.28, height: size * 0.28)
                }
            }

            labels
        }
        .frame(width: size, height: size)
    }

    private var labels: some View {
        ZStack {
            if showsRankLabel {
                Text("\(square.rank + 1)")
                    .font(.system(size: max(8, size * 0.20), weight: .semibold))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(size * 0.05)
            }
            if showsFileLabel {
                Text(square.fileName)
                    .font(.system(size: max(8, size * 0.20), weight: .semibold))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(size * 0.05)
            }
        }
    }

    private var labelColor: Color {
        return square.isLight ? Theme.darkSquare : Theme.lightSquare
    }
}

/// Pieces are drawn with the solid Unicode glyphs for both colours, tinted and
/// outlined, so White and Black read the same shape at any size.
struct PieceView: View {
    let piece: Piece
    let size: CGFloat

    private var glyph: String {
        return Piece(.black, piece.kind).unicodeSymbol
    }

    var body: some View {
        Text(glyph)
            .font(.system(size: size * 0.78))
            .foregroundStyle(piece.color == .white ? Color.white : Color(white: 0.10))
            .shadow(color: piece.color == .white ? Color.black.opacity(0.65) : Color.white.opacity(0.35),
                    radius: 0.6, x: 0.5, y: 0.5)
            .shadow(color: piece.color == .white ? Color.black.opacity(0.65) : Color.white.opacity(0.35),
                    radius: 0.6, x: -0.5, y: -0.5)
            .shadow(color: Color.black.opacity(0.25), radius: size * 0.04, x: 0, y: size * 0.02)
            .frame(width: size, height: size)
    }
}

/// A simple arrow from one square centre to another.
struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let unit = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)

        let headLength = min(length * 0.45, thickness * 2.4)
        let headWidth = thickness * 2.2
        let shaftEnd = CGPoint(x: end.x - unit.x * headLength, y: end.y - unit.y * headLength)
        let half = thickness / 2

        path.move(to: CGPoint(x: start.x + normal.x * half, y: start.y + normal.y * half))
        path.addLine(to: CGPoint(x: shaftEnd.x + normal.x * half, y: shaftEnd.y + normal.y * half))
        path.addLine(to: CGPoint(x: shaftEnd.x + normal.x * headWidth, y: shaftEnd.y + normal.y * headWidth))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: shaftEnd.x - normal.x * headWidth, y: shaftEnd.y - normal.y * headWidth))
        path.addLine(to: CGPoint(x: shaftEnd.x - normal.x * half, y: shaftEnd.y - normal.y * half))
        path.addLine(to: CGPoint(x: start.x - normal.x * half, y: start.y - normal.y * half))
        path.closeSubpath()
        return path
    }
}
