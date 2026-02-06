import Foundation

/// Orchestrates recipe parsing using a waterfall approach:
/// 1. Try schema.org parser (fast, no API cost)
/// 2. Fallback to OpenAI (slow, API cost)
actor RecipeParsingService {
    private let parsers: [RecipeParser]
    private let openAIFallback: RecipeURLService

    init() {
        // Initialize parsers in priority order
        self.parsers = [
            SchemaOrgRecipeParser()
        ]

        // Initialize OpenAI fallback
        self.openAIFallback = RecipeURLService(apiKey: AppConfiguration.openAIAPIKey)
    }

    /// Extract recipe from URL using waterfall parsing strategy
    /// - Parameter urlString: The recipe URL to parse
    /// - Returns: AIRecipeResponse containing recipe data
    /// - Throws: Error if all parsing methods fail
    func extractRecipe(from urlString: String) async throws -> AIRecipeResponse {
        let startTime = Date()

        guard let url = URL(string: urlString) else {
            throw RecipeParsingError.invalidURL
        }

        // Step 1: Fetch HTML
        let html = try await fetchHTML(from: url)

        // Step 2: Try each parser in sequence
        for parser in parsers {
            if parser.canParse(url: url) {
                do {
                    if let parsedRecipe = try await parser.parse(html: html, url: url) {
                        let duration = Date().timeIntervalSince(startTime) * 1000 // ms
                        let parserName = String(describing: type(of: parser))
                        print("✅ Recipe parsed via \(parserName) in \(Int(duration))ms")

                        return parsedRecipe.toAIRecipeResponse(sourceURL: urlString)
                    }
                } catch {
                    // Parser failed, try next one
                    continue
                }
            }
        }

        // Step 3: Fallback to OpenAI
        print("⚠️ Schema.org parsing failed, falling back to OpenAI")
        let response = try await openAIFallback.extractRecipeFromURL(urlString)

        let duration = Date().timeIntervalSince(startTime) * 1000 // ms
        print("✅ Recipe parsed via OpenAI in \(Int(duration))ms")

        return response
    }

    // MARK: - Private Helpers

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let html = String(data: data, encoding: .utf8) else {
            throw RecipeParsingError.unableToReadContent
        }

        return html
    }
}

enum RecipeParsingError: LocalizedError {
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
