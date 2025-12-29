import Foundation

actor RecipeURLService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func extractRecipeFromURL(_ urlString: String) async throws -> AIRecipeResponse {
        // First, fetch the webpage content
        guard let url = URL(string: urlString) else {
            throw RecipeURLError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let htmlContent = String(data: data, encoding: .utf8) else {
            throw RecipeURLError.unableToReadContent
        }

        // Use AI to extract recipe from HTML (limited to first 15000 chars to stay within token limits)
        let truncatedHTML = String(htmlContent.prefix(15000))

        let systemPrompt = """
        You are a recipe extraction assistant. Extract recipe information from the provided HTML content.
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
            "steps": ["step 1", "step 2", "step 3"],
            "imageURL": "https://example.com/image.jpg"
          },
          "alternatives": []
        }

        Extract:
        - All ingredients with their quantities
        - All cooking steps in order
        - The main recipe image URL (look for og:image, recipe images, or main content images)
        - Normalize ingredient names to common grocery items
        - If cooking time is not found, estimate based on the recipe type
        - For alternatives array, return an empty array since we're extracting a specific recipe
        """

        let userPrompt = "Extract the recipe from this HTML:\n\n\(truncatedHTML)"

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

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: responseData)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw AIServiceError.noContent
        }

        let contentData = content.data(using: .utf8)!
        return try JSONDecoder().decode(AIRecipeResponse.self, from: contentData)
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

enum RecipeURLError: LocalizedError {
    case invalidURL
    case unableToReadContent

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid recipe URL"
        case .unableToReadContent:
            return "Unable to read recipe content from URL"
        }
    }
}
