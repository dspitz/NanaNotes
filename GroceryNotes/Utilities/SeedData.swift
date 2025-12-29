import Foundation
import SwiftData

@MainActor
struct SeedData {
    static func seedIfNeeded(modelContext: ModelContext) {
        let hasData = (try? modelContext.fetchCount(FetchDescriptor<GroceryNote>())) ?? 0 > 0

        guard !hasData else { return }

        seedItemKnowledge(modelContext: modelContext)
        seedRecurringItems(modelContext: modelContext)
        seedNotes(modelContext: modelContext)
        seedDemoMeal(modelContext: modelContext)

        try? modelContext.save()
    }

    private static func seedItemKnowledge(modelContext: ModelContext) {
        let knowledgeData: [(String, GroceryCategory, String, Int, Int)] = [
            ("milk", .dairy, "Refrigerate at 40°F or below", 5, 7),
            ("eggs", .dairy, "Refrigerate in original carton", 21, 35),
            ("cheddar cheese", .dairy, "Refrigerate in sealed container", 21, 28),
            ("butter", .dairy, "Refrigerate or freeze for longer storage", 30, 90),
            ("yogurt", .dairy, "Refrigerate at 40°F or below", 7, 14),
            ("sour cream", .dairy, "Refrigerate after opening", 7, 14),

            ("chicken breast", .meat, "Refrigerate at 40°F or below, or freeze", 1, 2),
            ("ground beef", .meat, "Refrigerate at 40°F or below, or freeze", 1, 2),
            ("bacon", .meat, "Refrigerate in sealed package", 7, 14),
            ("salmon", .meat, "Refrigerate at 40°F or below, or freeze", 1, 2),
            ("pork chops", .meat, "Refrigerate at 40°F or below, or freeze", 3, 5),

            ("bread", .bakery, "Store at room temperature in sealed bag", 3, 7),
            ("bagels", .bakery, "Store at room temperature or freeze", 5, 7),
            ("tortillas", .bakery, "Refrigerate after opening", 7, 14),
            ("hamburger buns", .bakery, "Store at room temperature in sealed bag", 3, 5),

            ("bananas", .produce, "Store at room temperature", 3, 7),
            ("apples", .produce, "Refrigerate for best quality", 21, 42),
            ("lettuce", .produce, "Refrigerate in crisper drawer", 5, 7),
            ("tomatoes", .produce, "Store at room temperature until ripe", 3, 7),
            ("carrots", .produce, "Refrigerate in crisper drawer", 14, 21),
            ("onions", .produce, "Store in cool, dry place", 30, 60),
            ("potatoes", .produce, "Store in cool, dark, dry place", 30, 60),
            ("garlic", .produce, "Store in cool, dry place", 30, 90),
            ("broccoli", .produce, "Refrigerate in crisper drawer", 3, 7),
            ("spinach", .produce, "Refrigerate in crisper drawer", 3, 7),
            ("bell peppers", .produce, "Refrigerate in crisper drawer", 7, 10),
            ("cucumbers", .produce, "Refrigerate in crisper drawer", 7, 10),
            ("strawberries", .produce, "Refrigerate, don't wash until use", 3, 5),
            ("avocados", .produce, "Store at room temperature until ripe, then refrigerate", 3, 5),
            ("lemons", .produce, "Refrigerate for best quality", 14, 21),
            ("limes", .produce, "Refrigerate for best quality", 14, 21),

            ("rice", .pantry, "Store in airtight container in cool, dry place", 365, 730),
            ("pasta", .pantry, "Store in airtight container in cool, dry place", 365, 730),
            ("mac and cheese", .pantry, "Store in cool, dry place", 365, 730),
            ("macaroni and cheese", .pantry, "Store in cool, dry place", 365, 730),
            ("flour", .pantry, "Store in airtight container in cool, dry place", 180, 365),
            ("sugar", .pantry, "Store in airtight container in cool, dry place", 730, 1095),
            ("olive oil", .pantry, "Store in cool, dark place", 180, 365),
            ("canned tomatoes", .pantry, "Store in cool, dry place", 365, 730),
            ("black beans", .pantry, "Store in cool, dry place", 365, 730),
            ("cereal", .pantry, "Store in airtight container", 180, 365),
            ("peanut butter", .pantry, "Store in cool, dry place", 180, 365),
            ("coffee", .pantry, "Store in airtight container", 60, 180),

            ("ice cream", .frozen, "Keep frozen at 0°F or below", 60, 90),
            ("frozen pizza", .frozen, "Keep frozen at 0°F or below", 180, 365),
            ("frozen vegetables", .frozen, "Keep frozen at 0°F or below", 240, 365),

            ("orange juice", .beverages, "Refrigerate after opening", 7, 10),
            ("soda", .beverages, "Store at room temperature", 180, 270),
            ("beer", .beverages, "Store in cool place", 90, 180),
            ("water", .beverages, "Store at room temperature", 365, 730),

            ("dish soap", .household, "Store at room temperature", 730, 1095),
            ("paper towels", .household, "Store in dry place", 1095, 1825),
            ("laundry detergent", .household, "Store at room temperature", 365, 730)
        ]

        for (name, category, advice, minDays, maxDays) in knowledgeData {
            let knowledge = ItemKnowledge(
                normalizedName: name,
                categoryDefault: category,
                storageAdvice: advice,
                shelfLifeDaysMin: minDays,
                shelfLifeDaysMax: maxDays,
                source: "Seed"
            )
            modelContext.insert(knowledge)
        }
    }

