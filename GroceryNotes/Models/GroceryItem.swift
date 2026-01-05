import Foundation
import SwiftData

@Model
final class GroceryItem {
    var id: UUID
    var name: String
    var normalizedName: String
    var quantity: String?
    var categoryRaw: String
    var isChecked: Bool
    var checkedAt: Date?
    var isRecurring: Bool
    var createdAt: Date
    var updatedAt: Date

    var storageAdvice: String?
    var shelfLifeDaysMin: Int?
    var shelfLifeDaysMax: Int?
    var shelfLifeSource: String?
    var purchasedAt: Date?
    var estimatedBestBy: Date?

    // Author tracking for shared lists
    var createdByUserId: String?
    var createdByName: String?

    var note: GroceryNote?

    init(
        id: UUID = UUID(),
        name: String,
        normalizedName: String? = nil,
        quantity: String? = nil,
        category: GroceryCategory = .other,
        isChecked: Bool = false,
        checkedAt: Date? = nil,
        isRecurring: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        storageAdvice: String? = nil,
        shelfLifeDaysMin: Int? = nil,
        shelfLifeDaysMax: Int? = nil,
        shelfLifeSource: String? = nil,
        purchasedAt: Date? = nil,
        estimatedBestBy: Date? = nil,
        createdByUserId: String? = nil,
        createdByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? name.lowercased().trimmingCharacters(in: .whitespaces)
        self.quantity = quantity
        self.categoryRaw = category.rawValue
        self.isChecked = isChecked
        self.checkedAt = checkedAt
        self.isRecurring = isRecurring
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.storageAdvice = storageAdvice
        self.shelfLifeDaysMin = shelfLifeDaysMin
        self.shelfLifeDaysMax = shelfLifeDaysMax
        self.shelfLifeSource = shelfLifeSource
        self.purchasedAt = purchasedAt
        self.estimatedBestBy = estimatedBestBy
        self.createdByUserId = createdByUserId
        self.createdByName = createdByName
    }

    var category: GroceryCategory {
        get {
            GroceryCategory(rawValue: categoryRaw) ?? .other
        }
        set {
            categoryRaw = newValue.rawValue
        }
    }

    func toggleCheck() {
        isChecked.toggle()
        checkedAt = isChecked ? Date() : nil
        updatedAt = Date()
    }

    func toggleRecurring() {
        isRecurring.toggle()
        updatedAt = Date()
    }

    var shelfLifeDescription: String? {
        guard let min = shelfLifeDaysMin, let max = shelfLifeDaysMax else {
            return nil
        }
        if min == max {
            return "\(min) days"
        }
        return "\(min)-\(max) days"
    }

    var emoji: String {
        let itemEmojiMap: [String: String] = [
            // Produce
            "apple": "🍎", "apples": "🍎", "banana": "🍌", "bananas": "🍌",
            "orange": "🍊", "oranges": "🍊", "lemon": "🍋", "lemons": "🍋", "lime": "🍋",
            "strawberry": "🍓", "strawberries": "🍓", "grapes": "🍇", "grape": "🍇",
            "watermelon": "🍉", "peach": "🍑", "peaches": "🍑", "cherry": "🍒", "cherries": "🍒",
            "pear": "🍐", "pears": "🍐", "pineapple": "🍍", "mango": "🥭", "mangos": "🥭", "mangoes": "🥭",
            "avocado": "🥑", "avocados": "🥑", "tomato": "🍅", "tomatoes": "🍅",
            "potato": "🥔", "potatoes": "🥔", "carrot": "🥕", "carrots": "🥕", "corn": "🌽",
            "pepper": "🌶️", "peppers": "🌶️", "bell pepper": "🫑", "bell peppers": "🫑",
            "cucumber": "🥒", "cucumbers": "🥒", "broccoli": "🥦", "lettuce": "🥬",
            "mushroom": "🍄", "mushrooms": "🍄", "garlic": "🧄", "onion": "🧅", "onions": "🧅",

            // Meat & Protein
            "chicken": "🐔", "chicken breast": "🐔", "turkey": "🦃", "bacon": "🥓",
            "steak": "🥩", "beef": "🥩", "ground beef": "🥩", "pork": "🐷", "pork chops": "🐷",
            "ham": "🍖", "sausage": "🌭", "hot dog": "🌭", "hot dogs": "🌭",
            "fish": "🐟", "salmon": "🐟", "tuna": "🐟", "shrimp": "🦐",
            "egg": "🥚", "eggs": "🥚",

            // Dairy
            "milk": "🥛", "almond milk": "🥛", "oat milk": "🥛", "cheese": "🧀",
            "butter": "🧈", "yogurt": "🥛", "cream": "🥛", "ice cream": "🍦",

            // Bakery
            "bread": "🍞", "bagel": "🥯", "bagels": "🥯", "croissant": "🥐", "croissants": "🥐",
            "baguette": "🥖", "donut": "🍩", "donuts": "🍩", "cookie": "🍪", "cookies": "🍪",
            "cake": "🎂", "pie": "🥧", "muffin": "🧁", "muffins": "🧁",

            // Pantry
            "rice": "🍚", "pasta": "🍝", "spaghetti": "🍝", "noodles": "🍝", "cereal": "🥣",
            "soup": "🍲", "canned soup": "🥫", "beans": "🫘", "canned beans": "🫘",
            "peanut butter": "🥜", "honey": "🍯", "oil": "🫗", "olive oil": "🫗",
            "salt": "🧂", "sugar": "🧂",

            // Beverages
            "coffee": "☕", "coffee beans": "☕", "tea": "🍵",
            "juice": "🧃", "orange juice": "🧃", "apple juice": "🧃",
            "soda": "🥤", "pop": "🥤", "water": "💧", "bottled water": "💧",
            "beer": "🍺", "wine": "🍷", "red wine": "🍷", "white wine": "🍷",
            "champagne": "🍾", "cocktail": "🍹",

            // Frozen
            "frozen pizza": "🍕", "pizza": "🍕",

            // Household
            "soap": "🧼", "detergent": "🧴", "paper towel": "🧻", "paper towels": "🧻",
            "toilet paper": "🧻", "trash bag": "🗑️", "trash bags": "🗑️"
        ]

        let normalized = normalizedName.lowercased()

        // Try exact match
        if let emoji = itemEmojiMap[normalized] {
            return emoji
        }

        // Try partial match
        for (key, emoji) in itemEmojiMap {
            if normalized.contains(key) {
                return emoji
            }
        }

        // Fallback to category emoji
        return category.icon
    }
}
