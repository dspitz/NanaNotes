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
    @State private var imageGenerationProgress: [UUID: Bool] = [:]

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
                                        isLoadingImage: imageGenerationProgress[recipe.id] ?? false,
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
            loadPopularRecipes()
        }
    }

    private func loadPopularRecipes() {
        guard AppConfiguration.isOpenAIConfigured else {
            errorMessage = "OpenAI is not configured"
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

                // Generate images in background (non-blocking)
                generateImagesInBackground()

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func generateImagesInBackground() {
        guard AppConfiguration.isOpenAIConfigured else { return }

        for recipe in recipes {
            let recipeId = recipe.id

            Task.detached {
                await MainActor.run {
                    imageGenerationProgress[recipeId] = true
                }

                do {
                    let imageService = DALLEImageService(apiKey: AppConfiguration.openAIAPIKey)

                    // Use imagePrompt if available, otherwise use title
                    let prompt = recipe.imagePrompt ?? recipe.title
                    let imageURL = try await imageService.generateRecipeImage(for: prompt)

                    await MainActor.run {
                        // Update the recipe's imageURL
                        if let index = recipes.firstIndex(where: { $0.id == recipeId }) {
                            recipes[index].imageURL = imageURL
                        }
                        imageGenerationProgress[recipeId] = false
                    }
                } catch {
                    await MainActor.run {
                        imageGenerationProgress[recipeId] = false
                        print("Failed to generate image for \(recipe.title): \(error)")
                    }
                }
            }
        }
    }

    private func handleRecipeSelection(_ recipe: MealRecipe) {
        // Save to MealDraft
        let draft = MealDraft(
            title: recipe.title,
            selectedRecipe: recipe
        )
        modelContext.insert(draft)
        try? modelContext.save()

        // Call callback to show RecipeIngredientSelectionSheet
        onRecipeSelected(recipe)

        // Dismiss this sheet
        dismiss()
    }
}

// MARK: - PopularRecipeCard

struct PopularRecipeCard: View {
    let recipe: MealRecipe
    let isLoadingImage: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Recipe image with loading state
                Group {
                    if isLoadingImage || recipe.imageURL == nil {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 200)
                            .overlay {
                                if isLoadingImage {
                                    ProgressView()
                                } else {
                                    Image(systemName: "fork.knife")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                    } else if let imageURL = recipe.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 200)
                                    .clipped()
                            case .failure(_):
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 200)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundStyle(.tertiary)
                                    }
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 200)
                                    .overlay {
                                        ProgressView()
                                    }
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }

                // Recipe info
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(.outfit(15, weight: .semiBold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Popularity rating
                    if let score = recipe.popularityScore {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", score))
                                .font(.outfit(12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 11))
                            Text("\(recipe.servings)")
                                .font(.outfit(12))
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text("\(recipe.estimatedTimeMinutes)m")
                                .font(.outfit(12))
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

// MARK: - PopularRecipeCardSkeleton

struct PopularRecipeCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShimmerView()
                .frame(height: 200)

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
