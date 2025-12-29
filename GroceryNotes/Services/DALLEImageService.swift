import Foundation

actor DALLEImageService {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/images/generations"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func generateRecipeImage(for recipeName: String) async throws -> String {
        // Hand-painted cookbook illustration style - truly artistic, not photographic
        let prompt = """
        An original hand-painted illustration of \(recipeName) in gouache paint on textured watercolor paper. \
        This is a genuine artistic painting, NOT a photograph or photo with filters applied. \
        The illustration uses simplified, stylized shapes with bold brush strokes and visible paint texture. \
        The dish is shown from a top-down angle on a simple plate, painted with artistic interpretation and creative freedom. \
        Use a vibrant Mediterranean color palette: saturated tomato reds, fresh basil greens, golden olive oil yellows, warm terracotta oranges. \
        The painting style features: thick visible brushwork, imperfect hand-drawn edges, simplified forms, flat color blocks with hand-painted shadows, \
        and artistic details rather than photorealistic rendering. The food is recognizable but stylized with personality and charm. \
        Include a playful hand-drawn decorative border painted in one bold color (mustard yellow, crimson red, or cobalt blue) \
        with organic wavy lines and imperfect curves. The white background should show subtle paper texture. \
        Overall aesthetic: authentic artist's sketchbook, Mediterranean cookbook illustration, warm and inviting, \
        painterly and expressive, with the charming imperfections of genuine hand-painted artwork.
        """

        let requestBody: [String: Any] = [
            "model": "dall-e-3",
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "quality": "hd",
            "style": "natural"
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DALLEError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DALLEError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let dalleResponse = try JSONDecoder().decode(DALLEResponse.self, from: data)
        guard let imageURL = dalleResponse.data.first?.url else {
            throw DALLEError.noImageGenerated
        }

        return imageURL
    }
}

private struct DALLEResponse: Codable {
    struct ImageData: Codable {
        var url: String
    }
    var data: [ImageData]
}

enum DALLEError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noImageGenerated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from DALL-E service"
        case .apiError(let code, let message):
            return "DALL-E error (\(code)): \(message)"
        case .noImageGenerated:
            return "No image was generated"
        }
    }
}
