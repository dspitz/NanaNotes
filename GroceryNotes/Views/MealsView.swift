import SwiftUI
import SwiftData

struct MealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealDraft.createdAt, order: .reverse) private var mealDrafts: [MealDraft]

    @State private var selectedDraft: MealDraft?
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
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(mealDrafts) { draft in
                            if let recipe = draft.selectedRecipe {
                                MealCardView(recipe: recipe) {
                                    selectedDraft = draft
                                    showingAddToNote = true
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Recipes")
            .sheet(isPresented: $showingAddToNote) {
                if let draft = selectedDraft, let recipe = draft.selectedRecipe {
                    AddIngredientsSheet(recipe: recipe)
                }
            }
        }
    }

}

// Beautiful recipe card for 2-column grid with hand-painted illustration
struct MealCardView: View {
    let recipe: MealRecipe
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Hand-painted illustration
                if let imageURL = recipe.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: UIScreen.main.bounds.width / 2 - 32, height: 200)
                                .clipped()
                        case .failure(_):
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: UIScreen.main.bounds.width / 2 - 32, height: 200)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                }
                        case .empty:
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: UIScreen.main.bounds.width / 2 - 32, height: 200)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: UIScreen.main.bounds.width / 2 - 32, height: 200)
                        .overlay {
                            Image(systemName: "fork.knife")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        }
                }

                // Recipe info
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption2)
                            Text("\(recipe.servings)")
                                .font(.caption)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("\(recipe.estimatedTimeMinutes)m")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.gray.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RecipeCardView: View {
    let recipe: MealRecipe
    let onAddToNote: () -> Void

    @State private var showingSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(recipe.description)
                    .foregroundStyle(.secondary)

                HStack {
                    Label("\(recipe.servings) servings", systemImage: "person.2")
                    Spacer()
                    Label("\(recipe.estimatedTimeMinutes) min", systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Ingredients")
                    .font(.headline)

                ForEach(recipe.ingredients) { ingredient in
                    HStack(alignment: .top) {
                        Text("•")
                        Text("\(ingredient.quantity) \(ingredient.name)")
                    }
                    .font(.subheadline)
                }
            }

            Button {
                showingSteps.toggle()
            } label: {
                HStack {
                    Text("Instructions")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showingSteps ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.plain)

            if showingSteps {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .fontWeight(.semibold)
                            Text(step)
                        }
                        .font(.subheadline)
                    }
                }
            }

            Button {
                onAddToNote()
            } label: {
                Label("Add Ingredients to Grocery Note", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct AlternativeRecipeCard: View {
    let recipe: MealRecipe
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(recipe.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack {
                        Label("\(recipe.servings) servings", systemImage: "person.2")
                        Label("\(recipe.estimatedTimeMinutes) min", systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.blue)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

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
