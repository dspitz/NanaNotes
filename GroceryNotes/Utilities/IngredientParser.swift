import Foundation

/// Utility for parsing ingredient strings into components
/// Examples: "2 cups flour" → quantity: "2", unit: "cups", name: "flour"
struct IngredientParser {
    /// Parse an ingredient string into components
    /// - Parameter ingredientString: The raw ingredient string
    /// - Returns: A ParsedRecipeIngredient with extracted components
    static func parse(_ ingredientString: String) -> ParsedRecipeIngredient {
        let trimmed = ingredientString.trimmingCharacters(in: .whitespaces)

        // Check for patterns with quantity/unit in parentheses
        var quantity = ""
        var unit: String?
        var remainingString = trimmed

        // Pattern 1: "1 (12 ounce) package dried rice noodles" - number before parentheses
        let parenWithLeadingNum = #"^\d+\s+\((\d+(?:[./]\d+)?(?:\s+\d+/\d+)?)\s+([a-zA-Z]+(?:\s+[a-zA-Z]+)?)\)\s*(.+)$"#
        if let regex1 = try? NSRegularExpression(pattern: parenWithLeadingNum, options: []),
           let match = regex1.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {

            // Extract quantity from inside parentheses
            if let qtyRange = Range(match.range(at: 1), in: trimmed) {
                quantity = String(trimmed[qtyRange]).trimmingCharacters(in: .whitespaces)
            }

            // Extract unit from inside parentheses
            if let unitRange = Range(match.range(at: 2), in: trimmed) {
                let potentialUnit = String(trimmed[unitRange]).trimmingCharacters(in: .whitespaces)
                if isValidUnit(potentialUnit) {
                    unit = potentialUnit
                }
            }

            // Extract name (everything after parentheses)
            if let nameRange = Range(match.range(at: 3), in: trimmed) {
                remainingString = String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces)
            }

            var name = cleanPackagingTerms(remainingString)
            name = cleanToTastePhrases(name)
            return ParsedRecipeIngredient(
                name: name,
                quantity: quantity,
                unit: unit,
                categoryHint: nil
            )
        }

        // Pattern 2: "(12 ounce) package dried rice noodles" - starts with parentheses
        let parenPattern = #"^\((\d+(?:[./]\d+)?(?:\s+\d+/\d+)?)\s+([a-zA-Z]+(?:\s+[a-zA-Z]+)?)\)\s*(.+)$"#
        if let regex2 = try? NSRegularExpression(pattern: parenPattern, options: []),
           let match = regex2.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {

            // Extract quantity from parentheses
            if let qtyRange = Range(match.range(at: 1), in: trimmed) {
                quantity = String(trimmed[qtyRange]).trimmingCharacters(in: .whitespaces)
            }

            // Extract unit from parentheses
            if let unitRange = Range(match.range(at: 2), in: trimmed) {
                let potentialUnit = String(trimmed[unitRange]).trimmingCharacters(in: .whitespaces)
                if isValidUnit(potentialUnit) {
                    unit = potentialUnit
                }
            }

            // Extract name (everything after parentheses)
            if let nameRange = Range(match.range(at: 3), in: trimmed) {
                remainingString = String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces)
            }

