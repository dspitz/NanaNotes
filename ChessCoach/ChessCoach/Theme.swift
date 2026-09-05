import SwiftUI
import ChessKit

/// One place for every colour and metric, so iOS and macOS look the same and
/// nothing reaches for a platform-only system colour.
enum Theme {
    // Board
    static let lightSquare = Color(red: 0.925, green: 0.902, blue: 0.847)
    static let darkSquare = Color(red: 0.435, green: 0.541, blue: 0.404)
    static let boardBorder = Color.black.opacity(0.18)

    // Highlights
    static let selection = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let lastMove = Color(red: 0.97, green: 0.85, blue: 0.35)
    static let coachAccent = Color(red: 0.29, green: 0.56, blue: 0.94)
    static let checkGlow = Color(red: 0.87, green: 0.25, blue: 0.24)
    static let sandbox = Color(red: 0.55, green: 0.36, blue: 0.87)

    // Surfaces
    static let panel = Color.gray.opacity(0.10)
    static let panelStroke = Color.gray.opacity(0.22)

    // Move quality
    static func color(for quality: MoveQualityColor) -> Color {
        switch quality {
        case .great: return Color(red: 0.17, green: 0.62, blue: 0.40)
        case .fine: return Color(red: 0.42, green: 0.60, blue: 0.36)
        case .inaccuracy: return Color(red: 0.90, green: 0.68, blue: 0.20)
        case .mistake: return Color(red: 0.93, green: 0.51, blue: 0.18)
        case .blunder: return Color(red: 0.85, green: 0.26, blue: 0.24)
        }
    }

    static let cornerRadius: CGFloat = 14
}

enum MoveQualityColor {
    case great, fine, inaccuracy, mistake, blunder
}

extension View {
    /// The card treatment used by every panel in the app.
    func coachCard() -> some View {
        self
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.panelStroke, lineWidth: 1)
            )
    }
}
