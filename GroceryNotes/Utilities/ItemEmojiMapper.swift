import Foundation
import SwiftData

struct ItemEmojiMapper {
    /// Consolidated emoji map - single source of truth for all ingredient emojis
    /// Merged from ItemEmojiMapper, GroceryItem, and MealIngredient extension
    private static let itemEmojiMap: [String: String] = [
        // Produce
        "apple": "🍎", "apples": "🍎",
        "banana": "🍌", "bananas": "🍌",
        "orange": "🍊", "oranges": "🍊",
        "lemon": "🍋", "lemons": "🍋",
        "lime": "🍋",
        "strawberry": "🍓", "strawberries": "🍓",
        "grapes": "🍇", "grape": "🍇",
        "watermelon": "🍉",
        "peach": "🍑", "peaches": "🍑",
        "cherry": "🍒", "cherries": "🍒",
        "pear": "🍐", "pears": "🍐",
        "pineapple": "🍍",
        "mango": "🥭", "mangos": "🥭", "mangoes": "🥭",
        "avocado": "🥑", "avocados": "🥑",
        "tomato": "🍅", "tomatoes": "🍅",
        "potato": "🥔", "potatoes": "🥔",
        "carrot": "🥕", "carrots": "🥕",
        "corn": "🌽",
        "pepper": "🌶️", "peppers": "🌶️",
        "bell pepper": "🫑", "bell peppers": "🫑",
        "cucumber": "🥒", "cucumbers": "🥒",
        "broccoli": "🥦",
        "lettuce": "🥬",
        "mushroom": "🍄", "mushrooms": "🍄",
        "garlic": "🧄",
        "onion": "🧅", "onions": "🧅",

        // Herbs & Spices (from MealIngredient extension)
        "ginger": "🫚",
        "cilantro": "🌿", "parsley": "🌿", "basil": "🌿",

        // Meat & Protein
        "chicken": "🐔", "chicken breast": "🐔",
        "turkey": "🦃",
        "bacon": "🥓",
        "steak": "🥩", "beef": "🥩", "ground beef": "🥩",
        "pork": "🐷", "pork chops": "🐷",
        "ham": "🍖",
        "sausage": "🌭", "hot dog": "🌭", "hot dogs": "🌭",
        "fish": "🐟", "salmon": "🐟", "tuna": "🐟",
        "shrimp": "🦐",
        "egg": "🥚", "eggs": "🥚",

        // Dairy
        "milk": "🥛", "almond milk": "🥛", "oat milk": "🥛",
        "cheese": "🧀",
        "butter": "🧈",
        "yogurt": "🥛",
        "cream": "🥛", "heavy cream": "🥛", "sour cream": "🥛",
        "ice cream": "🍦",

        // Bakery
        "bread": "🍞",
        "bagel": "🥯", "bagels": "🥯",
        "croissant": "🥐", "croissants": "🥐",
        "baguette": "🥖",
        "donut": "🍩", "donuts": "🍩",
        "cookie": "🍪", "cookies": "🍪",
        "cake": "🎂",
        "pie": "🥧",
        "muffin": "🧁", "muffins": "🧁",

        // Pantry
        "rice": "🍚",
        "pasta": "🍝", "spaghetti": "🍝", "noodles": "🍝",
        "cereal": "🥣",
        "soup": "🍲", "canned soup": "🥫",
        "beans": "🫘", "canned beans": "🫘",
        "peanut butter": "🥜",
        "honey": "🍯",
        "oil": "🫗", "olive oil": "🫗", "vegetable oil": "🫗",
        "salt": "🧂",
        "sugar": "🧂",
        "flour": "🌾",

        // Spices (from MealIngredient extension)
        "spice": "🌶️", "cumin": "🌶️", "turmeric": "🌶️",
        "coriander": "🌶️", "paprika": "🌶️", "chili": "🌶️",
        "garam masala": "🌶️",
        "curry": "🍛",

        // Beverages
        "coffee": "☕", "coffee beans": "☕",
        "tea": "🍵",
        "juice": "🧃", "orange juice": "🧃", "apple juice": "🧃",
        "soda": "🥤", "pop": "🥤",
        "water": "💧", "bottled water": "💧",
        "beer": "🍺",
        "wine": "🍷", "red wine": "🍷", "white wine": "🍷",
        "champagne": "🍾",
        "cocktail": "🍹",

        // Frozen
        "frozen pizza": "🍕", "pizza": "🍕",
        "frozen vegetables": "🧊",
        "frozen fruit": "🧊",

        // Household
        "soap": "🧼",
        "detergent": "🧴",
        "paper towel": "🧻", "paper towels": "🧻",
        "toilet paper": "🧻",
        "trash bag": "🗑️", "trash bags": "🗑️",
    ]

    /// Get emoji for a GroceryItem, with fallback to category emoji
    static func emoji(for item: GroceryItem) -> String {
        emoji(for: item.normalizedName, category: item.category)
    }

    /// Get emoji for a MealIngredient, with fallback to category-based emoji
    static func emoji(for ingredient: MealIngredient) -> String {
        let categoryEnum: GroceryCategory?
        if let categoryHint = ingredient.categoryHint?.lowercased() {
            switch categoryHint {
            case "produce": categoryEnum = .produce
            case "meat": categoryEnum = .meat
            case "dairy": categoryEnum = .dairy
            case "pantry": categoryEnum = .pantry
            case "bakery": categoryEnum = .bakery
            default: categoryEnum = nil
            }
        } else {
            categoryEnum = nil
        }

        return emoji(for: ingredient.name, category: categoryEnum)
    }

    /// Get emoji for a name string, with optional category fallback
    static func emoji(for name: String, category: GroceryCategory? = nil) -> String {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // First try exact match
        if let emoji = itemEmojiMap[normalized] {
            return emoji
        }

        // Try partial match (for items like "organic bananas" -> match "banana")
        for (key, emoji) in itemEmojiMap {
            if normalized.contains(key) {
                return emoji
            }
        }

        // Fallback to category emoji
        if let category = category {
            return category.icon
        }

        // Final fallback
        return "🛒"
    }
}
