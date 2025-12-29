import Foundation

enum ParsingConfidence {
    case high    // Simple delimiter parsing succeeded
    case medium  // AI parsing used
    case low     // Ambiguous or uncertain
}

struct ParsedIngredient {
    let name: String
    let quantity: String?
    let confidence: ParsingConfidence
}

enum ParsingError: Error {
    case emptyInput
    case aiParsingFailed
    case noItemsFound
}

actor VoiceInputParserService {
    private let apiKey: String?
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    /// Parse transcribed text into individual grocery items
    func parseTranscription(_ text: String) async throws -> [ParsedIngredient] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ParsingError.emptyInput
        }

        // Try simple delimiter parsing first
        if let simpleResults = simpleDelimiterParse(trimmedText) {
            return simpleResults
        }

        // Fall back to AI parsing if available and input is complex
        if let apiKey = apiKey, shouldUseAIParsing(trimmedText) {
            do {
                return try await aiParse(trimmedText)
            } catch {
                // If AI parsing fails, fall back to treating the entire input as one item
                print("AI parsing failed: \(error.localizedDescription), falling back to single item")
                return [ParsedIngredient(name: trimmedText, quantity: nil, confidence: .low)]
            }
        }

        // Fallback: treat entire input as a single item
        return [ParsedIngredient(name: trimmedText, quantity: nil, confidence: .low)]
    }

    // MARK: - Simple Delimiter Parsing

    private func simpleDelimiterParse(_ text: String) -> [ParsedIngredient]? {
        var items: [ParsedIngredient] = []

        // First, split by newlines or bullet points
        let lines = text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { line -> String in
                // Remove common bullet point characters
                var cleaned = line
                let bullets = ["•", "·", "-", "*", "○", "▪", "▫"]
                for bullet in bullets {
                    if cleaned.hasPrefix(bullet) {
                        cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }
                }
                return cleaned
            }
            .filter { !$0.isEmpty }

        // If we have multiple lines, each line is likely a separate item
        if lines.count > 1 {
            for line in lines {
                let parsed = parseLineIntoItem(line)
                items.append(contentsOf: parsed)
            }
            return items.isEmpty ? nil : items
        }

        // Single line: split by commas, semicolons, or "and"
        let singleLine = lines.first ?? text
        let delimiters = [",", ";", " and ", " & "]

        // Try to split by delimiters
        var parts = [singleLine]
        for delimiter in delimiters {
            var newParts: [String] = []
            for part in parts {
                newParts.append(contentsOf: part.components(separatedBy: delimiter))
            }
            parts = newParts
        }

        parts = parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // If we found multiple parts, parse each
        if parts.count > 1 {
            for part in parts {
                let parsed = parseLineIntoItem(part)
                items.append(contentsOf: parsed)
            }
            return items.isEmpty ? nil : items
        }

        // If input is simple (no quantities, no complex phrasing), return as single item
        if !containsQuantities(singleLine) && parts.count == 1 {
            return [ParsedIngredient(name: singleLine, quantity: nil, confidence: .high)]
        }

        // Complex input, should use AI
        return nil
    }

    private func parseLineIntoItem(_ line: String) -> [ParsedIngredient] {
        // Extract quantity and name using regex
        let quantityPattern = #"^(\d+\.?\d*\s*(?:lb|lbs|oz|kg|g|cup|cups|tablespoon|tbsp|teaspoon|tsp|pound|pounds|ounce|ounces)?)\s+(.+)$"#

        if let regex = try? NSRegularExpression(pattern: quantityPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges == 3 {

            if let quantityRange = Range(match.range(at: 1), in: line),
               let nameRange = Range(match.range(at: 2), in: line) {
                let quantity = String(line[quantityRange]).trimmingCharacters(in: .whitespaces)
                let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                return [ParsedIngredient(name: name, quantity: quantity, confidence: .high)]
            }
        }

        // No quantity found, just return the name
        return [ParsedIngredient(name: line, quantity: nil, confidence: .high)]
    }

    private func containsQuantities(_ text: String) -> Bool {
        let quantityPattern = #"\d+\.?\d*\s*(?:lb|lbs|oz|kg|g|cup|cups|tablespoon|tbsp|teaspoon|tsp|pound|pounds|ounce|ounces)?"#
        if let regex = try? NSRegularExpression(pattern: quantityPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
        return false
    }

    private func shouldUseAIParsing(_ text: String) -> Bool {
        // Use AI if:
        // 1. Input contains quantities
        // 2. Input is complex (multiple items without clear delimiters)
        // 3. Simple parsing returned nil

        return containsQuantities(text) || text.count > 100
    }

    // MARK: - AI Parsing

    private func aiParse(_ text: String) async throws -> [ParsedIngredient] {
        guard let apiKey = apiKey else {
            throw ParsingError.aiParsingFailed
        }

        let systemPrompt = """
        You are a grocery list parser. Parse the user's natural language input into a structured list of grocery items.

        Return ONLY valid JSON in this exact format:
        {
            "ingredients": [
                {"name": "item name", "quantity": "2 lbs"},
                {"name": "item name", "quantity": null}
            ]
        }

        Rules:
        - Extract item names in singular or plural form as spoken
        - Extract quantities if mentioned (e.g., "2", "3 lbs", "a dozen")
        - If no quantity is mentioned, use null
        - Normalize item names to common grocery terms
        - Split compound requests into separate items
        """

        let userPrompt = "Parse this grocery list: \(text)"

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages,
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]

        guard let url = URL(string: baseURL) else {
            throw ParsingError.aiParsingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParsingError.aiParsingFailed
        }

        // Parse the OpenAI response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ParsingError.aiParsingFailed
        }

        // Parse the JSON content
        guard let contentData = content.data(using: .utf8),
              let contentJson = try JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let ingredients = contentJson["ingredients"] as? [[String: Any]] else {
            throw ParsingError.aiParsingFailed
        }

        var parsedItems: [ParsedIngredient] = []
        for ingredient in ingredients {
            guard let name = ingredient["name"] as? String else { continue }
            let quantity = ingredient["quantity"] as? String
            parsedItems.append(ParsedIngredient(name: name, quantity: quantity, confidence: .medium))
        }

        if parsedItems.isEmpty {
            throw ParsingError.noItemsFound
        }

        return parsedItems
    }
}
