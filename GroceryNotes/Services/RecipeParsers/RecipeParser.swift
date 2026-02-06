import Foundation

/// Protocol for recipe parsers that can extract recipe data from HTML
protocol RecipeParser {
    /// Check if this parser can handle the given URL
    /// - Parameter url: The URL to check
    /// - Returns: True if this parser can handle the URL
    func canParse(url: URL) -> Bool

    /// Parse recipe data from HTML
    /// - Parameters:
    ///   - html: The HTML content to parse
    ///   - url: The source URL
    /// - Returns: A ParsedRecipe if successful, nil otherwise
    func parse(html: String, url: URL) async throws -> ParsedRecipe?
}
