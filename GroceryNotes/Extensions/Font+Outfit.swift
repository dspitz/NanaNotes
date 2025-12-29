import SwiftUI

extension Font {
    static func outfit(_ size: CGFloat, weight: OutfitWeight = .regular) -> Font {
        return .custom(weight.fontName, size: size)
    }

    enum OutfitWeight {
        case regular
        case medium
        case semiBold
        case bold

        var fontName: String {
            switch self {
            case .regular:
                return "Outfit-Regular"
            case .medium:
                return "Outfit-Medium"
            case .semiBold:
                return "Outfit-SemiBold"
            case .bold:
                return "Outfit-Bold"
            }
        }
    }
}
