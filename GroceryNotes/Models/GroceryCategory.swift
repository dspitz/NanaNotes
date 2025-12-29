import Foundation

enum GroceryCategory: String, Codable, CaseIterable {
    case produce = "Produce"
    case bakery = "Bakery"
    case meat = "Meat"
    case dairy = "Dairy"
    case pantry = "Pantry"
    case frozen = "Frozen"
    case beverages = "Beverages"
    case household = "Household"
    case specialty = "Specialty"
    case other = "Other"

    // Legacy support for old category names (automatically mapped to produce)
    case fruits = "Fruits"
    case vegetables = "Vegetables"

    var displayOrder: Int {
        switch self {
        case .produce: return 0
        case .bakery: return 1
        case .meat: return 2
        case .dairy: return 3
        case .pantry: return 4
        case .frozen: return 5
        case .beverages: return 6
        case .household: return 7
        case .specialty: return 8
        case .other: return 9
        case .fruits: return 10 // Legacy - hidden from UI
        case .vegetables: return 11 // Legacy - hidden from UI
        }
    }

    var icon: String {
        switch self {
        case .produce: return "🥬"
        case .bakery: return "🥖"
        case .meat: return "🥩"
        case .dairy: return "🥛"
        case .pantry: return "🥫"
        case .frozen: return "🧊"
        case .beverages: return "🥤"
        case .household: return "🧹"
        case .specialty: return "✨"
        case .other: return "📦"
        case .fruits: return "🍎" // Legacy
        case .vegetables: return "🥬" // Legacy
        }
    }

    var sfSymbol: String {
        switch self {
        case .produce: return "carrot.fill"
        case .bakery: return "birthday.cake.fill"
        case .meat: return "basket.fill"
        case .dairy: return "drop.fill"
        case .pantry: return "takeoutbag.and.cup.and.straw.fill"
        case .frozen: return "snowflake"
        case .beverages: return "cup.and.saucer.fill"
        case .household: return "bubbles.and.sparkles.fill"
        case .specialty: return "star.fill"
        case .other: return "cart.fill"
        case .fruits: return "leaf.fill" // Legacy
        case .vegetables: return "carrot.fill" // Legacy
        }
    }
}

struct CategoryOrder {
    static let defaultStoreWalkOrder: [GroceryCategory] = [
        .produce, .bakery, .meat, .dairy, .pantry,
        .frozen, .beverages, .household, .specialty, .other
    ]

    static func sortedCategories() -> [GroceryCategory] {
        GroceryCategory.allCases
            .filter { $0 != .fruits && $0 != .vegetables } // Hide legacy categories
            .sorted { $0.displayOrder < $1.displayOrder }
    }
}
