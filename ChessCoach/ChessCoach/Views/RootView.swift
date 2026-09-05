import SwiftUI
import ChessKit
import CoachKit

struct RootView: View {
    @StateObject private var viewModel = GameViewModel()
    @State private var isShowingNewGame = false
    @State private var isShowingReview = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isWide = proxy.size.width > 880
                Group {
                    if isWide {
                        HStack(alignment: .top, spacing: 20) {
                            boardColumn
                                .frame(maxWidth: proxy.size.width * 0.52)
                            coachColumn
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                boardColumn
                                coachColumn
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Chess Coach")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingNewGame) {
                NewGameSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingSettings) {
                CoachSettingsSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingReview) {
                GameReviewSheet(viewModel: viewModel)
            }
            .sheet(item: $viewModel.promotionRequest) { _ in
                PromotionSheet(color: viewModel.activePosition.sideToMove) { kind in
                    viewModel.completePromotion(kind)
                }
            }
        }
        .task {
            await viewModel.refreshAnalysis()
        }
    }

    // MARK: - Columns

    private var boardColumn: some View {
        VStack(spacing: 12) {
            capturedAndStatus
            BoardView(viewModel: viewModel)
            MoveListView(game: viewModel.game, review: viewModel.gameReview)
            controlRow
            if viewModel.isExploring {
                SandboxBarView(viewModel: viewModel)
            }
        }
    }

    private var coachColumn: some View {
        CoachPanelView(viewModel: viewModel)
    }

    private var capturedAndStatus: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.statusText)
                    .font(.headline)
                Text("\(viewModel.opponentStrength.displayName) opponent \u{00B7} \(viewModel.opponentStrength.approximateRating)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isThinking {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            Button {
                if viewModel.isExploring {
                    viewModel.exitExploration()
                } else {
                    viewModel.enterExploration()
                }
            } label: {
                Label(viewModel.isExploring ? "Leave sandbox" : "Try it out",
                      systemImage: viewModel.isExploring ? "arrow.uturn.backward" : "flask")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isExploring ? Color.secondary : Theme.sandbox)

            Button {
                viewModel.takeBackMove()
            } label: {
                Label("Take back", systemImage: "arrow.uturn.left")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isExploring || viewModel.game.history.isEmpty || viewModel.isThinking)

            Spacer()

            Button {
                viewModel.flipBoard()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(.bordered)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                isShowingNewGame = true
            } label: {
                Label("New game", systemImage: "plus.circle")
            }
            Button {
                isShowingSettings = true
            } label: {
                Label("Coach settings", systemImage: "slider.horizontal.3")
            }
            Button {
                viewModel.reviewWholeGame()
                isShowingReview = true
            } label: {
                Label("Review game", systemImage: "chart.line.uptrend.xyaxis")
            }
            .disabled(viewModel.game.history.isEmpty)
        }
    }
}

// MARK: - Sheets

struct NewGameSheet: View {
    @ObservedObject var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var color: PieceColor = .white
    @State private var strength: OpponentStrength = .club

    var body: some View {
        NavigationStack {
            Form {
                Section("You play") {
                    Picker("Colour", selection: $color) {
                        Text("White").tag(PieceColor.white)
                        Text("Black").tag(PieceColor.black)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Opponent") {
                    ForEach(OpponentStrength.allCases) { option in
                        Button {
                            strength = option
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(option.displayName) \u{00B7} \(option.approximateRating)")
                                        .font(.body.weight(option == strength ? .semibold : .regular))
                                    Text(option.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if option == strength {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.coachAccent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("New game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        viewModel.startNewGame(as: color, strength: strength)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            color = viewModel.playerColor
            strength = viewModel.opponentStrength
        }
        .frame(minWidth: 320, minHeight: 420)
    }
}

struct CoachSettingsSheet: View {
    @ObservedObject var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("How the coach explains things") {
                    Picker("Level", selection: $viewModel.coachLevel) {
                        ForEach(CoachLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Text(viewModel.coachLevel.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("How often it speaks up") {
                    Picker("Verbosity", selection: $viewModel.coachVerbosity) {
                        ForEach(CoachVerbosity.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
                Section("Board") {
                    Toggle("Show coach highlights and arrows", isOn: $viewModel.showCoachHighlights)
                }
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 380)
    }
}

struct PromotionSheet: View {
    let color: PieceColor
    let onSelect: (PieceKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("Promote to")
                .font(.headline)
            HStack(spacing: 16) {
                ForEach([PieceKind.queen, .rook, .bishop, .knight], id: \.rawValue) { kind in
                    Button {
                        onSelect(kind)
                        dismiss()
                    } label: {
                        PieceView(piece: Piece(color, kind), size: 64)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 300)
    }
}

struct GameReviewSheet: View {
    @ObservedObject var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let review = viewModel.gameReview {
                    content(review)
                } else {
                    VStack(spacing: 12) {
                        ProgressView(value: viewModel.reviewProgress)
                            .frame(maxWidth: 260)
                        Text("Going through the game move by move...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Game review")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 460)
    }

    private func content(_ review: GameReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 24) {
                    accuracyTile(color: viewModel.playerColor, title: "You", review: review)
                    accuracyTile(color: viewModel.playerColor.opponent, title: "Opponent", review: review)
                }

                let turningPoints = review.turningPoints(for: viewModel.playerColor, limit: 4)
                if !turningPoints.isEmpty {
                    Text("The moments that mattered")
                        .font(.headline)
                    ForEach(turningPoints) { moment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(moment.moveNumber)\(moment.color == .white ? "." : "...") \(moment.san)")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                Text(moment.quality.displayName)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.color(for: moment.quality.panelColor))
                                Spacer()
                                Text("\u{2212}\(Int(moment.winProbabilityDrop * 100))% win chance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(moment.explanation)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .coachCard()
                    }
                } else {
                    Text("No serious mistakes to report. Nicely held together.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func accuracyTile(color: PieceColor, title: String, review: GameReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(review.accuracy(for: color))")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("accuracy")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(review.count(of: .blunder, for: color)) blunders, \(review.count(of: .mistake, for: color)) mistakes")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachCard()
    }
}
