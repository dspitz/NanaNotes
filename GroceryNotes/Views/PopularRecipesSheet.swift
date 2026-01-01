import SwiftUI
import SwiftData
import WebKit

struct PopularRecipesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let searchQuery: String
    let onRecipeSelected: (MealRecipe) -> Void

    @State private var recipes: [MealRecipe] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingRecipeWebView = false
    @State private var selectedRecipe: MealRecipe?

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
        .sheet(isPresented: $showingRecipeWebView) {
            if let recipe = selectedRecipe {
                RecipeWebViewSheet(recipe: recipe) {
                    handleAddIngredientsToList(recipe)
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
        guard recipe.sourceURL != nil else {
            errorMessage = "Recipe URL not available"
            return
        }

        // Show webview with the recipe
        selectedRecipe = recipe
        showingRecipeWebView = true
    }

    private func handleAddIngredientsToList(_ recipe: MealRecipe) {
        guard let sourceURL = recipe.sourceURL else {
            return
        }

        // Show recipe sheet with partial data immediately
        onRecipeSelected(recipe)
        dismiss()

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

// MARK: - RecipeWebViewSheet

struct RecipeWebViewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let recipe: MealRecipe
    let onAddIngredientsToList: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // WebView
                if let urlString = recipe.sourceURL,
                   let url = URL(string: urlString) {
                    WebView(url: url)
                } else {
                    ContentUnavailableView(
                        "Recipe URL Not Available",
                        systemImage: "link.slash",
                        description: Text("Could not load recipe")
                    )
                }

                // Fixed footer with CTA button
                VStack(spacing: 0) {
                    Divider()

                    Button {
                        onAddIngredientsToList()
                        dismiss()
                    } label: {
                        Text("Add Ingredients to List")
                            .font(.outfit(17, weight: .semiBold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.gray.opacity(0.7))
                    }
                }
            }
        }
    }
}

// MARK: - WebView

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Inject CSS to hide ads, popups, and annoying elements
        let cssString = """
        /* Hide common ad and popup elements */
        [class*="ad-"], [id*="ad-"],
        [class*="advertisement"], [id*="advertisement"],
        [class*="popup"], [id*="popup"],
        [class*="modal"], [id*="modal"],
        [class*="cookie"], [id*="cookie"],
        [class*="consent"], [id*="consent"],
        [class*="newsletter"], [id*="newsletter"],
        [class*="subscribe"], [id*="subscribe"],
        [class*="overlay"], [id*="overlay"],
        iframe[src*="doubleclick"],
        iframe[src*="googlesyndication"],
        iframe[src*="ads"],
        .ad, .ads, .advert, .advertisement,
        #ad, #ads, #advert, #advertisement {
            display: none !important;
            visibility: hidden !important;
            opacity: 0 !important;
            height: 0 !important;
            width: 0 !important;
            position: absolute !important;
            left: -9999px !important;
        }

        /* Prevent scroll locking from modals */
        html, body {
            overflow: auto !important;
            position: relative !important;
        }

        /* Improve readability */
        body {
            max-width: 100% !important;
            padding: 0 16px !important;
        }

        /* Hide sticky headers/footers that might overlap */
        [style*="position: fixed"],
        [style*="position:fixed"] {
            position: relative !important;
        }
        """

        let cssScript = WKUserScript(
            source: """
            var style = document.createElement('style');
            style.innerHTML = `\(cssString)`;
            document.head.appendChild(style);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        // JavaScript to remove popups and enable scrolling
        let jsScript = WKUserScript(
            source: """
            // Remove common popup/modal elements after page load
            setTimeout(function() {
                // Remove overlay/modal elements
                var selectors = [
                    '[class*="overlay"]', '[id*="overlay"]',
                    '[class*="modal"]', '[id*="modal"]',
                    '[class*="popup"]', '[id*="popup"]',
                    '[class*="cookie"]', '[id*="cookie"]',
                    '[class*="consent"]', '[id*="consent"]',
                    '[role="dialog"]', '[aria-modal="true"]'
                ];

                selectors.forEach(function(selector) {
                    var elements = document.querySelectorAll(selector);
                    elements.forEach(function(el) {
                        // Check if it's a blocking overlay
                        var styles = window.getComputedStyle(el);
                        if (styles.position === 'fixed' || styles.position === 'absolute') {
                            if (styles.zIndex > 100 || el.getAttribute('role') === 'dialog') {
                                el.remove();
                            }
                        }
                    });
                });

                // Re-enable scrolling
                document.body.style.overflow = 'auto';
                document.documentElement.style.overflow = 'auto';
                document.body.style.position = 'relative';
            }, 1000);

            // Keep checking and removing in case popups appear later
            setInterval(function() {
                document.body.style.overflow = 'auto';
                document.documentElement.style.overflow = 'auto';
            }, 500);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        userContentController.addUserScript(cssScript)
        userContentController.addUserScript(jsScript)
        config.userContentController = userContentController

        // Block pop-ups
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}
