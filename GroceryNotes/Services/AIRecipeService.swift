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
        Return JSON with this structure:
        {"recipe":{"title":"","description":"","servings":4,"estimatedTimeMinutes":30,"ingredients":[{"name":"","quantity":"","categoryHint":"Produce"}],"steps":[""]}}
        Use common US ingredients.
        """

        let userPrompt = "Recipe for: \(mealName)"

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 1200,
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

        print("📝 RAW JSON RESPONSE:")
        print(content)
        print("📝 END RAW JSON")

        let contentData = content.data(using: .utf8)!
        return try JSONDecoder().decode(AIRecipeResponse.self, from: contentData)
    }

    func generateRecipeStreaming(for mealName: String) -> AsyncThrowingStream<RecipeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let systemPrompt = """
                    You are a recipe assistant. Generate a practical recipe with common US ingredients.
                    Return JSON matching this schema (no markdown or code blocks):

                    {
                      "recipe": {
                        "title": "string",
                        "description": "string",
                        "servings": number,
                        "estimatedTimeMinutes": number,
                        "ingredients": [{"name": "string", "quantity": "string", "categoryHint": "Produce|Meat|Dairy|Pantry"}],
                        "steps": ["string"]
                      }
                    }

                    Keep recipes simple and realistic.
                    """

                    let userPrompt = "Generate a recipe for: \(mealName)"

                    let requestBody: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userPrompt]
                        ],
                        "temperature": 0.5,
                        "max_tokens": 1500,
                        "stream": true,
                        "response_format": ["type": "json_object"]
                    ]

                    var request = URLRequest(url: URL(string: baseURL)!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(statusCode: httpResponse.statusCode, message: "Streaming request failed")
                    }

                    var accumulatedContent = ""

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            if jsonString == "[DONE]" {
                                // Try final parse
                                if let data = accumulatedContent.data(using: .utf8),
                                   let finalRecipe = try? JSONDecoder().decode(AIRecipeResponse.self, from: data) {
                                    continuation.yield(.complete(finalRecipe))
                                }
                                continuation.finish()
                                return
                            }

                            // Parse the SSE delta
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {

                                accumulatedContent += content

                                // Try to parse the accumulated JSON periodically
                                if let data = accumulatedContent.data(using: .utf8),
                                   let partial = try? JSONDecoder().decode(AIRecipeResponse.self, from: data) {
                                    continuation.yield(.chunk(partial))
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func searchPopularRecipes(for query: String) async throws -> PopularRecipesResponse {
        guard !AppConfiguration.googleSearchAPIKey.isEmpty,
              !AppConfiguration.googleSearchEngineID.isEmpty else {
            throw AIServiceError.missingConfiguration
        }

        // Use Google Custom Search to find real recipe URLs
        let googleSearch = GoogleSearchService(
            apiKey: AppConfiguration.googleSearchAPIKey,
            searchEngineID: AppConfiguration.googleSearchEngineID
        )
        let searchResults = try await googleSearch.searchRecipes(for: query, count: 6)

        // Convert to PopularRecipesResponse format
        let recipes = searchResults.map { result in
            PopularRecipesResponse.PopularRecipeData(
                title: result.title,
                description: result.description,
                sourceURL: result.sourceURL,
                sourceName: result.sourceName,
                servings: 4,  // Default - will be filled in when recipe is extracted
                estimatedTimeMinutes: 30,  // Default
                popularityScore: result.rating ?? 4.5,  // Use actual rating from search or default
                reviewCount: result.reviewCount,  // Use actual review count from search
                imageURL: result.imageURL,
                ingredients: nil,  // Will be filled when tapped
                steps: nil,  // Will be filled when tapped
                tags: nil
            )
        }

        return PopularRecipesResponse(recipes: recipes)
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

enum RecipeStreamChunk {
    case chunk(AIRecipeResponse)
    case complete(AIRecipeResponse)
}

enum AIServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noContent
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let code, let message):
            return "AI service error (\(code)): \(message)"
        case .noContent:
            return "No content returned from AI service"
        case .missingConfiguration:
            return "Google Search API not configured"
        }
    }
}
