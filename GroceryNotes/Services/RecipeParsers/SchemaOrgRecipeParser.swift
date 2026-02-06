import Foundation

/// Parser for schema.org Recipe structured data (JSON-LD)
/// Handles the majority of recipe sites that include schema.org markup
struct SchemaOrgRecipeParser: RecipeParser {
    func canParse(url: URL) -> Bool {
        // Schema.org is universal - we try it for all URLs
        return true
    }

    func parse(html: String, url: URL) async throws -> ParsedRecipe? {
        // Extract all JSON-LD scripts from HTML
        guard let jsonLDBlocks = extractJSONLD(from: html) else {
            return nil
        }

        // Try to find a Recipe object in any of the JSON-LD blocks
        for jsonString in jsonLDBlocks {
            if let recipe = try? parseRecipeFromJSON(jsonString) {
                return recipe
            }
        }

        return nil
    }

    // MARK: - JSON-LD Extraction

    private func extractJSONLD(from html: String) -> [String]? {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)

        let jsonBlocks = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }

        return jsonBlocks.isEmpty ? nil : jsonBlocks
    }

    // MARK: - Recipe Parsing

    private func parseRecipeFromJSON(_ jsonString: String) throws -> ParsedRecipe? {
        guard let data = jsonString.data(using: .utf8) else { return nil }

        // Try to decode as single object
        if let schemaOrg = try? JSONDecoder().decode(SchemaOrgWrapper.self, from: data) {
            return parseSchemaOrgRecipe(schemaOrg)
        }

        // Try to decode as array (some sites wrap in array)
        if let schemaOrgArray = try? JSONDecoder().decode([SchemaOrgWrapper].self, from: data) {
            for schema in schemaOrgArray {
                if let recipe = parseSchemaOrgRecipe(schema) {
                    return recipe
                }
            }
        }

        return nil
    }

    private func parseSchemaOrgRecipe(_ wrapper: SchemaOrgWrapper) -> ParsedRecipe? {
        // Handle direct Recipe object
        if wrapper.type.contains("Recipe") {
            return convertToParsedRecipe(wrapper)
        }

        // Handle @graph array (WordPress and other CMS use this)
        if let graph = wrapper.graph {
            for item in graph {
                if item.type.contains("Recipe") {
                    return convertToParsedRecipe(item)
                }
            }
        }

        return nil
    }

    private func convertToParsedRecipe(_ schema: SchemaOrgWrapper) -> ParsedRecipe? {
        guard let title = schema.name else { return nil }

        // Parse ingredients
        let rawIngredients = schema.recipeIngredient ?? []

        // Filter and parse ingredients
        let ingredients = rawIngredients
            .filter { ingredient in
                // Filter out obvious section headers or malformed entries
                let trimmed = ingredient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                // Skip empty or very short entries
                guard trimmed.count > 2 else { return false }

                // Skip water (it's implied you have water!)
                if trimmed.contains("water") && !trimmed.contains("rose water") && !trimmed.contains("orange blossom water") {
                    return false
                }

                // Skip section headers (usually end with colon or are all caps)
                if trimmed.hasSuffix(":") { return false }
                if ingredient.uppercased() == ingredient && ingredient.count > 5 { return false }

                // Skip entries that are just a word and a number (likely headers)
                let words = trimmed.split(separator: " ")
                if words.count == 2, let last = words.last, Double(last) != nil {
                    // Check if first word is generic like "sauce", "for", "marinade"
                    let genericHeaders = ["sauce", "marinade", "dressing", "for", "topping", "garnish"]
                    if genericHeaders.contains(String(words[0])) {
                        return false
                    }
                }

                return true
            }
            .map { ingredientString in
                IngredientParser.parse(ingredientString)
            }

        // Parse steps
        let steps = parseSteps(from: schema)

        // Parse time
        let estimatedTime = parseTime(from: schema)

        // Parse servings
        let servings = parseServings(from: schema.recipeYield)

        // Parse image URL
        let imageURL = parseImageURL(from: schema.image)

        // Parse rating
        let (rating, reviewCount) = parseRating(from: schema.aggregateRating)

        return ParsedRecipe(
            title: title,
            description: schema.description,
            servings: servings,
            estimatedTimeMinutes: estimatedTime,
            ingredients: ingredients,
            steps: steps,
            imageURL: imageURL,
            rating: rating,
            reviewCount: reviewCount
        )
    }

    // MARK: - Parsing Helpers

    private func parseSteps(from schema: SchemaOrgWrapper) -> [String] {
        guard let instructions = schema.recipeInstructions else { return [] }

        // Instructions can be:
        // 1. Array of strings
        // 2. Array of HowToStep objects
        // 3. Array of HowToSection objects (with itemListElement)
        // 4. Single string

        var steps: [String] = []

        for instruction in instructions {
            if let text = instruction.text {
                // HowToStep with text property
                steps.append(text)
            } else if let itemListElement = instruction.itemListElement {
                // HowToSection with nested steps
                for item in itemListElement {
                    if let text = item.text {
                        steps.append(text)
                    }
                }
            }
        }

        // If we didn't find steps in structured format, try string array
        if steps.isEmpty, let firstInstruction = instructions.first {
            // Check if it's just a string instruction
            if let text = firstInstruction.text {
                steps.append(text)
            }
        }

        return steps
    }

    private func parseTime(from schema: SchemaOrgWrapper) -> Int? {
        // Try totalTime first, then fall back to prepTime + cookTime
        if let totalTime = schema.totalTime,
           let minutes = ISO8601DurationParser.parseMinutes(from: totalTime) {
            return minutes
        }

        var total = 0
        if let prepTime = schema.prepTime,
           let minutes = ISO8601DurationParser.parseMinutes(from: prepTime) {
            total += minutes
        }
        if let cookTime = schema.cookTime,
           let minutes = ISO8601DurationParser.parseMinutes(from: cookTime) {
            total += minutes
        }

        return total > 0 ? total : nil
    }

    private func parseServings(from recipeYield: SchemaOrgValue?) -> Int? {
        guard let recipeYield = recipeYield else { return nil }

        // recipeYield can be a string ("4 servings") or number (4)
        if case .string(let yieldString) = recipeYield {
            // Extract first number from string
            let pattern = #"(\d+)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: yieldString, options: [], range: NSRange(yieldString.startIndex..., in: yieldString)),
               let range = Range(match.range(at: 1), in: yieldString) {
                return Int(yieldString[range])
            }
        } else if case .int(let count) = recipeYield {
            return count
        }

        return nil
    }

    private func parseImageURL(from image: SchemaOrgImage?) -> String? {
        guard let image = image else { return nil }

        switch image {
        case .string(let url):
            return url
        case .object(let imageObj):
            return imageObj.url
        case .array(let images):
            // Return first image
            if case .string(let url) = images.first {
                return url
            } else if case .object(let imageObj) = images.first {
                return imageObj.url
            }
        }

        return nil
    }

    private func parseRating(from aggregateRating: AggregateRating?) -> (rating: Double?, reviewCount: Int?) {
        guard let aggregateRating = aggregateRating else {
            return (nil, nil)
        }

        let rating: Double? = {
            if let value = aggregateRating.ratingValue {
                if case .double(let d) = value {
                    return d
                } else if case .string(let s) = value, let d = Double(s) {
                    return d
                }
            }
            return nil
        }()

        let reviewCount: Int? = {
            if let value = aggregateRating.ratingCount {
                if case .int(let i) = value {
                    return i
                } else if case .string(let s) = value, let i = Int(s) {
                    return i
                }
            }
            return nil
        }()

        return (rating, reviewCount)
    }
}

