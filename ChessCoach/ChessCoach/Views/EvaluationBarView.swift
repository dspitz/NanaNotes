import SwiftUI
import ChessKit
import CoachKit

/// The win-probability bar. Deliberately shows *chances*, not centipawns, as the
/// primary number: "72% to win" means something to a human in a way that
/// "+1.35" does not.
struct EvaluationBarView: View {
    let probability: WinProbability
    let evaluation: Evaluation
    let perspective: PieceColor
    var isStale = false

    private var yourShare: Double {
        return probability.expectedScore(for: perspective)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((probability.chance(for: perspective) * 100).rounded()))%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("to win")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(evaluation.formatted)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Evaluation \(evaluation.formatted) from White's point of view")
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.25))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.coachAccent.opacity(0.9), Theme.coachAccent],
                                             startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: max(4, width * yourShare))
                    // Centre line: anything left of it and you are worse.
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: width / 2)
                }
            }
            .frame(height: 10)
            .animation(.easeInOut(duration: 0.35), value: yourShare)

            HStack(spacing: 10) {
                legend(color: Theme.coachAccent, text: "You \(probability.percentText(for: perspective))")
                legend(color: Color.gray.opacity(0.55), text: "Draw \(Int((probability.draw * 100).rounded()))%")
                legend(color: Color.gray.opacity(0.25), text: "Them \(probability.percentText(for: perspective.opponent))")
                Spacer()
                if isStale {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .opacity(isStale ? 0.65 : 1)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}
