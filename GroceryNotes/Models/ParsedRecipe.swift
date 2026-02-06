import Foundation

/// Intermediate model representing a parsed recipe
/// This decouples parsers from the app's MealRecipe model
struct ParsedRecipe {
    var title: String
    var description: String?
    var servings: Int?
    var estimatedTimeMinutes: Int?
    var ingredients: [ParsedRecipeIngredient]
    var steps: [String]
    var imageURL: String?
    var rating: Double?
    var reviewCount: Int?

    /// Convert to AIRecipeResponse for compatibility with existing code
    func toAIRecipeResponse(sourceURL: String) -> AIRecipeResponse {
        AIRecipeResponse(
            recipe: AIRecipeResponse.AIRecipeData(
                title: title,
                description: description ?? "",
                servings: servings ?? 4,
                estimatedTimeMinutes: estimatedTimeMinutes ?? 30,
                ingredients: ingredients.map { $0.toAIIngredientData() },
                steps: steps,
                tags: nil,
                imageURL: imageURL
            ),
            alternatives: nil
        )
    }
}

/// Intermediate model for a parsed recipe ingredient
struct ParsedRecipeIngredient {
    var name: String
    var quantity: String
    var unit: String?
    var categoryHint: String?

    /// Convert to AIRecipeResponse ingredient format
    func toAIIngredientData() -> AIRecipeResponse.AIRecipeData.AIIngredientData {
        // Combine quantity and unit if unit exists, abbreviating the unit
        let fullQuantity: String
        if let unit = unit {
            let abbreviated = IngredientParser.abbreviateUnit(unit)
            fullQuantity = "\(quantity) \(abbreviated)".trimmingCharacters(in: .whitespaces)
        } else {
            fullQuantity = quantity
        }

        return AIRecipeResponse.AIRecipeData.AIIngredientData(
            name: name,
            quantity: fullQuantity,
            categoryHint: categoryHint
        )
    }
}
