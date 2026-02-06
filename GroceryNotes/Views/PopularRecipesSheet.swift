import SwiftUI
import SwiftData

struct PopularRecipesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let searchQuery: String
    let onRecipeSelected: (MealRecipe) -> Void

    @State private var recipes: [MealRecipe] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedRecipe: MealRecipe?
    @State private var showingRecipeDetail = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    // Loading state with skeleton cards
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Searching popular recipes...")
                                .font(.outfit(17, weight: .semiBold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 24)
                                .padding(.top, 8)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(0..<6, id: \.self) { _ in
                                    PopularRecipeCardSkeleton()
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                    }
                    .background(Color(red: 0.941, green: 0.941, blue: 0.937)) // #F0F0EF
                } else if let error = errorMessage {
                    // Error state
                    ContentUnavailableView(
                        "Could Not Load Recipes",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if recipes.isEmpty {
                    // Empty state (shouldn't happen, but defensive)
                    ContentUnavailableView(
                        "No Recipes Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try searching for something else")
                    )
                } else {
                    // Success state with 2-column grid
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Popular recipes for '\(searchQuery)'")
                                .font(.outfit(17, weight: .semiBold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 24)
                                .padding(.top, 8)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ForEach(recipes) { recipe in
                                    RecipeCard(recipe: recipe) {
                                        selectedRecipe = recipe
                                        showingRecipeDetail = true
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                    }
                    .background(Color(red: 0.941, green: 0.941, blue: 0.937)) // #F0F0EF
                }
            }
            .navigationTitle("Search Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            print("🔍 PopularRecipesSheet appeared with searchQuery: '\(searchQuery)'")
            loadPopularRecipes()
        }
        .sheet(isPresented: $showingRecipeDetail) {
            if let recipe = selectedRecipe {
                RecipeDetailWrapper(
                    recipe: recipe,
                    onSaveRecipe: { fullRecipe in
                        // Save to MealDraft
                        let draft = MealDraft(title: fullRecipe.title, selectedRecipe: fullRecipe)
                        modelContext.insert(draft)
                        try? modelContext.save()

                        // Notify parent
                        onRecipeSelected(fullRecipe)

                        // Dismiss the entire sheet stack
                        showingRecipeDetail = false
                        dismiss()
                    }
                )
            }
        }
    }

    private func loadPopularRecipes() {
        guard AppConfiguration.isOpenAIConfigured else {
            errorMessage = "OpenAI is not configured"
            isLoading = false
            return
        }

        guard AppConfiguration.isGoogleSearchConfigured else {
            errorMessage = "Google Search is not configured. Please set up your Google Custom Search API key and Search Engine ID in Config.xcconfig"
            isLoading = false
            return
        }

        Task {
            do {
                let service = AIRecipeService(apiKey: AppConfiguration.openAIAPIKey)
                let response = try await service.searchPopularRecipes(for: searchQuery)

                await MainActor.run {
                    recipes = response.toMealRecipes()
                    isLoading = false
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

}

// MARK: - RecipeDetailWrapper

/// Wrapper view that manages state and uses RecipeIngredientSelectionSheet
/// for consistent recipe detail layout across the app
struct RecipeDetailWrapper: View {
    let recipe: MealRecipe
    let onSaveRecipe: (MealRecipe) -> Void

    @State private var fullRecipe: MealRecipe?
    @State private var isLoadingRecipe = true
    @State private var isLoadingImage = false

    var body: some View {
        RecipeIngredientSelectionSheet(
            recipe: $fullRecipe,
            note: nil,
            isLoadingRecipe: $isLoadingRecipe,
            isLoadingImage: $isLoadingImage,
            onSaveRecipe: onSaveRecipe,
            useStandardNavigation: false
        )
        .onAppear {
            loadFullRecipe()
        }
    }

    private func loadFullRecipe() {
        guard let sourceURL = recipe.sourceURL else {
            isLoadingRecipe = false
            fullRecipe = recipe
            return
        }

        Task {
            do {
                let recipeService = RecipeParsingService()
                let aiResponse = try await recipeService.extractRecipe(from: sourceURL)
                var loadedRecipe = aiResponse.toMealRecipe(sourceURL: sourceURL)

                // Preserve metadata from search results
                loadedRecipe.title = recipe.title
                loadedRecipe.popularityScore = recipe.popularityScore
                loadedRecipe.popularitySource = recipe.popularitySource
                if loadedRecipe.imageURL == nil {
                    loadedRecipe.imageURL = recipe.imageURL
                }

                await MainActor.run {
                    fullRecipe = loadedRecipe
                    isLoadingRecipe = false
                }
            } catch {
                await MainActor.run {
                    isLoadingRecipe = false
                    fullRecipe = recipe
                    print("⚠️ Failed to load full recipe: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - PopularRecipeCard

// MARK: - PopularRecipeCardSkeleton

struct PopularRecipeCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShimmerView()
                .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)

            VStack(alignment: .leading, spacing: 6) {
                ShimmerView()
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)

                ShimmerView()
                    .frame(height: 12)
                    .frame(maxWidth: 100)

                HStack(spacing: 10) {
                    ShimmerView()
                        .frame(width: 50, height: 12)
                    ShimmerView()
                        .frame(width: 50, height: 12)
                }
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - ShimmerView

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.3),
                            Color.gray.opacity(0.5),
                            Color.gray.opacity(0.3)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .mask {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: phase - 0.3),
                                    .init(color: .white, location: phase),
                                    .init(color: .clear, location: phase + 0.3)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
        }
    }
}
