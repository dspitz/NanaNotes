import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @AppStorage("skipFirebase") private var skipFirebase = false // Firebase enabled with real config
    @State private var authService = FirebaseAuthService.shared

    var body: some View {
        Group {
            if skipFirebase || authService.isAuthenticated {
                // Show main app if Firebase is disabled or user is authenticated
                TabView(selection: $selectedTab) {
                    NotesListView()
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
