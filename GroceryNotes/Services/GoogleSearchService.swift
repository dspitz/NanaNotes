import Foundation

struct GoogleSearchResult: Codable {
    var title: String
    var link: String
    var snippet: String
    var pagemap: PageMap?

    struct PageMap: Codable {
        var metatags: [MetaTag]?
        var cse_image: [CSEImage]?

        struct MetaTag: Codable {
            var ogImage: String?
            var ogDescription: String?

            enum CodingKeys: String, CodingKey {
                case ogImage = "og:image"
                case ogDescription = "og:description"
            }
        }

        struct CSEImage: Codable {
            var src: String?
        }
    }
}

struct GoogleSearchResponse: Codable {
    var items: [GoogleSearchResult]?
}

actor GoogleSearchService {
    private let apiKey: String
    private let searchEngineID: String
    private let baseURL = "https://www.googleapis.com/customsearch/v1"

    init(apiKey: String, searchEngineID: String) {
        self.apiKey = apiKey
        self.searchEngineID = searchEngineID
    }

    func searchRecipes(for query: String, count: Int = 6) async throws -> [RecipeSearchResult] {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "cx", value: searchEngineID),
            URLQueryItem(name: "q", value: "\(query) recipe"),
            URLQueryItem(name: "num", value: String(min(count, 10)))  // Max 10 per request
        ]

        guard let url = components.url else {
            throw GoogleSearchError.invalidURL
        }

        print("🔍 Google Search URL: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleSearchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GoogleSearchError.apiError(statusCode: httpResponse.statusCode)
        }

        let searchResponse = try JSONDecoder().decode(GoogleSearchResponse.self, from: data)

        guard let items = searchResponse.items, !items.isEmpty else {
            throw GoogleSearchError.noResults
        }

        return items.map { item in
            // Extract image from pagemap
            let imageURL = item.pagemap?.metatags?.first?.ogImage
                        ?? item.pagemap?.cse_image?.first?.src

            // Extract source name from URL
            let sourceName = extractSourceName(from: item.link)

            return RecipeSearchResult(
                title: item.title,
                sourceURL: item.link,
                sourceName: sourceName,
                description: item.snippet,
                imageURL: imageURL
            )
        }
    }

    private func extractSourceName(from url: String) -> String {
        guard let host = URL(string: url)?.host else { return "Unknown" }

        if host.contains("bonappetit.com") { return "Bon Appétit" }
        if host.contains("nytimes.com") { return "NYT Cooking" }
        if host.contains("seriouseats.com") { return "Serious Eats" }
        if host.contains("allrecipes.com") { return "AllRecipes" }
        if host.contains("foodnetwork.com") { return "Food Network" }
        if host.contains("bbcgoodfood.com") { return "BBC Good Food" }

        return host.replacingOccurrences(of: "www.", with: "")
    }
}

struct RecipeSearchResult {
    var title: String
    var sourceURL: String
    var sourceName: String
    var description: String
    var imageURL: String?
}

enum GoogleSearchError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid search URL"
        case .invalidResponse:
            return "Invalid response from Google"
        case .apiError(let code):
            return "Google Search API error (\(code))"
        case .noResults:
            return "No recipes found"
        }
    }
}