    private static func seedRecurringItems(modelContext: ModelContext) {
        let recurringData: [(String, String, GroceryCategory, String?)] = [
            ("milk", "Milk", .dairy, "1 gallon"),
            ("eggs", "Eggs", .dairy, "1 dozen"),
            ("bread", "Bread", .bakery, "1 loaf"),
            ("bananas", "Bananas", .produce, nil),
            ("coffee", "Coffee", .pantry, nil)
        ]

        for (normalized, display, category, quantity) in recurringData {
            let normalizedName = normalized
            let descriptor = FetchDescriptor<ItemKnowledge>(
                predicate: #Predicate<ItemKnowledge> { knowledge in
                    knowledge.normalizedName == normalizedName
                }
            )
            let knowledge = try? modelContext.fetch(descriptor).first

            let recurring = RecurringItem(
                normalizedName: normalized,
                displayName: display,
                defaultCategory: category,
                defaultQuantity: quantity,
                storageAdvice: knowledge?.storageAdvice,
                shelfLifeDaysMin: knowledge?.shelfLifeDaysMin,
                shelfLifeDaysMax: knowledge?.shelfLifeDaysMax,
                source: "Seed"
            )
            modelContext.insert(recurring)
        }
    }

    private static func seedNotes(modelContext: ModelContext) {
        let completedNote = GroceryNote(
            title: "Last Week's Shopping",
            createdAt: Date().addingTimeInterval(-7 * 24 * 60 * 60),
            updatedAt: Date().addingTimeInterval(-7 * 24 * 60 * 60),
            completedAt: Date().addingTimeInterval(-6.5 * 24 * 60 * 60)
        )

        let completedItems: [(String, GroceryCategory, Bool)] = [
            ("Milk", .dairy, true),
            ("Eggs", .dairy, true),
            ("Bread", .bakery, true),
            ("Chicken Breast", .meat, true),
            ("Bananas", .produce, true)
        ]

        for (name, category, checked) in completedItems {
            let item = GroceryItem(
                name: name,
                category: category,
                isChecked: checked,
                checkedAt: checked ? completedNote.completedAt : nil,
                purchasedAt: completedNote.completedAt
            )
            item.note = completedNote
            completedNote.items.append(item)
        }

        modelContext.insert(completedNote)

        let activeNote = GroceryNote(
            title: "This Week's List",
            createdAt: Date().addingTimeInterval(-2 * 60 * 60)
        )

        let activeItems: [(String, GroceryCategory, Bool, Bool)] = [
            ("Milk", .dairy, false, true),
            ("Eggs", .dairy, true, true),
            ("Lettuce", .produce, false, false),
            ("Tomatoes", .produce, false, false),
            ("Ground Beef", .meat, false, false),
            ("Pasta", .pantry, true, false),
            ("Ice Cream", .frozen, false, false)
        ]

        for (name, category, checked, recurring) in activeItems {
            let item = GroceryItem(
                name: name,
                category: category,
                isChecked: checked,
                checkedAt: checked ? Date().addingTimeInterval(-30 * 60) : nil,
                isRecurring: recurring
            )
            item.note = activeNote
            activeNote.items.append(item)
        }

        modelContext.insert(activeNote)
    }

    private static func seedDemoMeal(modelContext: ModelContext) {
        let chickenParmRecipe = MealRecipe(
            title: "Chicken Parmesan",
            description: "Classic Italian-American comfort food with crispy breaded chicken, marinara sauce, and melted mozzarella",
            servings: 4,
            estimatedTimeMinutes: 45,
            ingredients: [
                MealIngredient(name: "Chicken breast", quantity: "4 pieces", categoryHint: "Meat"),
                MealIngredient(name: "Breadcrumbs", quantity: "1 cup", categoryHint: "Pantry"),
                MealIngredient(name: "Mozzarella cheese", quantity: "8 oz", categoryHint: "Dairy"),
                MealIngredient(name: "Parmesan cheese", quantity: "1/2 cup", categoryHint: "Dairy"),
                MealIngredient(name: "Marinara sauce", quantity: "2 cups", categoryHint: "Pantry"),
                MealIngredient(name: "Eggs", quantity: "2", categoryHint: "Dairy"),
                MealIngredient(name: "Olive oil", quantity: "1/4 cup", categoryHint: "Pantry"),
                MealIngredient(name: "Italian seasoning", quantity: "1 tsp", categoryHint: "Pantry")
            ],
            steps: [
                "Preheat oven to 375°F",
                "Pound chicken breasts to even thickness",
                "Set up breading station with flour, beaten eggs, and seasoned breadcrumbs",
                "Bread each chicken piece by coating in flour, then egg, then breadcrumbs",
                "Heat olive oil in large skillet over medium-high heat",
                "Fry breaded chicken until golden brown on both sides, about 3-4 minutes per side",
                "Place chicken in baking dish and top each piece with marinara sauce and mozzarella",
                "Sprinkle parmesan cheese on top",
                "Bake for 20 minutes until cheese is melted and bubbly",
                "Let rest 5 minutes before serving"
            ],
            tags: ["Italian", "Comfort Food", "Family Dinner"]
        )

        let draft = MealDraft(
            title: "Chicken Parmesan",
            selectedRecipe: chickenParmRecipe,
            alternatives: []
        )

        modelContext.insert(draft)
    }
}
