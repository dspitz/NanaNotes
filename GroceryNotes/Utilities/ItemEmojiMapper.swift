import Foundation

struct ItemEmojiMapper {
    /// Maps normalized item names to specific emojis
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
        "cream": "🥛",
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
        "oil": "🫗", "olive oil": "🫗",
        "salt": "🧂",
        "sugar": "🧂",

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

    /// Get emoji for an item, with fallback to category emoji
    static func emoji(for item: GroceryItem) -> String {
        let normalized = item.normalizedName.lowercased()

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
        return item.category.icon
    }
}
