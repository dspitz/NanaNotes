import SwiftUI

/// Shared recipe card component used across the app
/// - Grocery note meals tab
/// - Root recipes tab
/// - Recipe search results
struct RecipeCard: View {
    let recipe: MealRecipe
    let onTap: () -> Void
    let onDelete: (() -> Void)?

    @State private var showingDeleteConfirmation = false

    init(recipe: MealRecipe, onTap: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.recipe = recipe
        self.onTap = onTap
        self.onDelete = onDelete
    }

    private var cardContent: some View {
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
                        placeholderImage
                    case .empty:
                        loadingImage
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholderImage
            }

            // Recipe info
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(.outfit(15, weight: .semiBold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

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

    private var placeholderImage: some View {
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
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }

    private var loadingImage: some View {
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
                ProgressView()
            }
    }

    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                if onDelete != nil {
                    showingDeleteConfirmation = true
                }
            }
            .confirmationDialog("Delete Recipe", isPresented: $showingDeleteConfirmation) {
                Button("Delete Recipe", role: .destructive) {
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(recipe.title)\"?")
            }
    }
}
