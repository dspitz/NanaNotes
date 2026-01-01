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
                    .background(Color(red: 0.882, green: 0.882, blue: 0.882))
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
                                    PopularRecipeCard(
                                        recipe: recipe,
                                        onTap: {
                                            handleRecipeSelection(recipe)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                    }
                    .background(Color(red: 0.882, green: 0.882, blue: 0.882))
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

    private func handleRecipeSelection(_ recipe: MealRecipe) {
        guard let sourceURL = recipe.sourceURL else {
            errorMessage = "Recipe URL not available"
            return
        }

        // Immediately show recipe sheet with partial data
        onRecipeSelected(recipe)
        // Don't dismiss - let user navigate back to recipe grid

        // Continue loading full recipe in background
        Task {
            do {
                // Extract full recipe from URL using RecipeURLService
                let recipeService = RecipeURLService(apiKey: AppConfiguration.openAIAPIKey)
                let aiResponse = try await recipeService.extractRecipeFromURL(sourceURL)
                var fullRecipe = aiResponse.toMealRecipe(sourceURL: sourceURL)

                // Preserve metadata from search results
                fullRecipe.popularityScore = recipe.popularityScore
                fullRecipe.popularitySource = recipe.popularitySource
                if fullRecipe.imageURL == nil {
                    fullRecipe.imageURL = recipe.imageURL  // Use search result image if extraction didn't find one
                }

                await MainActor.run {
                    // Save to MealDraft
                    let draft = MealDraft(title: fullRecipe.title, selectedRecipe: fullRecipe)
                    modelContext.insert(draft)
                    try? modelContext.save()

                    // Update with full recipe data
                    onRecipeSelected(fullRecipe)
                }
            } catch {
                // Silently fail - user already has partial recipe shown
                print("⚠️ Failed to load full recipe: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - PopularRecipeCard

struct PopularRecipeCard: View {
    let recipe: MealRecipe
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Recipe image
                if let imageURL = recipe.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)
                                .clipped()
                        case .failure(_):
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                }
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // No image URL - show placeholder
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)
                        .overlay {
                            Image(systemName: "fork.knife")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        }
                }

                // Recipe info
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.outfit(15, weight: .semiBold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 40, alignment: .topLeading)

                    // Recipe source
                    if let source = recipe.popularitySource {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 11))
                            Text(source)
                                .font(.outfit(12, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                    }
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
