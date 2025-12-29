import Foundation

struct AIStorageResponse: Codable {
    var normalizedName: String
    var storageAdvice: String
    var shelfLifeDaysMin: Int
    var shelfLifeDaysMax: Int
    var categorySuggestion: String
    var notes: String?
}

actor AIRecipeService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func generateRecipe(for mealName: String) async throws -> AIRecipeResponse {
        let systemPrompt = """
        You are a helpful recipe assistant. Generate a recipe with common US grocery ingredients.
        Return ONLY valid JSON matching this exact schema. Do not include any markdown, code blocks, or explanatory text.

        {
          "recipe": {
            "title": "Recipe name",
            "description": "Brief description",
            "servings": 4,
            "estimatedTimeMinutes": 30,
            "ingredients": [
              {"name": "ingredient name", "quantity": "amount", "categoryHint": "Produce|Meat|Dairy|Pantry|etc"}
            ],
            "steps": ["step 1", "step 2"]
          },
          "alternatives": []
        }

        Use realistic cooking times and common ingredients. Keep the recipe simple and practical.
        """

        let userPrompt = "Generate a recipe for: \(mealName)"

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.7,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw AIServiceError.noContent
        }

        let contentData = content.data(using: .utf8)!
        return try JSONDecoder().decode(AIRecipeResponse.self, from: contentData)
    }

    func searchPopularRecipes(for query: String) async throws -> PopularRecipesResponse {
        let systemPrompt = """
        You are a recipe expert with knowledge of popular recipes from trusted sources like Bon Appétit, NYT Cooking, Serious Eats, and AllRecipes.

        For the user's query, return 6 REAL popular recipes that are highly-rated and commonly made. Use your knowledge of actual popular recipes from these trusted sources.

        Return ONLY valid JSON matching this exact schema. Do not include any markdown, code blocks, or explanatory text.

        {
          "recipes": [
            {
              "title": "Recipe name (from real popular recipe)",
              "description": "Brief 1-2 sentence description",
              "servings": 4,
              "estimatedTimeMinutes": 30,
              "popularityScore": 4.5,
              "popularitySource": "Highly rated on Bon Appétit",
              "ingredients": [
                {"name": "ingredient", "quantity": "amount", "categoryHint": "Produce|Meat|Dairy|Pantry|etc"}
              ],
              "steps": ["step 1", "step 2"],
              "tags": ["Italian", "Comfort Food"],
              "imagePrompt": "Brief description for generating recipe image"
            }
          ]
        }

        Requirements:
        - Return exactly 6 recipes
        - Each recipe should be realistic and actually popular (not made up)
        - Popularity scores between 3.5-5.0 (only suggest good recipes)
        - Include variety in cooking times and difficulty
        - Use common US grocery ingredients
        - Provide realistic cooking times
        - Include helpful tags for categorization
        - ImagePrompt should describe the dish for DALL-E generation (e.g., "Creamy chicken parmesan with melted mozzarella on a white plate")
        """

        let userPrompt = "Find 6 popular recipes for: \(query)"

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.8,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw AIServiceError.noContent
        }

        let contentData = content.data(using: .utf8)!
        return try JSONDecoder().decode(PopularRecipesResponse.self, from: contentData)
    }
}

actor AIStorageService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func getStorageInfo(for itemName: String) async throws -> AIStorageResponse {
        let systemPrompt = """
        You are a food storage expert. Provide storage advice and shelf life estimates for grocery items.
        Return ONLY valid JSON matching this exact schema. Do not include any markdown, code blocks, or explanatory text.

        {
          "normalizedName": "lowercase item name",
          "storageAdvice": "Brief storage instructions",
          "shelfLifeDaysMin": 0,
          "shelfLifeDaysMax": 0,
          "categorySuggestion": "Produce|Bakery|Meat|Dairy|Pantry|Frozen|Beverages|Household|Specialty|Other",
          "notes": "Additional info"
        }

        Use conservative estimates for typical US household conditions. Be specific and practical.
        """

        let userPrompt = "Provide storage information for: \(itemName)"

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw AIServiceError.noContent
        }

        let contentData = content.data(using: .utf8)!
        return try JSONDecoder().decode(AIStorageResponse.self, from: contentData)
    }
}

private struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var content: String
        }
        var message: Message
    }
    var choices: [Choice]
}

enum AIServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let code, let message):
            return "AI service error (\(code)): \(message)"
        case .noContent:
            return "No content returned from AI service"
        }
    }
}