            var name = cleanPackagingTerms(remainingString)
            name = cleanToTastePhrases(name)
            return ParsedRecipeIngredient(
                name: name,
                quantity: quantity,
                unit: unit,
                categoryHint: nil
            )
        }

        // Try to extract quantity (numbers at the beginning)
        let quantityPattern = #"^(\d+(?:[./]\d+)?(?:\s+\d+/\d+)?)\s+"#
        if let qtyRegex = try? NSRegularExpression(pattern: quantityPattern, options: []),
           let qtyMatch = qtyRegex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
           let qtyRange = Range(qtyMatch.range(at: 1), in: trimmed) {
            quantity = String(trimmed[qtyRange]).trimmingCharacters(in: .whitespaces)

            // Remove quantity from remaining string
            if let fullRange = Range(qtyMatch.range(at: 0), in: trimmed) {
                remainingString = String(trimmed[fullRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Try to extract unit (at the beginning of remaining string)
        var name = remainingString

        // Check if the first word(s) are a valid unit
        let words = remainingString.split(separator: " ", maxSplits: 2)
        if !words.isEmpty {
            // Try first word
            let firstWord = String(words[0])
            if isValidUnit(firstWord) {
                unit = firstWord
                name = words.dropFirst().joined(separator: " ")
            } else if words.count >= 2 {
                // Try first two words (e.g., "fluid ounce")
                let firstTwoWords = "\(words[0]) \(words[1])"
                if isValidUnit(firstTwoWords) {
                    unit = firstTwoWords
                    name = words.dropFirst(2).joined(separator: " ")
                }
            }
        }

        // Clean up "of" if it's at the start of the name
        if name.lowercased().hasPrefix("of ") {
            name = String(name.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }

        // Clean up "to taste" type phrases
        name = cleanToTastePhrases(name)

        return ParsedRecipeIngredient(
            name: name.isEmpty ? trimmed : name,
            quantity: quantity,
            unit: unit,
            categoryHint: nil
        )
    }

    /// Remove "to taste", "as needed", "or more to taste" type phrases
    private static func cleanToTastePhrases(_ name: String) -> String {
        let phrasesToRemove = [
            ", or more to taste",
            ", or to taste",
            ", to taste",
            "or more to taste",
            "or to taste",
            "to taste",
            ", as needed",
            "as needed",
            ", if needed",
            "if needed",
            ", optional",
            "optional"
        ]

        var cleaned = name
        for phrase in phrasesToRemove {
            // Case insensitive removal
            if let range = cleaned.range(of: phrase, options: .caseInsensitive) {
                cleaned.removeSubrange(range)
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clean up packaging terms to extract the actual food item
    /// Example: "package dried rice noodles" → "dried rice noodles"
    private static func cleanPackagingTerms(_ name: String) -> String {
        let packagingTerms = [
            "package", "packages", "pkg",
            "container", "containers",
            "box", "boxes",
            "bag", "bags",
            "can", "cans",
            "jar", "jars",
            "bottle", "bottles",
            "bunch", "bunches"
        ]

        let words = name.split(separator: " ")
        guard !words.isEmpty else { return name }

        let firstWord = String(words[0]).lowercased()

        // If the first word is a packaging term, remove it
        if packagingTerms.contains(firstWord) {
            return words.dropFirst().joined(separator: " ")
        }

        return name
    }

    /// Check if a string is a valid measurement unit
    private static func isValidUnit(_ string: String) -> Bool {
        let units = [
            // Volume
            "cup", "cups", "tablespoon", "tablespoons", "tbsp", "teaspoon", "teaspoons", "tsp",
            "fluid ounce", "fluid ounces", "fl oz", "pint", "pints", "quart", "quarts",
            "gallon", "gallons", "milliliter", "milliliters", "ml", "liter", "liters", "l",
            // Weight
            "ounce", "ounces", "oz", "pound", "pounds", "lb", "lbs", "gram", "grams", "g",
            "kilogram", "kilograms", "kg",
            // Other
            "piece", "pieces", "slice", "slices", "clove", "cloves", "can", "cans",
            "package", "packages", "pkg", "jar", "jars", "bottle", "bottles",
            "bunch", "bunches", "sprig", "sprigs", "pinch", "dash", "whole", "large", "medium", "small"
        ]

        let lowercased = string.lowercased()
        return units.contains(lowercased)
    }

    /// Abbreviate common units for cleaner display
    static func abbreviateUnit(_ unit: String) -> String {
        let abbreviations: [String: String] = [
            "tablespoon": "tbsp",
            "tablespoons": "tbsp",
            "teaspoon": "tsp",
            "teaspoons": "tsp",
            "ounce": "oz",
            "ounces": "oz",
            "pound": "lb",
            "pounds": "lbs",
            "fluid ounce": "fl oz",
            "fluid ounces": "fl oz"
        ]

        let lowercased = unit.lowercased()
        return abbreviations[lowercased] ?? unit
    }
}

