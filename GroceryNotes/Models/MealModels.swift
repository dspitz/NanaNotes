import Foundation
import SwiftData

@Model
final class MealDraft {
    var id: UUID
    var title: String
    var selectedRecipeData: Data?
    var alternativesData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        selectedRecipe: MealRecipe? = nil,
        alternatives: [MealRecipe] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        if let recipe = selectedRecipe {
            self.selectedRecipeData = try? JSONEncoder().encode(recipe)
        }
        if !alternatives.isEmpty {
            self.alternativesData = try? JSONEncoder().encode(alternatives)
        }
    }

    var selectedRecipe: MealRecipe? {
        get {
            guard let data = selectedRecipeData else { return nil }
            return try? JSONDecoder().decode(MealRecipe.self, from: data)
        }
        set {
            selectedRecipeData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    var alternatives: [MealRecipe] {
        get {
            guard let data = alternativesData else { return [] }
            return (try? JSONDecoder().decode([MealRecipe].self, from: data)) ?? []
        }
        set {
            alternativesData = try? JSONEncoder().encode(newValue)
        }
    }
}

struct MealRecipe: Codable, Identifiable {
    var id: UUID
    var title: String
    var description: String
    var servings: Int
    var estimatedTimeMinutes: Int
    var ingredients: [MealIngredient]
    var steps: [String]
    var tags: [String]?
    var imageURL: String?
    var sourceURL: String?
    var popularityScore: Double?
    var popularitySource: String?
    var imagePrompt: String?

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        servings: Int = 4,
        estimatedTimeMinutes: Int = 30,
        ingredients: [MealIngredient] = [],
        steps: [String] = [],
        tags: [String]? = nil,
        imageURL: String? = nil,
        sourceURL: String? = nil,
        popularityScore: Double? = nil,
        popularitySource: String? = nil,
        imagePrompt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.servings = servings
        self.estimatedTimeMinutes = estimatedTimeMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.tags = tags
        self.imageURL = imageURL
        self.sourceURL = sourceURL
        self.popularityScore = popularityScore
        self.popularitySource = popularitySource
        self.imagePrompt = imagePrompt
    }
}

struct MealIngredient: Codable, Identifiable {
    var id: UUID
    var name: String
    var quantity: String
    var categoryHint: String?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: String,
        categoryHint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.categoryHint = categoryHint
    }
}

struct AIRecipeResponse: Codable {
    var recipe: AIRecipeData
    var alternatives: [AIRecipeData]

    struct AIRecipeData: Codable {
        var title: String
        var description: String
        var servings: Int
        var estimatedTimeMinutes: Int
        var ingredients: [AIIngredientData]
        var steps: [String]
        var tags: [String]?
        var imageURL: String?

        struct AIIngredientData: Codable {
            var name: String
            var quantity: String
            var categoryHint: String?
        }
    }

    func toMealRecipe(sourceURL: String? = nil) -> MealRecipe {
        MealRecipe(
            title: recipe.title,
            description: recipe.description,
            servings: recipe.servings,
            estimatedTimeMinutes: recipe.estimatedTimeMinutes,
            ingredients: recipe.ingredients.map { ing in
                MealIngredient(name: ing.name, quantity: ing.quantity, categoryHint: ing.categoryHint)
            },
            steps: recipe.steps,
            tags: recipe.tags,
            imageURL: recipe.imageURL,
            sourceURL: sourceURL
        )
    }

    func toAlternatives() -> [MealRecipe] {
        alternatives.map { alt in
            MealRecipe(
                title: alt.title,
                description: alt.description,
                servings: alt.servings,
                estimatedTimeMinutes: alt.estimatedTimeMinutes,
                ingredients: alt.ingredients.map { ing in
                    MealIngredient(name: ing.name, quantity: ing.quantity, categoryHint: ing.categoryHint)
                },
                steps: alt.steps,
                tags: alt.tags,
                imageURL: alt.imageURL
            )
        }
    }
}

struct PopularRecipesResponse: Codable {
    var recipes: [PopularRecipeData]

    struct PopularRecipeData: Codable {
        var title: String
        var description: String
        var servings: Int
        var estimatedTimeMinutes: Int
        var popularityScore: Double
        var popularitySource: String
        var ingredients: [AIRecipeResponse.AIRecipeData.AIIngredientData]
        var steps: [String]
        var tags: [String]?
        var imagePrompt: String?
    }

    func toMealRecipes() -> [MealRecipe] {
        recipes.map { recipe in
            MealRecipe(
                title: recipe.title,
                description: recipe.description,
                servings: recipe.servings,
                estimatedTimeMinutes: recipe.estimatedTimeMinutes,
                ingredients: recipe.ingredients.map { ing in
                    MealIngredient(
                        name: ing.name,
                        quantity: ing.quantity,
                        categoryHint: ing.categoryHint
                    )
                },
                steps: recipe.steps,
                tags: recipe.tags,
                imageURL: nil,
                sourceURL: nil,
                popularityScore: recipe.popularityScore,
                popularitySource: recipe.popularitySource,
                imagePrompt: recipe.imagePrompt
            )
        }
    }
}