// MARK: - Schema.org Models

/// Flexible wrapper for schema.org objects
struct SchemaOrgWrapper: Codable {
    var type: [String]
    var name: String?
    var description: String?
    var recipeYield: SchemaOrgValue?
    var recipeIngredient: [String]?
    var recipeInstructions: [InstructionItem]?
    var totalTime: String?
    var prepTime: String?
    var cookTime: String?
    var image: SchemaOrgImage?
    var aggregateRating: AggregateRating?
    var graph: [SchemaOrgWrapper]?

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case name
        case description
        case recipeYield
        case recipeIngredient
        case recipeInstructions
        case totalTime
        case prepTime
        case cookTime
        case image
        case aggregateRating
        case graph = "@graph"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // @type can be string or array
        if let typeString = try? container.decode(String.self, forKey: .type) {
            type = [typeString]
        } else if let typeArray = try? container.decode([String].self, forKey: .type) {
            type = typeArray
        } else {
            type = []
        }

        name = try? container.decode(String.self, forKey: .name)
        description = try? container.decode(String.self, forKey: .description)
        recipeYield = try? container.decode(SchemaOrgValue.self, forKey: .recipeYield)
        recipeIngredient = try? container.decode([String].self, forKey: .recipeIngredient)
        recipeInstructions = try? container.decode([InstructionItem].self, forKey: .recipeInstructions)
        totalTime = try? container.decode(String.self, forKey: .totalTime)
        prepTime = try? container.decode(String.self, forKey: .prepTime)
        cookTime = try? container.decode(String.self, forKey: .cookTime)
        image = try? container.decode(SchemaOrgImage.self, forKey: .image)
        aggregateRating = try? container.decode(AggregateRating.self, forKey: .aggregateRating)
        graph = try? container.decode([SchemaOrgWrapper].self, forKey: .graph)
    }
}

/// Flexible value that can be string, int, or double
enum SchemaOrgValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected String, Int, or Double")
        }
    }
}

/// Recipe instruction item (can be string or HowToStep or HowToSection)
struct InstructionItem: Codable {
    var text: String?
    var itemListElement: [InstructionItem]?

    enum CodingKeys: String, CodingKey {
        case text
        case itemListElement
    }

    init(from decoder: Decoder) throws {
        // Try as string first
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            self.text = stringValue
            self.itemListElement = nil
            return
        }

        // Try as object
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try? container.decode(String.self, forKey: .text)
        itemListElement = try? container.decode([InstructionItem].self, forKey: .itemListElement)
    }
}

/// Image can be string URL, object with url property, or array of either
enum SchemaOrgImage: Codable {
    case string(String)
    case object(ImageObject)
    case array([SchemaOrgImage])

    struct ImageObject: Codable {
        var url: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let objectValue = try? container.decode(ImageObject.self) {
            self = .object(objectValue)
        } else if let arrayValue = try? container.decode([SchemaOrgImage].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected String, Object, or Array for image")
        }
    }
}

/// Aggregate rating
struct AggregateRating: Codable {
    var ratingValue: SchemaOrgValue?
    var ratingCount: SchemaOrgValue?
}
