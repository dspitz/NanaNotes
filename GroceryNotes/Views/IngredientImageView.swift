import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Reusable component that displays ingredient images with emoji fallback
/// Implements the waterfall priority: Custom Image → Remote URL → Emoji
struct IngredientImageView: View {
    let imageName: String?      // From displayImageName
    let imageURL: String?       // From customImageURL
    let emoji: String           // Fallback emoji
    let size: CGFloat           // 20, 34, etc.

    private func findImageName(_ name: String) -> String? {
        #if canImport(UIKit)
        let normalized = name.lowercased()

        // Try exact match first
        if UIImage(named: normalized) != nil {
            return normalized
        }

        // Try singular form (remove trailing 's')
        if normalized.hasSuffix("s") {
            let singular = String(normalized.dropLast())
            if UIImage(named: singular) != nil {
                return singular
            }
        }
        // Try plural form (add 's')
        else {
            let plural = normalized + "s"
            if UIImage(named: plural) != nil {
                return plural
            }
        }

        // Try partial match (for "egg whites" → match "egg")
        // Split by spaces and check each word
        let words = normalized.split(separator: " ")
        for word in words {
            let wordStr = String(word)
            // Try the word itself
            if UIImage(named: wordStr) != nil {
                return wordStr
            }
            // Try singular of the word
            if wordStr.hasSuffix("s") {
                let singular = String(wordStr.dropLast())
                if UIImage(named: singular) != nil {
                    return singular
                }
            }
        }

        return nil
        #else
        return nil
        #endif
    }

    var body: some View {
        Group {
            if let imageName = imageName, let actualImageName = findImageName(imageName) {
                // Priority 1: Static asset (check if it exists)
                Image(actualImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else if let imageURL = imageURL, let url = URL(string: imageURL) {
                // Priority 2: Remote URL (future)
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                    case .failure, .empty:
                        // Fallback to emoji on error - wrap in container for smooth animation
                        emojiView
                    @unknown default:
                        emojiView
                    }
                }
            } else {
                // Priority 3: Emoji fallback - wrap in container for smooth animation
                emojiView
            }
        }
    }

    // Helper view for emoji that animates more smoothly
    // Render at fixed size then scale (smoother animation than changing font size)
    private var emojiView: some View {
        Text(emoji)
            .font(.system(size: 100)) // Fixed large size
            .frame(width: 100, height: 100, alignment: .center)
            .scaleEffect(size / 100)  // Scale to match desired size
            .frame(width: size, height: size, alignment: .center)
    }
}
