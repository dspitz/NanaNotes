import SwiftUI
import ChessKit
import CoachKit

/// The controls that appear when the game is frozen and you are playing a
/// position out. The purple frame around the board is the other half of this:
/// you should never be in any doubt about whether moves are "real".
struct SandboxBarView: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flask")
                    .foregroundStyle(Theme.sandbox)
                Text("Sandbox")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.sandbox)
                Spacer()
                Button {
                    viewModel.exitExploration()
                } label: {
                    Label("Back to the game", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.sandbox)
            }

            Text("Nothing here counts. Play the position out, see what happens, then step back into the real game exactly where you left it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Opponent", selection: Binding(
                get: { viewModel.explorationMode },
                set: { viewModel.setExplorationMode($0) }
            )) {
                ForEach(ExplorationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if let tree = viewModel.exploration {
                if !tree.currentLineSAN.isEmpty {
                    Text(tree.currentLineSAN)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button {
                        viewModel.sandboxBack()
                    } label: {
                        Image(systemName: "arrow.left")
                    }
                    .disabled(!tree.canGoBack)

                    Button {
                        viewModel.sandboxForward()
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .disabled(!tree.canGoForward)

                    Button {
                        viewModel.sandboxReset()
                    } label: {
                        Label("Start of line", systemImage: "backward.end")
                            .font(.caption)
                    }
                    .disabled(tree.isAtRoot)

                    Spacer()
                    Text("\(tree.currentLine.count) ply deep")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.bordered)

                if let note = tree.current.coachNote, !note.isEmpty {
                    Text(note)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sandbox.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if tree.branches.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lines you have tried")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(tree.branches.enumerated()), id: \.offset) { _, branch in
                            if let leaf = branch.last {
                                Button {
                                    viewModel.sandboxGo(to: leaf.id)
                                } label: {
                                    Text(branch.map { $0.san }.joined(separator: " "))
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(leaf.id == tree.currentID ? Theme.sandbox : Color.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }
}
