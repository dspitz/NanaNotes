import SwiftUI
import SwiftData

struct RecipeIngredientSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var recipe: MealRecipe?
    let note: GroceryNote
    @Binding var isLoadingRecipe: Bool
    @Binding var isLoadingImage: Bool
    let onIngredientsAdded: (UUID?) -> Void

    @State private var selectedIngredients: Set<UUID>
    @State private var isAddingIngredients = false

    init(recipe: Binding<MealRecipe?>, note: GroceryNote, isLoadingRecipe: Binding<Bool>, isLoadingImage: Binding<Bool>, onIngredientsAdded: @escaping (UUID?) -> Void = { _ in }) {
        self._recipe = recipe
        self.note = note
        self._isLoadingRecipe = isLoadingRecipe
        self._isLoadingImage = isLoadingImage
        self.onIngredientsAdded = onIngredientsAdded
        // All ingredients selected by default, except staples (salt, pepper, water)
        if let recipe = recipe.wrappedValue {
            let staplesKeywords = ["salt", "pepper", "black pepper", "sea salt", "kosher salt", "water"]
            let nonStaples = recipe.ingredients.filter { ingredient in
                let lowercasedName = ingredient.name.lowercased()
                return !staplesKeywords.contains(where: { lowercasedName.contains($0) })
            }
            _selectedIngredients = State(initialValue: Set(nonStaples.map { $0.id }))
        } else {
            _selectedIngredients = State(initialValue: Set())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // Recipe Header and content
                    ScrollView {
                        VStack(spacing: 0) {
                            // Recipe Image at top edge
                            if isLoadingImage || recipe?.imageURL == nil {
                                ShimmerView()
                                    .frame(width: UIScreen.main.bounds.width, height: 240)
                            } else if let imageURL = recipe?.imageURL, let url = URL(string: imageURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: UIScreen.main.bounds.width, height: 240)
                                            .clipped()
                                    case .failure(_):
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: UIScreen.main.bounds.width, height: 240)
                                            .overlay {
                                                Image(systemName: "photo")
                                                    .font(.largeTitle)
                                                    .foregroundStyle(.secondary)
                                            }
                                    case .empty:
                                        ShimmerView()
                                            .frame(width: UIScreen.main.bounds.width, height: 240)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }

                        VStack(alignment: .center, spacing: 16) {
                            // Recipe Title & Info - show immediately if recipe exists
                            VStack(alignment: .center, spacing: 8) {
                                if let recipe = recipe {
                                Text(recipe.title)
                                    .font(.outfit(32, weight: .bold))
                                    .lineSpacing(-4)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 16)

                                HStack(spacing: 16) {
                                    if let score = recipe.popularityScore {
                                        Label(String(format: "%.1f", score), systemImage: "star.fill")
                                    }
                                    Label("\(recipe.servings) servings", systemImage: "person.2")
                                    Label("\(recipe.estimatedTimeMinutes) min", systemImage: "clock")
                                }
                                .font(.outfit(12))
                                .foregroundStyle(.secondary)

                                Text(recipe.description)
                                    .font(.outfit(14))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)

                                // Source info
                                if let source = recipe.popularitySource {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.outfit(11))
                                        Text(source)
                                            .font(.outfit(11, weight: .medium))
                                    }
                                    .foregroundStyle(.blue)
                                    .frame(height: 40)
                                    .padding(.horizontal, 24)
                                    .background(Color(red: 0.969, green: 0.969, blue: 0.969))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.top, 16)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        Divider()
                            .padding(.horizontal, 16)

                        // Ingredients List with shimmer
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Ingredients")
                                    .font(.outfit(18, weight: .semiBold))
                                Spacer()
                                if !isLoadingRecipe, let recipe = recipe {
                                    Button(selectedIngredients.count == recipe.ingredients.count ? "Deselect All" : "Select All") {
                                        if selectedIngredients.count == recipe.ingredients.count {
                                            selectedIngredients.removeAll()
                                        } else {
                                            selectedIngredients = Set(recipe.ingredients.map { $0.id })
                                        }
                                    }
                                    .font(.outfit(12))
                                    .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)

                            if isLoadingRecipe || recipe == nil {
                                // Shimmer placeholders for ingredients
                                ForEach(0..<6, id: \.self) { _ in
                                    HStack(spacing: 12) {
                                        ShimmerView()
                                            .frame(width: 24, height: 24)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 4) {
                                            ShimmerView()
                                                .frame(height: 16)
                                                .frame(maxWidth: 150)
                                            ShimmerView()
                                                .frame(height: 12)
                                                .frame(maxWidth: 80)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
                            } else if let recipe = recipe {
                                ForEach(recipe.ingredients) { ingredient in
                                    IngredientCheckRow(
                                        ingredient: ingredient,
                                        isSelected: selectedIngredients.contains(ingredient.id),
                                        onToggle: {
                                            if selectedIngredients.contains(ingredient.id) {
                                                selectedIngredients.remove(ingredient.id)
                                            } else {
                                                selectedIngredients.insert(ingredient.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        // Cooking Steps with shimmer
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Instructions")
                                .font(.outfit(18, weight: .semiBold))
                                .padding(.horizontal, 16)

                            if isLoadingRecipe || recipe == nil {
                                // Shimmer placeholders for steps
                                ForEach(0..<4, id: \.self) { index in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.outfit(16, weight: .bold))
                                            .foregroundStyle(.blue)
                                            .frame(width: 24, alignment: .trailing)

                                        VStack(alignment: .leading, spacing: 4) {
                                            ShimmerView()
                                                .frame(height: 16)
                                            ShimmerView()
                                                .frame(height: 16)
                                                .frame(maxWidth: 250)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            } else if let recipe = recipe, !recipe.steps.isEmpty {
                                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.outfit(16, weight: .bold))
                                            .foregroundStyle(.blue)
                                            .frame(width: 24, alignment: .trailing)

                                        Text(step)
                                            .font(.outfit(15))
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .padding(.bottom, 16)
                        }
                    }
                }

                // Bottom CTA - only show when ingredients are loaded
                if !isLoadingRecipe, let recipe = recipe, !recipe.ingredients.isEmpty {
                    VStack(spacing: 0) {
                        Divider()

                        Button {
                            addSelectedIngredientsToList()
                        } label: {
                            HStack {
                                if isAddingIngredients {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Text("Add \(selectedIngredients.count) Ingredient\(selectedIngredients.count == 1 ? "" : "s") to List")
                                        .font(.outfit(16, weight: .semiBold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(selectedIngredients.isEmpty ? Color.gray : Color.black)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(selectedIngredients.isEmpty || isAddingIngredients)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.systemBackground))
                }
            }
            .navigationBarHidden(true)

                // Back button overlaid on image
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(16)
            }
            .onChange(of: isLoadingRecipe) { _, isLoading in
                // When recipe finishes loading, preselect all ingredients except staples
                if !isLoading, let loadedRecipe = recipe, selectedIngredients.isEmpty {
                    preselectIngredients(from: loadedRecipe)
                }
            }
        }
    }

    private func preselectIngredients(from recipe: MealRecipe) {
        let staplesKeywords = ["salt", "pepper", "black pepper", "sea salt", "kosher salt", "water"]
        let nonStaples = recipe.ingredients.filter { ingredient in
            let lowercasedName = ingredient.name.lowercased()
            return !staplesKeywords.contains(where: { lowercasedName.contains($0) })
        }
        selectedIngredients = Set(nonStaples.map { $0.id })
    }

    private func addSelectedIngredientsToList() {
        guard let recipe = recipe else { return }
        isAddingIngredients = true

        Task {
            do {
                let categorizationService = CategorizationService(modelContext: modelContext)
                let selectedIngredientsList = recipe.ingredients.filter { selectedIngredients.contains($0.id) }

                // Batch categorize all ingredients at once (MUCH faster!)
                let itemsToProcess = selectedIngredientsList.map { ($0.name, $0.quantity) }
                let categorizedItems = try await categorizationService.batchCategorize(itemsToProcess)

                // Create all items in a single MainActor block
                await MainActor.run {
                    var firstItemId: UUID?
                    for categorizedItem in categorizedItems {
                        let item = GroceryItem(
                            name: categorizedItem.name,
                            normalizedName: categorizedItem.normalized,
                            quantity: categorizedItem.quantity,
                            category: categorizedItem.category,
                            storageAdvice: categorizedItem.knowledge?.storageAdvice,
                            shelfLifeDaysMin: categorizedItem.knowledge?.shelfLifeDaysMin,
                            shelfLifeDaysMax: categorizedItem.knowledge?.shelfLifeDaysMax,
                            shelfLifeSource: categorizedItem.knowledge?.source
                        )
                        item.note = note
                        note.items.append(item)

                        // Track first item for scrolling
                        if firstItemId == nil {
                            firstItemId = item.id
                        }
                    }

                    note.updatedAt = Date()
                    try? modelContext.save()
                    isAddingIngredients = false
                    dismiss()
                    onIngredientsAdded(firstItemId)
                }

                // Optionally fetch AI storage info in background (don't block dismissal)
                if AppConfiguration.isOpenAIConfigured {
                    Task.detached {
                        for categorizedItem in categorizedItems where categorizedItem.knowledge == nil {
                            do {
                                let aiService = AIStorageService(apiKey: AppConfiguration.openAIAPIKey)
                                let aiResponse = try await aiService.getStorageInfo(for: categorizedItem.name)

                                await MainActor.run {
                                    let aiCategory = GroceryCategory(rawValue: aiResponse.categorySuggestion) ?? categorizedItem.category
                                    let itemKnowledge = ItemKnowledge(
                                        normalizedName: categorizedItem.normalized,
                                        categoryDefault: aiCategory,
                                        storageAdvice: aiResponse.storageAdvice,
                                        shelfLifeDaysMin: aiResponse.shelfLifeDaysMin,
                                        shelfLifeDaysMax: aiResponse.shelfLifeDaysMax,
                                        source: "OpenAI"
                                    )
                                    modelContext.insert(itemKnowledge)
                                    try? modelContext.save()
                                }
                            } catch {
                                // Silently fail - AI is optional
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isAddingIngredients = false
                    print("Failed to add ingredients: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct IngredientCheckRow: View {
    let ingredient: MealIngredient
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(ingredient.emoji)
                    .font(.system(size: 34))

                Text(ingredient.name)
                    .font(.outfit(16))

                if !ingredient.quantity.isEmpty {
                    Text("(\(ingredient.quantity))")
                        .foregroundStyle(.secondary)
                        .font(.outfit(15))
                }
            }

            Spacer()

            ZStack {
                // Background circle
                Circle()
                    .fill(isSelected ? Color.black : Color(red: 0.851, green: 0.851, blue: 0.851))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(.white, lineWidth: 1)
                    )

                // Checkmark icon
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .center) {
                Button {
                    // Minimal haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()

                    onToggle()
                } label: {
                    Color.clear
                        .frame(width: 68, height: 58)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - MealIngredient Extension for Emoji

extension MealIngredient {
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
            "ginger": "🫚", "cilantro": "🌿", "parsley": "🌿", "basil": "🌿",

            // Meat & Protein
            "chicken": "🐔", "chicken breast": "🐔", "turkey": "🦃", "bacon": "🥓",
            "steak": "🥩", "beef": "🥩", "ground beef": "🥩", "pork": "🐷", "pork chops": "🐷",
            "ham": "🍖", "sausage": "🌭", "hot dog": "🌭", "hot dogs": "🌭",
            "fish": "🐟", "salmon": "🐟", "tuna": "🐟", "shrimp": "🦐",
            "egg": "🥚", "eggs": "🥚",

            // Dairy
            "milk": "🥛", "almond milk": "🥛", "oat milk": "🥛", "cheese": "🧀",
            "butter": "🧈", "yogurt": "🥛", "cream": "🥛", "heavy cream": "🥛", "sour cream": "🥛",
            "ice cream": "🍦",

            // Bakery
            "bread": "🍞", "bagel": "🥯", "bagels": "🥯", "croissant": "🥐", "croissants": "🥐",
            "baguette": "🥖", "donut": "🍩", "donuts": "🍩", "cookie": "🍪", "cookies": "🍪",
            "cake": "🎂", "pie": "🥧", "muffin": "🧁", "muffins": "🧁",

            // Pantry
            "rice": "🍚", "pasta": "🍝", "spaghetti": "🍝", "noodles": "🍝", "cereal": "🥣",
            "soup": "🍲", "canned soup": "🥫", "beans": "🫘", "canned beans": "🫘",
            "peanut butter": "🥜", "honey": "🍯", "oil": "🫗", "olive oil": "🫗", "vegetable oil": "🫗",
            "salt": "🧂", "sugar": "🧂", "flour": "🌾", "spice": "🌶️", "cumin": "🌶️",
            "turmeric": "🌶️", "coriander": "🌶️", "paprika": "🌶️", "chili": "🌶️",
            "garam masala": "🌶️", "curry": "🍛",

            // Beverages
            "coffee": "☕", "coffee beans": "☕", "tea": "🍵",
            "juice": "🧃", "orange juice": "🧃", "apple juice": "🧃",
            "soda": "🥤", "pop": "🥤", "water": "💧", "bottled water": "💧",
            "beer": "🍺", "wine": "🍷", "red wine": "🍷", "white wine": "🍷",

            // Frozen
            "frozen pizza": "🍕", "pizza": "🍕"
        ]

        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

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

        // Fallback based on category hint
        if let category = categoryHint {
            switch category.lowercased() {
            case "produce": return "🥬"
            case "meat": return "🥩"
            case "dairy": return "🥛"
            case "pantry": return "🥫"
            case "bakery": return "🍞"
            default: return "🛒"
            }
        }

        // Final fallback
        return "🛒"
    }
}
