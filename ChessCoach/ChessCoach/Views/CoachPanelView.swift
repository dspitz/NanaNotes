import SwiftUI
import ChessKit
import CoachKit

/// The coach. Everything it says is grounded in the numbers on the left of the
/// screen, and the hint ladder means it never blurts out the move unless asked.
struct CoachPanelView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                EvaluationBarView(probability: viewModel.winProbability,
                                  evaluation: viewModel.evaluation,
                                  perspective: viewModel.playerColor,
                                  isStale: viewModel.isAnalyzing)
                    .coachCard()

                if let review = viewModel.lastReview {
                    moveReviewCard(review)
                }

                if let commentary = viewModel.commentary {
                    assessmentCard(commentary)
                    if !commentary.watchOut.isEmpty {
                        watchOutCard(commentary)
                    }
                    hintCard(commentary)
                    plansCard(commentary)
                }

                if let report = viewModel.report, !report.candidateMoves.isEmpty {
                    candidatesCard(report)
                }

                if let report = viewModel.report, !report.themes.isEmpty {
                    themesCard(report)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Cards

    private func assessmentCard(_ commentary: CoachCommentary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Where the game stands", systemImage: "scope")
            Text(commentary.headline)
                .font(.headline)
            Text(commentary.assessment)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(commentary.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func watchOutCard(_ commentary: CoachCommentary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("What they are up to", systemImage: "exclamationmark.triangle")
            ForEach(Array(commentary.watchOut.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Theme.color(for: index == 0 ? .mistake : .inaccuracy))
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(item)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let threat = viewModel.report?.opponentThreats.first, !threat.squares.isEmpty {
                Button {
                    viewModel.highlight(threat.squares)
                } label: {
                    Label("Show me on the board", systemImage: "eye")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func hintCard(_ commentary: CoachCommentary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Need a hand?", systemImage: "lightbulb")

            if viewModel.revealedHints.isEmpty {
                Text("Ask for a nudge first. Each tap tells you a little more, so you still get to find the move yourself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(viewModel.revealedHints) { hint in
                VStack(alignment: .leading, spacing: 3) {
                    Text(hint.depth.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.coachAccent)
                    Text(hint.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.coachAccent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack {
                Button {
                    viewModel.revealNextHint()
                } label: {
                    Label(viewModel.revealedHints.isEmpty ? "Give me a nudge" : "Tell me more",
                          systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasMoreHints || commentary.hints.isEmpty)

                if !viewModel.revealedHints.isEmpty {
                    Button("Hide") { viewModel.hideHints() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func plansCard(_ commentary: CoachCommentary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Plans", systemImage: "map")
            if !commentary.yourPlan.isEmpty {
                Text("Your plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(commentary.yourPlan.enumerated()), id: \.offset) { index, plan in
                    planRow(plan, index: index, squares: viewModel.report?.yourPlans[safe: index]?.squares ?? [])
                }
            }
            if !commentary.theirPlan.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Their plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(commentary.theirPlan.enumerated()), id: \.offset) { index, plan in
                    planRow(plan, index: index, squares: viewModel.report?.theirPlans[safe: index]?.squares ?? [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func planRow(_ text: String, index: Int, squares: [Square]) -> some View {
        Button {
            viewModel.highlight(squares)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Theme.panelStroke))
                Text(text)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(squares.isEmpty)
    }

    private func candidatesCard(_ report: PositionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Moves worth considering", systemImage: "arrow.triangle.branch")
            ForEach(report.candidateMoves) { candidate in
                Button {
                    viewModel.highlight([candidate.move.from, candidate.move.to])
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(candidate.san)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .frame(minWidth: 54, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.rationale)
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if !candidate.lineSAN.isEmpty {
                                Text(candidate.lineSAN)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(candidate.isBest ? "best" : "\u{2212}\(String(format: "%.2f", Double(candidate.centipawnsBehindBest) / 100))")
                            .font(.caption.monospaced())
                            .foregroundStyle(candidate.isBest ? Theme.color(for: .great) : .secondary)
                    }
                }
                .buttonStyle(.plain)
                if candidate.id != report.candidateMoves.last?.id {
                    Divider()
                }
            }
            Text("Depth \(report.searchDepth), \(report.nodes.formattedNodeCount) positions looked at.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func themesCard(_ report: PositionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("What matters here", systemImage: "square.stack.3d.up")
            ForEach(report.themes.prefix(5)) { theme in
                Button {
                    viewModel.highlight(theme.squares)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForOwner(theme.favours))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.title)
                                .font(.callout.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Text(theme.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func moveReviewCard(_ review: MoveReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(review.quality.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.color(for: review.quality.panelColor).opacity(0.20),
                                in: Capsule())
                    .foregroundStyle(Theme.color(for: review.quality.panelColor))
                Text("\(review.moveNumber)\(review.color == .white ? "." : "...") \(review.san)")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Spacer()
            }
            Text(review.explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func colorForOwner(_ color: PieceColor?) -> Color {
        guard let color = color else { return Theme.panelStroke }
        return color == viewModel.playerColor ? Theme.color(for: .great) : Theme.color(for: .mistake)
    }
}

extension MoveQuality {
    var panelColor: MoveQualityColor {
        switch self {
        case .brilliant, .best: return .great
        case .excellent, .good: return .fine
        case .inaccuracy: return .inaccuracy
        case .mistake: return .mistake
        case .blunder: return .blunder
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Int {
    var formattedNodeCount: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.0fk", Double(self) / 1_000) }
        return "\(self)"
    }
}
