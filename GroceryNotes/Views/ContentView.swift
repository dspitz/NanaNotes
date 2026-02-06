import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @AppStorage("skipFirebase") private var skipFirebase = false // Firebase enabled with real config
    @State private var authService = FirebaseAuthService.shared
    @State private var pendingShareCode: String?

    var body: some View {
        Group {
            if skipFirebase || authService.isAuthenticated {
                // Show main app if Firebase is disabled or user is authenticated
                TabView(selection: $selectedTab) {
                    NotesListView(pendingShareCode: $pendingShareCode)
                        .tabItem {
                            Label("Notes", systemImage: "cart")
                        }
                        .tag(0)

                    MealsView()
                        .tabItem {
                            Label("Recipes", systemImage: "fork.knife")
                        }
                        .tag(1)
                }
                .applyOutfitFont()
            } else {
                // Show authentication view if Firebase is enabled and user is not authenticated
                AuthenticationView()
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Parse: nananotes://share/{shareCode}
        guard url.scheme == "nananotes",
              url.host == "share" else {
            print("⚠️ Invalid deep link: \(url)")
            return
        }

        // Extract share code from path
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let shareCode = pathComponents.first else {
            print("⚠️ No share code in deep link: \(url)")
            return
        }

        print("✅ Deep link received with share code: \(shareCode)")

        // Switch to Notes tab and set pending share code
        selectedTab = 0
        pendingShareCode = shareCode
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            GroceryNote.self,
            GroceryItem.self,
            RecurringItem.self,
            ItemKnowledge.self,
            MealDraft.self
        ])
}
