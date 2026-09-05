import SwiftUI
import ChessKit
import CoachKit

struct MoveListView: View {
    let game: Game
    let review: GameReview?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(game.movePairs) { pair in
                        HStack(spacing: 6) {
                            Text("\(pair.number).")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            if let white = pair.white {
                                moveChip(white)
                            }
                            if let black = pair.black {
                                moveChip(black)
                            }
                        }
                        .id(pair.number)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: game.ply) { _ in
                withAnimation {
                    proxy.scrollTo(game.movePairs.last?.number, anchor: .trailing)
                }
            }
        }
        .frame(height: 30)
    }

    private func moveChip(_ record: MoveRecord) -> some View {
        let match = review?.reviews.first(where: { $0.move == record.move && $0.moveNumber == record.moveNumber && $0.color == record.color })
        let quality = match?.quality
        return Text(record.san + (quality?.symbol ?? ""))
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(quality.map { Theme.color(for: $0.panelColor) } ?? Color.primary)
    }
}
