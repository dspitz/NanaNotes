import Foundation

protocol CommerceService {
    func setPreferredStore(storeId: String) async throws
    func mapItemsToProducts(items: [GroceryItem]) async throws -> [ProductMapping]
    func rememberSelection(item: GroceryItem, productId: String) async throws
}

struct ProductMapping {
    var item: GroceryItem
    var productId: String?
    var productName: String?
    var price: Decimal?
    var imageURL: URL?
}

class InstacartCommerceService: CommerceService {
    func setPreferredStore(storeId: String) async throws {
        print("[V2 Stub] Would set preferred Instacart store: \(storeId)")
    }

    func mapItemsToProducts(items: [GroceryItem]) async throws -> [ProductMapping] {
        print("[V2 Stub] Would map \(items.count) items to Instacart products")
        return items.map { ProductMapping(item: $0, productId: nil, productName: nil, price: nil, imageURL: nil) }
    }

    func rememberSelection(item: GroceryItem, productId: String) async throws {
        print("[V2 Stub] Would remember product selection for \(item.name): \(productId)")
    }
}

protocol MealPlannerService {
    func generateMealPlan(meals: [String], days: Int) async throws -> MealPlan
    func swapMeal(in plan: MealPlan, mealId: UUID, newMeal: String) async throws -> MealPlan
    func getGroceryListDiff(from oldPlan: MealPlan?, to newPlan: MealPlan) -> GroceryListDiff
}

struct MealPlan: Codable {
    var id: UUID
    var days: [DayPlan]

    struct DayPlan: Codable {
        var date: Date
        var meals: [PlannedMeal]
    }

    struct PlannedMeal: Codable {
        var id: UUID
        var mealType: String
        var recipeName: String
        var ingredients: [String]
    }
}

struct GroceryListDiff {
    var itemsToAdd: [String]
    var itemsToRemove: [String]
    var itemsToModify: [(item: String, oldQuantity: String, newQuantity: String)]
}

class DefaultMealPlannerService: MealPlannerService {
    func generateMealPlan(meals: [String], days: Int) async throws -> MealPlan {
        print("[V2 Stub] Would generate meal plan for \(days) days with meals: \(meals)")
        return MealPlan(id: UUID(), days: [])
    }

    func swapMeal(in plan: MealPlan, mealId: UUID, newMeal: String) async throws -> MealPlan {
        print("[V2 Stub] Would swap meal \(mealId) with \(newMeal)")
        return plan
    }

    func getGroceryListDiff(from oldPlan: MealPlan?, to newPlan: MealPlan) -> GroceryListDiff {
        print("[V2 Stub] Would calculate grocery list diff")
        return GroceryListDiff(itemsToAdd: [], itemsToRemove: [], itemsToModify: [])
    }
}
