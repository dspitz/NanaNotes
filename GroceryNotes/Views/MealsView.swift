import SwiftUI
import SwiftData

struct MealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealDraft.createdAt, order: .reverse) private var mealDrafts: [MealDraft]

    @State private var selectedRecipe: MealRecipe?
    @State private var showingRecipeDetail = false
    @State private var showingAddToNote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if mealDrafts.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "fork.knife",
                        description: Text("Generate recipes from the Notes tab by typing a meal idea")
                    )
                    .padding(.top, 100)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(mealDrafts) { draft in
                                if let recipe = draft.selectedRecipe {
                                    RecipeCard(
                                        recipe: recipe,
                                        onTap: {
                                            selectedRecipe = recipe
                                            showingRecipeDetail = true
                                        },
                                        onDelete: {
                                            deleteMealDraft(draft)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color(red: 0.882, green: 0.882, blue: 0.882))
            .navigationTitle("Recipes")
            .sheet(isPresented: $showingRecipeDetail) {
                if let recipe = selectedRecipe {
                    RecipeDetailSheetForRootTab(recipe: recipe)
                }
            }
        }
    }

    private func deleteMealDraft(_ draft: MealDraft) {
        modelContext.delete(draft)
        try? modelContext.save()
    }
}

/// Recipe detail view for root recipes tab
/// Shows recipe using RecipeIngredientSelectionSheet with "Add to Note" functionality
struct RecipeDetailSheetForRootTab: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: MealRecipe

    @State private var fullRecipe: MealRecipe?
    @State private var isLoadingRecipe = false
    @State private var isLoadingImage = false
    @State private var showingAddToNote = false

    var body: some View {
        ZStack {
            RecipeIngredientSelectionSheet(
                recipe: $fullRecipe,
                note: nil,
                isLoadingRecipe: $isLoadingRecipe,
                isLoadingImage: $isLoadingImage,
                onSaveRecipe: { _ in
                    showingAddToNote = true
                },
                useStandardNavigation: false
            )
            .onAppear {
                fullRecipe = recipe
            }
        }
        .sheet(isPresented: $showingAddToNote) {
            if let recipe = fullRecipe {
                AddIngredientsSheet(recipe: recipe)
            }
        }
    }
}

// MARK: - AddIngredientsSheet

struct AddIngredientsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryNote.createdAt, order: .reverse) private var notes: [GroceryNote]

    let recipe: MealRecipe

    @State private var selectedNote: GroceryNote?
    @State private var createNewNote = false
    @State private var collisionHandling: [UUID: CollisionAction] = [:]

    enum CollisionAction: String, CaseIterable {
        case keep = "Keep Existing"
        case duplicate = "Add Duplicate"
        case increase = "Increase Quantity"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Grocery Note") {
                    Picker("Note", selection: $selectedNote) {
                        Text("Select a note").tag(nil as GroceryNote?)
                        ForEach(notes.filter { !$0.isCompleted }) { note in
                            Text(note.title).tag(note as GroceryNote?)
                        }
                    }

                    Toggle("Create New Note", isOn: $createNewNote)
                }

                if !collisionHandling.isEmpty {
                    Section("Existing Items") {
                        ForEach(Array(collisionHandling.keys), id: \.self) { ingredientId in
                            if let ingredient = recipe.ingredients.first(where: { $0.id == ingredientId }) {
                                VStack(alignment: .leading) {
                                    Text(ingredient.name)
                                        .font(.headline)

                                    Picker("Action", selection: Binding(
                                        get: { collisionHandling[ingredientId] ?? .keep },
                                        set: { collisionHandling[ingredientId] = $0 }
                                    )) {
                                        ForEach(CollisionAction.allCases, id: \.self) { action in
                                            Text(action.rawValue).tag(action)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Grocery Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addIngredientsToNote()
                        dismiss()
                    }
                    .disabled(selectedNote == nil && !createNewNote)
                }
            }
            .onChange(of: selectedNote) {
                checkForCollisions()
            }
        }
    }

    private func checkForCollisions() {
        guard let note = selectedNote else { return }

        collisionHandling.removeAll()

        let categorizationService = CategorizationService(modelContext: modelContext)

        for ingredient in recipe.ingredients {
            Task {
                let normalized = await categorizationService.normalizeItemName(ingredient.name)
                let exists = note.items.contains { $0.normalizedName == normalized }

                await MainActor.run {
                    if exists {
                        collisionHandling[ingredient.id] = .keep
                    }
                }
            }
        }
    }

    private func addIngredientsToNote() {
        let targetNote: GroceryNote
        if createNewNote {
            targetNote = GroceryNote(title: recipe.title)
            modelContext.insert(targetNote)
        } else if let selected = selectedNote {
            targetNote = selected
        } else {
            return
        }

        let categorizationService = CategorizationService(modelContext: modelContext)

        for ingredient in recipe.ingredients {
            Task {
                let normalized = await categorizationService.normalizeItemName(ingredient.name)
                let (category, knowledge) = try await categorizationService.categorizeItem(ingredient.name)

                if let categoryHint = ingredient.categoryHint,
                   let hintCategory = GroceryCategory(rawValue: categoryHint) {
                    await addIngredient(
                        to: targetNote,
                        ingredient: ingredient,
                        normalized: normalized,
                        category: hintCategory,
                        knowledge: knowledge
                    )
                } else {
                    await addIngredient(
                        to: targetNote,
                        ingredient: ingredient,
                        normalized: normalized,
                        category: category,
                        knowledge: knowledge
                    )
                }
            }
        }

        try? modelContext.save()
    }

    private func addIngredient(
        to note: GroceryNote,
        ingredient: MealIngredient,
        normalized: String,
        category: GroceryCategory,
        knowledge: ItemKnowledge?
    ) async {
        await MainActor.run {
            let action = collisionHandling[ingredient.id] ?? .duplicate

            if action == .keep {
                return
            }

            let item = GroceryItem(
                name: ingredient.name,
                normalizedName: normalized,
                quantity: ingredient.quantity,
                category: category,
                storageAdvice: knowledge?.storageAdvice,
                shelfLifeDaysMin: knowledge?.shelfLifeDaysMin,
                shelfLifeDaysMax: knowledge?.shelfLifeDaysMax,
                shelfLifeSource: knowledge?.source
            )
            item.note = note
            note.items.append(item)
            note.updatedAt = Date()
        }
    }
}

#Preview {
    MealsView()
        .modelContainer(for: [MealDraft.self])
}
