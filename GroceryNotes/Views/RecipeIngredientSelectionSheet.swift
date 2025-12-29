import SwiftUI
import SwiftData

struct RecipeIngredientSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var recipe: MealRecipe?
    let note: GroceryNote
    @Binding var isLoadingRecipe: Bool
    @Binding var isLoadingImage: Bool

    @State private var selectedIngredients: Set<UUID>
    @State private var isAddingIngredients = false

    init(recipe: Binding<MealRecipe?>, note: GroceryNote, isLoadingRecipe: Binding<Bool>, isLoadingImage: Binding<Bool>) {
        self._recipe = recipe
        self.note = note
        self._isLoadingRecipe = isLoadingRecipe
        self._isLoadingImage = isLoadingImage
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
            VStack(spacing: 0) {
                // Recipe Header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Recipe Image with shimmer
                        if isLoadingImage || recipe?.imageURL == nil {
                            ShimmerView()
                                .frame(height: 240)
                        } else if let imageURL = recipe?.imageURL, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 240)
                                        .clipped()
                                case .failure(_):
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 240)
                                        .overlay {
                                            Image(systemName: "photo")
                                                .font(.largeTitle)
                                                .foregroundStyle(.secondary)
                                        }
                                case .empty:
                                    ShimmerView()
                                        .frame(height: 240)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }

                        // Recipe Title & Info with shimmer
                        VStack(alignment: .leading, spacing: 8) {
                            if isLoadingRecipe || recipe == nil {
                                ShimmerView()
                                    .frame(height: 28)
                                    .frame(maxWidth: 200)
                                ShimmerView()
                                    .frame(height: 40)
                                ShimmerView()
                                    .frame(height: 16)
                                    .frame(maxWidth: 150)
                            } else if let recipe = recipe {
                                Text(recipe.title)
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text(recipe.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 16) {
                                    Label("\(recipe.servings) servings", systemImage: "person.2")
                                    Label("\(recipe.estimatedTimeMinutes) min", systemImage: "clock")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            // Source URL if available
                            if let recipe = recipe, let sourceURL = recipe.sourceURL, let url = URL(string: sourceURL) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                        Text("View original recipe")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                }
                                .padding(.top, 4)
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
                                    .font(.headline)
                                Spacer()
                                if !isLoadingRecipe, let recipe = recipe {
                                    Button(selectedIngredients.count == recipe.ingredients.count ? "Deselect All" : "Select All") {
                                        if selectedIngredients.count == recipe.ingredients.count {
                                            selectedIngredients.removeAll()
                                        } else {
                                            selectedIngredients = Set(recipe.ingredients.map { $0.id })
                                        }
                                    }
                                    .font(.caption)
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
                                .font(.headline)
                                .padding(.horizontal, 16)

                            if isLoadingRecipe || recipe == nil {
                                // Shimmer placeholders for steps
                                ForEach(0..<4, id: \.self) { index in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.body)
                                            .fontWeight(.bold)
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
                                            .font(.body)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.blue)
                                            .frame(width: 24, alignment: .trailing)

                                        Text(step)
                                            .font(.body)
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

                // Bottom CTA
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
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(selectedIngredients.isEmpty ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(selectedIngredients.isEmpty || isAddingIngredients)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle("Add Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
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
                    }

                    note.updatedAt = Date()
                    try? modelContext.save()
                    isAddingIngredients = false
                    dismiss()
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
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(ingredient.quantity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
